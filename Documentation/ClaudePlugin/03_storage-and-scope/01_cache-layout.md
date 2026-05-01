# Cache layout

Plugin files live **once** at user-level, regardless of which scope enabled them. There is no project-local plugin cache.

## Path

```
~/.claude/plugins/cache/<marketplace-name>/<plugin-name>/<version>/
```

After `/plugin install documentation-guide@documentation-template`, the files land at:

```
~/.claude/plugins/cache/documentation-template/documentation-guide/0.1.1/
├── .claude-plugin/plugin.json
├── README.md
├── LICENSE
├── bin/
├── commands/
└── skills/
```

This is true regardless of the install scope. Project-scope folders (`<repo>/.claude/`) have **no `plugins/` directory** — the per-scope `settings.json` only carries the `enabledPlugins` boolean.

## What's inside

A cached plugin is the verbatim payload extracted from the marketplace source. The directories that may appear:

| Directory / file | Purpose |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest (required) |
| `.claude-plugin/marketplace.json` | Present if the cached entity is a marketplace, not just a plugin |
| `bin/` | CLI wrappers added to `$PATH` while the plugin is enabled |
| `commands/` | Slash commands (legacy flat layout) |
| `skills/<name>/SKILL.md` | Skills (current convention) |
| `agents/<name>.md` | Subagent definitions |
| `hooks/hooks.json` | Hook configuration |
| `monitors/monitors.json` | Background monitors |
| `themes/<name>.json` | Theme JSON files |
| `.mcp.json` | MCP server declarations (or via `mcpServers` in `plugin.json`) |
| `.lsp.json` | LSP server declarations (or via `lspServers` in `plugin.json`) |
| `outputStyles/` | Output style definitions (or string/array in `plugin.json`) |
| `channels/` | Channel definitions (or `channels` in `plugin.json`) |
| `settings.json` | Plugin-shipped Claude Code defaults (`agent`, `subagentStatusLine`) |
| `README.md`, `LICENSE` | Documentation, not loaded by the runtime |

The presence of any specific directory is up to the plugin author — most plugins ship just one or two of these.

## Multiple versions side-by-side

Multiple **versions** can coexist in the cache:

```
~/.claude/plugins/cache/my-marketplace/formatter/
├── 0.1.0/
├── 0.2.0/
└── 0.3.0/         ← active
```

`/plugin update` adds a new version folder and switches the active version. Older versions are not deleted immediately — they're orphan-marked and removed 7 days later (see [`../07_lifecycle-and-runtime/05_garbage-collection.md`](../07_lifecycle-and-runtime/05_garbage-collection.md)).

The 7-day grace window lets concurrent sessions that already loaded the old version continue running without errors. Glob and Grep skip orphaned directories during searches, so file results don't include outdated plugin code.

## Never per-project

There is no `<repo>/.claude/plugins/` directory. Even when a plugin is "installed at project scope", only the `enabledPlugins` boolean lands in the project's settings — the files themselves still come from the user-level cache. A teammate cloning the repo gets the boolean from the committed `settings.json`; the plugin files download to *their* user-level cache the first time they open the project. At no point does the repo carry plugin binaries.

## Path-traversal limitation

Plugins cannot reference files outside their own root after install. Paths like `../shared-utils` won't resolve because external files aren't copied into the cache. Bundle everything you need inside the plugin folder.

## See also

- [`02_data-dir.md`](./02_data-dir.md) — the *other* plugin path, which survives updates
- [`05_env-vars.md`](./05_env-vars.md) — `${CLAUDE_PLUGIN_ROOT}` resolves to `<version>/` inside this cache
- [`../07_lifecycle-and-runtime/04_updates.md`](../07_lifecycle-and-runtime/04_updates.md) — how new versions get added
- [`../07_lifecycle-and-runtime/05_garbage-collection.md`](../07_lifecycle-and-runtime/05_garbage-collection.md) — orphan marking and the 7-day window
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — wiping the cache for clean-install testing
