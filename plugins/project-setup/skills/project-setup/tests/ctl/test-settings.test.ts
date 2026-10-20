// The TESTING settings of ctl gate and ctl test: a flag wins over the process environment, which
// wins over .env, which wins over the default. The gate loads .env before it reads any of them, and
// a run nested in the gate (each stand-in rung resolves the settings again) sees the gate's values.
// The fixture is no git checkout, so its change set widens to every rung, with no history needed.
import { afterEach, beforeEach, expect, setDefaultTimeout, test } from 'bun:test';
import { allowedCores, fixture, type Fixture } from './gate-fixture';

setDefaultTimeout(60_000);
let f: Fixture;
beforeEach(() => { f = fixture(); });
afterEach(() => f.cleanup());

const cores = allowedCores();
const core = String(cores[0]);
const line = (rung: string) => f.rungs().find(entry => entry.startsWith(`${rung} `)) ?? '';
const lidMiB = () => f.lid().match(/MemoryMax=(\d+)M/g)?.at(-1);
// coreList <n> — the first n cores this test may use, as taskset -c reads them; undefined when it has fewer
const coreList = (n: number) => cores.length >= n ? cores.slice(0, n).join(',') : undefined;

test('with no TESTING keys the gate takes every core, 80 % of the memory available, and derives the jobs', () => {
  f.put('.env', 'API_PORT=8000\n');
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(f.rungs().map(entry => entry.split(' ')[0])).toEqual(['lint', 'typecheck', 'test', 'check']);
  expect(line('lint')).toMatch(/ memory=$/);
  expect(run.out).toContain('every core');
  expect(run.out).toMatch(/compiler job\(s\) per Cargo command \(the default, from \d+ cores and a memory budget of /);
  expect(run.err).toContain('80 % of');
});

test('the default jobs follow both the cores and the memory budget, at 2 GB a job', () => {
  const cases: [string, string, string][] = [[core, '64G', '1'], [core, '2G', '1']];
  const two = coreList(2), four = coreList(4);
  if (two) cases.push([two, '64G', '2'], [two, '2G', '1'], [two, '4G', '2']);
  if (four) cases.push([four, '6G', '3'], [four, '1G', '1']);
  for (const [cpus, memory, jobs] of cases) {
    f.clearRungs();
    f.put('.env', `TEST_CPUS=${cpus}\nTEST_MEMORY=${memory}\n`);
    const run = f.ctl(['gate']);
    expect(run.code, run.all).toBe(0);
    expect(line('test'), `${cpus} ${memory}`).toContain(`jobs=${jobs} `);
  }
});

test('the gate reads the TESTING values from .env before it uses them', () => {
  f.put('.env', `TEST_CPUS=${core}\nTEST_BUILD_JOBS=6\nTEST_MEMORY=1G\n`);
  const run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  for (const rung of ['lint', 'typecheck', 'test', 'check']) {
    expect(line(rung)).toContain(`cores=${core} `);
    expect(line(rung)).toContain('jobs=6 ');
  }
  expect(lidMiB()).toBe('MemoryMax=1024M');
  expect(run.out).toContain('6 compiler job(s) per Cargo command (TEST_BUILD_JOBS)');
});

test('the process environment wins over .env', () => {
  f.put('.env', 'TEST_BUILD_JOBS=6\nTEST_MEMORY=1G\n');
  const run = f.ctl(['gate'], { TEST_BUILD_JOBS: '4', TEST_MEMORY: '2G' });
  expect(run.code, run.all).toBe(0);
  expect(line('lint')).toContain('jobs=4 ');
  expect(lidMiB()).toBe('MemoryMax=2048M');
});

test('CARGO_BUILD_JOBS from the shell wins over TEST_BUILD_JOBS, and a CARGO_BUILD_JOBS line in .env does not', () => {
  f.put('.env', 'TEST_BUILD_JOBS=6\n');
  let run = f.ctl(['gate'], { CARGO_BUILD_JOBS: '3', TEST_BUILD_JOBS: '5' });
  expect(run.code, run.all).toBe(0);
  expect(line('test')).toContain('jobs=3 ');
  f.clearRungs();
  f.put('.env', 'TEST_BUILD_JOBS=6\nCARGO_BUILD_JOBS=9\n');
  run = f.ctl(['gate']);
  expect(run.code, run.all).toBe(0);
  expect(line('test')).toContain('jobs=6 ');
});

test('flags win over the shell and .env, and a nested run keeps the flag values', () => {
  f.put('.env', 'TEST_CPUS=0-99999\nTEST_BUILD_JOBS=6\nTEST_MEMORY=1G\n');
  const run = f.ctl(['gate', '--cpus', core, '--build-jobs', '2', '--memory', '3G'], { CARGO_BUILD_JOBS: '3' });
  expect(run.code, run.all).toBe(0);
  for (const rung of ['lint', 'typecheck', 'test', 'check']) {
    expect(line(rung)).toContain(`cores=${core} `);
    expect(line(rung)).toContain('jobs=2 ');
    expect(line(rung)).toMatch(/ memory=3G$/);
  }
  expect(lidMiB()).toBe('MemoryMax=3072M');
  expect(run.out).toContain('2 compiler job(s) per Cargo command (--build-jobs)');
});

test('a bad value is refused before any rung runs and before the lid, naming where it came from', () => {
  const cases: [string, Record<string, string>, string[], string][] = [
    ['TEST_BUILD_JOBS=abc\n', {}, [], 'TEST_BUILD_JOBS wants a whole number'],
    ['TEST_BUILD_JOBS=0\n', {}, [], 'TEST_BUILD_JOBS wants a whole number'],
    ['', { CARGO_BUILD_JOBS: '-2' }, [], 'CARGO_BUILD_JOBS wants a whole number'],
    ['', {}, ['--build-jobs', 'many'], '--build-jobs wants a whole number'],
    ['TEST_CPUS=0-x\n', {}, [], 'TEST_CPUS wants cores as taskset -c reads them'],
    ['TEST_CPUS=5-2\n', {}, [], 'TEST_CPUS has a backwards range'],
    ['TEST_CPUS=0-99999\n', {}, [], 'cores in 0-99999'],
    ['TEST_MEMORY=lots\n', {}, [], 'TEST_MEMORY wants a size like 8G'],
    ['TEST_MEMORY=10M\n', {}, [], 'TEST_MEMORY wants at least 64M'],
    ['', {}, ['--memory', 'lots'], '--memory wants a size like 8G'],
    ['', {}, ['--cpus'], '--cpus needs a value'],
  ];
  for (const [env, shell, args, message] of cases) {
    f.put('.env', env);
    const run = f.ctl(['gate', ...args], shell);
    expect(run.code, `${env}${JSON.stringify(shell)}${args}: ${run.all}`).toBe(1);
    expect(run.err).toContain(message);
    expect(f.rungs()).toEqual([]);
    expect(f.lid()).toBe('');
  }
});

test('a core named twice is refused, never run on fewer cores than it reads', () => {
  const two = coreList(2);
  if (!two) return;
  f.put('.env', `TEST_CPUS=${two},${cores[0]}\n`);
  const run = f.ctl(['gate']);
  expect(run.code).toBe(1);
  expect(run.err).toContain('name each core once');
});

test('a rung run by name reads the settings too', () => {
  f.put('.env', `TEST_CPUS=${core}\nTEST_BUILD_JOBS=7\n`);
  const run = f.ctl(['gate', 'lint']);
  expect(run.code, run.all).toBe(0);
  expect(line('lint')).toContain(`cores=${core} `);
  expect(line('lint')).toContain('jobs=7 ');
});
