# Plugin lifecycle and storage

The canonical reference for "where does this plugin live and how does it actually run". Other docs cross-link here.

## The model: cache vs registration

Two independent things:

- **The cache.** Plugin files live **once**, at user-level, regardless of which scope enabled them.
- **The registration.** A boolean per scope's `settings.json` (`enabledPlugins.<plugin-id> = true|false`).

Multiple scopes can enable the same plugin — files don't duplicate. Resolution at session start is the **union** across all applicable scopes' `enabledPlugins`. Each plugin loads once even if multiple scopes enable it.

## Filesystem layout

```
~/.claude/
├── settings.json                              ← User-scope enabledPlugins
└── plugins/
    └── cache/
        └── <marketplace-name>/
            └── <plugin-name>/
                └── <version>/                 ← THE plugin files, once
                    ├── .claude-plugin/plugin.json
                    └── ...

# Project scope (committed to git)
<repo>/.claude/settings.json                   ← Project enabledPlugins

# Local scope (gitignored, project-local, per-developer)
<repo>/.claude/settings.local.json             ← Local enabledPlugins
```

Project-scope folders have **no `plugins/` directory** — there's no per-project cache. Plugin files only live at user-level. A teammate cloning the repo gets the project-scope `enabledPlugins` boolean from committed `settings.json`; the plugin files download to *their* user-level cache the first time they open the project.

Multiple **versions** can coexist: `<plugin>/0.1.0/` and `<plugin>/0.2.0/` sit side-by-side. `/plugin update` adds new version folders; older ones are GC'd (see below).

## Two plugin paths: `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}`

| Variable | Resolves to | Lifetime |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/` | **Replaced on every plugin update** |
| `${CLAUDE_PLUGIN_DATA}` | `~/.claude/plugins/data/<plugin-id>/` | **Survives plugin updates** |

The `<plugin-id>` is the install identifier with non-`[a-zA-Z0-9_-]` characters replaced with `-`. For `formatter@my-marketplace`, the data dir is `~/.claude/plugins/data/formatter-my-marketplace/`.

Use `${CLAUDE_PLUGIN_ROOT}` for bundled scripts, executables, config files, templates — anything that ships with the plugin and should change when the plugin updates.

Use `${CLAUDE_PLUGIN_DATA}` for installed dependencies (`node_modules`, Python venvs), generated code, caches, log files — anything to persist across updates. Standard pattern: on `SessionStart`, diff the bundled manifest against a copy in the data dir, reinstall deps if they differ.

Both substitute inline in skill content, agent content, hook commands, monitor commands, and MCP/LSP server configs. Both are also exported as env vars to hook processes and MCP/LSP server subprocesses.

## Scope precedence

Resolution order — **higher wins**:

| Scope | Settings file | Visibility |
|---|---|---|
| **Managed** | Set by admin (platform-specific path) | Locked, can't be overridden |
| **Local** | `<repo>/.claude/settings.local.json` | This project, just this developer (gitignored) |
| **Project** | `<repo>/.claude/settings.json` | This project, all teammates (committed) |
| **User** | `~/.claude/settings.json` | All projects, this machine |

`Managed > Local > Project > User`. The active set is the **union** of scopes: a plugin enabled at *any* scope is loaded, unless a higher-precedence scope explicitly sets it to `false`. So a project-scope `true` enables the plugin even if the user scope says nothing; a local-scope `false` disables it even if the user scope says `true`. The precedence chain only matters when two scopes set the same plugin's flag to different values.

> **Note on filesystem slugification.** `enabledPlugins` keys are the literal install identifier `<name>@<marketplace>` (with `@`). Filesystem-side keys (the data dir, `pluginConfigs[<plugin-id>]`) slugify the `@` to `-`: `formatter@my-marketplace` → `formatter-my-marketplace`. Two different keying conventions for the same plugin, depending on whether you're looking at settings booleans or filesystem layout.

`--plugin-dir` (used during dev — see [`testing.md`](testing.md)) is a session-only Local-scope override that doesn't write to any settings file.

## `enabledPlugins` shape

Boolean values, keyed by `<plugin-name>@<marketplace>`:

```json
{
  "enabledPlugins": {
    "documentation-guide@documentation-template": true,
    "rust-analyzer-lsp@claude-plugins-official": false
  }
}
```

`/plugin enable | disable` flip these. `/plugin install` adds an entry set to `true`. `/plugin uninstall` removes the entry.

## Activation flow

When the user runs `/plugin install <plugin>@<mkt>`:

1. **Resolve.** Read the marketplace's `marketplace.json` from cache (or fetch). Find the entry. Resolve `version` to a specific tag if pinned.
2. **Fetch.** If `cache/<mkt>/<plugin>/<version>/` is missing, download from the source.
3. **Resolve dependencies.** Recursively for each `dependencies[]` entry. Cross-marketplace deps require the root marketplace's `allowCrossMarketplaceDependenciesOn` to list the dep's marketplace.
4. **Compute install set.** Detect range conflicts (intersected ranges, see [`../config/dependencies.md`](../config/dependencies.md)). Auto-installed deps are tracked separately from user-requested installs.
5. **Activate.** Write `enabledPlugins[<plugin-id>] = true` in the active scope's `settings.json`.
6. **Load.** On the next prompt (or after `/reload-plugins`), Claude Code re-scans enabled plugins and registers components.

## Hot-swap matrix

What requires a session restart vs what `/reload-plugins` picks up:

| Component | `/reload-plugins` picks up edits? |
|---|---|
| Skills | Yes |
| Commands | Yes |
| Agents | Yes |
| MCP servers | Yes — subprocess restarted on reload |
| LSP servers | Yes — subprocess restarted on reload |
| Themes / output styles / bin wrappers | Yes |
| Hooks | **No — load at session start; full restart required for any hook change** |
| Background monitors | **No — session-lifetime; not started, stopped, or restarted by `/reload-plugins`. Disabling a plugin mid-session also doesn't stop running monitors** |

Hooks and monitors are the consistent exceptions — both are wired up at session start and not refreshed afterward.

## Updates

```
/plugin update                           # all installed plugins
/plugin update <plugin>@<marketplace>    # specific plugin
```

Refetches from the marketplace. Drops the new version into a sibling `<version>/` folder under the cache. Switches the active version.

## Garbage collection — orphan marking

**Old versions are auto-GC'd 7 days after orphaning.** The mechanism:

- Every `install` or `update` marks the **previous** version directory as orphaned.
- Claude Code removes orphaned directories 7 days later.
- Glob and Grep skip orphaned directories during searches.

The 7-day grace window lets concurrent sessions that already loaded the old version keep running without errors. There's no on-demand "wipe orphans" — the timer runs automatically.

`claude plugin prune` is a different operation: it removes **auto-installed dependencies** that no installed plugin requires. It does not affect cache-version GC.

## Disabling vs uninstalling

| Action | Command | Cache | `enabledPlugins` | Data dir |
|---|---|---|---|---|
| Disable | `/plugin disable` | unchanged | flipped to `false` | unchanged |
| Enable | `/plugin enable` | unchanged | flipped to `true` | unchanged |
| Uninstall | `/plugin uninstall` | (orphaned, 7-day GC) | entry removed | **deleted** if uninstalling from the *last* scope |
| Uninstall + keep data | `/plugin uninstall --keep-data` | (orphaned, 7-day GC) | entry removed | preserved |

The data dir is deleted automatically when the plugin is uninstalled from the last scope where it was registered. `--keep-data` preserves it (useful when reinstalling a different version for testing).

## Schema validation

`plugin.json` is validated against Claude Code's schema at install time and at every `/reload-plugins`. Validation failures at install abort with a clear error pointing at the failed field.

## Multi-plugin `.mcp.json` merging

Multiple enabled plugins can each ship their own `.mcp.json` (or declare `mcpServers` in `plugin.json`). MCP server names are merged across plugins. Name collisions are surfaced as load errors in the `/plugin` Errors tab — by convention, server names should be plugin-prefixed to avoid this (see [`../config/naming.md`](../config/naming.md)).

User-level `.mcp.json` (in `~/.claude/`) and project-level (in `<project>/.mcp.json`) merge with plugin-shipped MCP configs the same way.

## Diagnostic paths

```bash
# What plugins does Claude Code think are enabled?
claude plugin list --json

# Health overview (errors, missing tags, range conflicts)
# (use the slash command in an interactive session)
/doctor
```

For "why isn't my plugin loading?" walkthroughs, see [`troubleshooting.md`](troubleshooting.md).

## Reference

- Official: [Plugin caching and file resolution](https://code.claude.com/docs/en/plugins-reference#plugin-caching-and-file-resolution) (ground truth for the cache/scope model)
- Official: [Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
