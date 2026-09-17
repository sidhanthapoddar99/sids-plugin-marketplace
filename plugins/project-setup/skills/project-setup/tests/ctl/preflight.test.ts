import { afterEach, beforeEach, expect, test } from 'bun:test';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

let root: string, env: Record<string, string>;
const template = resolve(import.meta.dir, '../../template');
function put(path: string, text: string, executable = false) {
  const file = join(root, path); mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, text, executable ? { mode: 0o755 } : undefined);
}
function read(path: string) { return readFileSync(join(root, path), 'utf8'); }
function calls() { return existsSync(join(root, 'calls')) ? read('calls') : ''; }
function run(...args: string[]) {
  return Bun.spawnSync(['bash', join(root, 'scripts/dev/dev.sh'), 'api', '--no-core', '--nqa', ...args],
    { cwd: root, env, timeout: 10000 });
}
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'template-preflight-'));
  cpSync(join(template, 'scripts'), join(root, 'scripts'), { recursive: true });
  const configuration = 'API_PORT=8000\nAPI_HOST=localhost\nDATA_DIR=./data\nLOGS_DIR=./logs\nOPTIONAL_KEY=\n';
  put('.env', configuration); put('.env.template', configuration);
  put('.mise.toml', '[tools]\n');
  for (const [dir, manifest, lock] of [['api', 'pyproject.toml', 'uv.lock'],
    ['web', 'package.json', 'bun.lock'], ['engine', 'Cargo.toml', 'Cargo.lock']]) {
    put(`apps/${dir}/${manifest}`, 'fixture'); put(`apps/${dir}/${lock}`, 'unchanged');
  }
  put('bin/mise', '#!/bin/bash\ncase "$1" in\n install) echo "mise install" >> "$CTL_ROOT/calls";;\n env) echo "export CTL_FIXTURE_ACTIVE=1";;\n esac\n', true);
  for (const tool of ['uv', 'bun', 'cargo']) {
    put(`bin/${tool}`, '#!/bin/bash\ncase "$1" in --version) exit 0;; locate-project) echo "$PWD/Cargo.toml"; exit 0;; esac\n'
      + `echo "${tool} $*" >> "$CTL_ROOT/calls"\n`, true);
  }
  put('scripts/dev/_apps.sh', `app_names() { echo api; }
frontends() { :; }
app_tools() { :; }
app_port() { echo 8000; }
app_cmd() { echo true; }
`);
  put('scripts/common/_process.sh', 'process_init() { echo launch >> "$CTL_ROOT/calls"; exit 0; }\n');
  env = { PATH: `${root}/bin:${process.env.PATH}`, HOME: root, CTL_ROOT: root, NO_COLOR: '1', DATA_SVCS: '' };
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

test('dev validates, activates and synchronizes each package before launch', () => {
  put('apps/web/node_modules/vendor/Cargo.toml', '<version>');
  const result = run(); expect(result.exitCode, result.stderr.toString()).toBe(0);
  expect(calls()).toContain('uv sync --locked');
  expect(calls()).toContain('bun install --frozen-lockfile');
  expect(calls()).toContain('cargo fetch --locked');
  expect(calls().trim().endsWith('launch')).toBe(true);
  expect(read('apps/web/bun.lock')).toBe('unchanged');
});
test('missing configuration or invalid override stops before installation', () => {
  put('.env.template', read('.env.template') + 'NEW_SETTING=value\n');
  expect(run().exitCode).not.toBe(0); expect(calls()).toBe('');
  put('.env.template', read('.env')); env.API_PORT = '70000';
  expect(run().exitCode).not.toBe(0); expect(calls()).toBe('');
});
test('blank required credentials fail while optional blanks remain optional', () => {
  put('.env', read('.env') + 'POSTGRES_PASSWORD=\n');
  put('.env.template', read('.env.template') + 'POSTGRES_PASSWORD=\n');
  const result = run(); expect(result.exitCode).not.toBe(0);
  expect(result.stderr.toString()).toContain('required local credential'); expect(calls()).toBe('');
});
test('malformed and duplicate configuration never leaks supplied values', () => {
  for (const line of ['API_PORT=PRIVATE_VALUE', 'BROKEN PRIVATE_VALUE']) {
    put('.env', read('.env.template') + line + '\n');
    const result = run(); expect(result.exitCode).not.toBe(0);
    expect(result.stdout.toString() + result.stderr.toString()).not.toContain('PRIVATE_VALUE');
    expect(calls()).toBe('');
  }
});
for (const tool of ['mise', 'uv', 'bun', 'cargo']) {
  test(`${tool} failure prevents launch`, () => {
    put(`bin/${tool}`, '#!/bin/bash\necho "fixture failure" >&2\nexit 7\n', true);
    expect(run().exitCode).not.toBe(0); expect(calls()).not.toContain('launch');
  });
}
test('missing lockfile fails; help and dry-run do not install', () => {
  expect(run('--help').exitCode).toBe(0); expect(run('--dry-run').exitCode).toBe(0);
  expect(calls()).toBe(''); rmSync(join(root, 'apps/web/bun.lock'));
  expect(run().exitCode).not.toBe(0); expect(calls()).not.toContain('launch');
});
