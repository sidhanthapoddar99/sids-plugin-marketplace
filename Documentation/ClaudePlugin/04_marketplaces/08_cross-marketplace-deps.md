# Cross-marketplace dependencies

A plugin in one marketplace can declare a dependency on a plugin in a *different* marketplace, but only if the **root** marketplace explicitly opts in. The opt-in lives in `marketplace.json`'s `allowCrossMarketplaceDependenciesOn` field; the dependency declaration itself lives on the depending plugin via `dependencies[].marketplace`.

> Cross-marketplace deps are how a plugin like `plugin-handbook` (in your own marketplace) can build on `plugin-dev` (in `claude-plugins-official`) without forcing every consumer to manually add both marketplaces.

## The two ends

### 1. Marketplace-side: the allowlist

`allowCrossMarketplaceDependenciesOn` is a top-level array of marketplace names that plugins in *this* marketplace are allowed to depend on:

```json
{
  "name": "your-marketplace",
  "owner": { "name": "Your Name" },
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    {
      "name": "your-plugin",
      "source": "./plugins/your-plugin"
    }
  ]
}
```

Without this field (or without the target marketplace listed), any cross-marketplace dependency in any of this marketplace's plugins fails with a `cross-marketplace` error.

### 2. Plugin-side: the dependency declaration

Inside the depending plugin's `plugin.json`, the `dependencies` array uses object form with the `marketplace` field set:

```json
{
  "name": "your-plugin",
  "version": "1.0.0",
  "dependencies": [
    { "name": "plugin-dev", "marketplace": "claude-plugins-official" },
    { "name": "secrets-vault", "version": "~2.1.0" }
  ]
}
```

The `marketplace` field can be omitted when the dependency lives in the same marketplace as the depending plugin (the second entry above resolves within the same marketplace).

## Trust does not chain

This is the central rule:

> Only the **root** marketplace's allowlist is consulted — the root being the marketplace hosting the plugin the user is installing. Even if marketplace A allows B and B allows C, A's plugins cannot transitively pull from C unless A also allows C.

Why: trust is established at install time by the user adding a marketplace, and that trust shouldn't leak through dependency graphs to marketplaces the user has never seen. Each cross-marketplace edge requires explicit opt-in by the marketplace closest to the user's install point.

| Scenario | Allowed? |
|---|---|
| User installs `X@A`, `X` depends on `Y@A` (same marketplace) | Yes — same marketplace, no allowlist check |
| User installs `X@A`, `X` depends on `Y@B`, A's `allowCrossMarketplaceDependenciesOn: [B]` | Yes |
| User installs `X@A`, `X` depends on `Y@B`, A's allowlist doesn't include B | No — `cross-marketplace` error |
| User installs `X@A`, `X` depends on `Y@B`, `Y` depends on `Z@C`, A allows B and B allows C | No — A must also allow C |
| User pre-installs `Y@B` manually, then installs `X@A` which depends on `Y@B` | Yes — the dependency is already satisfied; allowlist not re-checked |

## Worked example

A plugin `plugin-handbook` in `sids-plugin-marketplace` that auto-installs `plugin-dev` from `claude-plugins-official`:

### Marketplace manifest

```json
{
  "name": "sids-plugin-marketplace",
  "owner": { "name": "Sid" },
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    {
      "name": "plugin-handbook",
      "source": "./plugins/plugin-handbook",
      "description": "End-to-end plugin development handbook"
    }
  ]
}
```

### Plugin manifest

`plugins/plugin-handbook/.claude-plugin/plugin.json`:

```json
{
  "name": "plugin-handbook",
  "version": "0.1.0",
  "dependencies": [
    { "name": "plugin-dev", "marketplace": "claude-plugins-official" }
  ]
}
```

### Install flow

When a user runs `/plugin install plugin-handbook@sids-plugin-marketplace`:

1. Claude Code reads `plugin-handbook`'s `dependencies`
2. Sees `plugin-dev@claude-plugins-official`
3. Checks the root (`sids-plugin-marketplace`) `allowCrossMarketplaceDependenciesOn` → finds `claude-plugins-official` listed → allowed
4. Resolves `plugin-dev`'s latest tag in `claude-plugins-official`
5. Installs both plugins
6. Lists the auto-installed dependency in the install output

When the user uninstalls `plugin-handbook`, `plugin-dev` stays unless they pass `--prune` or run `claude plugin prune` later.

## Errors

| Error | Cause | Fix |
|---|---|---|
| `cross-marketplace` | Dep marketplace not in root's allowlist | Add target marketplace to `allowCrossMarketplaceDependenciesOn`, or pre-install the dep manually |
| `dependency-unsatisfied` | Allowed but the dep marketplace isn't registered on the user's machine | Tell the user to add the target marketplace, or document it in the plugin README |
| `range-conflict` | Multiple plugins constrain the same cross-marketplace dep with non-intersecting ranges | Widen one range, or remove a constrainer |
| `no-matching-tag` | Dep marketplace's repo has no `<plugin>--v*` tag satisfying the range | Ask the upstream maintainer to tag using the convention, or relax the range |

## When to use

| Goal | Use cross-marketplace dep |
|---|---|
| Build on top of an upstream plugin without copy-pasting | Yes |
| Auto-install a related plugin alongside yours | Yes |
| Recommend an external plugin in your README | No — there's no formal "recommend" mechanism, just document it |
| Vendor upstream content into your own plugin | No — use the soft-fork pattern instead. See [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md) |

## See also

- [`08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — the full dependency story (semver ranges, range intersection, `claude plugin prune`)
- [`09_versioning-and-publishing/01_semver.md`](../09_versioning-and-publishing/01_semver.md) — the version-range syntax dependencies use
- [`09_versioning-and-publishing/02_tagging-convention.md`](../09_versioning-and-publishing/02_tagging-convention.md) — how cross-marketplace deps resolve to specific git tags
- [`10_trust-and-security.md`](../10_trust-and-security.md) — broader trust model
