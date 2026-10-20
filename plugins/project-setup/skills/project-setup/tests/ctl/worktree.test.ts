// ctl worktree: named worktrees on a fixed pool of warm slots, a slot's .env, when a branch counts as
// merged, the state checks and the physical path. Each test works in a throwaway git repository
// copied from the template, never in a real checkout.
import { expect, setDefaultTimeout, test } from 'bun:test';
import { existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, realpathSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { W, branchOf, f, mainEnv, nothingCreated, ok, refused, useWorktreeFixture, wt } from './worktree-fixture';

setDefaultTimeout(60_000);
useWorktreeFixture();

const line = (text: string, key: string) => text.split('\n').find(row => row.startsWith(`${key}=`));
// storage <dir> — DATA_DIR, LOGS_DIR and BACKUP_DIR as ctl resolves them in <dir>, through _lib.sh
const storage = (dir: string) => Bun.spawnSync(['bash', '-c',
  'source scripts/common/_lib.sh; require_env; resolve_storage_dirs; printf "%s\\n" "$DATA_DIR" "$LOGS_DIR" "$BACKUP_DIR"'],
  { cwd: dir, env: { PATH: process.env.PATH!, NO_COLOR: '1' } }).stdout.toString().trim().split('\n');

test('create puts slot-1 on a new branch, links the nested name to it, and prints only the path', () => {
  const run = ok(['create', 'feat/login']);
  expect(run.out).toBe(W('feat/login') + '\n');
  expect(readlinkSync(W('feat/login'))).toBe('../slot-1');
  expect(branchOf(W('slot-1'))).toBe('feat/login');
  expect(f.git('rev-parse', 'feat/login')).toBe(f.git('rev-parse', 'HEAD'));
  expect(run.err).toContain('a new branch from HEAD of the main tree');
  // git ignores .worktrees/, so the main tree stays clean.
  expect(f.git('status', '--porcelain')).toBe('');
});

test("a slot's first .env is the main tree's with ports + 100 × n and its own stack name, mode 600", () => {
  ok(['create', 'foo']);
  const env = readFileSync(W('slot-1/.env'), 'utf8');
  expect(line(env, 'API_PORT')).toBe('API_PORT=8100');
  expect(line(env, 'POSTGRES_PORT')).toBe('POSTGRES_PORT=5532');
  expect(line(env, 'WEB_APP_PORT')).toBe('WEB_APP_PORT=5273');
  expect(line(env, 'COMPOSE_PROJECT_NAME')).toBe('COMPOSE_PROJECT_NAME=demo-slot-1');
  expect(line(env, 'ENGINE_URL')).toBe('ENGINE_URL=http://${ENGINE_HOST}:${ENGINE_PORT}');
  expect(line(env, 'BACKUP_DIR')).toBe('BACKUP_DIR=${LOGS_DIR}/backups');
  expect(lstatSync(W('slot-1/.env')).mode & 0o777).toBe(0o600);
  // The storage paths stay relative, so the slot keeps its own data and logs.
  const slot = realpathSync(W('slot-1'));
  expect(storage(W('foo'))).toEqual([`${slot}/data`, `${slot}/logs`, `${slot}/logs/backups`]);
  ok(['create', 'bar']);
  expect(line(readFileSync(W('slot-2/.env'), 'utf8'), 'API_PORT')).toBe('API_PORT=8200');
});

test('a BASE_DIR storage block is copied as it is and resolves inside the slot; an absolute one is refused', () => {
  // The template ships the block: BASE_DIR=., with DATA_DIR, LOGS_DIR and BACKUP_DIR derived from it.
  const block = mainEnv();
  expect(block).toContain('\nBASE_DIR=.\n');
  f.put('.env', block.replace('\nBASE_DIR=.\n', '\nBASE_DIR=/srv/demo\n'));
  expect(refused(['create', 'foo'])).toContain('BASE_DIR is an absolute path, so slot-1 could share the main tree');
  nothingCreated('foo');
  f.put('.env', block);
  ok(['create', 'foo']);
  expect(line(readFileSync(W('slot-1/.env'), 'utf8'), 'DATA_DIR')).toBe('DATA_DIR=${BASE_DIR}/data');
  const slot = realpathSync(W('slot-1'));
  expect(storage(W('foo'))).toEqual([`${slot}/data`, `${slot}/logs`, `${slot}/logs/backups`]);
});

test('an empty COMPOSE_PROJECT_NAME becomes the main folder name, as compose reads it, plus -slot-<n>', () => {
  f.put('.env', mainEnv().replace('COMPOSE_PROJECT_NAME=demo', 'COMPOSE_PROJECT_NAME='));
  ok(['create', 'foo']);
  expect(line(readFileSync(W('slot-1/.env'), 'utf8'), 'COMPOSE_PROJECT_NAME')).toBe('COMPOSE_PROJECT_NAME=demorepo-slot-1');
});

test("a main tree .env that would make a slot reach the main tree's services or files is refused, and nothing changes", () => {
  const cases: [string, string][] = [
    [mainEnv().replace('ENGINE_URL=http://${ENGINE_HOST}:${ENGINE_PORT}', 'ENGINE_URL=http://localhost:8080'),
      'ENGINE_URL names port 8080 as a number; write ${ENGINE_PORT} instead'],
    [mainEnv().replace('DATA_DIR=${BASE_DIR}/data', 'DATA_DIR=/srv/demo'), 'DATA_DIR is an absolute path'],
    [mainEnv().replace('LOGS_DIR=${BASE_DIR}/logs', 'LOGS_DIR=../shared-logs'), 'LOGS_DIR has a .. part'],
    [mainEnv().replace('DATA_DIR=${BASE_DIR}/data', 'DATA_DIR=${HOME}/data'), 'DATA_DIR is built from ${HOME}'],
    [mainEnv().replace('API_PORT=8000\n', ''), 'it lacks API_PORT, which .env.template declares'],
    [mainEnv().replace('API_PORT=8000', 'API_PORT=eighty'), 'API_PORT is neither a port number nor a ${NAME} reference'],
    [mainEnv().replace('API_PORT=8000', 'API_PORT=65500'), 'API_PORT would be 65600 in slot-1, past the last port'],
  ];
  for (const [env, message] of cases) {
    expect(env, `the case for "${message}" changes nothing in the template's .env`).not.toBe(mainEnv());
    f.put('.env', env);
    const err = refused(['create', 'foo']);
    expect(err).toContain(message);
    expect(err).not.toContain('/srv/demo');   // values never print; a value may hold a credential
    nothingCreated('foo');
  }
  rmSync(join(f.root, '.env'));
  expect(refused(['create', 'foo'])).toContain('the main tree has no .env');
  nothingCreated('foo');
});

test("a slot's ports must be clear of the main tree's, every other slot's .env and PORT_PRESETS", () => {
  f.put('.env', mainEnv() + 'EXTRA_PORT=8100\n');
  expect(refused(['create', 'a'])).toContain("slot-1's API_PORT=8100 is the main tree's EXTRA_PORT too (.env)");
  nothingCreated('a');
  f.put('.env', mainEnv());
  // PORT_PRESETS is an array in _lib.sh, so the test sets it there, as a project adapts it.
  const lib = f.read('scripts/common/_lib.sh');
  f.put('scripts/common/_lib.sh', lib.replace('5380 5381 5382 4173', '8100'));
  expect(refused(['create', 'a'])).toContain("slot-1's API_PORT=8100 is a ctl build start port too (PORT_PRESETS)");
  f.put('scripts/common/_lib.sh', lib);
  ok(['create', 'a']); ok(['create', 'b']);
  // slot-2 was edited by hand onto the port slot-3 would get (8000 + 300).
  writeFileSync(W('slot-2/.env'), readFileSync(W('slot-2/.env'), 'utf8').replace('API_PORT=8200', 'API_PORT=8300'));
  expect(refused(['create', 'c'])).toContain("slot-3's API_PORT=8300 is slot-2's API_PORT too (.worktrees/slot-2/.env)");
  expect(existsSync(W('slot-3'))).toBe(false);
  expect(() => f.git('show-ref', '--verify', 'refs/heads/c')).toThrow();
});

test('the pool grows to WORKTREE_SLOTS and then refuses, naming every slot; ctl runs from a named worktree too', () => {
  f.put('.env', mainEnv().replace('WORKTREE_SLOTS=\n', 'WORKTREE_SLOTS=2\n'));
  ok(['create', 'a']);
  ok(['create', 'b'], {}, W('a'));
  expect(readlinkSync(W('b'))).toBe('slot-2');
  expect(refused(['create', 'c'])).toContain('every slot is in use (WORKTREE_SLOTS=2): slot-1 (.worktrees/a) slot-2 (.worktrees/b)');
  // The shell wins over the main tree's .env.
  ok(['create', 'c'], { WORKTREE_SLOTS: '3' });
  expect(refused(['create', 'd'], { WORKTREE_SLOTS: 'many' })).toContain('WORKTREE_SLOTS must be a whole number from 1 to 99');
});

test('create refuses a taken name, a bad or slot- name, --from on an existing branch, and a branch checked out elsewhere', () => {
  mkdirSync(W('taken'), { recursive: true });
  expect(refused(['create', 'taken'])).toContain('.worktrees/taken already exists');
  expect(refused(['create', 'bad..name'])).toContain('is not a usable worktree name');
  expect(refused(['create', '-x'])).toContain('unknown option -x');
  expect(refused(['create', 'slot-9'])).toContain('starts with slot-, which the slot folders use');
  f.git('branch', 'old');
  expect(refused(['create', 'old', '--from', 'HEAD'])).toContain('branch old exists, so --from does not apply');
  expect(refused(['create', 'main'])).toContain(`branch main is checked out at ${realpathSync(f.root)}`);
  expect(refused(['create', 'new', '--from', 'no-such-ref'])).toContain('--from no-such-ref is not a commit');
  expect(existsSync(W('slot-1'))).toBe(false);
  ok(['create', 'feat']);
  expect(refused(['create', 'feat/inner'])).toContain('.worktrees/feat is a worktree link, so it cannot hold .worktrees/feat/inner');
});

test('create switches a slot to a branch that exists, and --from starts a new branch elsewhere', () => {
  f.put('README.md', 'second\n'); f.git('commit', '-q', '-am', 'second');
  f.git('branch', 'old', 'HEAD~1');
  ok(['create', 'old']);
  expect(f.git('-C', W('old'), 'rev-parse', 'HEAD')).toBe(f.git('rev-parse', 'HEAD~1'));
  ok(['create', 'fresh', '--from', 'HEAD~1']);
  expect(branchOf(W('slot-2'))).toBe('fresh');
  expect(f.git('rev-parse', 'fresh')).toBe(f.git('rev-parse', 'HEAD~1'));
});

test('remove refuses changes and untracked files, but not ignored build folders, and refuses until merged into the main tree', () => {
  ok(['create', 'feat/login']);
  const named = W('feat/login');
  writeFileSync(join(named, 'README.md'), 'changed\n');
  expect(refused(['remove', 'feat/login'])).toContain('has uncommitted changes or untracked files');
  f.git('-C', named, 'checkout', '-q', '--', '.');
  writeFileSync(join(named, 'notes.txt'), 'untracked\n');
  expect(refused(['remove', 'feat/login'])).toContain('notes.txt');
  rmSync(join(named, 'notes.txt'));
  mkdirSync(join(named, 'apps/example-engine-rust/target/debug'), { recursive: true });
  writeFileSync(join(named, 'apps/example-engine-rust/target/debug/marker'), 'warm\n');
  writeFileSync(join(named, 'README.md'), 'committed\n');
  f.git('-C', named, 'commit', '-q', '-am', 'work');
  expect(refused(['remove', 'feat/login'])).toMatch(/branch feat\/login is not merged into the main tree \(branch main at [0-9a-f]+\); merge it there first/);
  f.git('merge', '-q', '--ff-only', 'feat/login');
  ok(['remove', 'feat/login']);
  expect(existsSync(W('feat'))).toBe(false);
  expect(branchOf(W('slot-1'))).toBe('');
  expect(f.git('rev-parse', '--verify', 'feat/login')).toBe(f.git('rev-parse', 'HEAD'));
  expect(readFileSync(W('slot-1/apps/example-engine-rust/target/debug/marker'), 'utf8')).toBe('warm\n');
  expect(refused(['remove', 'nothing'])).toContain('no worktree named nothing');
  mkdirSync(W('handmade'));
  expect(refused(['remove', 'handmade'])).toContain('.worktrees/handmade is not a slot link');
});

test('a freed slot is taken again with its build folders and its .env as they were', () => {
  ok(['create', 'foo']);
  mkdirSync(W('foo/apps/example-engine-rust/target'), { recursive: true });
  writeFileSync(W('foo/apps/example-engine-rust/target/marker'), 'warm\n');
  writeFileSync(W('slot-1/.env'), readFileSync(W('slot-1/.env'), 'utf8') + 'MINE=kept\n');
  ok(['remove', 'foo']);
  const run = ok(['create', 'bar']);
  expect(run.err).not.toContain('wrote slot-1/.env');
  expect(readlinkSync(W('bar'))).toBe('slot-1');
  expect(readFileSync(W('bar/apps/example-engine-rust/target/marker'), 'utf8')).toBe('warm\n');
  expect(readFileSync(W('slot-1/.env'), 'utf8')).toContain('MINE=kept');
});

test('list shows each slot with its name or free, clean or dirty, merged, and last use', () => {
  expect(ok(['list']).out).toContain('no slots yet');
  ok(['create', 'foo']); ok(['create', 'bar']); ok(['create', 'gone']); ok(['remove', 'gone']);
  writeFileSync(W('bar/README.md'), 'changed\n');
  writeFileSync(W('foo/NOTES.md'), 'work not in the main tree\n');
  f.git('-C', W('foo'), 'add', 'NOTES.md'); f.git('-C', W('foo'), 'commit', '-q', '-m', 'unmerged');
  const rows = ok(['list']).out.split('\n');
  const row = (slot: string) => rows.find(text => text.startsWith(`${slot} `))!.split(/\s+/);
  expect(row('slot-1').slice(0, 4)).toEqual(['slot-1', 'foo', 'clean', 'no']);
  expect(row('slot-2').slice(0, 4)).toEqual(['slot-2', 'bar', 'dirty', 'yes']);
  expect(row('slot-3').slice(0, 4)).toEqual(['slot-3', 'free', 'clean', '-']);
  expect(rows.join('\n')).toMatch(/slot-1 .* \d{4}-\d{2}-\d{2} \d{2}:\d{2}/);
  expect(rows.join('\n')).toContain(`main tree: ${realpathSync(f.root)}`);
});

test('list warns about a worktree outside .worktrees/', () => {
  f.git('worktree', 'add', '-q', join(f.base, 'outside'), '-b', 'outside');
  expect(ok(['list']).err).toContain(`worktrees outside .worktrees/, which this repo's rules do not allow: ${join(f.base, 'outside')}`);
});

test('a pool whose state does not match the rules is reported, and nothing changes', () => {
  ok(['create', 'foo']); ok(['create', 'bar']);
  unlinkSync(W('foo'));
  let err = refused(['create', 'other']);
  expect(err).toContain('slot-1 is on branch foo, but no .worktrees/foo links to it');
  expect(err).toContain('changed nothing');
  expect(existsSync(W('slot-3'))).toBe(false);
  expect(wt(['list']).code).toBe(1);
  f.git('-C', W('slot-1'), 'switch', '-q', '--detach');
  f.git('-C', W('slot-2'), 'switch', '-q', '-c', 'elsewhere');
  err = refused(['remove', 'bar']);
  expect(err).toContain('slot-2 is on branch elsewhere, but its link is .worktrees/bar');
  expect(existsSync(W('bar'))).toBe(true);
});

test("a branch whose work is in the main tree's HEAD counts as merged, even when rebased in; later work does not", () => {
  ok(['create', 'foo']);
  writeFileSync(W('foo/README.md'), 'feature\n');
  f.git('-C', W('foo'), 'commit', '-q', '-am', 'feature');
  // The main tree moves on, then takes the work by cherry-pick: new commits, so foo is no ancestor of HEAD.
  f.put('LICENSE', 'other work\n'); f.git('commit', '-q', '-am', 'other');
  expect(refused(['remove', 'foo'])).toContain('branch foo is not merged into the main tree');
  f.git('cherry-pick', 'foo');
  expect(() => f.git('merge-base', '--is-ancestor', 'foo', 'HEAD')).toThrow();
  expect(ok(['list']).out.split('\n').find(text => text.startsWith('slot-1 '))).toMatch(/^slot-1\s+foo\s+clean\s+yes\s/);
  ok(['remove', 'foo']);
  ok(['create', 'foo']);
  writeFileSync(W('foo/README.md'), 'more\n');
  f.git('-C', W('foo'), 'commit', '-q', '-am', 'more');
  expect(refused(['remove', 'foo'])).toContain('is not merged into the main tree');
});

test('create refuses while git does not ignore .worktrees/', () => {
  f.put('.gitignore', f.read('.gitignore').replace('/.worktrees/\n', ''));
  f.git('commit', '-q', '-am', 'no ignore');
  expect(refused(['create', 'foo'])).toContain('git does not ignore .worktrees/ here; add /.worktrees/ to .gitignore first');
  expect(existsSync(W())).toBe(false);
});

test("ctl run through a name sees the slot's one physical path as CTL_ROOT, and so does _lib.sh alone", () => {
  ok(['create', 'feat/login']);
  // A worker that prints the CTL_ROOT ctl hands it, in place of the slot's status worker.
  writeFileSync(W('slot-1/scripts/config/status.sh'), 'printf "%s" "$CTL_ROOT"\n');
  const run = f.ctl(['status'], {}, W('feat/login'));
  expect(run.code, run.all).toBe(0);
  expect(run.out).toBe(realpathSync(W('slot-1')));
  const alone = Bun.spawnSync(['bash', '-c', 'source scripts/common/_lib.sh; printf "%s" "$CTL_ROOT"'],
    { cwd: W('feat/login'), env: { PATH: process.env.PATH!, NO_COLOR: '1' } });
  expect(alone.stdout.toString()).toBe(realpathSync(W('slot-1')));
});

test('ctl --help lists the worktree verbs, and ctl worktree --help explains them', () => {
  const help = f.ctl(['--help']);
  for (const verb of ['worktree create <name>', 'worktree list', 'worktree remove <name>', 'worktree trim']) expect(help.out).toContain(verb);
  const own = wt(['--help']);
  expect(own.code).toBe(0);
  expect(own.out).toContain('WORKTREE_ONLY');
  expect(wt(['create', '--help']).out).toContain('Subcommands');
  expect(wt(['nonsense']).code).toBe(1);
});
