# Updates

`/plugin update` re-fetches a plugin from its marketplace, drops the new version into a sibling cache folder, and switches the active version. The old version is orphan-marked for garbage collection; concurrent sessions can finish on the old version without errors.

## Commands

```
/plugin update                           # update all installed plugins
/plugin update <plugin>@<marketplace>    # update one specific plugin
```

CLI equivalents:

```
claude plugin update
claude plugin update <plugin>@<marketplace>
```

## What happens

1. **Re-resolve** the plugin's version constraint against the marketplace's current `marketplace.json`. The constraint may resolve to a different tag than the currently installed one.
2. **Compare** with the installed version. If equal, no-op.
3. **Fetch** the new version into a sibling folder under `~/.claude/plugins/cache/<mkt>/<plugin>/<new-version>/`. The old `<old-version>/` directory is **not touched yet**.
4. **Switch active version.** The runtime now reads from the new directory.
5. **Mark old version orphaned.** Garbage collection removes it 7 days later. See [`05_garbage-collection.md`](./05_garbage-collection.md).

The old version directory remains on disk for the grace window. Concurrent sessions that already loaded the old version keep running against it — when those sessions end, no resources are leaked because the GC sweep happens after the grace expires.

## What gets re-loaded after update

`/plugin update` writes the new version to disk but **does not auto-reload** the running session. To pick up the new version's components:

| Edit type | Action needed |
|---|---|
| Skills, agents, commands, MCP, LSP, monitors, themes | `/reload-plugins` |
| Hooks (added, removed, or changed) | **Restart session** |
| Bin wrappers | `/reload-plugins` |
| `${CLAUDE_PLUGIN_DATA}` content | Untouched — survives by design |
| `${CLAUDE_PLUGIN_ROOT}` content | Replaced with new version's content |

If you've been writing to `${CLAUDE_PLUGIN_ROOT}` (don't), those writes are lost on update.

## Auto-update behaviour

Marketplaces auto-update at startup. The default depends on the marketplace type:

| Marketplace type | Auto-update default |
|---|---|
| **Official Anthropic marketplaces** | **Enabled** by default |
| **Third-party marketplaces** | **Disabled** by default |
| **Local-development marketplaces** | **Disabled** by default |

The user can toggle per-marketplace in the `/plugin` UI's Marketplaces tab.

## Auto-update environment variables

Two env vars control update behaviour at the Claude Code process level:

| Variable | Effect |
|---|---|
| `DISABLE_AUTOUPDATER` | Globally disables Claude Code auto-updates *including* plugin updates |
| `FORCE_AUTOUPDATE_PLUGINS` | When set together with `DISABLE_AUTOUPDATER`, keeps plugin auto-updates running while disabling Claude Code core updates |

Common combinations:

| Env | Claude Code core | Plugin updates |
|---|---|---|
| Neither set | Auto-updates on | Auto-updates per marketplace default |
| `DISABLE_AUTOUPDATER=1` | Disabled | Disabled |
| `DISABLE_AUTOUPDATER=1` + `FORCE_AUTOUPDATE_PLUGINS=1` | Disabled | Auto-updates per marketplace default |

## Pinning

If you want to pin a plugin to a specific version (i.e., not have `/plugin update` move it), the version-constraint syntax in `enabledPlugins` is documented in the official Claude Code release notes — the syntax has evolved across releases. The default `enabledPlugins[<plugin>@<mkt>]: true` follows the marketplace's recommended version.

For dependency version pinning *within a plugin's `plugin.json`* `dependencies[]` block, see [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md).

## Failure modes

| Failure | Cause | Mitigation |
|---|---|---|
| Network error during fetch | Marketplace source unreachable | Retry; old version still active |
| New version's `plugin.json` fails schema validation | Bad release | Old version stays active, new version is not switched in |
| Range conflict introduced by new version's deps | Dep updates broke compatibility | `claude plugin list --json` shows the conflict; pin or revert |
| Hook config changed | Won't be picked up | Restart session |
| Auto-update unexpectedly fired | Marketplace had auto-update enabled | Disable in `/plugin` UI for that marketplace |

## See also

- [`05_garbage-collection.md`](./05_garbage-collection.md) — how the old version is cleaned up
- [`../03_storage-and-scope/01_cache-layout.md`](../03_storage-and-scope/01_cache-layout.md) — sibling-version layout
- [`../03_storage-and-scope/02_data-dir.md`](../03_storage-and-scope/02_data-dir.md) — the data dir survives updates by design
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — semver, tag convention, version resolution
- [`../03_storage-and-scope/05_env-vars.md`](../03_storage-and-scope/05_env-vars.md) — auto-update env vars
