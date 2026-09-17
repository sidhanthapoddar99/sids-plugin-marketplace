import { afterEach, beforeEach, expect, test } from 'bun:test';
import { cpSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const template = resolve(import.meta.dir, '../../template');
let root: string, record: string, env: Record<string, string>, command: string[], declarations: string;
const original = `
controller_names() { echo compiler; }
controller_command() { echo 'echo started >> "$CTL_ROOT/starts"; touch "$CTL_ROOT/ready"; trap "exit 0" TERM; while :; do sleep .1; done'; }
controller_probe() { echo 'test -f "$CTL_ROOT/ready"'; }
controller_timeout() { echo 3; }
`;
function start() { return Bun.spawnSync(command, { env }); }
function stop() {
  return Bun.spawnSync(['bash', '-euc', 'source "$1/scripts/common/_lib.sh"; process_stop "$2" "$CTL_ROOT"',
    'bash', root, record], { env });
}
function assertSuccess(result: ReturnType<typeof Bun.spawnSync>) {
  expect(result.exitCode, result.stderr.toString()).toBe(0);
}
function starts() { return readFileSync(join(root, 'starts'), 'utf8').trim().split('\n'); }
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'controller-fixture-'));
  cpSync(join(template, 'scripts'), join(root, 'scripts'), { recursive: true });
  declarations = join(root, 'scripts/dev/_controllers.sh');
  writeFileSync(declarations, original);
  record = join(root, 'logs/run/controller-compiler.process');
  env = { PATH: process.env.PATH!, CTL_ROOT: root, LOGS_DIR: join(root, 'logs'),
    PROCESS_STOP_TIMEOUT: '1', NO_COLOR: '1' };
  command = ['bash', '-euc', 'source "$1/scripts/common/_lib.sh"; source "$1/scripts/dev/_controllers.sh"; '
    + 'resolve_storage_dirs; process_init; controller_ensure compiler; process_release', 'bash', root];
});
afterEach(() => { stop(); rmSync(root, { recursive: true, force: true }); });

test('controller reuse and clean shutdown', () => {
  assertSuccess(start());
  const identity = readFileSync(join(record, 'pid'), 'utf8');
  assertSuccess(start());
  expect(readFileSync(join(record, 'pid'), 'utf8')).toBe(identity);
  expect(starts()).toEqual(['started']);
  assertSuccess(stop()); assertSuccess(start());
  expect(starts()).toEqual(['started', 'started']);
});

test('concurrent startups create one controller', async () => {
  const runners = [Bun.spawn(command, { env, stdout: 'pipe', stderr: 'pipe' }),
    Bun.spawn(command, { env, stdout: 'pipe', stderr: 'pipe' })];
  for (const runner of runners) expect(await runner.exited, await new Response(runner.stderr).text()).toBe(0);
  expect(starts()).toEqual(['started']);
});

for (const state of ['dead', 'reused', 'incomplete', 'killed']) {
  test(`abandoned ${state} owner recovers under kernel lock`, async () => {
    if (state === 'killed') {
      assertSuccess(start());
      process.kill(-Number(readFileSync(join(record, 'pid'), 'utf8').split(' ')[0]), 'SIGKILL');
      await Bun.sleep(100);
    } else {
      mkdirSync(record, { recursive: true });
      if (state === 'dead') writeFileSync(join(record, 'pid'), '99999999 1\n');
      if (state === 'reused') writeFileSync(join(record, 'pid'), `${process.pid} 0\n`);
    }
    assertSuccess(start());
    expect(existsSync(join(root, 'starts'))).toBe(true);
  });
}

test('live unlocked owner is not replaced', async () => {
  const owner = Bun.spawn(['setsid', 'sleep', '60'], { cwd: root });
  try {
    await Bun.sleep(30);
    mkdirSync(record, { recursive: true });
    const raw = readFileSync(`/proc/${owner.pid}/stat`, 'utf8');
    const birth = raw.slice(raw.lastIndexOf(') ') + 2).trim().split(/\s+/)[19];
    writeFileSync(join(record, 'pid'), `${owner.pid} ${birth}\n`);
    writeFileSync(join(record, 'project'), root + '\n');
    expect(start().exitCode).not.toBe(0);
    expect(owner.exitCode).toBeNull();
    expect(existsSync(join(root, 'starts'))).toBe(false);
  } finally { owner.kill('SIGTERM'); await owner.exited; }
});

test('a reusing caller cannot clean up the original controller', () => {
  assertSuccess(start());
  const identity = readFileSync(join(record, 'pid'), 'utf8');
  assertSuccess(Bun.spawnSync(command.map(part => part.replace('process_release', 'process_cleanup')), { env }));
  expect(readFileSync(join(record, 'pid'), 'utf8')).toBe(identity);
  assertSuccess(start());
  expect(starts()).toEqual(['started']);
});

test('failed readiness releases the owned controller and lock', () => {
  writeFileSync(declarations, original.replace('test -f', 'false && test -f').replace('echo 3', 'echo 1'));
  expect(start().exitCode).not.toBe(0);
  expect(existsSync(record)).toBe(false);
  writeFileSync(declarations, original);
  assertSuccess(start());
});
