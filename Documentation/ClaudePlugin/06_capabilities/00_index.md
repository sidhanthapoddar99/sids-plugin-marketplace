---
title: Capabilities
description: The eleven capability surfaces a plugin can ship — what each one is, where it lives, and how to choose between them
---

# Capabilities

A plugin is a bundle of **capabilities**. Each capability surface is its own opt-in folder or manifest field, with its own runtime semantics, lifecycle, and trust class. This folder is a per-surface reference: what it *is*, where it lives in the plugin layout, the schema, lifecycle, and boundaries.

For *how to author* one, the companion plugin `plugins/ai-toolkit-dev/` ships task-oriented topic skills that pair with each page here.

## The eleven surfaces

| # | Surface | File / manifest field | Trust class | Hot-swap |
|---|---|---|---|---|
| 1 | **Skill** | `skills/<name>/SKILL.md` | model-loaded | yes |
| 2 | **Slash command** | `commands/<name>.md` | model-loaded | yes |
| 3 | **Subagent** | `agents/<name>.md` | model-loaded | next invoke |
| 4 | **Hook** | `hooks/hooks.json` | unsandboxed | **no** (restart) |
| 5 | **MCP server** | `.mcp.json` / `mcpServers` | unsandboxed | restart for config |
| 6 | **LSP server** | `.lsp.json` / `lspServers` | unsandboxed | restart for config |
| 7 | **Monitor** | `monitors/monitors.json` / `monitors` | unsandboxed | restart |
| 8 | **Channel** | `channels` (binds to MCP server) | unsandboxed | restart |
| 9 | **Theme** | `themes/<name>.json` | UI only | yes |
| 10 | **Output style** | `outputStyles` | model-loaded | yes |
| 11 | **Bin wrapper** | `bin/<name>` | unsandboxed | yes |

Hooks are the consistent exception in the hot-swap matrix. See [`../07_lifecycle-and-runtime/03_hot-swap-matrix.md`](../07_lifecycle-and-runtime/03_hot-swap-matrix.md).

## Decision table — which surface for which goal

| I want to… | Use |
|---|---|
| Auto-fire context when the user's prompt matches a topic | [Skill](./01_skills.md) |
| Provide a user-invoked named action (`/<name>`) | [Slash command](./02_slash-commands.md) |
| Spawn a specialist Claude with a different system prompt | [Subagent](./03_subagents.md) |
| Act on Claude Code lifecycle events (PreToolUse, Stop, …) | [Hook](./04_hooks.md) |
| Expose external tools the model can call | [MCP server](./05_mcp-servers.md) |
| Provide code intelligence (diagnostics, definitions) for a language | [LSP server](./06_lsp-servers.md) |
| Run an always-on background watcher whose output the model sees | [Monitor](./07_monitors.md) |
| Surface external messaging (Slack/Discord) into the conversation | [Channel](./08_channels.md) |
| Ship a color scheme | [Theme](./09_themes.md) |
| Change response shape / formatting rules | [Output style](./10_output-styles.md) |
| PATH-install a CLI tool the model can shell into | [Bin wrapper](./11_bin-wrappers.md) |

## Description-as-trigger

Skills, slash commands, and subagents share a pattern: a short `description` field is always loaded into model context; the body loads only when the description matches user intent. This is the single biggest authoring lever — vague descriptions don't trigger; specific, trigger-rich descriptions trigger reliably. See [`01_skills.md`](./01_skills.md) and [`03_subagents.md`](./03_subagents.md).

## Trust classes

- **Model-loaded** — content the model reads as instructions or context. No OS-level execution. Skills, commands, agents, output styles, themes.
- **Unsandboxed** — runs as a subprocess at the user's shell privilege. Hooks, MCP servers, LSP servers, monitors, channels (via their MCP server), bins.

There is no middle tier. Plugins are not sandboxed; only install from sources you trust. See [`../05_plugin-anatomy/`](../05_plugin-anatomy/) for trust posture details.

## See also

- [Plugin anatomy](../05_plugin-anatomy/) — folder layout for each capability
- [Lifecycle and runtime](../07_lifecycle-and-runtime/) — when each surface loads, dies, restarts
- [Composition patterns](../08_composition-patterns/) — combining surfaces into workflows
