# Plugin dependencies

A plugin can declare other plugins it depends on. Claude Code resolves and installs them at install time so the dependent plugin can rely on them being present.

## Shape

The `dependencies` field in `plugin.json` is an **array** of dependency descriptors:

```json
{
  "name": "my-plugin",
  "dependencies": [
    {
      "name": "skill-creator",
      "marketplace": "claude-plugins-official",
      "version": "^1.0"
    },
    {
      "name": "shared-utils",
      "version": "~2.1.0"
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `name` | string, required | Dependency plugin's name |
| `marketplace` | string, optional | Which marketplace to fetch from. Omit if the dep is in the same marketplace as this plugin |
| `version` | string, optional | SemVer range. Defaults to `*` (any version) |
| `optional` | boolean, optional | If `true`, missing dependency doesn't block install — the plugin loads degraded |

## Version ranges

Claude Code uses standard SemVer-range syntax:

| Range | Matches |
|---|---|
| `1.2.3` | Exactly `1.2.3` |
| `^1.2.3` | `>=1.2.3 <2.0.0` (caret = compatible major) |
| `~1.2.3` | `>=1.2.3 <1.3.0` (tilde = compatible minor) |
| `>=1.2.0` | Any version `1.2.0` or above |
| `1.2.x` | Any patch of `1.2` |
| `*` | Any version |

The matched version must exist as an upstream tag `<dependency-name>--v<X.Y.Z>`. If no tag matches, install fails.

## Cross-marketplace dependencies

Depending on a plugin in *another* marketplace requires opt-in on both sides:

1. The **dependency descriptor** names the marketplace:
   ```json
   { "name": "skill-creator", "marketplace": "claude-plugins-official", "version": "^1.0" }
   ```

2. The **dependent plugin's marketplace** declares it:
   ```json
   {
     "name": "my-marketplace",
     "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"]
   }
   ```

Without #2, resolution fails with "cross-marketplace dependency not allowed". This protects users from a malicious marketplace silently pulling in plugins from sources they didn't trust.

## Resolution algorithm

When `claude plugin install <plugin>` runs:

1. Fetch the plugin's `plugin.json`.
2. For each `dependencies[]` entry:
   - Resolve marketplace (default: same marketplace as the dependent plugin).
   - Look up the dependency's available versions in that marketplace.
   - Pick the highest version satisfying the range.
   - Recursively resolve *its* dependencies.
3. Compute a flat install set.
4. Detect conflicts (see below).
5. Install each plugin in the set.

Resolution is deterministic given the same marketplace state.

## Conflicts

Two kinds:

### Version conflicts

Plugin A depends on `shared@^1.0`; plugin B depends on `shared@^2.0`. Claude Code does not install two versions side-by-side — it errors out and asks the user to pick one (or to use `optional: true` on one side).

### Name conflicts

Two plugins with the same `name` from different marketplaces both pulled into the install set. Claude Code rejects the install set; the user has to disable one marketplace or pin to a single source.

## Install set lifecycle

Dependencies installed transitively are tracked separately from user-requested installs:

- **User-requested**: appear in `enabledPlugins` directly. `claude plugin uninstall` removes them.
- **Transitive**: not in `enabledPlugins`. Removed automatically when the depending plugin is uninstalled and they have no other dependents.

Cleanup of orphaned transitives runs on every uninstall and via `claude plugin prune`.

## `claude plugin prune`

```
claude plugin prune
```

Removes:
- Cached plugin versions older than 7 days that no installed plugin references
- Transitive dependencies that have no remaining dependents
- Marketplace caches no longer referenced by any installed marketplace

Idempotent and reversible (re-installs will re-fetch).

## Optional dependencies

`"optional": true` lets a plugin gracefully degrade when a dependency is missing:

```json
{
  "dependencies": [
    {
      "name": "image-renderer",
      "version": "^1.0",
      "optional": true
    }
  ]
}
```

The plugin's runtime code should check whether `image-renderer` is installed (via `claude plugin list --json`) before invoking its components. There's no automatic feature gating — the plugin author handles it.

## What dependencies don't do

- **They don't import individual skills/agents.** Composition is at the plugin level — the dependency's components become available alongside yours. Your plugin can reference them (e.g. delegate to a dependency's agent) but you can't pick-and-choose.
- **They don't replace soft-forking.** If you need to *modify* upstream content, dependencies don't help — soft-fork instead. See `topics/plugin-structure/SKILL.md` and the marketplace's docs on the soft-fork pattern.
- **They don't substitute for marketplace dependencies.** The marketplace's `allowCrossMarketplaceDependenciesOn` is a security control, not a substitute for the `dependencies` array.
