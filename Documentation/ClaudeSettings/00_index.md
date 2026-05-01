---
title: Claude Code Settings Reference
description: The user/project/local/managed settings surface — the runtime side of Claude Code that plugins cannot ship
---

# Claude Code Settings Reference

This doc set covers the **user-settings surface** of Claude Code: the things configured in `settings.json` (and a handful of related files) at the user, project, local, or managed scope. It is the companion to [Claude Code Plugins](../ClaudePlugin/00_index.md), which covers the plugin-authoring side.

## The plugin-vs-settings boundary

Plugins package capabilities (skills, commands, agents, hooks, MCP servers, themes, monitors). Settings configure the runtime that loads them — what tools the user has allowed, what their status line looks like, which marketplaces they trust, which plugins are enabled in which scope. **A plugin cannot ship a `permissions` block, a main `statusLine`, or keybindings** — those belong to the user. The only two settings keys a plugin's root-level `settings.json` may apply are `agent` and `subagentStatusLine` (see [Plugin-Shipped Settings](../ClaudePlugin/05_plugin-anatomy/05_plugin-shipped-settings.md)). Everything else in `settings.json` is the user's territory.

## Sub-pages

| Page | Covers |
|---|---|
| [01 Settings Files and Precedence](./01_settings-files-and-precedence.md) | The four `settings.json` locations, JSON format, Managed > Local > Project > User precedence, the union rule |
| [02 Status Line](./02_status-line.md) | Main `statusLine` config — format, common patterns, why it's not plugin-shippable, distinction from subagent status line |
| [03 Permissions and Keybindings](./03_permissions-and-keybindings.md) | `permissions` keys in `settings.json` and the separate `~/.claude/keybindings.json` file |
| [04 Environment Variables](./04_environment-variables.md) | User-controlled env vars — `DISABLE_AUTOUPDATER`, `FORCE_AUTOUPDATE_PLUGINS`, marketplace auth tokens |
| [05 Plugin-Related Settings](./05_plugin-related-settings.md) | Settings keys that *are about* plugins but live in `settings.json`: `enabledPlugins`, `extraKnownMarketplaces`, `strictKnownMarketplaces`, `pluginConfigs[].options` |

## How this set relates to the plugin docs

| Concern | Lives here | Lives in `ClaudePlugin/` |
|---|---|---|
| Where `settings.json` files are stored | [01](./01_settings-files-and-precedence.md) | [03_storage-and-scope/04_settings-files.md](../ClaudePlugin/03_storage-and-scope/04_settings-files.md) |
| What the runtime sees at session start | — | [02_mental-model/02_what-the-runtime-sees.md](../ClaudePlugin/02_mental-model/02_what-the-runtime-sees.md) |
| Multi-scope union (`enabledPlugins`) | [01](./01_settings-files-and-precedence.md), [05](./05_plugin-related-settings.md) | [03_storage-and-scope/03_scope-union.md](../ClaudePlugin/03_storage-and-scope/03_scope-union.md) |
| Plugin-shipped `agent` / `subagentStatusLine` | [02](./02_status-line.md) (boundary) | [05_plugin-anatomy/05_plugin-shipped-settings.md](../ClaudePlugin/05_plugin-anatomy/05_plugin-shipped-settings.md) |
| `extraKnownMarketplaces` | [05](./05_plugin-related-settings.md) | [04_marketplaces/06_extra-known-marketplaces.md](../ClaudePlugin/04_marketplaces/06_extra-known-marketplaces.md) |
| `strictKnownMarketplaces` (managed) | [05](./05_plugin-related-settings.md) | [04_marketplaces/07_managed-restrictions.md](../ClaudePlugin/04_marketplaces/07_managed-restrictions.md) |
| Plugin-side env vars (`${CLAUDE_PLUGIN_ROOT}`, etc.) | — | [15_reference/01_env-vars-cheatsheet.md](../ClaudePlugin/15_reference/01_env-vars-cheatsheet.md) |

## See also

- [Claude Code Plugins — Index](../ClaudePlugin/00_index.md) — the companion doc set covering plugin authoring
- [What the runtime sees](../ClaudePlugin/02_mental-model/02_what-the-runtime-sees.md) — how the runtime composes settings from all four scopes at session start
- Official: [Claude Code settings](https://code.claude.com/docs/en/settings) — the canonical reference
