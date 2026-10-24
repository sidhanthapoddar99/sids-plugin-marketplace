// Fixture for the gate and test-runner tests: a throwaway copy of the template's ctl and scripts/
// in a temporary folder. `standIns` replaces the lint, typecheck and check rungs and the test
// worker with scripts that resolve the TESTING settings as a real rung does and record what they
// got, so a test sees what the gate passed on without compiling anything. A stand-in systemd-run
// records its arguments and runs the command, so the memory lid's size shows without a real scope.
// Each fixture has its own gate lock file, so no test waits on a gate this machine is running.
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

export const template = resolve(import.meta.dir, '../../template');

// The cores this test process may use, as a list of numbers.
export function allowedCores(): number[] {
  const list = readFileSync('/proc/self/status', 'utf8').match(/^Cpus_allowed_list:\s*(\S+)/m)![1];
  return list.split(',').flatMap(part => {
    const [low, high] = part.split('-').map(Number);
    return high === undefined ? [low] : Array.from({ length: high - low + 1 }, (_, i) => low + i);
  });
}

export type Run = { code: number; out: string; err: string; all: string };

export function fixture(options: { standIns?: boolean; at?: string } = {}) {
  const base = mkdtempSync(join(tmpdir(), 'ctl-gate-'));
  const root = join(base, options.at ?? 'repo');
  const log = join(base, 'rungs.log'), lid = join(base, 'systemd-run.log'), lock = join(base, 'gate.lock');
  const put = (path: string, text: string, executable = false) => {
    const file = join(root, path); mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, text); if (executable) chmodSync(file, 0o755);
  };
  mkdirSync(root, { recursive: true });
  cpSync(join(template, 'ctl'), join(root, 'ctl'));
  cpSync(join(template, '.gitignore'), join(root, '.gitignore'));
  cpSync(join(template, 'scripts'), join(root, 'scripts'), { recursive: true });
  mkdirSync(join(base, 'bin'));
  writeFileSync(join(base, 'bin/systemd-run'), `#!/usr/bin/env bash
printf '%s\\n' "$*" >> '${lid}'
while [[ $# -gt 0 && $1 != -- ]]; do shift; done; shift; exec "$@"
`, { mode: 0o755 });
  if (options.standIns ?? true) {
    // A stand-in resolves the settings again, as a rung run inside the gate does, then records them.
    const standIn = (name: string) => `#!/usr/bin/env bash
set -euo pipefail
source '${root}/scripts/common/_lib.sh'; source '${root}/scripts/common/_test-settings.sh'
test_settings_init
printf '%s args=[%s] cores=%s jobs=%s memory=%s\\n' ${name} "$*" "$(test_allowed_cores)" "\${CARGO_BUILD_JOBS-unset}" \\
  "\${TEST_MEMORY-unset}" >> '${log}'
if [[ -n \${HOLD_FILE:-} && ${name} == lint ]]; then while [[ ! -f $HOLD_FILE ]]; do sleep 0.1; done; fi
`;
    for (const name of ['lint', 'typecheck', 'check']) put(`scripts/gate/${name}.sh`, standIn(name), true);
    put('scripts/test/test.sh', standIn('test'), true);
  }

  // TZ is fixed, so the local date-times a test gives --delta mean the same moment on every machine.
  const environment = (extra: Record<string, string> = {}) => ({
    PATH: `${base}/bin:${dirname(process.execPath)}:/usr/local/bin:/usr/bin:/bin`, HOME: base, NO_COLOR: '1', LANG: 'C.UTF-8',
    TZ: 'Asia/Kolkata', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1', GATE_LOCK_FILE: lock, ...extra });
  const git = (args: string[], extra: Record<string, string> = {}, cwd = root) => {
    const result = spawnSync('git', ['-c', 'user.name=ctl test', '-c', 'user.email=ctl-test@example.invalid', '-c', 'commit.gpgsign=false',
      '-c', 'core.hooksPath=/dev/null', '-c', 'init.defaultBranch=main', ...args], { cwd, env: environment(extra), encoding: 'utf8' });
    if (result.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${result.stderr}`);
    return result.stdout;
  };
  const result = (status: number | null, out: string, err: string): Run => ({ code: status ?? -1, out, err, all: out + err });
  return {
    base, root, lock, put,
    read: (path: string) => readFileSync(join(root, path), 'utf8'),
    rungs: () => existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : [],
    clearRungs: () => rmSync(log, { force: true }),
    lid: () => existsSync(lid) ? readFileSync(lid, 'utf8') : '',
    // ctl <args…> in the fixture, with only the environment given here, so nothing leaks in from the
    // run that executes the tests, such as a gate's own TEST_* values. It forgets earlier green gate
    // runs first, so every call runs its rungs; `again` keeps them, for the tests of that record.
    ctl(args: string[], extra: Record<string, string> = {}): Run {
      rmSync(join(root, '.git/ctl-gate-green'), { recursive: true, force: true });
      const run = spawnSync('bash', [join(root, 'ctl'), ...args], { cwd: root, env: environment(extra), encoding: 'utf8', timeout: 60_000 });
      return result(run.status, run.stdout, run.stderr);
    },
    again(args: string[], extra: Record<string, string> = {}): Run {
      const run = spawnSync('bash', [join(root, 'ctl'), ...args], { cwd: root, env: environment(extra), encoding: 'utf8', timeout: 60_000 });
      return result(run.status, run.stdout, run.stderr);
    },
    // the same, started in the background; `done` resolves when it exits, `output` reads it so far
    start(args: string[], extra: Record<string, string> = {}) {
      const child = spawn('bash', [join(root, 'ctl'), ...args], { cwd: root, env: environment(extra) });
      let out = '', err = '';
      child.stdout.on('data', chunk => { out += chunk; });
      child.stderr.on('data', chunk => { err += chunk; });
      const done = new Promise<Run>(settle => child.on('close', status => settle(result(status, out, err))));
      return { done, output: () => out + err };
    },
    // bash -c <script> in the fixture, with the same environment
    bash(script: string, extra: Record<string, string> = {}): Run {
      const run = spawnSync('bash', ['-c', script], { cwd: root, env: environment(extra), encoding: 'utf8', timeout: 60_000 });
      return result(run.status, run.stdout, run.stderr);
    },
    // git in the fixture's own throwaway repository, never in the checkout that runs the tests
    git: (...args: string[]) => git(args),
    gitAt: (cwd: string, ...args: string[]) => git(args, {}, cwd),
    // commitAt <date> <message> — commit everything, dated (author and committer) at <date>,
    // such as '2026-01-10 12:00:00 +0530'; returns the commit's short hash
    commitAt(date: string, message: string) {
      git(['add', '-A']);
      git(['commit', '-q', '-m', message], { GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date });
      return git(['rev-parse', '--short', 'HEAD']).trim();
    },
    cleanup: () => rmSync(base, { recursive: true, force: true }),
  };
}

export type Fixture = ReturnType<typeof fixture>;

// The files of a small repo shaped like the template: one file per app, a package, the engines'
// migrations, docker/ and the root docs.
export const appFiles = ['apps/example-api-python/app/main.py', 'apps/example-engine-rust/crates/api/src/main.rs',
  'apps/example-multi-web-app/app/src/main.ts', 'apps/example-multi-web-app/docs/src/index.ts',
  'apps/example-multi-web-app/nginx/nginx.conf.template', 'apps/database/postgres/migrations/V1__start.sql',
  'apps/packages/ui/src/index.ts', 'apps/example-tui-go/main.go', 'docker/compose.base.yaml', 'README.md', 'AGENTS.md',
  '.env.template'];
