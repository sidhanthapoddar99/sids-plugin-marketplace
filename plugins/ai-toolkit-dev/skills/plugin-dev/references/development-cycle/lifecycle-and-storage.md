# Plugin lifecycle and storage

The canonical reference for "where does this plugin live and how does it actually run". Other docs cross-link here for storage paths, scope rules, and activation mechanics.

## Three filesystem locations

A plugin's footprint splits across three places:

| Location | Purpose | Survives plugin updates? |
|---|---|---|
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | The plugin's installed code (read-only at runtime). `${CLAUDE_PLUGIN_ROOT}` resolves here | **No** — replaced on every version bump |
| `~/.claude/plugins/data/<plugin>/` | Mutable state, caches, dep installs. `${CLAUDE_PLUGIN_DATA}` resolves here | **Yes** |
| `~/.claude/settings.json` | Per-user activation state (`enabledPlugins`, marketplace refs). User-edited via `/plugin` UI | **Yes** |

Project-scope and managed-scope settings live at `<project>/.claude/settings.json` and `/etc/claude/settings.json` respectively.

## Cache layout in detail

```
~/.claude/plugins/
├── cache/
│   ├── <marketplace-name>/
│   │   ├── marketplace.json                    # cached marketplace manifest
│   │   ├── <plugin-name>/
│   │   │   ├── <version-1>/                    # one tree per installed version
│   │   │   │   ├── .claude-plugin/plugin.json
│   │   │   │   └── ... plugin contents ...
│   │   │   └── <version-2>/
│   │   └── ...
│   └── ...
└── data/
    └── <plugin-name>/
        └── ... plugin's mutable state ...
```

Notes:
- Multiple versions of the same plugin can coexist in cache (e.g. while resolving deps that pin different versions). Only one is *active* per scope.
- Data dirs are keyed by plugin name only — they're shared across all marketplaces and all versions of that plugin.
- The cache is fully reconstructable from the marketplace + ref. Deleting it just forces re-fetching on next install.

## Activation flow

When the user runs `/plugin install <plugin>@<marketplace>`:

1. **Resolve.** Read `cache/<marketplace>/marketplace.json`. Find the entry. Resolve `version` (or marketplace HEAD) to a specific tag/commit.
2. **Fetch.** If `cache/<marketplace>/<plugin>/<version>/` is missing, fetch from the source (git clone, npm install, etc.) and unpack.
3. **Resolve dependencies.** Recursively repeat steps 1–2 for every entry in `dependencies[]`. Cross-marketplace deps require `allowCrossMarketplaceDependenciesOn` on both sides.
4. **Validate.** Each plugin's `plugin.json` is checked against the JSON schema. Schema failures abort the install.
5. **Compute install set.** Detect version conflicts and name collisions. Abort or prompt the user.
6. **Activate.** Set `enabledPlugins["<plugin-name>"] = true` in the active scope's `settings.json`. Same for any transitive dependencies (marked as transitive, see "Transitive cleanup" below).
7. **Load.** On the *next* SessionStart (or immediately, for hot-swappable component types — see below), Claude Code re-scans enabled plugins and loads their components.

## Hot-swap vs restart matrix

When a plugin's code changes (install, update, uninstall, edit during dev), some component types pick up the change immediately, others require a session restart.

| Component | Hot-swap on enable/disable? | Hot-swap on code change? |
|---|---|---|
| Skills | Yes (next prompt) | Yes (next prompt re-reads SKILL.md) |
| Commands | Yes (immediate) | Yes (immediate) |
| Agents | Yes (next agent invocation re-reads frontmatter) | Yes (next invocation) |
| Hooks (config in `hooks.json`) | Restart required | Restart required |
| Hooks (script content) | Hot — next event re-execs the script | Hot |
| MCP servers | Restart required | Restart required (the MCP process is long-running) |
| LSP servers | Restart required | Restart required |
| Monitors | Restart required | Hot (the watcher process re-execs) |
| `bin/` entries | Hot (next subprocess sees new `$PATH`) | Hot |
| `userConfig` schema | Hot for *new* fields, but existing field values aren't re-validated | n/a |

When a restart is required, Claude Code surfaces a "Plugin changes pending — restart to apply" notice in the UI.

## Scope union

Plugins are enabled at one or more **scopes**. Scopes form a stack with later scopes overriding earlier ones for any plugin that appears in multiple:

| Scope | Settings file | Typical owner |
|---|---|---|
| Managed | `/etc/claude/settings.json` (or platform equivalent) | IT / org admin |
| Local | Per-machine, e.g. `~/.config/claude/local.json` | Power user |
| Project | `<project>/.claude/settings.json` | Per-project, in-repo |
| User | `~/.claude/settings.json` | Per-user default |

**Resolution order** (highest priority first): **Managed > Local > Project > User**.

If a plugin is enabled at User scope but disabled at Project scope, the Project setting wins for that project. If Managed scope sets `enabledPlugins["foo"] = false`, no other scope can override it.

`--plugin-dir` (used in development) acts as a temporary "Local" scope override — it doesn't write to any settings file but injects the plugin into the active set for the duration of that session.

## `enabledPlugins`

```json
{
  "enabledPlugins": {
    "<plugin-name>": true,
    "<another-plugin>": false,
    "<transitive-dep>": { "enabled": true, "transitive": true }
  }
}
```

The `transitive` marker distinguishes user-requested installs from dependencies pulled in indirectly. Used by `claude plugin prune` to cleanup orphaned transitives.

## Disable vs uninstall

| Action | Cache | `enabledPlugins` | Data dir |
|---|---|---|---|
| `/plugin disable <plugin>` | unchanged | flipped to `false` | unchanged |
| `/plugin uninstall <plugin>` | unchanged (GC after 7 days) | entry removed | unchanged |
| `/plugin uninstall --purge <plugin>` | removed immediately | entry removed | **removed** |

A re-install picks up where the user left off — `${CLAUDE_PLUGIN_DATA}` is preserved across uninstall/install cycles unless `--purge` is used. This is the "venv survives a clean reinstall" property.

## Garbage collection

Cached plugin versions are GC'd when:
- No installed plugin references the version, AND
- The version's directory mtime is older than 7 days

Marketplace caches are GC'd when:
- No installed plugin references the marketplace, AND
- The marketplace cache is older than 7 days

`claude plugin prune` runs GC on demand without waiting 7 days.

GC never touches `~/.claude/plugins/data/` — data dirs survive until the user explicitly purges them.

## Schema validation at load

Every time a plugin's `plugin.json` is loaded (install, refresh, SessionStart for an enabled plugin), it's validated against the `plugin.schema.json` shipped with Claude Code. Failures:

- **Install path** — install aborts with a clear error pointing at the failed field
- **SessionStart for an already-installed plugin** — the plugin is auto-disabled and a warning is shown; other plugins continue to load. The user must edit and re-enable, or roll back to a working version

The schema is closed (unknown top-level fields are rejected). This catches typos like `userconfig` instead of `userConfig`.

## Multi-plugin `.mcp.json` merging

Multiple plugins can each ship their own `.mcp.json`. At load:

1. Claude Code reads every enabled plugin's `.mcp.json`
2. MCP server names are checked for collisions across plugins
3. On collision, Claude Code aborts with `MCP server name conflict: '<name>' declared by <plugin-a> and <plugin-b>`

There is no automatic prefixing or namespacing — the rule is "first plugin to claim a server name wins, unless another plugin tries the same name, in which case both fail". This is why MCP server names should be plugin-prefixed by convention (see `config/naming.md`).

User-level `.mcp.json` (in `~/.claude/`) and project-level (in `<project>/.mcp.json`) merge with plugin-shipped MCP configs the same way: name collisions abort. Project-level wins over plugin-level for collisions on the *user's own* MCP entries (the project owner is overriding a plugin's choice intentionally).

## Diagnostic paths

For debugging "why isn't my plugin loading?":

```bash
# What plugins does Claude Code think are enabled?
claude plugin list --json

# What's in the cache for a specific plugin?
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/

# What does the plugin's data dir contain?
ls ~/.claude/plugins/data/<plugin>/

# Where is enabledPlugins resolved from?
claude plugin scope <plugin>
```

See `troubleshooting.md` for failure-mode walkthroughs.
