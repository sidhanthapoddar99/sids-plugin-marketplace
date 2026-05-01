# Hot-swap matrix

`/reload-plugins` re-reads all active plugins from the cache without restarting the session. Most components pick up edits this way. Hooks are the consistent exception.

## The matrix

| Component | `/reload-plugins` picks up edits? | Notes |
|---|---|---|
| **Skill** (`skills/<name>/SKILL.md`) | Yes | Frontmatter and body re-parsed |
| **Slash command** (`commands/<name>.md`) | Yes | Same as skills |
| **Subagent** (`agents/<name>.md`) | Yes | Same |
| **MCP server** (`.mcp.json` / `mcpServers`) | Yes | Subprocess restarted, tool list refetched |
| **LSP server** (`.lsp.json` / `lspServers`) | Yes | Subprocess restarted |
| **Background monitor** (`monitors/...`) | Yes | Subprocess restarted (long-running monitors are killed and re-spawned) |
| **Theme** (`themes/<name>.json`) | Yes | New themes appear in `/theme` |
| **Output style** | Yes | |
| **Channel** | Yes | Subprocess restarted |
| **Bin wrapper** (`bin/<name>`) | Yes | `$PATH` membership refreshed |
| **Plugin-shipped `settings.json`** | Yes | New defaults applied |
| **Hooks** (`hooks/hooks.json` / `hooks`) | **No — full session restart required** | Hooks load at session start only |

> Source: official `/reload-plugins` documentation explicitly excludes hook changes.

## Why hooks are the exception

Hooks are indexed at session start into a dispatch table keyed by event type (`PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `Stop`, `SubagentStop`, `UserPromptSubmit`, `PreCompact`, `Notification`). The dispatcher is built once and not rebuilt during a session — the cost of dynamic hook loading would be paid on every event dispatch, and the consistency guarantees are nicer when the hook set is known to be stable for the session's duration.

In practice this means:

- Edited a hook's `command`? Restart.
- Added a new hook to an already-enabled plugin? Restart.
- Removed a hook? Restart (the old one will keep firing until restart).
- Just enabled a plugin that ships hooks? Restart.

Skill, agent, command, MCP, LSP, and monitor edits don't require restart — `/reload-plugins` is sufficient.

## What `/reload-plugins` actually does

1. Re-reads `enabledPlugins` from all applicable scopes (re-computes the union)
2. Re-scans `~/.claude/plugins/cache/` for each enabled plugin
3. Re-validates each `plugin.json` against the schema
4. Tears down and rebuilds: skill registry, command registry, agent registry, theme list, output style list
5. Restarts MCP, LSP, monitor, channel subprocesses (graceful where possible)
6. Refreshes `$PATH` for `bin/` wrappers
7. Reports aggregate counts: `Reloaded: 5 plugins · 4 skills · 5 agents · 1 hook · 0 plugin MCP servers · 1 plugin LSP server`

The hook count in the output is informational — the dispatcher built at session start is *not* rebuilt.

## When `/reload-plugins` is enough vs. when to restart

| Change | Action |
|---|---|
| Edit a skill body or frontmatter | `/reload-plugins` |
| Edit an agent | `/reload-plugins` |
| Edit a slash command | `/reload-plugins` |
| Add a new skill / command / agent to enabled plugin | `/reload-plugins` |
| Edit MCP server `command` or `args` | `/reload-plugins` |
| Edit LSP server config | `/reload-plugins` |
| Edit a hook command, matcher, or event | **Restart session** |
| Add a hook to a plugin (any) | **Restart session** |
| Enable a plugin that ships hooks | **Restart session** |
| Update a plugin (cache version bump) | `/reload-plugins` (hooks still need restart) |
| Wipe the cache | **Restart session** (`/reload-plugins` will report missing plugins) |

## Diagnostic tip

If you can't tell whether your hook is loaded:

```
/hooks
```

Lists hooks loaded in the current session. If the hook you're looking for isn't there, you haven't restarted since the change.

For other components, the `/reload-plugins` aggregate output and the `/plugin` Errors tab are the canonical signals.

## See also

- [`02_activation-and-loading.md`](./02_activation-and-loading.md) — what loading actually means per component
- [`../12_cli-and-ui/`](../12_cli-and-ui/00_index.md) — `/reload-plugins`, `/hooks`, `/plugin` UI
- [`../11_testing-and-iteration/`](../11_testing-and-iteration/00_index.md) — fast iteration with `--plugin-dir`
- Official: [`/reload-plugins`](https://code.claude.com/docs/en/plugins-reference)
