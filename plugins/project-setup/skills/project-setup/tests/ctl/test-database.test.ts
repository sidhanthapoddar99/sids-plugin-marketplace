// ctl test and the throwaway PostgreSQL a run owns (scripts/test/_test-database.sh), against a fake
// docker that records its calls: one server per run, migrated once, one database copy per db suite,
// the caller's own database, the sweep of leftovers, and the server's removal when the run ends.
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fixture, type Fixture } from './gate-fixture';

let f: Fixture;
const calls = () => existsSync(join(f.base, 'docker.calls')) ? readFileSync(join(f.base, 'docker.calls'), 'utf8').trim().split('\n') : [];
const seen = () => existsSync(join(f.base, 'seen.env')) ? readFileSync(join(f.base, 'seen.env'), 'utf8') : '';
const withCore = { DATA_SVCS_STR: 'postgres' };

beforeEach(() => {
  f = fixture({ standIns: false });
  // The fake docker: compose names the images, `run -d` starts the server, `run --rm` is Flyway,
  // `port` gives the loopback port, `ps` lists what ps.txt holds.
  writeFileSync(join(f.base, 'bin/docker'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> '${f.base}/docker.calls'
case $1 in
  compose) [[ " $* " == *" config "* ]] && echo '{"name":"fixture","services":{"postgres":{"image":"postgres:18"},"migrate":{"image":"fixture/migrate:dev"}}}'
           exit 0 ;;
  run) [[ " $* " == *" -d "* ]] && { echo server-1; exit 0; }
       exit "$(cat '${f.base}/flyway-exit' 2>/dev/null || echo 0)" ;;
  port) echo 127.0.0.1:23456 ;;
  ps) cat '${f.base}/ps.txt' 2>/dev/null || true ;;
esac
exit 0
`, { mode: 0o755 });
  // Two apps: probe reads the database, plain does not. Each records the settings it ran with.
  const targets = f.read('scripts/gate/_targets.sh');
  const start = targets.indexOf('GATE_TARGETS=('), end = targets.indexOf(')\n', start);
  f.put('scripts/gate/_targets.sh', targets.slice(0, start) +
    'GATE_TARGETS=(\n  "probe apps/probe bun test db"\n  "other apps/other bun test db"\n  "plain apps/plain bun test"\n' + targets.slice(end));
  for (const name of ['probe', 'other', 'plain']) {
    f.put(`apps/${name}/package.json`, JSON.stringify({ scripts: { test: `printf '${name} %s\\n' "\${DATABASE_URL:-none}" >> '${f.base}/seen.env'` } }));
    f.put(`apps/${name}/one.test.ts`, '');
  }
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
    const result = f.ctl(['test'], withCore);
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
