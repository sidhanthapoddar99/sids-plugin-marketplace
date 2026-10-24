// `ctl merge <branch>` and its version step, in a throwaway copy of the template: the main tree on
// main and the branch in its own worktree. The gate is a stand-in that records where it ran and with
// what, so each test reads the git result directly.
import { afterEach, beforeEach, expect, test } from 'bun:test';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { template } from './gate-fixture';

let base: string, root: string;
const slot = () => join(root, '.worktrees/work');
const env = (extra: Record<string, string> = {}) => ({
  PATH: `${dirname(process.execPath)}:/usr/local/bin:/usr/bin:/bin`, HOME: base, NO_COLOR: '1', LANG: 'C.UTF-8',
  GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', FIXTURE_BASE: base, GIT_AUTHOR_NAME: 'ctl test', GIT_AUTHOR_EMAIL: 'ctl-test@example.invalid',
  GIT_COMMITTER_NAME: 'ctl test', GIT_COMMITTER_EMAIL: 'ctl-test@example.invalid', ...extra });
function git(dir: string, ...args: string[]) {
  const r = spawnSync('git', ['-c', 'user.name=ctl test', '-c', 'user.email=ctl-test@example.invalid', '-c', 'commit.gpgsign=false',
    '-c', 'core.hooksPath=/dev/null', '-c', 'init.defaultBranch=main', ...args], { cwd: dir, env: env(), encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}
const put = (path: string, text: string) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };
const commitAll = (dir: string, message: string) => { git(dir, 'add', '-A'); git(dir, 'commit', '-qm', message); };
const ctl = (args: string[], extra: Record<string, string> = {}) => {
  const r = spawnSync('bash', [join(root, 'ctl'), ...args], { cwd: root, env: env(extra), encoding: 'utf8', timeout: 60_000 });
  return { code: r.status ?? -1, out: r.stdout, err: r.stderr };
};
const gateRuns = () => existsSync(join(base, 'gate.log')) ? readFileSync(join(base, 'gate.log'), 'utf8').trim().split('\n') : [];
const versionFiles = (files: string) => {
  const path = join(root, 'scripts/release/versions.sh');
  writeFileSync(path, readFileSync(path, 'utf8').replace('VERSION_FILES=()', `VERSION_FILES=(${files})`));
};

beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'ctl-merge-'));
  root = join(base, 'repo');
  mkdirSync(root);
  cpSync(join(template, 'ctl'), join(root, 'ctl'));
  cpSync(join(template, '.gitignore'), join(root, '.gitignore'));
  cpSync(join(template, 'scripts'), join(root, 'scripts'), { recursive: true });
  put(join(root, 'scripts/gate/all.sh'), `printf '%s merge=%s %s\\n' "$(pwd -P)" "\${CTL_MERGE:-}" "$*" >> "$FIXTURE_BASE/gate.log"
exit "\${FIXTURE_GATE_EXIT:-0}"
`);
  put(join(root, 'apps/web/package.json'), '{\n  "name": "web",\n  "version": "1.2.3",\n  "dependencies": { "x": "1.2.3" }\n}\n');
  put(join(root, 'apps/web/src/page.ts'), 'export {};\n');
  git(root, 'init', '-q');
  commitAll(root, 'base');
  git(root, 'worktree', 'add', '-q', '-b', 'work', slot());
});
afterEach(() => rmSync(base, { recursive: true, force: true }));

test('lands a branch: merges main in, gates the merged tree with CTL_MERGE=1, fast-forwards main, pushes nothing', () => {
  put(join(slot(), 'apps/web/src/feature.ts'), 'export {};\n'); commitAll(slot(), 'feature');
  put(join(root, 'docs.txt'), 'main side\n'); commitAll(root, 'upstream');
  const run = ctl(['merge', 'work']);
  expect(run.code, run.err).toBe(0);
  expect(run.out).toContain('merged main into work');
  expect(gateRuns()).toEqual([`${slot()} merge=1 --delta main`]);
  expect(git(root, 'rev-parse', 'main')).toBe(git(slot(), 'rev-parse', 'HEAD'));
  expect(existsSync(join(root, 'apps/web/src/feature.ts')) && existsSync(join(root, 'docs.txt'))).toBe(true);
  expect(run.out).toContain('push it with: git push origin main');
});

test('with VERSION_FILES set, shipped code raises the patch part once in a Release commit; a dependency keeps its version', () => {
  versionFiles('apps/web/package.json'); commitAll(root, 'versioned');
  git(slot(), 'merge', '-q', 'main');
  put(join(slot(), 'apps/web/src/feature.ts'), 'export {};\n'); commitAll(slot(), 'feature');
  const run = ctl(['merge', 'work']);
  expect(run.code, run.err).toBe(0);
  expect(git(slot(), 'log', '-1', '--format=%s')).toBe('Release: product 1.2.3 → 1.2.4');
  const manifest = readFileSync(join(root, 'apps/web/package.json'), 'utf8');
  expect(manifest).toContain('"version": "1.2.4"');
  expect(manifest).toContain('"x": "1.2.3"');
});

test('a test-only or docs-only branch sets no version, --minor raises the minor part, and a hand-raised version is kept', () => {
  versionFiles('apps/web/package.json'); commitAll(root, 'versioned');
  git(slot(), 'merge', '-q', 'main');
  const at = git(root, 'rev-parse', 'HEAD');
  const step = (...args: string[]) => spawnSync('bash', [join(slot(), 'scripts/release/versions.sh'), '--base', at, ...args], { cwd: slot(), env: env(), encoding: 'utf8' }).stdout.trim();
  put(join(slot(), 'apps/web/src/page.test.ts'), 'test\n'); put(join(slot(), 'apps/web/README.md'), 'notes\n'); commitAll(slot(), 'tests');
  expect(step('--dry-run')).toBe('none');
  expect(step('--minor', '--dry-run')).toBe('product 1.2.3 → 1.3.0');
  put(join(slot(), 'apps/web/package.json'), readFileSync(join(slot(), 'apps/web/package.json'), 'utf8').replace('"version": "1.2.3"', '"version": "2.0.0"'));
  commitAll(slot(), 'major by hand');
  expect(step()).toBe('product 1.2.3 → 2.0.0 (raised on the branch)');
});

test('without VERSION_FILES the step sets none and adds no commit', () => {
  put(join(slot(), 'apps/web/src/feature.ts'), 'export {};\n'); commitAll(slot(), 'feature');
  const before = git(slot(), 'rev-parse', 'HEAD');
  expect(ctl(['merge', 'work']).code).toBe(0);
  expect(git(slot(), 'rev-parse', 'HEAD')).toBe(before);
});

test('a red gate leaves main where it was, and a conflict stops before any version is set', () => {
  put(join(slot(), 'apps/web/src/page.ts'), 'export const a = 1;\n'); commitAll(slot(), 'feature');
  const main = git(root, 'rev-parse', 'main');
  const red = ctl(['merge', 'work'], { FIXTURE_GATE_EXIT: '1' });
  expect(red.code).not.toBe(0);
  expect(red.err).toContain('the gate is red');
  expect(git(root, 'rev-parse', 'main')).toBe(main);
  put(join(root, 'apps/web/src/page.ts'), 'export const b = 2;\n'); commitAll(root, 'conflicting');
  const branch = git(slot(), 'rev-parse', 'HEAD');
  const conflict = ctl(['merge', 'work']);
  expect(conflict.err).toContain('conflicts');
  expect(git(slot(), 'rev-parse', 'HEAD')).toBe(branch);
  expect(git(slot(), 'status', '--porcelain')).toBe('');
});

test('refuses uncommitted work, a branch with no worktree and the default branch; --dry-run changes nothing', () => {
  put(join(slot(), 'apps/web/src/page.ts'), 'edited\n');
  expect(ctl(['merge', 'work']).err).toContain('uncommitted changes; commit them on work first');
  git(slot(), 'checkout', '-q', '--', '.');
  git(root, 'branch', 'loose');
  expect(ctl(['merge', 'loose']).err).toContain('no worktree holds loose');
  expect(ctl(['merge', 'main']).err).toContain('main is the default branch');
  put(join(root, 'docs.txt'), 'main side\n'); commitAll(root, 'upstream');
  const [main, branch] = [git(root, 'rev-parse', 'main'), git(slot(), 'rev-parse', 'HEAD')];
  const dry = ctl(['merge', 'work', '--dry-run']);
  expect(dry.code, dry.err).toBe(0);
  expect(dry.out).toContain('would merge main into work');
  expect([git(root, 'rev-parse', 'main'), git(slot(), 'rev-parse', 'HEAD')]).toEqual([main, branch]);
  expect(gateRuns()).toEqual([]);
});
