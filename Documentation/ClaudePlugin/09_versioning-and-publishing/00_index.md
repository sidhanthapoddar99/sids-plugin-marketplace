# Versioning and publishing

Plugins carry a `version` field in `plugin.json`. The runtime uses it to:

- Name the cache folder (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`)
- Coexist multiple installed versions side-by-side
- Drive the `/plugin update` flow
- Resolve dependency version ranges via git tags

This folder is the reference for how versions get assigned, how releases get cut, and how dependencies pick a version that satisfies all constraints.

## What versioning controls

| What | Driven by |
|---|---|
| What `/plugin update` fetches | Version comparison between installed and marketplace |
| Which content sits at `cache/<mkt>/<plugin>/<version>/` | The resolved version string |
| How dependency `version` ranges resolve | Git tags on the marketplace repo |
| Whether two installs of the same plugin can coexist | Distinct version strings |

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_semver.md` | Semver in Claude Code; range syntax (`~`, `^`, `>=`, `=`, two-end ranges); pre-release inclusion rules |
| 02 | `02_tagging-convention.md` | The `<plugin>--v<X.Y.Z>` tag format; `claude plugin tag --push --dry-run -f` |
| 03 | `03_version-resolution.md` | The three sources of version info; precedence; range intersection across dependents |
| 04 | `04_release-loop.md` | The dogfood loop: edit → bump → tag → marketplace entry → push → consumer update |
| 05 | `05_pre-releases-and-hotfixes.md` | `-rc.N` pre-release tags, hotfix bumps, release-branch backports |

## See also

- [`04_marketplaces/`](../04_marketplaces/) — where the marketplace entry's `version` field lives
- [`08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — how `dependencies[].version` constraints interact
- [`07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/) — how the resolved version becomes a cache folder
