---
title: Monitors
description: Long-running shell processes whose stdout becomes notifications — schema, the `when` gate, lifecycle, trust posture
---

# Monitors

A **monitor** is a shell command Claude Code spawns at session start (or skill-invoke time) and keeps running for the lifetime of the session. **Each stdout line becomes a notification the model sees.** Useful for tailing logs, watching the filesystem, polling external state.

Requires Claude Code **v2.1.105+**.

## Where it lives

Two equivalent declaration formats:

```
my-plugin/
├── .claude-plugin/plugin.json # method 1 — inline `monitors` field
├── monitors/monitors.json     # method 2 — dedicated file
└── scripts/
    └── watch-files.sh
```

### Inline in `plugin.json`

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

### `monitors/monitors.json`

An array of the same shape:

```json
[
  {
    "name": "file-watcher",
    "command": "...",
    "description": "..."
  }
]
```

## Schema — fields

The full set is just four fields. There is **no** `args`, `env`, `outputHandling`, `restart`, `startupTimeout`, or readiness signal — Claude Code uses the command verbatim and treats every stdout line as a notification.

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Identifier. Used in error messages and `/doctor` |
| `command` | yes | Shell command to run. Substitutions: `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, `${user_config.<key>}` |
| `description` | yes | One-line description shown in `/plugin` and used by the model to interpret notifications |
| `when` | no | `"always"` (default — start at session start) or `"on-skill-invoke:<skill-name>"` |

## The `when` gate

| Value | Behavior |
|---|---|
| `"always"` (default) | Monitor starts at session start |
| `"on-skill-invoke:<skill-name>"` | Monitor starts when the named skill is first dispatched in the session |

Skill-gated monitors keep expensive watchers off until the relevant context is in play.

## Output semantics

Each line printed to stdout is delivered to the model as a separate notification. The model sees them prefixed with the monitor's `name`.

| Behavior | Implication |
|---|---|
| One stdout line = one notification | A monitor that emits 100 lines/s drowns the conversation. Throttle or batch |
| stderr is captured but **not surfaced** to the model | Use stderr for debugging; stdout for the model |
| No structured payload | Just lines of text. Format readably for the model to interpret |

## Lifecycle

| Event | Behavior |
|---|---|
| Session start (with `when: "always"`) | Spawned immediately |
| First skill dispatch (with `when: "on-skill-invoke:<x>"`) | Spawned then |
| Process exits mid-session | **Not restarted** — gone for the rest of the session |
| Plugin disabled mid-session | Monitor keeps running until session end |
| Session end | SIGTERM sent |

Notable: monitors **don't stop mid-session if the plugin is disabled** — only on session end. There's no auto-restart, no exponential backoff. If your monitor needs resilience, build the loop inside the script itself.

## Multiple monitors

A plugin can declare multiple monitors. They run independently, each with its own process and `when` gate. Communication between them goes through `${CLAUDE_PLUGIN_DATA}` — no IPC contract Claude Code mediates.

## Patterns

### Filesystem watcher (Linux)

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT="$1"

# Throttle: aggregate events for 5s, emit a summary
inotifywait -m -r -e create,modify,delete --format '%w%f %e' "$PROJECT" 2>/dev/null \
  | grep -v -E '/(\.git|node_modules)/' \
  | while read -r path event; do
    last_event="$path ($event)"
    if [[ -z "${timer_pid:-}" ]] || ! kill -0 "$timer_pid" 2>/dev/null; then
      ( sleep 5; echo "Files changed; latest: $last_event" ) &
      timer_pid=$!
    fi
  done
```

### Periodic summary

```bash
#!/usr/bin/env bash
while true; do
  status=$(curl -s "${CLAUDE_PLUGIN_OPTION_STATUSURL}" | jq -r .summary)
  echo "[$(date +%T)] status: $status"
  sleep 300
done
```

### Skill-gated

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

## Boundaries

A monitor can:

- Run any shell command for the lifetime of the session
- Read `userConfig` values via `${user_config.<key>}` and `CLAUDE_PLUGIN_OPTION_<KEY>`
- Read/write `${CLAUDE_PLUGIN_DATA}` for persistent state
- Be gated on a specific skill being dispatched

A monitor **cannot**:

- Restart automatically when the process exits
- Stop when the plugin is disabled (session-end only)
- Receive structured input from the model
- Inject anything beyond a stream of lines

## Trust class

**Unsandboxed.** Same trust class as hooks. Monitors execute arbitrary code at the user's shell privilege. Only enable plugins from sources you trust.

## When to use a monitor vs alternatives

| Goal | Use |
|---|---|
| Always-on background watcher whose output the model sees | Monitor |
| One-shot side effect on a specific event | [Hook](./04_hooks.md) |
| Notify an external service (no model awareness needed) | `Notification` hook with a webhook script |
| Bidirectional conversation surface (Slack/Discord) | [Channel](./08_channels.md) |

## Common pitfalls

- **Inventing fields.** `outputHandling`, `args`, `env`, `restart`, `::ready::` sentinels are not part of the schema
- **Verbose output.** Each line is a notification — drowning the conversation
- **Assuming auto-restart.** It doesn't restart. If your monitor needs resilience, build the loop in the script

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/monitor-development/`
- [Reference](../../../docs/Claude%20Plugins/07_reference.md) § Background monitors — ground truth
- [Hooks](./04_hooks.md) — for one-shot event-driven logic
- [Channels](./08_channels.md) — for bidirectional messaging
- Official: [Monitors](https://code.claude.com/docs/en/plugins-reference#monitors)
- [Capabilities index](./00_index.md)
