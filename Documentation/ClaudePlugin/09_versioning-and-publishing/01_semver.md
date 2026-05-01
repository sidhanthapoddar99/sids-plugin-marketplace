# SemVer in Claude Code

Plugin versions follow semantic versioning: `MAJOR.MINOR.PATCH`. Dependency `version` ranges accept any expression supported by Node's `semver` package.

> Version constraints in `dependencies` require Claude Code v2.1.110+. The `claude plugin prune` command requires v2.1.121+.

## SemVer convention

| Component | Bump when |
|---|---|
| **PATCH** (`0.1.0` → `0.1.1`) | Bug fixes, doc updates, no behaviour change |
| **MINOR** (`0.1.0` → `0.2.0`) | New capabilities (added a skill / command / wrapper) without breaking existing ones |
| **MAJOR** (`0.1.0` → `1.0.0`) | Breaking changes; consumers may need to adjust expectations |

| Phase | Discipline |
|---|---|
| Pre-1.0 (`0.x.y`) | Anything goes — version is mostly a "did the cache content change?" marker |
| Post-1.0 | SemVer discipline. Breaking changes require a major bump. Document migration in the README |

For a one-author plugin in your own projects, you can stay on `0.x` indefinitely. The convention only matters when other people depend on you.

## Range syntax in `dependencies`

The `version` field on a dependency entry accepts any standard semver range expression:

| Range | Matches | Example use |
|---|---|---|
| `~2.1.0` | `2.1.x` (any patch ≥ `2.1.0`) | "Take patches but not new features" |
| `^2.0` | `2.x.x` (any minor/patch with major `2`) | "Take everything compatible with 2.0 API" |
| `>=1.4` | Anything `1.4.0` or higher | "Need at least 1.4.0; no upper bound" |
| `=2.1.0` | Exactly `2.1.0` | "Pin to one specific version" |
| `>=1.4 <2.0` | Range with both ends | "Anywhere in the 1.x line at or after 1.4" |
| `1.x` / `1.*` | Any `1.y.z` | Equivalent to `^1.0.0` |

Examples in `plugin.json`:

```json
{
  "dependencies": [
    { "name": "audit-logger", "version": "^2.0" },
    { "name": "secrets-vault", "version": "~2.1.0" },
    { "name": "platform-base", "version": ">=1.4 <2.0" },
    { "name": "exact-tool", "version": "=2.1.0" }
  ]
}
```

The dependency is fetched at the **highest tagged version** that satisfies the range — see [`02_tagging-convention.md`](./02_tagging-convention.md) for how tag-based resolution works.

## Pre-release exclusion

Pre-release versions (`2.0.0-beta.1`, `1.4.0-rc.2`) are **excluded** from regular range resolution:

| Range | Matches `2.0.0-beta.1`? |
|---|---|
| `^2.0.0` | No |
| `>=2.0.0` | No |
| `^2.0.0-0` | Yes (opts in to pre-releases at or above `2.0.0-0`) |
| `>=2.0.0-beta` | Yes |

To opt in, append a `-0` suffix (or any explicit pre-release tag) to the range. This convention prevents pre-release tags from accidentally satisfying `^2.0.0`-style ranges that consumers expect to be stable-only.

## Range intersection across multiple dependents

When multiple installed plugins constrain the same dependency, Claude Code intersects their ranges and resolves to the highest tag satisfying *all* of them:

| Plugin A requires | Plugin B requires | Result |
|---|---|---|
| `^2.0` | `>=2.1` | Highest `2.x` tag at or above `2.1.0`. Both load |
| `~2.1` | `~3.0` | Plugin B install fails with `range-conflict`. A and the dep stay as-is |
| `=2.1.0` | none | Dep stays at `2.1.0`. Auto-update skips newer versions while A is installed |

When you uninstall the last plugin constraining a dependency, the dependency resumes tracking its marketplace's latest on the next update.

## Range conflicts

If you write a syntactically valid but unsatisfiable range, or two installed plugins' ranges have empty intersection, you'll see one of:

| Error | Trigger |
|---|---|
| `range-conflict` | Combined ranges across dependents don't intersect, or syntax is invalid |
| `dependency-version-unsatisfied` | Installed dep's version is outside the declaring plugin's range |
| `no-matching-tag` | The dep repo has no `<plugin>--v*` tag in the requested range |

The fix is usually to widen one range, or to ask the upstream author to tag a release that fits.

## See also

- [`02_tagging-convention.md`](./02_tagging-convention.md) — the `<plugin>--v<version>` tag format dependency ranges resolve against
- [`03_version-resolution.md`](./03_version-resolution.md) — how version strings are assigned in the first place
- [`08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — full dependency story
- [`Documentation/ClaudePlugin/04_marketplaces/08_cross-marketplace-deps.md`](../04_marketplaces/08_cross-marketplace-deps.md) — cross-marketplace constraints
