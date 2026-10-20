// ctl worktree's safety: the busy check that create, remove and the trim share, the trim itself,
// and the main-tree guard. Each test works in a throwaway git repository copied from the template,
// never in a real checkout, and holds only locks inside the system temp folder.
import { expect, setDefaultTimeout, test } from 'bun:test';
import { cpSync, existsSync, mkdirSync, readFileSync, readlinkSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { W, age, cargoProfile, f, liveProcess, mainEnv, ok, refused, spawnKept, useWorktreeFixture } from './worktree-fixture';

setDefaultTimeout(60_000);
useWorktreeFixture();

// holdLock <file> — an exclusive kernel lock on <file>, held by a background process, as a running
// gate or Cargo build holds its lock. It returns once the lock is held. One process holds the lock,
// so killing it releases the lock.
async function holdLock(file: string) {
  const child = spawnKept(['bash', '-c', 'exec 9>>"$1"; flock 9; exec sleep 60', 'hold', file]);
  for (let i = 0; i < 100; i++) {
    if (Bun.spawnSync(['flock', '-n', '-s', file, 'true']).exitCode !== 0) return child;
    await Bun.sleep(20);
  }
  throw new Error(`could not hold ${file}`);
}

test('trim deletes only Cargo outputs unused for N days, and --dry-run deletes nothing', () => {
  ok(['create', 'foo']);
  const plain = cargoProfile(W('slot-1/apps/example-engine-rust/target/debug'));
  // A profile under a target triple, as a WASM build writes it.
  const triple = cargoProfile(W('slot-1/apps/example-engine-rust/target/wasm32-unknown-unknown/debug'), W('slot-1/apps/example-engine-rust/target'));
  // Old files that are no Cargo output: a Cargo-shaped folder without Cargo's tag, data, logs and .env.
  const keep = [W('slot-1/other/target/debug/.fingerprint/x-0123456789abcdef/output'), W('slot-1/other/target/debug/deps/libx.rlib'),
    W('slot-1/data/postgres/base'), W('slot-1/logs/dev/api.log'), W('slot-1/.env')];
  for (const path of keep) { mkdirSync(join(path, '..'), { recursive: true }); if (!existsSync(path)) writeFileSync(path, 'x'); age(path, 30); }
  ok(['list']);   // walks every folder, which must not make an old output look used
  age(W('.trim-stamp'), 2);   // the first create trimmed the empty pool
  const stamp = () => statSync(W('.trim-stamp')).mtimeMs;
  const before = stamp();
  const dry = ok(['trim', '--days', '7', '--dry-run']);
  expect(dry.out).toContain('trim, dry run: 8 Cargo output(s) unused for 7 day(s) would free');
  for (const path of [...plain.old, ...plain.fresh, ...triple.old, ...keep]) expect(existsSync(path), path).toBe(true);
  expect(stamp()).toBe(before);
  const real = ok(['trim', '--days', '7']);
  expect(real.out).toContain('slot-1/apps/example-engine-rust/target/debug: 4 output(s), freed');
  expect(real.out).toContain('slot-1/apps/example-engine-rust/target/wasm32-unknown-unknown/debug: 4 output(s), freed');
  for (const path of [...plain.old, ...triple.old]) expect(existsSync(path), path).toBe(false);
  for (const path of [...plain.fresh, ...triple.fresh, ...keep]) expect(existsSync(path), path).toBe(true);
  expect(stamp()).toBeGreaterThan(before);
  expect(refused(['trim', '--days', '0'])).toContain('--days wants a whole number of days');
});

test('create and remove trim on their own once the last trim is a week old, and not before', () => {
  ok(['create', 'foo']);
  const { old } = cargoProfile(W('slot-1/apps/example-engine-rust/target/debug'));
  age(W('.trim-stamp'), 2);
  const create = ok(['create', 'bar']);
  expect(create.err).not.toContain('trims too');
  expect(create.out).toBe(W('bar') + '\n');
  old.forEach(path => expect(existsSync(path), path).toBe(true));
  age(W('.trim-stamp'), 8);
  expect(ok(['remove', 'bar']).err).toContain('no trim in the last 7 days, so this command trims too');
  old.forEach(path => expect(existsSync(path), path).toBe(false));
});

test('trim skips a profile whose .cargo-lock a running Cargo holds', async () => {
  ok(['create', 'foo']);
  const profile = W('slot-1/apps/example-engine-rust/target/debug');
  const { old } = cargoProfile(profile);
  const cargo = await holdLock(join(profile, '.cargo-lock'));
  expect(ok(['trim']).out).toContain('slot-1/apps/example-engine-rust/target/debug: skipped, Cargo is building there');
  old.forEach(path => expect(existsSync(path), path).toBe(true));
  cargo.kill('SIGKILL'); await Bun.sleep(50);
  ok(['trim']);
  old.forEach(path => expect(existsSync(path), path).toBe(false));
});

test('create and remove refuse while containers of the slot run; a stopped docker passes, a failing one refuses', () => {
  ok(['create', 'foo']);
  writeFileSync(join(f.base, 'docker-running'), 'demo-slot-1\n');
  let err = refused(['remove', 'foo']);
  expect(err).toContain('slot-1 (.worktrees/foo) is in use, so ctl worktree changed nothing');
  expect(err).toContain('1 container(s) of compose project demo-slot-1 run');
  expect(readlinkSync(W('foo'))).toBe('slot-1');
  writeFileSync(join(f.base, 'docker-state'), 'broken');
  expect(refused(['remove', 'foo'])).toContain('Docker did not answer, so ctl cannot tell whether containers of compose project demo-slot-1 run');
  writeFileSync(join(f.base, 'docker-state'), 'stopped');
  ok(['remove', 'foo']);
  // A free slot whose stack still runs is not handed out.
  writeFileSync(join(f.base, 'docker-state'), 'ok');
  err = refused(['create', 'bar']);
  expect(err).toContain('slot-1 is in use');
  expect(existsSync(W('bar'))).toBe(false);
});

test('create and remove refuse while a process ctl recorded in the slot still runs', async () => {
  ok(['create', 'foo']);
  const live = liveProcess();
  mkdirSync(W('slot-1/logs/run/api.process'), { recursive: true });
  writeFileSync(W('slot-1/logs/run/api.process/pid'), `${live.pid} ${live.birth}\n`);
  expect(refused(['remove', 'foo'])).toContain('a process ctl started still runs: logs/run/api.process');
  // A record whose start time does not match is a reused PID, not the recorded process.
  writeFileSync(W('slot-1/logs/run/api.process/pid'), `${live.pid} 1\n`);
  writeFileSync(W('slot-1/logs/run/old.pid'), `${live.pid}\n`);
  expect(refused(['remove', 'foo'])).toContain('a process with a PID-only record still runs: logs/run/old.pid');
  live.child.kill('SIGKILL'); await Bun.sleep(100);
  ok(['remove', 'foo']);
});

test("the busy check reads the slot's own storage paths, whatever absolute ones the caller exports", async () => {
  ok(['create', 'foo']);
  // A process ctl started in the main tree exports its storage paths as absolute paths.
  const main = realpathSync(f.root);
  const exported = { BASE_DIR: main, DATA_DIR: `${main}/data`, LOGS_DIR: `${main}/logs`, BACKUP_DIR: `${main}/logs/backups` };
  const record = (dir: string, pid: number, birth: string) => {
    mkdirSync(join(dir, 'logs/run/api.process'), { recursive: true });
    writeFileSync(join(dir, 'logs/run/api.process/pid'), `${pid} ${birth}\n`);
  };
  const live = liveProcess();
  // The main tree's live record does not make the slot busy...
  record(f.root, live.pid, live.birth);
  ok(['remove', 'foo'], exported);
  ok(['create', 'foo'], exported);
  // ...and the slot's own live record is found, although the caller's LOGS_DIR points elsewhere.
  rmSync(join(f.root, 'logs/run'), { recursive: true });
  record(W('slot-1'), live.pid, live.birth);
  expect(refused(['remove', 'foo'], exported)).toContain('a process ctl started still runs: logs/run/api.process');
});

test('create and remove refuse while a gate run holds the lock for the slot, and not for another checkout', async () => {
  ok(['create', 'foo']);
  const slot = realpathSync(W('slot-1'));
  // A lock every checkout shares names its holder on a checkout= line.
  const shared = join(f.base, 'gate.lock');
  writeFileSync(shared, `checkout=${realpathSync(f.root)}\npid=1\nverb=gate\n`);
  let gate = await holdLock(shared);
  ok(['remove', 'foo'], { GATE_LOCK_FILE: shared });
  ok(['create', 'foo'], { GATE_LOCK_FILE: shared });
  gate.kill('SIGKILL'); await Bun.sleep(50);
  writeFileSync(shared, `checkout=${slot}\npid=1\nverb=gate\n`);
  gate = await holdLock(shared);
  expect(refused(['remove', 'foo'], { GATE_LOCK_FILE: shared })).toContain('a gate run holds the gate lock');
  // A held lock that does not say whose it is counts as busy, because ctl cannot tell.
  writeFileSync(shared, 'pid=1\nverb=gate\n');
  expect(refused(['remove', 'foo'], { GATE_LOCK_FILE: shared })).toContain('a gate run holds the gate lock');
  gate.kill('SIGKILL'); await Bun.sleep(50);
  // A lock file inside the slot belongs to the slot. It sits in logs/, which git ignores, so the
  // worktree stays clean and only the lock can make remove refuse.
  const own = join(slot, 'logs/gate.lock');
  gate = await holdLock(own);
  expect(refused(['remove', 'foo'], { GATE_LOCK_FILE: own })).toContain('a gate run holds the gate lock: logs/gate.lock');
  gate.kill('SIGKILL'); await Bun.sleep(50);
  ok(['remove', 'foo'], { GATE_LOCK_FILE: own });
});

test('the trim, by hand and weekly, skips a slot that is in use and says so', () => {
  ok(['create', 'busy']); ok(['create', 'idle']);
  const busy = cargoProfile(W('slot-1/apps/example-engine-rust/target/debug'));
  const idle = cargoProfile(W('slot-2/apps/example-engine-rust/target/debug'));
  writeFileSync(join(f.base, 'docker-running'), 'demo-slot-1\n');
  const run = ok(['trim', '--days', '7']);
  expect(run.err).toContain('trim skipped slot-1, which is in use: 1 container(s) of compose project demo-slot-1 run');
  busy.old.forEach(path => expect(existsSync(path), path).toBe(true));
  idle.old.forEach(path => expect(existsSync(path), path).toBe(false));
  // The weekly trim that create runs skips it the same way.
  const again = cargoProfile(W('slot-2/apps/example-engine-rust/target/release'));
  age(W('.trim-stamp'), 8);
  expect(ok(['create', 'third']).err).toContain('trim skipped slot-1, which is in use');
  busy.old.forEach(path => expect(existsSync(path), path).toBe(true));
  again.old.forEach(path => expect(existsSync(path), path).toBe(false));
});

test('with WORKTREE_ONLY=1 the build verbs refuse in the main tree, and run in a worktree; setup is never guarded', () => {
  ok(['create', 'foo']);
  // Stand-in workers that only say they ran, so the test sees what the guard let through.
  const stub = 'printf "ran %s\\n" "${BASH_SOURCE[0]##*/scripts/}"\n';
  const workers = ['dev/dev.sh', 'dev/db.sh', 'dev/dev-stop.sh', 'test/test.sh', 'gate/all.sh', 'container/build.sh', 'test/build.sh', 'config/setup.sh'];
  for (const dir of [f.root, W('slot-1')]) for (const worker of workers) writeFileSync(join(dir, 'scripts', worker), stub);
  f.put('.env', mainEnv().replace('WORKTREE_ONLY=\n', 'WORKTREE_ONLY=1\n'));
  for (const args of [['dev'], ['test', 'api'], ['gate'], ['build'], ['build', 'save']]) {
    const run = f.ctl(args);
    expect(run.code, args.join(' ')).toBe(1);
    expect(run.err).toContain(`ctl ${args[0]} writes build outputs into this checkout, and WORKTREE_ONLY=1 keeps the main tree`);
    expect(run.err).toContain('ctl worktree create <name>');
  }
  // Help anywhere, a frozen build's start and clean, the data core alone, stopping the dev apps,
  // setup and ctl worktree pass.
  for (const args of [['gate', '--help'], ['test', 'api', '-h'], ['build', 'start'], ['build', 'clean'], ['dev', 'db'], ['dev', 'stop'], ['setup'], ['worktree', 'list']]) {
    const run = f.ctl(args);
    expect(run.code, `${args.join(' ')}: ${run.all}`).toBe(0);
  }
  expect(f.ctl(['setup']).out).toContain('ran config/setup.sh');
  expect(f.ctl(['dev', 'db']).out).toContain('ran dev/db.sh');
  expect(f.ctl(['dev', 'stop']).out).toContain('ran dev/dev-stop.sh');
  // The shell wins over .env, including an empty value.
  expect(f.ctl(['gate'], { WORKTREE_ONLY: '' }).out).toContain('ran gate/all.sh');
  // A worktree is never the main tree, whatever its .env says.
  writeFileSync(W('slot-1/.env'), readFileSync(W('slot-1/.env'), 'utf8').replace('WORKTREE_ONLY=\n', 'WORKTREE_ONLY=1\n'));
  const inside = f.ctl(['gate'], {}, W('foo'));
  expect(inside.code, inside.all).toBe(0);
  expect(inside.out).toContain('ran gate/all.sh');
  f.put('.env', mainEnv().replace('WORKTREE_ONLY=\n', 'WORKTREE_ONLY=yes\n'));
  expect(f.ctl(['gate']).err).toContain('WORKTREE_ONLY must be empty, 0 or 1 (got: yes)');
});

test('outside a git checkout the guard has no main tree to keep, so the build verbs run', () => {
  const copy = join(f.base, 'exported');
  cpSync(f.root, copy, { recursive: true, filter: source => !/\/\.(git|worktrees)(\/|$)/.test(source) });
  writeFileSync(join(copy, 'scripts/gate/all.sh'), 'printf "ran\\n"\n');
  writeFileSync(join(copy, '.env'), mainEnv().replace('WORKTREE_ONLY=\n', 'WORKTREE_ONLY=1\n'));
  const run = f.ctl(['gate'], {}, copy);
  expect(run.code, run.all).toBe(0);
  expect(run.out).toBe('ran\n');
});
