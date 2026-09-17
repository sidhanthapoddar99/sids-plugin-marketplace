// Watchexec detects edits; this coordinator runs the declared development cycle.
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('Rust development watcher: [--config FILE] [--cycle]. Use ctl dev engine for managed ownership.');
  process.exit(0);
}
let configPath = new URL('./rust-watch.config.ts', import.meta.url).pathname;
let cycle = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--cycle') cycle = true;
  else if (args[i] === '--config' && args[i + 1]) configPath = resolve(args[++i]);
  else throw new Error(`Unknown or incomplete watcher option: ${args[i]}`);
}
const { default: config } = await import(pathToFileURL(configPath).href);
if (!Array.isArray(config.commands) || !config.commands.length ||
    config.commands.some((command: unknown) => !Array.isArray(command) || !command.length ||
      command.some(arg => typeof arg !== 'string' || !arg.length)) ||
    !Array.isArray(config.paths) || config.paths.some((path: unknown) => typeof path !== 'string') ||
    !Number.isInteger(config.debounceMs) || config.debounceMs < 0) {
  throw new Error('Watcher requires paths, nonempty command arrays, and a nonnegative debounceMs.');
}
const paths = config.paths.filter((path: string) => existsSync(path));
if (!cycle && !paths.length) throw new Error('No declared Rust watch paths exist. Adapt rust-watch.config.ts.');
let child: ReturnType<typeof Bun.spawn> | undefined;
let stopped = false;
function stop() { stopped = true; child?.kill('SIGTERM'); }
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
try {
  const commands: string[][] = cycle ? config.commands : [[
    'watchexec', '--restart', '--debounce', `${config.debounceMs}ms`,
    '--ignore', '**/target/**', '--ignore', '**/generated/**', '--ignore', '**/node_modules/**',
    '--ignore', '**/.venv/**', '--shell', 'none',
    ...paths.flatMap((path: string) => ['--watch', path]), '--',
    process.execPath, import.meta.path, '--config', configPath, '--cycle',
  ]];
  for (const command of commands) {
    if (stopped) break;
    child = Bun.spawn(command, { stdin: 'ignore', stdout: 'inherit', stderr: 'inherit' });
    const code = await child.exited;
    if (code !== 0) { process.exitCode = code; break; }
  }
} finally {
  process.off('SIGTERM', stop);
  process.off('SIGINT', stop);
}
