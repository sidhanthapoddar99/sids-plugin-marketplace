---
name: monitor-development
description: Use when authoring `monitors` — long-running shell processes Claude Code spawns for the lifetime of a session, where each stdout line becomes a notification the model sees. Covers the manifest declaration, the four required and optional fields, the `when` gate (`always` vs `on-skill-invoke:<skill>`), trust model (unsandboxed), and patterns for filesystem watchers, log tailers, and skill-gated triggers.
---

# Authoring monitors

A **monitor** is a shell command Claude Code spawns at session start (or skill-invoke time) and keeps running for the lifetime of the session. Each stdout line is delivered to the model as a notification. Monitors require Claude Code v2.1.105+.

## When to use

- Watch the filesystem and surface meaningful changes
- Tail an external log and emit relevant lines
- Run a periodic health check whose output the model should see

## When NOT to use

- One-shot side effects → a hook (PreToolUse, PostToolUse, etc.) is lighter
- Notifications to external surfaces → a `Notification` hook with a webhook script
- Bidirectional conversation surfaces → channels (see [`../channel-development/SKILL.md`](../channel-development/SKILL.md))

## Manifest shape

Either inline in `plugin.json`:

```json
{
  "monitors": [
    {
      "name": "file-watcher",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/watch-files.sh ${CLAUDE_PROJECT_DIR}",
      "description": "Notify on src/ changes",
      "when": "always"
    }
  ]
}
```

Or as a separate file at `monitors/monitors.json` (an array of the same shape).

## Required and optional fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Identifier. Used in error messages and `/doctor` output |
| `command` | yes | Shell command to run. `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, `${user_config.<key>}` all substitute |
| `description` | yes | One-line description shown in `/plugin` and used by the model to interpret the notifications |
| `when` | optional | `"always"` (default — start at session start) or `"on-skill-invoke:<skill-name>"` (start when the named skill is dispatched) |

The full set is just those four. There is **no** `args`, `env`, `outputHandling`, `restart`, `startupTimeout`, or readiness signal — Claude Code uses the command verbatim and treats every stdout line as a notification.

## Lifecycle

- **Spawned** when the gating condition is met (`always` = at session start; `on-skill-invoke:<x>` = when skill `<x>` first dispatches in the session).
- **Running** for the lifetime of the session. **Doesn't stop mid-session if the plugin is disabled** — only on session end.
- **Stopped** when the session ends (SIGTERM).

There's no auto-restart, no exponential backoff. If the process exits, it's gone for the rest of the session.

## Output semantics

Each line printed to stdout is delivered to the model as a separate notification. The model sees them prefixed with the monitor's `name` (and possibly `description`). Plan accordingly:

- Don't emit one line per filesystem event in a busy directory — the model will drown
- Throttle or batch
- Send a *summary* line periodically rather than raw events

stderr is captured for debugging but not surfaced to the model.

## Patterns

### Filesystem watcher (Linux)

```bash
#!/usr/bin/env bash
# watch-files.sh
set -euo pipefail
PROJECT="$1"

# Throttle: aggregate events for 5s, then emit a summary
{ inotifywait -m -r -e create,modify,delete --format '%w%f %e' "$PROJECT" 2>/dev/null \
    | grep -v -E '/(\.git|node_modules)/' ; } |
  while read -r path event; do
    last_event="$path ($event)"
    if [[ -z "$timer_pid" ]] || ! kill -0 "$timer_pid" 2>/dev/null; then
      ( sleep 5; echo "Files changed; latest: $last_event" ) &
      timer_pid=$!
    fi
  done
```

### Periodic summary

```bash
#!/usr/bin/env bash
# poll-status.sh
while true; do
  status=$(curl -s "${CLAUDE_PLUGIN_OPTION_STATUSURL}" | jq -r .summary)
  echo "[$(date +%T)] status: $status"
  sleep 300
done
```

### Skill-gated monitor

A monitor with `when: "on-skill-invoke:my-skill"` only starts when `my-skill` is dispatched. Useful for expensive monitors you only want running when relevant:

```json
{
  "monitors": [
    {
      "name": "build-watcher",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/watch-build.sh",
      "description": "Watch the build for failures",
      "when": "on-skill-invoke:debug-build"
    }
  ]
}
```

## Trust and security

Monitors run **unsandboxed at the same privilege as the user's shell**. Same trust class as hooks. They can execute arbitrary code; users should only enable plugins from sources they trust.

## Multiple monitors

A plugin can declare multiple monitors. They run independently, each with its own process and `when` gate. Communication between them goes through `${CLAUDE_PLUGIN_DATA}` — no IPC contract Claude Code mediates.

## Common pitfalls

- **Inventing fields.** `outputHandling`, `args`, `env`, `restart`, `::ready::` sentinels are not part of the monitor schema. Use what's listed above; everything else is just shell pipeline plumbing inside `command`.
- **Verbose output.** Each line is a notification. A monitor that streams 100 lines/s will drown the conversation.
- **Long startup.** Claude Code spawns and proceeds; long startup means initial output is delayed but doesn't block session readiness.
- **Assuming auto-restart.** It doesn't restart. If your monitor needs resilience, build the loop inside the script.

## Reference

- Official: [Monitors](https://code.claude.com/docs/en/plugins-reference#monitors) (ground truth)
