---
title: Hooks
description: Event-driven shell commands and prompts — events, JSON I/O contract, the session-start-only loading rule, and trust posture
---

# Hooks

A **hook** is a runtime-fired action attached to a Claude Code lifecycle event. Hooks can block tool calls, inject context, log activity, or trigger external integrations. They come in two types — **command hooks** (shell commands) and **prompt hooks** (LLM evaluation).

## Where it lives

```
my-plugin/
└── hooks/
    ├── hooks.json             # required
    ├── validate-write.sh      # referenced from hooks.json
    └── load-context.sh
```

Default file: `hooks/hooks.json`. Override via `"hooks"` in `plugin.json` (additive — supplements the default scan, doesn't replace it).

## Schema — `hooks.json`

The plugin format wraps events in a `hooks` object (vs the user-settings format which puts events at the top level):

```json
{
  "description": "Validation hooks for code quality (optional)",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/validate-write.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Verify task completion: tests run, build succeeded. Return 'approve' or 'block' with reason."
          }
        ]
      }
    ]
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `description` | no | Plugin-level description shown in `/hooks` |
| `hooks` | yes | Object keyed by event name. Each event maps to an array of matcher blocks |
| `matcher` | yes (per event entry) | Pattern matching tool names (or `"*"` for all). Regex-supported, case-sensitive |
| `hooks` (inner) | yes | Array of `{type, command/prompt, timeout?}` |

## Hook events

| Event | When | Use for |
|---|---|---|
| `PreToolUse` | Before any tool runs | Validate, modify, deny tool calls |
| `PostToolUse` | After tool completes | React to results, log, follow-up |
| `UserPromptSubmit` | User submits a prompt | Inject context, validate input |
| `Stop` | Main agent considers stopping | Verify completion |
| `SubagentStop` | Subagent considers stopping | Validate subagent task |
| `SessionStart` | Session begins | Load context, set env vars |
| `SessionEnd` | Session ends | Cleanup, logging |
| `PreCompact` | Before context compaction | Preserve critical info |
| `Notification` | Claude sends a notification | Log, react, forward |

## Hook types

### Command hooks

Execute a shell command. Receives the event payload as JSON on stdin.

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check.sh",
  "timeout": 60
}
```

Default timeout: 60s.

### Prompt hooks

Evaluate via an LLM call. The prompt receives event-payload variables (`$TOOL_INPUT`, `$USER_PROMPT`, etc.).

```json
{
  "type": "prompt",
  "prompt": "Evaluate file write safety: $TOOL_INPUT. Return 'approve' or 'deny'.",
  "timeout": 30
}
```

Supported events: `Stop`, `SubagentStop`, `UserPromptSubmit`, `PreToolUse`. Default timeout: 30s.

## I/O contract

### Input (stdin, JSON)

Every hook receives:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "PreToolUse"
}
```

Plus event-specific fields: `tool_name`, `tool_input`, `tool_result` (Pre/PostToolUse); `user_prompt` (UserPromptSubmit); `reason` (Stop).

### Output

**Standard fields (any hook):**

```json
{
  "continue": true,
  "suppressOutput": false,
  "systemMessage": "Message visible to Claude"
}
```

**PreToolUse-specific:**

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": { "field": "modified" }
  },
  "systemMessage": "Why this was decided"
}
```

**Stop / SubagentStop:**

```json
{
  "decision": "approve|block",
  "reason": "Tests must run before stopping"
}
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success — stdout shown in transcript |
| `2` | Blocking error — stderr fed back to Claude |
| Other | Non-blocking error |

## Environment variables

Available in command hooks:

| Variable | Resolves to |
|---|---|
| `CLAUDE_PLUGIN_ROOT` | Plugin install root — use for portable references |
| `CLAUDE_PLUGIN_DATA` | Plugin persistent data dir |
| `CLAUDE_PROJECT_DIR` | Current project root |
| `CLAUDE_ENV_FILE` | **SessionStart only** — write `export X=Y` lines here to persist env vars into the session |
| `CLAUDE_CODE_REMOTE` | Set if running in remote context |

## Matchers

| Pattern | Matches |
|---|---|
| `"Write"` | Exact tool name |
| `"Read|Write|Edit"` | Multiple tools (regex alternation) |
| `"*"` | All tools |
| `"mcp__.*"` | All MCP tools (regex) |
| `"mcp__.*__delete.*"` | All MCP delete-style tools |

Matchers are case-sensitive.

## Lifecycle — the consistent exception

Hooks are loaded **only at session start**. They are the consistent exception in the hot-swap matrix:

| Action | Effect |
|---|---|
| Edit `hooks.json` | **No effect** until session restart |
| Add new hook script | Not picked up until session restart |
| Edit hook command/prompt | Not picked up until session restart |
| `/reload-plugins` | Does **not** reload hooks |
| Full restart (`exit` and re-launch) | Picks up hook changes |

This is unique among capability surfaces. See [`../07_lifecycle-and-runtime/03_hot-swap-matrix.md`](../07_lifecycle-and-runtime/03_hot-swap-matrix.md).

Use `/hooks` to inspect hooks loaded in the current session.

## Parallel execution

All matching hooks for an event run **in parallel**. They don't see each other's output. Don't write hooks that depend on execution order.

## Boundaries

A hook can:

- Block a tool call (exit 2 + stderr, or `permissionDecision: "deny"`)
- Modify tool input before execution (`updatedInput`)
- Inject context for the model (`systemMessage`, stdout)
- Run any shell command at the user's privilege

A hook **cannot**:

- See other concurrent hooks' output
- Persist data through normal Claude Code APIs (use `${CLAUDE_PLUGIN_DATA}`)
- Hot-reload mid-session

## Trust class

**Unsandboxed.** Hooks run as subprocesses at the user's shell privilege. Same trust model as `.git/hooks/`. Only install plugins with hooks from sources you trust.

## When to use a hook vs alternatives

| Goal | Use |
|---|---|
| Auto-format on save / block dangerous commands / log every tool call | Hook |
| Add new tools the model can call | [MCP server](./05_mcp-servers.md) |
| Run a long-running watcher whose output the model sees | [Monitor](./07_monitors.md) |
| Provide a CLI the model can shell into | [Bin wrapper](./11_bin-wrappers.md) |

## Security best practices

- Validate JSON input with `jq` and reject unexpected shapes
- Quote all bash variables (`"$file_path"`, never `$file_path`)
- Reject path traversal (`*".."*`) and sensitive files (`*".env"*`)
- Set explicit `timeout` — don't rely on the 60s default for fast checks
- Don't log sensitive values (`tool_input` may contain secrets)

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/hook-development/`
- [`../07_lifecycle-and-runtime/03_hot-swap-matrix.md`](../07_lifecycle-and-runtime/03_hot-swap-matrix.md) — why hooks need restart
- [Monitors](./07_monitors.md) — for long-running, not event-fired
- [Capabilities index](./00_index.md)
