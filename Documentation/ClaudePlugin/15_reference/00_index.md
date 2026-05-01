# Reference

Catch-all nomenclature index. The earlier chapters cover the lifecycle and authoring story end-to-end at the depth most plugin authors need. This folder is the lookup-table set: every env var, settings key, frontmatter flag, and legacy pattern in one place.

If a name appears anywhere in plugin docs and you don't remember what it does, look here first.

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_env-vars-cheatsheet.md` | Plugin-side and user-side env vars: `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_OPTION_<KEY>`, `${user_config.KEY}`, `DISABLE_AUTOUPDATER`, `FORCE_AUTOUPDATE_PLUGINS` |
| 02 | `02_settings-keys.md` | Keys Claude Code reads from `settings.json`: `enabledPlugins`, `extraKnownMarketplaces`, `strictKnownMarketplaces`, `pluginConfigs`, plus plugin-shipped `agent` and `subagentStatusLine` |
| 03 | `03_frontmatter-flags.md` | YAML frontmatter recognised in skills, commands, agents — including `disable-model-invocation` |
| 04 | `04_legacy-and-migration.md` | The flat `commands/<name>.md` layout, `.claude/<plugin-name>.local.md` files, and migration paths |

## Related chapters

- [`../03_storage-and-scope/`](../03_storage-and-scope/00_index.md) — where the env vars and settings files live on disk
- [`../05_plugin-anatomy/`](../05_plugin-anatomy/00_index.md) — how the manifest fields these reference get authored
- [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) — the auto-update env vars in context
- [`../../ClaudeSettings/`](../../ClaudeSettings/) — broader Claude Code settings (status line, permissions, keybindings) — non-plugin keys live there
