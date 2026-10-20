// One gate run per user at a time: a second run, from any checkout, waits for the first and names
// it, and the lock goes away with the run that held it. Two fixtures stand for two checkouts and
// share one lock file. The first run's lint stand-in holds until the test lets it go.
import { afterEach, beforeEach, expect, setDefaultTimeout, test } from 'bun:test';
import { existsSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fixture, type Fixture } from './gate-fixture';

setDefaultTimeout(60_000);
let a: Fixture, b: Fixture;
beforeEach(() => { a = fixture(); b = fixture(); });
afterEach(() => { a.cleanup(); b.cleanup(); });

async function until(what: string, condition: () => boolean, ms = 20_000) {
  const deadline = Date.now() + ms;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${what}`);
    await Bun.sleep(50);
  }
}
// The holder, as a reader such as `ctl worktree` sees it: a shared flock that never waits and never
// writes, then the `checkout=` line when a run holds the lock. Empty when no run holds it.
const holder = (f: Fixture, lock: string) =>
  f.bash('exec {fd}<"$LOCK" || exit 1; flock -n -s "$fd" && exit 0; sed -n "s/^checkout=//p" "$LOCK"', { LOCK: lock }).out.trim();

test('a second gate waits for the first, names it, and runs once the first ends', async () => {
  const hold = join(a.base, 'release');
  const first = a.start(['gate'], { HOLD_FILE: hold });
  await until('the first run to reach lint', () => a.rungs().length > 0);
  expect(holder(a, a.lock)).toBe(a.root);
  const second = b.start(['gate'], { GATE_LOCK_FILE: a.lock });
  await until('the second run to wait', () => second.output().includes('waiting for it to finish'));
  expect(second.output()).toContain(`another gate run holds the lock: gate all in ${a.root}`);
  expect(second.output()).toContain('on lint');
  expect(b.rungs()).toEqual([]);
  writeFileSync(hold, '');
  const [one, two] = await Promise.all([first.done, second.done]);
  expect(one.code, one.all).toBe(0);
  expect(two.code, two.all).toBe(0);
  expect(two.all).toContain('the other gate run finished — starting');
  expect(b.rungs().map(entry => entry.split(' ')[0])).toEqual(['lint', 'typecheck', 'test', 'check']);
  expect(holder(a, a.lock)).toBe('');
});

test("a waiting gate already holds its checkout's own lock, which ctl worktree tests", async () => {
  const hold = join(a.base, 'release');
  const first = a.start(['gate'], { HOLD_FILE: hold });
  await until('the first run to reach lint', () => a.rungs().length > 0);
  b.git('init', '-q');
  const own = join(b.git('rev-parse', '--absolute-git-dir').trim(), 'ctl-gate.lock');
  // An exclusive flock that never waits, as scripts/worktree/_busy.sh takes it: 1 while a gate holds the lock.
  const probe = () => b.bash('exec {fd}<"$OWN" || exit 2; flock -n -x "$fd"', { OWN: own }).code;
  const second = b.start(['gate'], { GATE_LOCK_FILE: a.lock });
  await until('the second run to wait', () => second.output().includes('waiting for it to finish'));
  expect(probe()).toBe(1);
  writeFileSync(hold, '');
  await Promise.all([first.done, second.done]);
  expect(probe()).toBe(0);
});

test('a finished or killed run leaves no lock behind', async () => {
  const hold = join(a.base, 'release');
  const run = a.start(['gate'], { HOLD_FILE: hold });
  await until('the run to reach lint', () => a.rungs().length > 0);
  // Kill the whole run, rung included: the kernel drops the lock, and nothing is left to clean.
  a.bash(`pkill -KILL -f '${a.root}/' || true`);
  await run.done;
  expect(existsSync(a.lock)).toBe(true);
  expect(holder(a, a.lock)).toBe('');
  const next = a.ctl(['gate']);
  expect(next.code, next.all).toBe(0);
  expect(next.all).not.toContain('waiting');
});

test('a lock file that is a symlink is refused, because ctl did not make it', () => {
  symlinkSync(join(a.base, 'elsewhere'), a.lock);
  const run = a.ctl(['gate']);
  expect(run.code).toBe(1);
  expect(run.err).toContain('is a symlink');
  expect(a.rungs()).toEqual([]);
});
