# Storage and Scope

Where plugin files live on disk, and which scopes' settings files mark them enabled. The two are independent — files live once, registration is a boolean per scope.

## The split

| Concern | Where it lives | Cardinality |
|---|---|---|
| **Cache** — actual plugin files | `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | One copy per version, user-level only |
| **Registration** — "is this plugin enabled?" | `enabledPlugins` boolean in each scope's `settings.json` | One boolean per scope, unioned at session start |
| **Persistent data** — survives updates | `~/.claude/plugins/data/<plugin-id>/` | One per plugin id, cross-version |

Multi-scope enable is harmless: the union is computed at session start, the plugin loads once. Plugin files never duplicate per scope — there is no project-local cache.

## Sub-pages

| File | Topic |
|---|---|
| [`01_cache-layout.md`](./01_cache-layout.md) | The `~/.claude/plugins/cache/` tree, multiple versions side-by-side, what's inside a cached plugin |
| [`02_data-dir.md`](./02_data-dir.md) | `~/.claude/plugins/data/<plugin-id>/`, slugification rule, what to store there |
| [`03_scope-union.md`](./03_scope-union.md) | The four scopes, precedence, how `enabledPlugins` is unioned |
| [`04_settings-files.md`](./04_settings-files.md) | Each settings file's path, what goes in it, the `enabledPlugins` shape |
| [`05_env-vars.md`](./05_env-vars.md) | `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${user_config.KEY}`, auto-update vars |

## Related chapters

- [`../07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/00_index.md) — install flow, updates, garbage collection
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — when the cache survives uninstall and how to wipe it
- [`../../ClaudeSettings/`](../../ClaudeSettings/00_index.md) — broader settings file model (status line, permissions, env vars, keybindings)
