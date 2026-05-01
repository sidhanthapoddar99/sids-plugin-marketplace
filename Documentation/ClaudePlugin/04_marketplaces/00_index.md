# Marketplaces

A **marketplace** is a Git repository (or local directory) that catalogues one or more plugins via a single file: `.claude-plugin/marketplace.json`. Users add a marketplace once with `/plugin marketplace add`, then install any plugin it lists.

## What a marketplace owns vs. doesn't own

| Owns | Doesn't own |
|---|---|
| The catalogue (`marketplace.json`) | The plugins it lists (those have their own `plugin.json`) |
| The discovery index — what shows up in `/plugin` Discover | The plugin source code (can live in any repo or registry) |
| The cross-marketplace dependency allowlist | The version each plugin resolves to (that's the plugin's manifest) |
| The marketplace ref users pin against | Trust beyond what the user grants the marketplace at add time |

A marketplace can ship plugins from its own repo (the common case), point at plugins in other repos, or do both. It can also list plugins distributed via npm or hosted on non-GitHub git servers.

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_anatomy.md` | `marketplace.json` top-level fields and plugin-entry shape |
| 02 | `02_source-types.md` | The five `source` forms (relative path, `github`, `url`, `git-subdir`, `npm`) |
| 03 | `03_ref-and-sha-pinning.md` | `#<ref>` on the marketplace URL; `ref`/`sha` on plugin sources |
| 04 | `04_release-channels.md` | Stable/latest channels via two marketplaces pointing at the same plugins |
| 05 | `05_catalogue-pattern.md` | A marketplace as a curated index of plugins it doesn't host |
| 06 | `06_extra-known-marketplaces.md` | The settings-side `extraKnownMarketplaces` for team bootstrap |
| 07 | `07_managed-restrictions.md` | `strictKnownMarketplaces` allowlist/denylist for managed deployments |
| 08 | `08_cross-marketplace-deps.md` | `allowCrossMarketplaceDependenciesOn` and the trust-doesn't-chain rule |

## See also

- [`05_plugin-anatomy/`](../05_plugin-anatomy/) — what each plugin folder looks like internally
- [`09_versioning-and-publishing/`](../09_versioning-and-publishing/) — how versions get cut and resolved
- [`10_trust-and-security.md`](../10_trust-and-security.md) — the trust model behind installing from a marketplace
