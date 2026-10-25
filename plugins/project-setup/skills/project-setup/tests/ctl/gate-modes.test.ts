// What ctl gate runs in each of its modes: changed (the default, the uncommitted changes), delta
// (the changes since a branch, a commit or a date-time) and all. The fixture is a throwaway git
// repository shaped like the template, with stand-in rungs that record their arguments.
import { afterEach, beforeEach, expect, setDefaultTimeout, test } from 'bun:test';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { appFiles, fixture, type Fixture } from './gate-fixture';

setDefaultTimeout(60_000);
let f: Fixture;
// The fixture's history on main, in the fixture's time zone (+05:30).
let first: string, second: string, third: string;
beforeEach(() => {
  f = fixture();
  for (const file of appFiles) f.put(file, 'first\n');
  f.git('init', '-q');
  first = f.commitAt('2026-01-10 12:00:00 +0530', 'base');
  f.put('apps/example-multi-web-app/app/src/main.ts', 'second\n');
  second = f.commitAt('2026-01-11 09:30:00 +0530', 'app');
  f.put('apps/example-api-python/app/main.py', 'third\n');
  third = f.commitAt('2026-01-12 18:45:30 +0530', 'api');
});
afterEach(() => f.cleanup());

// plan <args…> — the dry run's selection, one entry per rung
function plan(...args: string[]) {
  const run = f.ctl(['gate', ...args, '--dry-run']);
  expect(run.code, run.all).toBe(0);
  return Object.fromEntries(run.out.split('\n').map(line => line.match(/^ {2}(lint|typecheck|test|check): (.*)$/)).filter(Boolean)
    .map(match => [match![1], match![2]]));
}
const narrowed = (lint: string, typecheck = lint, tests = lint) => ({ lint, typecheck, test: tests, check: 'runs (always)' });
const skipped = narrowed('not reached — skipped');
const everything = narrowed('every target');
const refusal = (args: string[]) => { const run = f.ctl(['gate', ...args]); expect(run.code, run.all).toBe(1); expect(f.rungs()).toEqual([]); return run.err; };
const rungArgs = () => f.rungs().map(entry => entry.split(' cores=')[0]);
const restore = () => { f.git('checkout', '-q', '--', '.'); f.git('clean', '-q', '-fd'); };

test('changed, the default: a clean tree reaches only check, and the run says there were no changes', () => {
  expect(plan()).toEqual(skipped);
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(rungArgs()).toEqual(['check args=[]']);
  expect(run.out).toContain('no uncommitted changes — ran check only');
});

test('changed: each app path selects its own target, and the migrations reach the backends too', () => {
  const cases: [string[], ReturnType<typeof narrowed>][] = [
    [['apps/example-multi-web-app/app/src/main.ts'], narrowed('app')],
    [['apps/example-multi-web-app/docs/src/index.ts'], narrowed('docs')],
    [['apps/example-api-python/app/main.py'], narrowed('api')],
    [['apps/example-tui-go/main.go'], narrowed('cli')],
    // typecheck has no database target, so it gets only the backends the schema reaches
    [['apps/database/postgres/migrations/V1__start.sql'], narrowed('api database engine', 'api engine')],
    [['apps/example-multi-web-app/app/src/main.ts', 'apps/example-api-python/app/main.py'], narrowed('api app')],
  ];
  for (const [paths, expected] of cases) {
    restore();
    for (const path of paths) f.put(path, 'changed\n');
    expect(plan(), paths.join(' ')).toEqual(expected);
  }
});

test('changed: an untracked file counts, and a deleted one does too', () => {
  f.put('apps/example-multi-web-app/app/src/new.ts', 'new\n');
  expect(plan()).toEqual(narrowed('app'));
  rmSync(join(f.root, 'apps/example-multi-web-app/app/src/new.ts'));
  rmSync(join(f.root, 'apps/example-api-python/app/main.py'));
  expect(plan()).toEqual(narrowed('api'));
});

test('changed: a deleted app counts as changed, but no rung runs on a folder that is gone', () => {
  rmSync(join(f.root, 'apps/example-tui-go'), { recursive: true });
  const run = f.ctl(['gate', '--dry-run']);
  expect(run.out).toContain('apps/example-tui-go/main.go → cli');
  expect(plan()).toEqual(skipped);
});

test('changed: docker/ and documentation reach only check, in an app folder too', () => {
  f.put('README.md', 'changed\n'); f.put('AGENTS.md', 'changed\n'); f.put('CLAUDE.md', '@AGENTS.md\n'); f.put('docker/compose.base.yaml', 'changed\n');
  f.put('apps/example-api-python/README.md', 'changed\n'); f.put('notes/plan.md', 'changed\n');
  expect(plan()).toEqual(skipped);
});

test('changed: ctl, scripts, the toolchain file, a shared package, root config and unmapped paths reach everything', () => {
  for (const path of ['ctl', 'scripts/gate/_changed.sh', '.mise.toml', 'apps/packages/ui/src/index.ts', '.env.template',
    'apps/example-multi-web-app/nginx/nginx.conf.template', 'notes/idea.txt']) {
    restore();
    // Append, so ctl and the scripts still run after the change.
    mkdirSync(dirname(join(f.root, path)), { recursive: true }); appendFileSync(join(f.root, path), '\n# changed\n');
    expect(plan(), path).toEqual(everything);
  }
});

test('--changed is the default run said outright, and takes no base', () => {
  f.put('apps/example-multi-web-app/app/src/main.ts', 'changed\n');
  expect(plan('--changed')).toEqual(plan());
  expect(refusal(['--changed', 'main'])).toContain('--changed takes no base; for changes since main, use --delta main');
  expect(refusal(['--changed=main'])).toContain('use --delta main');
  // A group after --changed is no base.
  expect(plan('--changed', 'static')).toEqual({ lint: 'app', typecheck: 'app', check: 'runs (always)' });
});

test('a partial run passes its targets to each rung, runs check, and names what the changes did not reach', () => {
  f.put('apps/example-multi-web-app/app/src/main.ts', 'changed\n');
  f.put('apps/example-api-python/app/main.py', 'changed\n');
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(rungArgs()).toEqual(['lint args=[api app]', 'typecheck args=[api app]', 'test args=[api app]', 'check args=[]']);
  expect(run.out).toContain('gate green for the uncommitted changes only, a PARTIAL run — ran: lint (api app) typecheck (api app) test (api app) check');
  expect(run.out).toContain('skipped, not reached by the changes: lint (database engine docs cli) typecheck (engine docs cli) test (database engine docs cli)');
  expect(run.out).not.toContain('--all');
});

test('a change to shared tooling widens the run to the full ladder, and the closing line says why', () => {
  f.put('.gitignore', f.read('.gitignore') + '# changed\n');
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(rungArgs()).toEqual(['lint args=[]', 'typecheck args=[]', 'test args=[]', 'check args=[]']);
  expect(run.out).toContain('.gitignore → everything (root config)');
  expect(run.out).toContain('the uncommitted changes reach shared tooling or a path no rule maps (listed above), so the selection widened to every target');
});

test('a long change set prints its first paths, and always the path that widened the run', () => {
  for (let i = 0; i < 45; i++) f.put(`apps/example-multi-web-app/app/src/file${String(i).padStart(2, '0')}.ts`, 'new\n');
  f.put('zz-root-config', 'new\n');
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(run.out).toContain('zz-root-config → everything (root config)');
  expect(run.out).toContain('… and 5 more path(s)');
  expect(run.out).not.toContain('file44.ts');
  expect(f.ctl(['gate', '--dry-run']).out).toContain('file44.ts → app');
});

test('delta: a branch, a short hash, a date and a date-time each name a base, printed before the run', () => {
  const header = (...args: string[]) => f.ctl(['gate', ...args, '--dry-run']).out.split('\n')[0];
  // A date means its first moment, so 2026-01-12 is the last commit before that day began.
  expect(plan('--delta', '2026-01-12')).toEqual(narrowed('api'));
  expect(header('--delta', '2026-01-12')).toBe(`▸ delta since 2026-01-12 → ${second} (2026-01-11 09:30) app`);
  // At or before, to the second, in local time.
  expect(plan('--delta', '2026-01-11 09:29')).toEqual(narrowed('api app'));
  expect(plan('--delta', '2026-01-11T09:30')).toEqual(narrowed('api'));
  expect(plan('--delta', '2026-01-12 18:45:30')).toEqual(skipped);
  expect(plan('--delta', first)).toEqual(narrowed('api app'));
  expect(header('--delta', first)).toBe(`▸ delta since ${first} → ${first} (2026-01-10 12:00) base`);
  // A branch counts from its merge base with HEAD, and uncommitted files count too.
  f.git('checkout', '-q', '-b', 'work');
  f.put('apps/example-multi-web-app/app/src/main.ts', 'committed\n'); f.commitAt('2026-01-13 10:00:00 +0530', 'app again');
  f.put('docker/compose.base.yaml', 'uncommitted\n');
  expect(plan()).toEqual(skipped);
  expect(plan('--delta', 'main')).toEqual(narrowed('app'));
  expect(header('--delta', 'main')).toBe(`▸ delta since main → ${third} (2026-01-12 18:45) api`);
});

test('delta: a base off HEAD\'s line starts at the merge base, and the run says so', () => {
  f.git('checkout', '-q', '-b', 'side', first);
  f.put('apps/example-tui-go/main.go', 'side\n'); f.commitAt('2026-01-11 10:00:00 +0530', 'side');
  f.git('checkout', '-q', 'main');
  const run = f.ctl(['gate', '--delta', 'side', '--dry-run']);
  expect(run.out).toContain(`the delta starts at their merge base: ${first}`);
  expect(plan('--delta', 'side')).toEqual(narrowed('api app'));
});

test('delta: after a merge, ORIG_HEAD names what the target branch held, so the run covers what the merge brought in', () => {
  f.git('checkout', '-q', '-b', 'side', third);
  f.put('apps/example-tui-go/main.go', 'side\n'); f.commitAt('2026-01-13 10:00:00 +0530', 'side');
  f.git('checkout', '-q', 'main');
  f.put('apps/example-engine-rust/crates/api/src/main.rs', 'main\n'); f.commitAt('2026-01-13 11:00:00 +0530', 'engine');
  f.git('-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'merge', '-q', '--no-ff', '-m', 'merge side', 'side');
  // main is HEAD now, so the delta since main is empty and only check would run.
  expect(plan('--delta', 'main')).toEqual(skipped);
  expect(plan('--delta', 'ORIG_HEAD')).toEqual(narrowed('cli'));
});

test('delta: the closing line says the run was partial and names the base', () => {
  const run = f.ctl(['gate', '--delta', second]);
  expect(run.code, run.all).toBe(0);
  expect(rungArgs()).toEqual(['lint args=[api]', 'typecheck args=[api]', 'test args=[api]', 'check args=[]']);
  expect(run.out).toContain(`gate green for the changes since ${second} (${second}) only, a PARTIAL run`);
});

test('delta: a date before the first commit, junk text, a date that does not exist and a name that is also a date are refused', () => {
  expect(refusal(['--delta', '2026-01-09'])).toContain("no commit on HEAD's first-parent line is at or before 2026-01-09");
  expect(refusal(['--delta', 'last tuesday'])).toContain('is neither a branch or commit here nor a date-time');
  expect(refusal(['--delta', 'yesterday'])).toContain('is neither a branch or commit here nor a date-time');
  expect(refusal(['--delta', '2026-02-30'])).toContain('2026-02-30 is not a real date and time');
  expect(refusal(['--delta', '2026-01-11 9:30'])).toContain('is neither a branch or commit here nor a date-time');
  expect(refusal(['--delta', 'main@{yesterday}'])).toContain('reflog date');
  expect(refusal(['--delta'])).toContain('--delta needs a value');
  f.git('branch', '2026-01-11');
  expect(refusal(['--delta', '2026-01-11'])).toContain('both a date-time and a git name');
});

test('all: --all, or all as a word, runs every rung on every target whatever changed', () => {
  for (const args of [['--all'], ['all']]) {
    f.clearRungs();
    const run = f.ctl(['gate', ...args]);
    expect(run.code, run.all).toBe(0);
    expect(rungArgs()).toEqual(['lint args=[]', 'typecheck args=[]', 'test args=[]', 'check args=[]']);
    expect(run.out).toContain('gate --all green — every target of lint typecheck test check');
  }
  f.clearRungs();
  expect(f.ctl(['gate', '--all', 'static']).code).toBe(0);
  expect(rungArgs()).toEqual(['lint args=[]', 'typecheck args=[]', 'check args=[]']);
});

test('one mode at a time, and --dry-run goes with every mode but --all and runs nothing', () => {
  for (const args of [['--delta', 'main', '--all'], ['--changed', '--all'], ['--changed', '--delta', 'main'], ['all', '--delta', 'main']])
    expect(refusal(args), args.join(' ')).toContain('--changed, --delta and --all each choose what runs; give one of them');
  expect(refusal(['--all', '--dry-run'])).toContain('--dry-run shows what a changed-only run selects');
  f.put('apps/example-multi-web-app/app/src/main.ts', 'changed\n');
  for (const args of [[], ['--changed'], ['--delta', third]]) {
    const run = f.ctl(['gate', ...args, '--dry-run']);
    expect(run.code, run.all).toBe(0);
    expect(run.out).toContain('apps/example-multi-web-app/app/src/main.ts → app');
  }
  expect(f.rungs()).toEqual([]);
  expect(f.lid()).toBe('');
});

test('a group no change reaches runs nothing and says so', () => {
  f.put('README.md', 'changed\n');
  const run = f.ctl(['gate', 'dynamic']);
  expect(run.code, run.all).toBe(0);
  expect(f.rungs()).toEqual([]);
  expect(run.out).toContain('nothing to run — 1 changed path(s), and they reach no dynamic rung · skipped, not reached by the changes: test');
});

test('a repository with no commit yet counts every file, so the run widens', () => {
  const fresh = fixture();
  try {
    for (const file of appFiles) fresh.put(file, 'first\n');
    fresh.git('init', '-q');
    const run = fresh.ctl(['gate', '--dry-run']);
    expect(run.code, run.all).toBe(0);
    expect(run.out).toContain('no commit yet, so every file counts as changed');
    expect(run.out).toContain('ctl → everything');
  } finally { fresh.cleanup(); }
});

test('outside a git checkout there is no change set: the run widens, and --delta is refused', () => {
  const loose = fixture();
  try {
    const run = loose.ctl(['gate']);
    expect(run.code, run.all).toBe(0);
    expect(run.out).toContain('no change set: this is no git checkout');
    expect(run.out).toContain('gate green — this is no git checkout, so the selection widened to every target');
    expect(loose.rungs().map(entry => entry.split(' cores=')[0])).toEqual(['lint args=[]', 'typecheck args=[]', 'test args=[]', 'check args=[]']);
    const delta = loose.ctl(['gate', '--delta', 'main']);
    expect(delta.code).toBe(1);
    expect(delta.err).toContain('--delta needs a git checkout');
  } finally { loose.cleanup(); }
});

test('a ctl root inside a larger repository sees only its own changes, by its own paths', () => {
  const nested = fixture({ at: 'outer/project' });
  try {
    for (const file of appFiles) nested.put(file, 'first\n');
    const outer = join(nested.base, 'outer');
    nested.gitAt(outer, 'init', '-q');
    nested.gitAt(outer, 'add', '-A');
    nested.gitAt(outer, 'commit', '-q', '-m', 'base');
    nested.put('apps/example-api-python/app/main.py', 'changed\n');
    mkdirSync(join(outer, 'elsewhere'));
    appendFileSync(join(outer, 'elsewhere/file.txt'), 'outside the ctl root\n');
    const run = nested.ctl(['gate', '--dry-run']);
    expect(run.code, run.all).toBe(0);
    expect(run.out).toContain('1 changed path(s)');
    expect(run.out).toContain('apps/example-api-python/app/main.py → api');
  } finally { nested.cleanup(); }
});

test('GATE_REACHES may name only rows of GATE_TARGETS, in every mode, so a rename cannot drop a target quietly', () => {
  f.put('scripts/gate/_changed.sh', f.read('scripts/gate/_changed.sh').replace('[database]="api engine"', '[database]="api backend"'));
  f.commitAt('2026-01-13 10:00:00 +0530', 'rename');
  for (const args of [['gate', '--dry-run'], ['gate', '--all']]) {
    const run = f.ctl(args);
    expect(run.code, args.join(' ')).toBe(1);
    expect(run.err).toContain("GATE_REACHES in scripts/gate/_changed.sh names 'backend', which is no row of GATE_TARGETS");
  }
  expect(f.rungs()).toEqual([]);
});

test('a tree that already passed with the same base runs nothing, and --rerun runs it again', () => {
  f.put('apps/example-api-python/app/main.py', 'changed\n');
  expect(f.ctl(['gate']).code).toBe(0);
  f.clearRungs();
  const again = f.again(['gate']);
  expect(again.code, again.all).toBe(0);
  expect(again.out).toContain('already green on this tree');
  expect(f.rungs()).toEqual([]);
  expect(f.again(['gate', '--rerun']).code).toBe(0);
  expect(f.rungs().length).toBeGreaterThan(0);
});

test('an edit after a green run, or another base, runs again; a commit of the checked work keeps the receipt for its delta', () => {
  f.put('apps/example-api-python/app/main.py', 'changed\n');
  const start = f.git('rev-parse', 'HEAD').trim();
  expect(f.ctl(['gate']).code).toBe(0);
  f.clearRungs();
  f.put('apps/example-api-python/app/main.py', 'changed again\n');
  expect(f.again(['gate']).out).not.toContain('already green');
  f.clearRungs();
  f.git('add', '-A'); f.git('commit', '-qm', 'work');
  const delta = f.again(['gate', '--delta', start]);
  expect(delta.out, delta.all).toContain('already green on this tree');
  expect(f.again(['gate', '--delta', second]).out).not.toContain('already green');
});

test('an --all run covers a changed run of the same tree, and a red run records no whole-gate receipt', () => {
  expect(f.ctl(['gate', '--all']).code).toBe(0);
  f.clearRungs();
  expect(f.again(['gate']).out).toContain('already green on this tree');
  const wholeGate = () => readdirSync(join(f.root, '.git/ctl-gate-green')).filter(name => !name.includes('.rung-'));
  f.put('apps/example-api-python/app/main.py', 'red\n');
  f.put('scripts/gate/check.sh', 'exit 3\n', true);
  expect(f.ctl(['gate']).code).not.toBe(0);
  expect(wholeGate()).toEqual([]);
});

test('a same-size edit in the second of the last commit is part of the tree the receipt names', () => {
  // Git trusts a file's cached size and times unless the file is as new as the index. The edit keeps
  // the size and lands in the second of the commit, so only that check finds it; the gate runs a
  // second later, so a copy of the index stamped then would hide the edit.
  const file = 'apps/example-api-python/app/main.py';
  let same = false;
  for (let attempt = 0; attempt < 5 && !same; attempt++) {
    while (Date.now() % 1000 > 100) Bun.sleepSync(5);
    f.put(file, `aaa${attempt}\n`);
    f.git('add', '-A'); f.git('commit', '-qm', 'same size');
    f.put(file, `bbb${attempt}\n`);
    const second = (path: string) => Math.floor(statSync(join(f.root, path)).ctimeMs / 1000);
    same = second(file) === second('.git/index');
  }
  expect(same).toBe(true);
  Bun.sleepSync(1100);
  expect(f.ctl(['gate']).code).toBe(0);
  // The tree as git hashes it with no cached stat: a fresh index, every file read.
  const index = join(mkdtempSync(join(tmpdir(), 'tree-')), 'index');
  const tree = f.bash('git add -A -- . && git write-tree', { GIT_INDEX_FILE: index }).out.trim();
  rmSync(dirname(index), { recursive: true, force: true });
  const named = readdirSync(join(f.root, '.git/ctl-gate-green')).filter(name => !name.includes('.rung-'));
  expect(named.map(name => name.split('.')[0])).toEqual([tree]);
});

test('a run that went red at one rung reruns from that rung while the tree is unchanged', () => {
  f.put('apps/example-api-python/app/main.py', 'changed\n');
  f.put('scripts/gate/check.sh', 'exit 3\n', true);
  expect(f.ctl(['gate']).code).not.toBe(0);
  f.clearRungs();
  const again = f.again(['gate']);
  expect(again.code, again.all).not.toBe(0);
  for (const rung of ['lint', 'typecheck', 'test']) expect(again.out).toContain(`gate ${rung}: already green on this tree`);
  expect(f.rungs()).toEqual([]);
  f.clearRungs();
  expect(f.again(['gate', '--rerun']).code).not.toBe(0);
  expect(f.rungs().length).toBeGreaterThan(0);
});
