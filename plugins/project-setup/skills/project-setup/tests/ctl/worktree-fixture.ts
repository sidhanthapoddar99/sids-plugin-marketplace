// Fixture for the ctl worktree tests: a throwaway git repository copied from the template, with a
// filled .env, a stand-in docker, and an isolated git configuration. useWorktreeFixture() gives each
// test a fresh repository in the system temp folder; `f` always means the current one.
import { afterEach, beforeEach, expect } from 'bun:test';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { spawn, type ChildProcess } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';

const template = resolve(import.meta.dir, '../../template');

// A stand-in docker, so no test reaches the real daemon. <base>/docker-state is ok (the default),
// stopped, or broken (docker answers info, but ps fails). <base>/docker-running lists the compose
// projects whose containers run, one per line.
const standInDocker = (base: string) => `#!/usr/bin/env bash
state=$(cat '${base}/docker-state' 2>/dev/null || echo ok)
case "$1" in
  info|compose) [[ $state != stopped ]] ;;
  ps) [[ $state == ok ]] || exit 1
      want=\${@: -1}; want=\${want#label=com.docker.compose.project=}
      grep -qx -- "$want" '${base}/docker-running' 2>/dev/null && echo 0123456789ab; exit 0 ;;
  *) exit 1 ;;
esac
`;

function fixture() {
  const base = mkdtempSync(join(tmpdir(), 'ctl-worktree-'));
  // A space in the path proves every script quotes it.
  const root = join(base, 'demo repo');
  cpSync(template, root, { recursive: true });
  mkdirSync(join(base, 'bin'));
  writeFileSync(join(base, 'bin/docker'), standInDocker(base), { mode: 0o755 });
  writeFileSync(join(base, 'gitconfig'), '');
  const env: Record<string, string> = {
    PATH: `${join(base, 'bin')}:${process.env.PATH}`, HOME: base, NO_COLOR: '1', XDG_RUNTIME_DIR: base,
    GIT_CONFIG_GLOBAL: join(base, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1',
    GIT_AUTHOR_NAME: 'Test', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Test', GIT_COMMITTER_EMAIL: 'test@example.com',
  };
  const run = (command: string[], cwd: string, extra: Record<string, string> = {}) => {
    const result = Bun.spawnSync(command, { cwd, env: { ...env, ...extra }, timeout: 60_000 });
    const out = result.stdout.toString(), err = result.stderr.toString();
    return { code: result.exitCode ?? -1, out, err, all: out + err };
  };
  const self = {
    base, root,
    put(path: string, text: string) { const file = join(root, path); mkdirSync(dirname(file), { recursive: true }); writeFileSync(file, text); },
    read(path: string) { return readFileSync(join(root, path), 'utf8'); },
    // ctl <args…> from <dir>, the main tree unless a test names a worktree
    ctl(args: string[], extra: Record<string, string> = {}, dir = root) { return run(['bash', join(dir, 'ctl'), ...args], dir, extra); },
    // git in the throwaway repository, never in a real checkout
    git(...args: string[]) {
      const result = run(['git', ...args], root);
      if (result.code !== 0) throw new Error(`git ${args.join(' ')}: ${result.err}`);
      return result.out.trim();
    },
    cleanup() { rmSync(base, { recursive: true, force: true }); },
  };
  return self;
}

let current: ReturnType<typeof fixture>;
let sleepers: ChildProcess[] = [];
export const f = new Proxy({} as ReturnType<typeof fixture>, { get: (_, key) => (current as any)[key] });
export const mainEnv = () => f.read('.env.template').replace(/^COMPOSE_PROJECT_NAME=.*$/m, 'COMPOSE_PROJECT_NAME=demo');

export function useWorktreeFixture() {
  beforeEach(() => {
    current = fixture();
    f.put('.env', mainEnv());
    f.git('init', '-q', '-b', 'main');
    f.git('add', '-A');
    f.git('commit', '-q', '-m', 'base');
  });
  afterEach(() => { sleepers.forEach(child => child.kill('SIGKILL')); sleepers = []; current.cleanup(); });
}

export const W = (path = '') => join(f.root, '.worktrees', path);
export const wt = (args: string[], extra: Record<string, string> = {}, dir?: string) => f.ctl(['worktree', ...args], extra, dir);
export const ok = (args: string[], extra: Record<string, string> = {}, dir?: string) => {
  const run = wt(args, extra, dir); expect(run.code, run.all).toBe(0); return run;
};
export const refused = (args: string[], extra: Record<string, string> = {}, dir?: string) => {
  const run = wt(args, extra, dir); expect(run.code, run.all).toBe(1); return run.err;
};
export const branchOf = (dir: string) => f.git('-C', dir, 'branch', '--show-current');
export const nothingCreated = (name: string) => {
  expect(existsSync(W('slot-1'))).toBe(false);
  expect(existsSync(W(name))).toBe(false);
  expect(() => f.git('show-ref', '--verify', `refs/heads/${name}`)).toThrow();
};

// spawnKept <command…> — a background process that the fixture kills after the test
export function spawnKept(command: string[], cwd = f.base) {
  const child = spawn(command[0], command.slice(1), { cwd, stdio: 'ignore' }); sleepers.push(child); return child;
}
// liveProcess — a running process and its start time, as ctl's process records hold them
export function liveProcess() {
  const child = spawnKept(['sleep', '60']);
  const stat = readFileSync(`/proc/${child.pid}/stat`, 'utf8');
  return { child, pid: child.pid!, birth: stat.slice(stat.lastIndexOf(') ') + 2).split(' ')[19] };
}

const daysAgo = (days: number) => new Date(Date.now() - days * 86_400_000);
// age <path> <days> — set its access and modification times, as if nobody used it since
export const age = (path: string, days: number) => utimesSync(path, daysAgo(days), daysAgo(days));

// cargoProfile <profile folder> [tag folder] — a fake Cargo profile with an old (30 days) and a fresh
// (1 day) entry in each of deps, build, .fingerprint and incremental. Cargo's CACHEDIR.TAG goes into
// <tag folder>, the target folder, which is the profile's parent unless a triple sits between.
export function cargoProfile(profile: string, tagFolder = dirname(profile)) {
  mkdirSync(profile, { recursive: true });
  writeFileSync(join(tagFolder, 'CACHEDIR.TAG'),
    'Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo.\n');
  const old: string[] = [], fresh: string[] = [];
  for (const part of ['deps', 'build', '.fingerprint', 'incremental']) {
    for (const [name, days, list] of [['old-0123456789abcdef', 30, old], ['new-0123456789abcdef', 1, fresh]] as const) {
      const entry = join(profile, part, part === 'deps' ? `lib${name}.rlib` : name);
      mkdirSync(dirname(entry), { recursive: true });
      if (part === 'deps') writeFileSync(entry, 'x'.repeat(10_000));
      else { mkdirSync(entry, { recursive: true }); writeFileSync(join(entry, 'output'), 'x'); age(join(entry, 'output'), days); }
      age(entry, days); list.push(entry);
    }
  }
  return { old, fresh };
}
