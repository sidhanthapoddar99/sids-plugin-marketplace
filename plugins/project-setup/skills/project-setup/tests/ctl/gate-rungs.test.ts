// The real lint, typecheck and test workers over the one target table (scripts/gate/_targets.sh),
// with recording stand-ins for uv, cargo, bun, go, gofmt and golangci-lint. Nothing compiles: each
// stand-in records its folder, its arguments and the compiler jobs it was given, and fails when the
// test names it in FAIL.
import { afterEach, beforeEach, expect, setDefaultTimeout, test } from 'bun:test';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fixture, type Fixture } from './gate-fixture';

setDefaultTimeout(60_000);
let f: Fixture, calls: string;
beforeEach(() => {
  f = fixture({ standIns: false });
  calls = join(f.base, 'tools.log');
  // tool <name> — a stand-in that answers the version probe, records the call and fails on FAIL=<name>-<first argument>
  const tool = (name: string, body = '') => writeFileSync(join(f.base, 'bin', name), `#!/usr/bin/env bash
case "$1" in --version|version) exit 0 ;; esac
printf '%s|%s|%s|jobs=%s\\n' ${name} "\${PWD#${f.root}/}" "$*" "\${CARGO_BUILD_JOBS-}" >> '${calls}'
${body}
key=${name}-$1; [[ $1 == run ]] && key=${name}-$2
[[ " \${FAIL:-} " != *" $key "* ]] || { echo "${name} $* failed" >&2; exit 1; }
`, { mode: 0o755 });
  for (const name of ['uv', 'cargo', 'bun', 'go', 'golangci-lint']) tool(name);
  tool('gofmt', '[[ -z ${UNFORMATTED:-} ]] || printf "%s\\n" $UNFORMATTED');
  f.put('apps/example-api-python/pyproject.toml', '');
  f.put('apps/example-api-python/app/main.py', '');
  f.put('apps/example-api-python/tests/test_main.py', '');
  f.put('apps/database/postgres/migrations/V1__start.sql', '');
  f.put('apps/example-engine-rust/Cargo.toml', '');
  f.put('apps/example-multi-web-app/app/package.json', '');
  f.put('apps/example-multi-web-app/app/src/main.test.ts', '');
  f.put('apps/example-multi-web-app/docs/package.json', '');
  f.put('apps/example-tui-go/go.mod', '');
});
afterEach(() => f.cleanup());

const toolCalls = () => existsSync(calls) ? readFileSync(calls, 'utf8').trim().split('\n').map(entry => entry.split('|jobs=')[0]) : [];

test('lint runs the cheap linters on every target before any linter that compiles', () => {
  const run = f.ctl(['gate', 'lint']);
  expect(run.code, run.all).toBe(0);
  expect(toolCalls()).toEqual([
    'uv|apps/example-api-python|run ruff check .',
    'cargo|apps/example-engine-rust|fmt --check',
    'bun|apps/example-multi-web-app/app|run lint',
    'bun|apps/example-multi-web-app/docs|run lint',
    'gofmt|apps/example-tui-go|-l .',
    'cargo|apps/example-engine-rust|clippy --all-targets -- -D warnings -D clippy::cognitive_complexity',
    'golangci-lint|apps/example-tui-go|run ./...',
  ]);
  expect(run.err).toContain('apps/database/postgres: no Python file yet — nothing to lint here');
  expect(run.out).toContain('gate lint green — 5 target(s)');
});

test('a cheap lint failure stops the compiling linters and names them as not run', () => {
  const run = f.ctl(['gate', 'lint'], { FAIL: 'cargo-fmt' });
  expect(run.code).toBe(1);
  expect(toolCalls().some(entry => entry.includes('clippy') || entry.startsWith('golangci-lint'))).toBe(false);
  expect(run.err).toContain('NOT RUN, because a cheap lint above failed first: clippy and golangci-lint on engine cli');
});

test('gofmt names each file it would change', () => {
  const run = f.ctl(['gate', 'lint', 'cli'], { UNFORMATTED: 'main.go cmd/tool.go' });
  expect(run.code).toBe(1);
  expect(run.err).toContain('not gofmt-formatted: main.go');
  expect(run.err).toContain('not gofmt-formatted: cmd/tool.go');
});

test('each worker takes several targets and runs them in table order, under the TESTING settings', () => {
  f.put('.env', 'TEST_BUILD_JOBS=5\n');
  expect(f.ctl(['gate', 'typecheck', 'cli', 'api']).code).toBe(0);
  expect(f.ctl(['test', 'cli', 'engine']).code).toBe(0);
  expect(toolCalls()).toEqual([
    'uv|apps/example-api-python|run mypy app',
    'go|apps/example-tui-go|vet ./...',
    'cargo|apps/example-engine-rust|test',
    'go|apps/example-tui-go|test -race ./...',
  ]);
  expect(readFileSync(calls, 'utf8')).toContain('cargo|apps/example-engine-rust|test|jobs=5');
});

test('a target the worker does not take, or one whose folder is gone, is refused by name', () => {
  let run = f.ctl(['gate', 'typecheck', 'database']);
  expect(run.code).toBe(1);
  expect(run.err).toContain('unknown target: database (ctl gate typecheck takes api|engine|single|');
  run = f.ctl(['test', 'single']);
  expect(run.code).toBe(1);
  expect(run.err).toContain('apps/example-single-web-app-vite not found — the target \'single\' has no folder to test');
  run = f.ctl(['test', '--fast']);
  expect(run.code).toBe(1);
  expect(run.err).toContain('unknown flag --fast');
  expect(toolCalls()).toEqual([]);
});

test('ctl test with no target skips absent apps and names those with no test file yet', () => {
  const run = f.ctl(['test']);
  expect(run.code, run.all).toBe(0);
  expect(toolCalls()).toEqual([
    'uv|apps/example-api-python|run pytest',
    'cargo|apps/example-engine-rust|test',
    'bun|apps/example-multi-web-app/app|run test',
    'go|apps/example-tui-go|test -race ./...',
  ]);
  expect(run.err).toContain('apps/database/postgres: no test file yet');
  expect(run.err).toContain('apps/example-multi-web-app/docs: no test file yet');
  expect(run.out).toContain('tests passed — 4 suite(s) ran');
});
