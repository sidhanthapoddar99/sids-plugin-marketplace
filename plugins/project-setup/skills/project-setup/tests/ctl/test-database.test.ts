// ctl test and the throwaway PostgreSQL a run owns (scripts/test/_test-database.sh), against a fake
// docker that records its calls: one server per run, migrated once, one database copy per db suite,
// the caller's own database, the sweep of leftovers, and the server's removal when the run ends. A
// suite marked `db workers` on more than one worker gets one server per worker, each migrated, and
// its copy on each; a stand-in uv records the pytest flags and the settings the suite got.
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fixture, type Fixture } from './gate-fixture';

let f: Fixture;
const calls = () => existsSync(join(f.base, 'docker.calls')) ? readFileSync(join(f.base, 'docker.calls'), 'utf8').trim().split('\n') : [];
const seen = () => existsSync(join(f.base, 'seen.env')) ? readFileSync(join(f.base, 'seen.env'), 'utf8') : '';
const withCore = { DATA_SVCS_STR: 'postgres' };

beforeEach(() => {
  f = fixture({ standIns: false });
  // The fake docker: compose names the images, `run -d` starts server-<n> (or fails when start-exit-<n>
  // exists), `run --rm` is Flyway (it exits with flyway-exit, or with flyway-exit-<server> on that
  // server alone), `port` gives server <n> port 23455+n, `exec` of a CREATE DATABASE fails on a server
  // with copy-exit-<server>, `ps` lists what ps.txt holds.
  writeFileSync(join(f.base, 'bin/docker'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> '${f.base}/docker.calls'
case $1 in
  compose) [[ " $* " == *" config "* ]] && echo '{"name":"fixture","services":{"postgres":{"image":"postgres:18"},"migrate":{"image":"fixture/migrate:dev"}}}'
           exit 0 ;;
  run) if [[ " $* " == *" -d "* ]]; then n=$(( $(cat '${f.base}/servers' 2>/dev/null || echo 0) + 1 ))
         echo "$n" > '${f.base}/servers'; [[ -f '${f.base}/start-exit-'$n ]] && exit 1; echo "server-$n"; exit 0; fi
       server=$(sed -n 's/.*--network container:\\(server-[0-9]*\\).*/\\1/p' <<< "$*")
       echo "flyway on $server"
       exit "$(cat "${f.base}/flyway-exit-$server" 2>/dev/null || cat '${f.base}/flyway-exit' 2>/dev/null || echo 0)" ;;
  port) echo "127.0.0.1:$(( 23455 + \${2#server-} ))" ;;
  exec) [[ " $* " == *" CREATE DATABASE "* && -f "${f.base}/copy-exit-$2" ]] && { echo "copy on $2" >&2; exit 1; } ;;
  ps) cat '${f.base}/ps.txt' 2>/dev/null || true ;;
esac
exit 0
`, { mode: 0o755 });
  // The stand-in uv: `uv run pytest <flags>` records its flags and the database settings it got.
  writeFileSync(join(f.base, 'bin/uv'), `#!/usr/bin/env bash
[[ $1 == --version ]] && { echo 'uv 0.0.0'; exit 0; }
printf 'args=%s\\nDATABASE_URL=%s\\nTEST_DATABASE_URLS=%s\\nTEST_DATABASE_TEMPLATE=%s\\n' "$*" "\${DATABASE_URL:-}" "\${TEST_DATABASE_URLS:-}" "\${TEST_DATABASE_TEMPLATE:-}" > '${f.base}/pytest.seen'
`, { mode: 0o755 });
  // Two apps: probe reads the database, plain does not. Each records the settings it ran with.
  const targets = f.read('scripts/gate/_targets.sh');
  const start = targets.indexOf('GATE_TARGETS=('), end = targets.indexOf(')\n', start);
  f.put('scripts/gate/_targets.sh', targets.slice(0, start) +
    'GATE_TARGETS=(\n  "probe apps/probe bun test db"\n  "other apps/other bun test db"\n  "plain apps/plain bun test"\n' +
    '  "pyw apps/pyw python test db workers"\n' + targets.slice(end));
  for (const name of ['probe', 'other', 'plain']) {
    f.put(`apps/${name}/package.json`, JSON.stringify({ scripts: { test: `printf '${name} %s\\n' "\${DATABASE_URL:-none}" >> '${f.base}/seen.env'` } }));
    f.put(`apps/${name}/one.test.ts`, '');
  }
  f.put('apps/pyw/tests/test_one.py', '');
});
afterEach(() => f.cleanup());

describe('a db suite', () => {
  test('runs against the run\'s own server: the dev image on tmpfs, migrated once, then removed', () => {
    const result = f.ctl(['test', 'probe'], withCore);
    expect(result.code, result.all).toBe(0);
    const server = calls().find(call => call.startsWith('run -d '))!;
    expect(server).toContain('--tmpfs /var/lib/postgresql');
    expect(server).toContain('-c fsync=off');
    expect(server).toContain(`--label ctl.test-database.root=${f.root}`);
    expect(server).toMatch(/-p 127\.0\.0\.1::5432 postgres:18 /);
    const flyway = calls().filter(call => call.startsWith('run --rm '));
    expect(flyway.length).toBe(1);
    expect(flyway[0]).toContain('--network container:server-1');
    expect(flyway[0]).toContain('FLYWAY_URL=jdbc:postgresql://127.0.0.1:5432/test_template');
    expect(flyway[0]).toMatch(/fixture\/migrate:dev migrate$/);
    expect(calls().at(-1)).toBe('rm -f server-1');
    expect(seen()).toMatch(/^probe postgresql:\/\/test:[0-9a-f]{32}@127\.0\.0\.1:23456\/test_probe\n$/);
  });

  test('each db suite gets its own copy of the migrated database, and the server starts once', () => {
    const result = f.ctl(['test', 'probe', 'other', 'plain'], withCore);
    expect(result.code, result.all).toBe(0);
    expect(calls().filter(call => call.startsWith('run -d ')).length).toBe(1);
    expect(calls().filter(call => call.startsWith('run --rm ')).length).toBe(1);
    for (const name of ['probe', 'other'])
      expect(calls()).toContain(`exec server-1 psql -q -v ON_ERROR_STOP=1 -U test -d postgres -c CREATE DATABASE "test_${name}" TEMPLATE test_template`);
    expect(seen()).toContain('/test_probe\n');
    expect(seen()).toContain('/test_other\n');
    expect(seen()).toContain('plain none\n');
  });

  test('a run with no db suite starts no server', () => {
    expect(f.ctl(['test', 'plain'], withCore).code).toBe(0);
    expect(calls().filter(call => call.startsWith('run '))).toEqual([]);
  });

  test('a caller\'s TEST_DATABASE_URL is used as it is, and no server starts', () => {
    const result = f.ctl(['test', 'probe'], { ...withCore, TEST_DATABASE_URL: 'postgresql://ci@db:5432/ci' });
    expect(result.code, result.all).toBe(0);
    expect(calls().filter(call => call.startsWith('run '))).toEqual([]);
    expect(seen()).toBe('probe postgresql://ci@db:5432/ci\n');
  });

  test('a project with no postgres in its data core starts no server', () => {
    expect(f.ctl(['test', 'probe']).code).toBe(0);
    expect(calls()).toEqual([]);
    expect(seen()).toBe('probe none\n');
  });

  test('failed migrations stop the run by name and remove the server', () => {
    writeFileSync(join(f.base, 'flyway-exit'), '1\n');
    const result = f.ctl(['test', 'probe'], withCore);
    expect(result.code).not.toBe(0);
    expect(result.err).toContain('the migrations failed on the test database');
    expect(calls().at(-1)).toBe('rm -f server-1');
    expect(seen()).toBe('');
  });

  test('a server whose run is gone is removed first, and a live run keeps its own', () => {
    const identity = (pid: number) => readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1].split(' ')[19];
    writeFileSync(join(f.base, 'ps.txt'), `dead-1 999999999:1\nlive-1 ${process.pid}:${identity(process.pid)}\n`);
    expect(f.ctl(['test', 'probe'], withCore).code).toBe(0);
    expect(calls()).toContain('rm -f dead-1');
    expect(calls()).not.toContain('rm -f live-1');
  });
});

// pytest.seen as settings: the flags uv got and the database settings the suite ran with
const pytestSeen = () => Object.fromEntries(readFileSync(join(f.base, 'pytest.seen'), 'utf8').trim().split('\n')
  .map(line => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)]));

describe('a suite marked db workers', () => {
  test('gets one server per worker, each migrated, with distinct URLs and no password in the output; stop removes every server', () => {
    const result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DB_WORKERS: '3' });
    expect(result.code, result.all).toBe(0);
    const servers = calls().filter(call => call.startsWith('run -d '));
    expect(servers.length).toBe(3);
    for (const server of servers) {
      expect(server).toContain('--tmpfs /var/lib/postgresql');
      expect(server).toContain(`--label ctl.test-database.root=${f.root}`);
      expect(server).toMatch(/-p 127\.0\.0\.1::5432 postgres:18 /);
    }
    const flyway = calls().filter(call => call.startsWith('run --rm '));
    expect(flyway.map(call => call.match(/container:(server-\d+)/)![1]).sort()).toEqual(['server-1', 'server-2', 'server-3']);
    for (const n of [1, 2, 3])
      expect(calls()).toContain(`exec server-${n} psql -q -v ON_ERROR_STOP=1 -U test -d postgres -c CREATE DATABASE "test_pyw" TEMPLATE test_template`);
    const seen = pytestSeen();
    expect(seen.args).toBe('run pytest -n 3 --dist loadfile --max-worker-restart 0');
    const urls = seen.TEST_DATABASE_URLS.split(' ');
    expect(urls.length).toBe(3);
    expect(new Set(urls).size).toBe(3);
    urls.forEach((url, index) => expect(url).toMatch(new RegExp(`^postgresql://test:[0-9a-f]{32}@127\\.0\\.0\\.1:${23456 + index}/test_pyw$`)));
    // Until the worker plugin points it at a worker's database, the plain URL names none that exists.
    expect(seen.DATABASE_URL).toBe(urls[0].replace(/test_pyw$/, 'test_worker_database_not_set'));
    expect(seen.TEST_DATABASE_TEMPLATE).toBe('test_template');
    const password = urls[0].split(':')[2].split('@')[0];
    expect(result.all).not.toContain(password);
    expect(result.out).toContain('3 db test workers (TEST_DB_WORKERS)');
    expect(result.all).toContain('3 servers, one per db test worker');
    expect(calls().at(-1)).toBe('rm -f server-1 server-2 server-3');
  });

  test('runs serially on one server with TEST_DB_WORKERS=1: the serial path is unchanged', () => {
    const result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DB_WORKERS: '1' });
    expect(result.code, result.all).toBe(0);
    expect(calls().filter(call => call.startsWith('run -d ')).length).toBe(1);
    expect(calls().filter(call => call.startsWith('run --rm ')).length).toBe(1);
    const seen = pytestSeen();
    expect(seen.args).toBe('run pytest');
    expect(seen.TEST_DATABASE_URLS).toBe('');
    expect(seen.DATABASE_URL).toMatch(/^postgresql:\/\/test:[0-9a-f]{32}@127\.0\.0\.1:23456\/test_pyw$/);
    expect(result.all).not.toContain('db test worker');
    expect(calls().at(-1)).toBe('rm -f server-1');
  });

  test('a plain db suite in the same run reads the first server', () => {
    const result = f.ctl(['test', 'probe', 'pyw'], { ...withCore, TEST_DB_WORKERS: '2' });
    expect(result.code, result.all).toBe(0);
    expect(calls().filter(call => call.startsWith('run -d ')).length).toBe(2);
    expect(seen()).toMatch(/^probe postgresql:\/\/test:[0-9a-f]{32}@127\.0\.0\.1:23456\/test_probe\n$/);
    expect(calls()).not.toContain('exec server-2 psql -q -v ON_ERROR_STOP=1 -U test -d postgres -c CREATE DATABASE "test_probe" TEMPLATE test_template');
    expect(pytestSeen().TEST_DATABASE_URLS.split(' ').length).toBe(2);
  });

  test('a failed migration on one server prints that server\'s output, runs no suite and removes every server and its logs', () => {
    writeFileSync(join(f.base, 'flyway-exit-server-2'), '1\n');
    const tmp = join(f.base, 'tmp'); mkdirSync(tmp);
    const result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DB_WORKERS: '3', TMPDIR: tmp });
    expect(result.code).not.toBe(0);
    expect(result.err).toContain('the migrations failed on test database server 1:');
    expect(result.err).toContain('flyway on server-2');
    expect(result.err).not.toContain('flyway on server-1');
    expect(result.err).toContain('the migrations failed on the test database');
    expect(existsSync(join(f.base, 'pytest.seen'))).toBe(false);
    expect(calls().at(-1)).toBe('rm -f server-1 server-2 server-3');
    expect(readdirSync(tmp)).toEqual([]);
  });

  test('a failed copy on one server prints that server\'s output, runs no suite and removes every server', () => {
    writeFileSync(join(f.base, 'copy-exit-server-3'), '');
    const result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DB_WORKERS: '3' });
    expect(result.code).not.toBe(0);
    expect(result.err).toContain('the copy for the pyw suite failed on test database server 2:');
    expect(result.err).toContain('copy on server-3');
    expect(result.err).toContain('could not copy test_template for the pyw suite');
    expect(existsSync(join(f.base, 'pytest.seen'))).toBe(false);
    expect(calls().at(-1)).toBe('rm -f server-1 server-2 server-3');
  });

  test('a server that fails to start removes the servers started before it', () => {
    writeFileSync(join(f.base, 'start-exit-3'), '');
    const result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DB_WORKERS: '3' });
    expect(result.code).not.toBe(0);
    expect(result.err).toContain('could not start the test database from postgres:18');
    expect(calls().filter(call => call.startsWith('run --rm '))).toEqual([]);
    expect(calls().at(-1)).toBe('rm -f server-1 server-2');
  });

  test('a caller\'s TEST_DATABASE_URL runs it serially by default, and refuses more workers by name', () => {
    let result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DATABASE_URL: 'postgresql://ci@db:5432/ci' });
    expect(result.code, result.all).toBe(0);
    expect(result.out).not.toContain('db test worker');
    expect(pytestSeen().args).toBe('run pytest');
    expect(calls().filter(call => call.startsWith('run '))).toEqual([]);
    result = f.ctl(['test', 'pyw'], { ...withCore, TEST_DATABASE_URL: 'postgresql://ci@db:5432/ci', TEST_DB_WORKERS: '4' });
    expect(result.code).toBe(1);
    expect(result.err).toContain('TEST_DB_WORKERS=4 gives each worker a server of its own, and TEST_DATABASE_URL names one database');
  });

  test('workers on a row that is not a pytest db suite stop the run before any server starts', () => {
    const targets = f.read('scripts/gate/_targets.sh');
    for (const [row, message] of [['"probe apps/probe bun test db workers"', 'ctl test runs workers for pytest suites only'],
      ['"pyw apps/pyw python test workers"', 'marks pyw with workers but not db']]) {
      const name = row.split(' ')[0].slice(1);
      f.put('scripts/gate/_targets.sh', targets.replace(new RegExp(`"${name} [^"]*"`), row));
      const result = f.ctl(['test', name], { ...withCore, TEST_DB_WORKERS: '2' });
      expect(result.code).toBe(1);
      expect(result.err).toContain(message);
      expect(calls()).toEqual([]);
    }
  });
});
