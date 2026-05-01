# Multi-plugin merging

When multiple plugins are enabled simultaneously, their components compose into a single runtime registry. Most components compose without conflict — skills, commands, agents, themes are namespaced by name and addressed individually. MCP servers and hooks are the two surfaces where collisions matter.

## What composes cleanly

| Component | Composition rule | Collision behaviour |
|---|---|---|
| **Skills** | Each skill is a separate entry in the model's skill list | If two plugins ship a skill named `format`, both register; the model sees both |
| **Slash commands** | Same — each command is its own entry | Same as skills |
| **Subagents** | Each agent is its own entry | Same |
| **Themes** | All available in `/theme` | Same |
| **Output styles** | All available | Same |
| **Bin wrappers** | All added to `$PATH` | Last writer wins per name (subsequent plugins override the same `bin/<name>`) |
| **LSP servers** | Each language server runs as a separate process | Two LSP servers for the same language: both run; behaviour may be unintended |

Naming collisions are mostly cosmetic — the model can distinguish two skills with similar names by their descriptions. By convention, plugin authors prefix component names with the plugin name when collision is plausible.

## MCP server merging

This is where collisions matter most. MCP servers across enabled plugins are merged into a single MCP server registry. **Server name** is the key.

Sources merged:

1. Each enabled plugin's `.mcp.json` (or `mcpServers` declaration in `plugin.json`)
2. User-level `~/.claude/.mcp.json` (if present)
3. Project-level `<repo>/.mcp.json` (if present)

If two sources declare a server with the same name, the runtime surfaces a load error in the `/plugin` Errors tab. The plugin whose server failed to register is partially broken — its tools don't get added to the model's tool list.

**Convention: plugin-prefix server names.** Instead of:

```json
{ "mcpServers": { "filesystem": { "command": "..." } } }
```

use:

```json
{ "mcpServers": { "myplugin-filesystem": { "command": "..." } } }
```

This eliminates collisions across plugins and makes diagnostics easier — when a tool surfaces in a session, the prefix tells you which plugin shipped it.

The merging order is roughly: project `.mcp.json` → user `.mcp.json` → plugins (in some plugin-load order). Project-level configs typically win on collision because they're most specific to the user's intent for *this* repo, but the load-error surface is the canonical signal — don't rely on order, name uniquely.

## Hook merging

Hooks across plugins compose into a single dispatch table keyed by event:

| Event | All matching hooks fire? |
|---|---|
| `PreToolUse` | Yes — all matching hooks fire (in some order) |
| `PostToolUse` | Yes |
| `Stop`, `SubagentStop` | Yes |
| `SessionStart`, `SessionEnd` | Yes |
| `UserPromptSubmit` | Yes |
| `PreCompact`, `Notification` | Yes |

A single event firing dispatches all matching hooks across all enabled plugins. Hooks don't override each other — they all run. Order between plugins isn't part of the public contract; within a single plugin, the order in `hooks.json` determines the order.

If a `PreToolUse` hook with `block: true` fires, that takes precedence — other hooks for the same event still run, but the tool call is blocked. (The semantics of multiple hooks each issuing a `block` is documented in the hooks reference.)

## User and project `.mcp.json` and plugin merging

User-level `~/.claude/.mcp.json` and project-level `<repo>/.mcp.json` exist independently of plugins. They merge with plugin-shipped MCP configs into one MCP registry per session.

This means:

- A user can declare MCP servers without writing a plugin
- A repo can ship an `.mcp.json` for project-wide MCP servers (typically gitignored or committed depending on whether the servers reference local-only paths)
- Plugin-shipped MCP servers compose with both

Naming collision risk extends across all three sources. Plugin-prefixing is the convention even though the project's own `.mcp.json` usually wouldn't collide with itself.

## Channels

Channels (MCP-server-backed conversation channels) are scoped to a server reference, so collisions show up first in the MCP server registry. A channel whose `server` field doesn't match any registered MCP server fails to register.

## Hooks-merge gotcha

Because hooks are loaded only at session start (see [`03_hot-swap-matrix.md`](./03_hot-swap-matrix.md)), the merge happens once per session. Enabling a new plugin with hooks mid-session means those hooks aren't merged in — restart to pick them up.

## Diagnostic

```bash
# See all MCP servers including those from plugins:
/mcp

# See all hooks loaded this session:
/hooks

# Errors from any merge collision:
# /plugin → Errors tab
# OR
claude plugin list --json | jq '.errors'
```

## See also

- [`02_activation-and-loading.md`](./02_activation-and-loading.md) — load order within a single plugin
- [`03_hot-swap-matrix.md`](./03_hot-swap-matrix.md) — hooks load only at session start
- [`../06_capabilities/`](../06_capabilities/00_index.md) — per-capability composition rules
- [`../12_cli-and-ui/`](../12_cli-and-ui/00_index.md) — `/mcp` and `/hooks` slash commands
