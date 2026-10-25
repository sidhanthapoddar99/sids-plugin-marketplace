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
// versionParts <line…> — fill VERSION_PARTS in the main tree's copy, as a project adapts it.
const versionParts = (...lines: string[]) => {
  const path = join(root, 'scripts/release/versions.sh');
  writeFileSync(path, readFileSync(path, 'utf8').replace('VERSION_PARTS=(\n)', `VERSION_PARTS=(\n${lines.map(l => `  "${l}"`).join('\n')}\n)`));
};
// step <args…> — the version step alone, in the branch's worktree, counted from main.
const step = (...args: string[]) => {
  const r = spawnSync('bash', [join(slot(), 'scripts/release/versions.sh'), '--base', git(root, 'rev-parse', 'main'), ...args], { cwd: slot(), env: env(), encoding: 'utf8' });
  return (r.stdout + r.stderr).trim();
};
// land <message> — commit the parts on main, then bring the branch up to date with it.
const land = (message: string) => { commitAll(root, message); git(slot(), 'merge', '-q', 'main'); };

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
  expect(run.out).toContain('push it with: git push --follow-tags origin main');
});

test('one part: shipped code raises the patch number once in a Release commit; a dependency keeps its version', () => {
  versionParts('web apps/web/package.json'); land('versioned');
  put(join(slot(), 'apps/web/src/feature.ts'), 'export {};\n'); commitAll(slot(), 'feature');
  const run = ctl(['merge', 'work']);
  expect(run.code, run.err).toBe(0);
  expect(git(slot(), 'log', '-1', '--format=%s')).toBe('Release: web 1.2.3 → 1.2.4');
  const manifest = readFileSync(join(root, 'apps/web/package.json'), 'utf8');
  expect(manifest).toContain('"version": "1.2.4"');
  expect(manifest).toContain('"x": "1.2.3"');
});

test('a test-only or docs-only branch sets no version, --minor raises the minor number, and a hand-raised version is kept', () => {
  versionParts('web apps/web/package.json'); land('versioned');
  put(join(slot(), 'apps/web/src/page.test.ts'), 'test\n'); put(join(slot(), 'apps/web/README.md'), 'notes\n'); commitAll(slot(), 'tests');
  expect(step('--dry-run')).toBe('none');
  expect(step('--minor', '--dry-run')).toBe('web 1.2.3 → 1.3.0');
  expect(step('--major=web', '--dry-run')).toBe('web 1.2.3 → 2.0.0');
  put(join(slot(), 'apps/web/package.json'), readFileSync(join(slot(), 'apps/web/package.json'), 'utf8').replace('"version": "1.2.3"', '"version": "2.0.0"'));
  commitAll(slot(), 'major by hand');
  expect(step()).toBe('web 1.2.3 → 2.0.0 (raised on the branch)');
});

test('without VERSION_PARTS the step sets none and adds no commit', () => {
  put(join(slot(), 'apps/web/src/feature.ts'), 'export {};\n'); commitAll(slot(), 'feature');
  const before = git(slot(), 'rev-parse', 'HEAD');
  expect(ctl(['merge', 'work']).code).toBe(0);
  expect(git(slot(), 'rev-parse', 'HEAD')).toBe(before);
});

test('several parts in several languages move apart: only the part whose paths changed goes up', () => {
  put(join(root, 'apps/api/pyproject.toml'), '[tool.other]\nversion = "9.9.9"\n\n[project]\nname = "api"\nversion = "2.0.0"\n');
  put(join(root, 'apps/api/app/main.py'), 'x = 1\n');
  put(join(root, 'apps/engine/Cargo.toml'), '[package]\nname = "engine"\nversion = "0.4.1"\n\n[dependencies.serde]\nversion = "1.0.0"\n');
  put(join(root, 'apps/engine/src/lib.rs'), '\n');
  put(join(root, 'apps/worker/VERSION'), '3.1.0\n'); put(join(root, 'apps/worker/main.go'), 'package main\n');
  versionParts('web apps/web/package.json', 'api apps/api/pyproject.toml', 'engine apps/engine/Cargo.toml', 'worker apps/worker/VERSION');
  land('four parts');
  put(join(slot(), 'apps/api/app/main.py'), 'x = 2\n'); put(join(slot(), 'apps/engine/src/lib.rs'), '// edit\n'); commitAll(slot(), 'api and engine');
  expect(step('--minor=worker').split('\n')).toEqual(['api 2.0.0 → 2.0.1', 'engine 0.4.1 → 0.4.2', 'worker 3.1.0 → 3.2.0']);
  expect(readFileSync(join(slot(), 'apps/api/pyproject.toml'), 'utf8')).toBe('[tool.other]\nversion = "9.9.9"\n\n[project]\nname = "api"\nversion = "2.0.1"\n');
  expect(readFileSync(join(slot(), 'apps/engine/Cargo.toml'), 'utf8')).toContain('[dependencies.serde]\nversion = "1.0.0"');
  expect(readFileSync(join(slot(), 'apps/worker/VERSION'), 'utf8')).toBe('3.2.0\n');
  expect(readFileSync(join(slot(), 'apps/web/package.json'), 'utf8')).toContain('"version": "1.2.3"');
});

test('one version in several manifests moves together, and manifests that disagree stop the step', () => {
  put(join(root, 'apps/api/pyproject.toml'), '[project]\nname = "api"\nversion = "1.2.3"\n');
  versionParts('product apps/web/package.json,apps/api/pyproject.toml apps'); land('one product');
  put(join(slot(), 'apps/api/main.py'), 'x = 1\n'); commitAll(slot(), 'api');
  expect(step()).toBe('product 1.2.3 → 1.2.4');
  expect(readFileSync(join(slot(), 'apps/web/package.json'), 'utf8')).toContain('"version": "1.2.4"');
  expect(readFileSync(join(slot(), 'apps/api/pyproject.toml'), 'utf8')).toContain('version = "1.2.4"');
  git(slot(), 'checkout', '-q', '--', '.');
  put(join(slot(), 'apps/api/pyproject.toml'), '[project]\nname = "api"\nversion = "1.5.0"\n'); commitAll(slot(), 'drift');
  expect(step()).toContain("product's manifests disagree");
});

test('a tag part, such as a Go module, starts at 0.0.0 and is tagged on main only after the gate passes', () => {
  put(join(root, 'apps/cli/go.mod'), 'module example.com/cli\n'); put(join(root, 'apps/cli/main.go'), 'package main\n');
  versionParts('cli tag:apps/cli/v apps/cli'); land('cli');
  put(join(slot(), 'apps/cli/main.go'), 'package main // edit\n'); commitAll(slot(), 'cli edit');
  const branchHead = git(slot(), 'rev-parse', 'HEAD');
  expect(ctl(['merge', 'work'], { FIXTURE_GATE_EXIT: '1' }).code).not.toBe(0);
  expect(git(root, 'tag', '--list')).toBe('');
  const run = ctl(['merge', 'work']);
  expect(run.code, run.err).toBe(0);
  expect(git(slot(), 'rev-parse', 'HEAD')).toBe(branchHead);
  expect(git(root, 'tag', '--list')).toBe('apps/cli/v0.0.1');
  expect(git(root, 'rev-parse', 'apps/cli/v0.0.1^{commit}')).toBe(branchHead);
  expect(run.out).toContain('git push --follow-tags origin main');
  put(join(slot(), 'apps/cli/main.go'), 'package main // again\n'); commitAll(slot(), 'again');
  expect(step('--dry-run')).toBe('cli 0.0.1 → 0.0.2 (tag apps/cli/v0.0.2)');
});

test('refuses an unnamed --minor with several parts, an unknown part, and a manifest with no version', () => {
  put(join(root, 'apps/api/pyproject.toml'), '[project]\nname = "api"\ndynamic = ["version"]\n');
  versionParts('web apps/web/package.json', 'api apps/api/pyproject.toml'); land('dynamic');
  expect(step('--minor')).toContain('name the part: --minor=<part>, one of: web api');
  expect(step('--minor=cli')).toContain('no part named cli');
  expect(step()).toContain('apps/api/pyproject.toml holds no x.y.z version');
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
