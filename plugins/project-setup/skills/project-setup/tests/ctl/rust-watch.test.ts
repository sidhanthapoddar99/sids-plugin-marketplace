import { expect, test } from 'bun:test';
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
const watcher = resolve(import.meta.dir, '../../template/scripts/dev/rust-watch.ts');
async function until(check: () => boolean) {
  for (let n = 0; n < 100; n++) { if (check()) return; await Bun.sleep(50); }
  throw new Error('Watcher condition timed out');
}

test('development cycle preserves argument boundaries and stops after a failed build', () => {
  const root = mkdtempSync(join(tmpdir(), 'rust-cycle-'));
  try {
    const config = join(root, 'config.ts');
    const output = join(root, 'output');
    const commands = [[process.execPath, '-e', `await Bun.write(${JSON.stringify(output)}, process.argv[1]);`, 'value with spaces'],
      [process.execPath, '-e', 'process.exit(17)'], [process.execPath, '-e', `await Bun.write(${JSON.stringify(join(root, 'unexpected'))}, 'bad')`]];
    writeFileSync(config, 'export default ' + JSON.stringify({ paths: [], commands, debounceMs: 50 }));
    const result = Bun.spawnSync([process.execPath, watcher, '--config', config, '--cycle'], { cwd: root });
    expect(result.exitCode, result.stderr.toString()).toBe(17);
    expect(readFileSync(output, 'utf8')).toBe('value with spaces');
    expect(existsSync(join(root, 'unexpected'))).toBe(false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('one watcher rebuilds after source edits and ignores generated artifacts', async () => {
  const root = mkdtempSync(join(tmpdir(), 'rust-watch-fixture-'));
  let child: ReturnType<typeof Bun.spawn> | undefined;
  try {
    mkdirSync(join(root, 'src/generated'), { recursive: true });
    const source = join(root, 'src/lib.rs');
    const output = join(root, 'output');
    writeFileSync(source, 'first');
    const config = join(root, 'config.ts');
    const commands = [[process.execPath, '-e', `
      const fs = await import('node:fs');
      fs.appendFileSync(${JSON.stringify(output)}, fs.readFileSync(${JSON.stringify(source)}, 'utf8') + '\\n');
      setInterval(() => {}, 1000);
    `]];
    writeFileSync(config, 'export default ' + JSON.stringify({ paths: [join(root, 'src')], commands, debounceMs: 100 }));
    child = Bun.spawn([process.execPath, watcher, '--config', config], { cwd: root, stdout: 'pipe', stderr: 'pipe' });
    await until(() => existsSync(output));
    writeFileSync(source, 'second');
    await until(() => readFileSync(output, 'utf8').includes('second'));
    await Bun.sleep(400);
    const before = readFileSync(output, 'utf8');
    writeFileSync(join(root, 'src/generated/output.rs'), 'generated');
    await Bun.sleep(600);
    expect(readFileSync(output, 'utf8')).toBe(before);
    child.kill('SIGTERM'); await child.exited;
  } finally {
    if (child && child.exitCode === null) { child.kill('SIGTERM'); await child.exited; }
    rmSync(root, { recursive: true, force: true });
  }
}, 15_000);
