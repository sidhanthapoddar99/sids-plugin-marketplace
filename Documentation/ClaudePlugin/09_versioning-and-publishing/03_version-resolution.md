# Version resolution

A plugin's effective version comes from one of three sources, checked in order. Whichever yields a value first wins. The resolved version is what gets used as the cache folder name and what `/plugin update` compares against.

## Resolution order

Claude Code resolves a plugin's version from the first of these that's set:

| Order | Source | Set in | Best for |
|---|---|---|---|
| 1 | Plugin's own `version` field | The plugin's `.claude-plugin/plugin.json` | Published plugins with stable release cycles |
| 2 | Marketplace entry's `version` field | The marketplace's `marketplace.json` plugin-entries | Catalogue-style marketplaces wanting to override the upstream |
| 3 | Git commit SHA of the plugin source | Computed from the source's resolved commit | In-flight development without explicit versioning |
| 4 | `unknown` | (fallback) | npm sources without `version` set, or non-git local paths |

> The plugin's `plugin.json` always wins over the marketplace entry. **Don't set `version` in both** — a stale `plugin.json` value will silently mask a marketplace bump.

## Resolution table by source type

| Source type | If `plugin.json` has `version` | If only marketplace entry has `version` | If neither |
|---|---|---|---|
| Relative path / `github` / `url` / `git-subdir` | Use `plugin.json`'s | Use marketplace entry's | Use the resolved commit's SHA (12-char suffix in cache folder name) |
| `npm` | Use `plugin.json`'s | Use marketplace entry's | `unknown` |
| Local directory not in a git repo | Use `plugin.json`'s | Use marketplace entry's | `unknown` |

## Two practical strategies

| Strategy | Setup | Update behaviour | Best for |
|---|---|---|---|
| **Explicit version** | Set `"version": "2.1.0"` in `plugin.json` | Users get updates only when you bump this field. New commits without a bump are no-ops — `/plugin update` reports "already at the latest" | Published plugins with stable release cycles |
| **Commit-SHA version** | Omit `version` from both `plugin.json` and marketplace entry | Every new commit becomes a new version automatically | Internal/team plugins under active development |

> If you set `version` in `plugin.json`, you **must** bump it for every change you want consumers to see. Pushing new commits alone isn't enough — Claude Code sees the same version string and keeps the cached copy.

The cache-folder rule: the resolved version is also the cache-folder name (`~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`). Multiple versions coexist there. For commit-SHA versioning, the folder name has a 12-character SHA suffix.

## Version comparison and `/plugin update`

```
/plugin update                            # update all installed plugins
/plugin update <plugin>@<marketplace>     # update one
```

Steps:

1. Re-fetch the marketplace source (Git pull, or re-read of the local path)
2. Read the plugin's resolved version from the new marketplace state
3. Compare to the locally cached version
4. If different, fetch the new content into a new cache folder and switch active version
5. If same, no-op

Old versions remain on disk until `/plugin uninstall` or manual cache cleanup.

## Range intersection across multiple dependents

When several plugins each carry a `dependencies[].version` constraint on the same target, Claude Code intersects all the ranges and picks the highest tag satisfying every constraint:

| Plugin A requires | Plugin B requires | Result |
|---|---|---|
| `^2.0` | `>=2.1` | Highest `2.x` tag at or above `2.1.0`. Both load |
| `~2.1` | `~3.0` | B install fails with `range-conflict`. A and dep stay as-is |
| `=2.1.0` | none | Dep stays at `2.1.0`. Auto-update skips newer while A installed |

The resolved version is the **highest tag satisfying every installed plugin's range**, not the marketplace's latest. If no tag fits, the update is skipped — surfaces in `/doctor` and the `/plugin` Errors tab.

When you uninstall the last constrainer, the dep resumes tracking its marketplace's latest on next update.

## `version` in marketplace.json: when it's actually useful

The marketplace entry's `version` field is most useful for:

| Use case | Why marketplace `version` (not `plugin.json`) |
|---|---|
| You don't control the upstream `plugin.json` | Catalogue marketplaces overriding a partner's plugin |
| Pinning an npm-distributed plugin | The marketplace entry's `version` overrides what npm picks |
| Channel-based releases pinning the same upstream to different versions per channel | See [`04_marketplaces/04_release-channels.md`](../04_marketplaces/04_release-channels.md) |

For your own plugins where you control both the source and the marketplace entry, set `version` only in `plugin.json` — it's the single source of truth.

## What does NOT determine the version

- The marketplace ref (`#v1.0.0` on the URL) — that's the marketplace catalogue's pin, not any plugin's
- The plugin source `ref`/`sha` fields — those determine *which commit* gets fetched; the version label still comes from the resolution order above
- Git tag names — even though dependency resolution uses tags, the *plugin's own* version label is read from `plugin.json` content at the resolved commit, not from the tag string

## See also

- [`01_semver.md`](./01_semver.md) — range syntax used in dependency `version` fields
- [`02_tagging-convention.md`](./02_tagging-convention.md) — the `<plugin>--v<version>` tag format
- [`04_release-loop.md`](./04_release-loop.md) — the typical bump flow
- [`07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/) — how the resolved version becomes a cache folder
