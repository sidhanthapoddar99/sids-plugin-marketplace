---
title: Status Line
description: The main statusLine setting — format, common patterns, and why a plugin cannot ship one
---

# Status Line

The status line is the strip Claude Code renders below the prompt, refreshed continuously while the session is running. It's a per-user (or per-project) preference configured in `settings.json` under the `statusLine` key.

## Format

```json
{
  "statusLine": {
    "type": "command",
    "command": "<shell command>",
    "padding": 0
  }
}
```

| Field | Notes |
|---|---|
| `type` | Always `"command"` for shell-driven status lines |
| `command` | A shell command whose stdout becomes the rendered status line |
| `padding` | Optional left padding in characters |

The command runs on every refresh. Output is read as a single line (the first line of stdout). Keep it cheap — slow status-line commands degrade interactive responsiveness.

## Common patterns

### Static informational line

```json
{
  "statusLine": {
    "type": "command",
    "command": "echo \"$USER@$(hostname) — $(pwd)\""
  }
}
```

### Git context

```json
{
  "statusLine": {
    "type": "command",
    "command": "echo \"$(git branch --show-current 2>/dev/null) | $(git status --porcelain | wc -l | tr -d ' ') changes\""
  }
}
```

### Token / cost telemetry

A common pattern is to point the status line at a small helper script that reads session telemetry from disk and renders model name, context-window usage, and cost so far. Such helpers can be installed at user scope or distributed via dotfiles — but **not via a plugin**.

## NOT plugin-shippable

A plugin **cannot ship the main `statusLine`**. The two keys a plugin's root-level `settings.json` is allowed to define are:

| Key | What it does | Plugin-shippable? |
|---|---|---|
| `agent` | Activates one of the plugin's custom agents as the main thread (replaces system prompt, tool restrictions, model) | yes |
| `subagentStatusLine` | Status line shown specifically when a subagent is active | yes |
| `statusLine` (main) | Main thread's status line | **no** |
| `permissions` | Tool allow/deny | no |
| anything else | — | no |

Any other key in a plugin's root-level `settings.json` is silently ignored. See [Plugin-Shipped Settings](../ClaudePlugin/05_plugin-anatomy/05_plugin-shipped-settings.md) for the full constraint and the rationale.

The reasoning: the main status line is the user's identity strip — it shouldn't change just because a plugin was enabled. Subagent status lines are scoped to the subagent's lifetime, so they're a reasonable thing for a plugin to ship as part of an agent's UX.

## Main status line vs subagent status line

| Property | Main `statusLine` | `subagentStatusLine` |
|---|---|---|
| Scope of effect | The whole session | Only while a subagent is the active thread |
| Where it can live | User / project / local / managed `settings.json` | Same, **plus** a plugin's root-level `settings.json` |
| Plugin-shippable? | No | Yes |
| Typical content | Git branch, cost, env name | Agent name, agent role, current task |

If a plugin ships a custom agent and wants the user to know when that agent is active, `subagentStatusLine` is the right surface. If a user wants their *whole-session* status line styled, that's a personal `~/.claude/settings.json` config — and remains untouched by plugin installs.

## Disabling

```json
{
  "statusLine": null
}
```

Or simply omit the key. There's no separate "disable" toggle.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Status line empty | `command` failed (non-zero exit, no stdout). Test it in a shell first |
| Session feels laggy | `command` is slow. Cache its output, or move heavy work to a background process |
| Status line doesn't update | Some commands (e.g. those reading dotfiles) only refresh on session start. Restart the session |
| Plugin's `statusLine` ignored | Correct — main `statusLine` is not plugin-shippable. Use `subagentStatusLine` instead |

## See also

- [Settings Files and Precedence](./01_settings-files-and-precedence.md) — where to put a `statusLine` config
- [Plugin-Shipped Settings](../ClaudePlugin/05_plugin-anatomy/05_plugin-shipped-settings.md) — the two keys a plugin *can* ship
- Official: [Status line configuration](https://code.claude.com/docs/en/statusline)
