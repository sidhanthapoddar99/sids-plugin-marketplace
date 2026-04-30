---
name: monitor-development
description: Use when authoring `monitors` — long-running watcher processes spawned by Claude Code while a session is active. Covers the manifest declaration, lifecycle (start/restart/stop), output handling, when to use a monitor vs a hook vs a bin, and patterns for filesystem watchers, log tailers, and background sync processes.
---

# Authoring monitors

A **monitor** is a long-running process Claude Code spawns when a plugin is enabled and a session is active. Unlike hooks (event-driven, short-lived) or bins (user-invoked), monitors run continuously alongside the session.

## When to use

- Watch the filesystem for changes the model should know about
- Tail an external log and surface relevant lines
- Maintain a background sync (project state ↔ external service)
- Run a periodic refresh of cached data the model relies on

When NOT to use:
- One-shot operations → a hook is lighter
- User-invoked tools → a bin or slash command
- Real-time I/O channels → see `topics/channel-development` for `channels`, which are more structured

## Manifest shape

```json
{
  "name": "my-plugin",
  "monitors": {
    "file-watcher": {
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/watch-files.sh",
      "args": ["${CLAUDE_PROJECT_ROOT}"],
      "outputHandling": "log",
      "restart": "on-failure",
      "startupTimeout": 5000
    }
  }
}
```

| Field | Purpose |
|---|---|
| `command` | Path to the executable or script |
| `args` | Args passed at start. Env vars are interpolated |
| `outputHandling` | `"log"` (write to plugin log file), `"prompt"` (inject as user-visible context), `"silent"` (discard) |
| `restart` | `"never"`, `"on-failure"` (default), `"always"` (restart even on clean exit) |
| `startupTimeout` | Milliseconds to wait for the process to print its readiness signal (see "Readiness" below) |
| `env` | Optional env-var overrides |

## Lifecycle

1. **Start.** When a session begins (or the plugin is enabled mid-session, after a restart), Claude Code spawns the monitor process. Stdin is closed; stdout/stderr are captured per `outputHandling`.
2. **Run.** The process is expected to run until killed. Print readiness signal on stdout once initialized (see below).
3. **Restart.** Per `restart` policy, with exponential backoff (1s, 2s, 4s, max 30s) capped at 5 restarts in 60s. After that, monitor is disabled with a warning.
4. **Stop.** On session end, plugin disable, or plugin uninstall. Claude Code sends SIGTERM, waits 5s, then SIGKILL.

## Readiness signal

By default Claude Code assumes a monitor is ready as soon as it spawns. For monitors that have meaningful initialization (file scan, network connect), print a single line:

```
::ready::
```

To stdout (or whatever `outputHandling` directs to). Claude Code will wait up to `startupTimeout` ms for this line; if it doesn't appear, the monitor is killed and restarted.

## Output handling modes

### `"log"` (default)

stdout/stderr go to `~/.claude/logs/plugins/<plugin>-<monitor>.log`. Useful for diagnostics; not visible to the model. Most monitors should use this — the model only needs to know about meaningful events, not raw output.

### `"prompt"`

stdout lines are injected as user-visible context messages, prefixed with `[<plugin>:<monitor>]`. Use sparingly — too much output drowns the conversation. Throttle in your monitor:

```bash
# emit a summary line every 30s, not per-event
while inotifywait -e modify .; do
  count=$((count + 1))
done &

while true; do
  if [[ $count -gt 0 ]]; then
    echo "[$(date +%T)] $count files changed since last update"
    count=0
  fi
  sleep 30
done
```

### `"silent"`

Output discarded. Use for monitors that side-effect via the filesystem or network and have nothing useful to print.

## Patterns

### Filesystem watcher (Linux)

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT="$1"

echo "::ready::"

inotifywait -m -r -e create,modify,delete --format '%w%f %e' "$PROJECT" |
  while read -r path event; do
    case "$path" in
      */.git/*) continue ;;        # ignore git noise
      */node_modules/*) continue ;;
    esac
    echo "[$event] $path"
  done
```

### Log tailer

```bash
#!/usr/bin/env bash
LOG_PATH="$1"
echo "::ready::"
exec tail -F "$LOG_PATH" 2>/dev/null
```

### Periodic refresh

```bash
#!/usr/bin/env bash
echo "::ready::"
while true; do
  sleep 300                           # 5 min
  ./refresh-cache.sh "$CLAUDE_PLUGIN_DATA"
done
```

## Vs hooks

| Concern | Monitor | Hook |
|---|---|---|
| When it runs | Always while session is active | On a specific event |
| Process model | Long-running daemon | Short-lived (per event) |
| Cost | Memory + CPU continuously | Negligible when idle |
| Use case | "Watch X" | "On Y, do Z" |

If your need can be expressed as a hook (e.g. "on PreToolUse, check whether the file's been modified externally"), use a hook. Monitors should be reserved for genuinely continuous work.

## Resource limits

Monitors compete with the user's session for CPU. Best practices:

- Use `nice` or set a low priority
- Avoid busy loops; sleep generously between checks
- Don't read large files repeatedly — cache reads, watch for filesystem events
- Memory should stay under ~50 MB for a typical monitor

If a monitor needs more resources, it might belong as a separate user-managed daemon that the plugin merely *talks to* via a socket or IPC mechanism.

## Multiple monitors

A plugin can declare multiple monitors. They run independently:

```json
{
  "monitors": {
    "watcher": { ... },
    "syncer": { ... }
  }
}
```

Each gets its own log file, its own restart policy, its own readiness signal. Communication between monitors should go through `${CLAUDE_PLUGIN_DATA}` — there's no IPC contract Claude Code mediates.

## Disabling a monitor without disabling the plugin

Currently no first-class way; the plugin author can expose a `userConfig` flag the monitor checks at startup:

```bash
if [[ "$(jq -r .enableWatcher "$CLAUDE_PLUGIN_CONFIG")" != "true" ]]; then
  echo "watcher disabled in config; exiting"
  exit 0
fi
```

A clean exit + `restart: "never"` means the monitor stays off until the session restarts.

## Testing locally

```bash
claude --plugin-dir ./my-plugin

# Check monitor status
> /monitor list
> /monitor logs <plugin>:<monitor>      # tail log file
> /monitor restart <plugin>:<monitor>
```
