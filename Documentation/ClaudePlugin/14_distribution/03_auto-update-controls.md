# Auto-update controls

Claude Code can auto-update plugins at session start. Whether it does so depends on the marketplace type and two environment variables. This page documents the rules.

## Default behaviour by marketplace type

Auto-update defaults differ depending on where a plugin came from:

| Marketplace type | Auto-update on by default? |
|---|---|
| Official Anthropic marketplaces | **Yes** |
| Third-party marketplaces (other Git remotes) | **No** |
| Local-development marketplaces (`file://` or relative paths) | **No** |

Rationale:

- Official marketplaces are reviewed; updates are presumed safe to take automatically.
- Third-party marketplaces are user-trusted but not Anthropic-trusted — silent updates would be a supply-chain footgun.
- Local-development marketplaces are typically your own work-in-progress; auto-updating from a path you're actively editing would create hard-to-debug surprises.

## Per-marketplace toggle in the UI

Override the default per-marketplace in `/plugin` → **Marketplaces** tab:

| Key | Action |
|---|---|
| Up / Down | Highlight a marketplace |
| `t` | Toggle auto-update for the highlighted marketplace |

The setting persists in the user's `settings.json` and survives across sessions. The same toggle is reachable through the `claude plugin marketplace` CLI in newer Claude Code versions (consult `--help` for current flag names).

## Environment-variable overrides

Two env vars control the global picture:

| Env var | Effect |
|---|---|
| `DISABLE_AUTOUPDATER` | Globally disables Claude Code auto-updates **and** plugin auto-updates |
| `FORCE_AUTOUPDATE_PLUGINS` | When set with `DISABLE_AUTOUPDATER=1`, keeps plugin auto-updates enabled while disabling the Claude Code core update |

The intended combinations:

| `DISABLE_AUTOUPDATER` | `FORCE_AUTOUPDATE_PLUGINS` | Result |
|---|---|---|
| unset | (any) | Both Claude Code and plugins auto-update according to per-marketplace defaults |
| `1` | unset | Neither Claude Code nor plugins auto-update |
| `1` | `1` | Claude Code core does not auto-update, but plugins still do |
| unset | `1` | Same as both unset (`FORCE_AUTOUPDATE_PLUGINS` is only meaningful when paired with `DISABLE_AUTOUPDATER`) |

Use case for the third row: corporate environments where Claude Code core is managed centrally (you don't want it auto-updating on the user) but plugin updates should still flow normally.

## Manual update

Regardless of the auto-update setting, users can always force a refresh:

```
/plugin update                            # update all plugins
/plugin update <plugin>@<marketplace>     # update one
claude plugin marketplace update          # refresh marketplace catalogues
```

Manual update bypasses the auto-update toggle entirely. Use it as the canonical "I want the latest" path when auto-update is off.

## What auto-update actually does

When auto-update fires for a marketplace at session start:

1. Re-fetch the marketplace source (Git pull, or re-read of the local path)
2. For each installed plugin from this marketplace, read its `plugin.json` to check the version
3. If a plugin's version differs from the cached one, download the new version into `~/.claude/plugins/cache/<marketplace>/<plugin>/<new-version>/`
4. Switch the active version
5. Old versions remain in the cache (cleanup is via `/plugin uninstall` or manual `rm -rf`)

It does **not**:

- Touch `enabledPlugins` booleans
- Run any code from the new version during the update itself
- Notify the user inline — there's no popup. Users see the new behaviour next time they trigger a relevant capability

## What `/doctor` reports

If auto-update was skipped for a plugin, `/doctor` surfaces the reason. Common cases:

| Reason | Fix |
|---|---|
| Range conflict with another plugin's dep | Investigate the constraining plugin named in the report |
| Missing tag | The new version's tag wasn't pushed; ask the maintainer |
| Marketplace unreachable | Network / auth; retry or check the source URL |

`/doctor` names the specific plugin and version it skipped, so you can decide whether to wait, force update, or pin.

## Pinning around auto-update

If you don't want a specific plugin to auto-update (regardless of the marketplace toggle), the cleanest path is pinning the marketplace itself to a tag or branch:

```
/plugin marketplace add owner/repo#v1.4
```

Then the marketplace fetch resolves to that ref, and updates only happen if you re-add with a different ref. See [`../04_marketplaces/03_ref-and-sha-pinning.md`](../04_marketplaces/03_ref-and-sha-pinning.md).

## See also

- [`../15_reference/01_env-vars-cheatsheet.md`](../15_reference/01_env-vars-cheatsheet.md) — the env-var reference table
- [`../12_cli-and-ui/03_plugin-ui.md`](../12_cli-and-ui/03_plugin-ui.md) — Marketplaces tab where the toggle lives
- [`../04_marketplaces/03_ref-and-sha-pinning.md`](../04_marketplaces/03_ref-and-sha-pinning.md) — pinning marketplaces by ref
- Official: [Configure auto-updates](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)
