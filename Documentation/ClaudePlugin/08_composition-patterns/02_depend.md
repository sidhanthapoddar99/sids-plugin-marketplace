# Depend

Declare your plugin requires another plugin. When installed, Claude Code resolves and auto-installs the dependency tree, and `/plugin update` keeps everything within the constraints you specify.

> [!note]
> Version constraints require Claude Code v2.1.110+. The `claude plugin prune` command requires v2.1.121+.

## When to use

| Goal | Use a dependency |
|---|---|
| Your plugin extends another plugin's skills/commands | ✅ |
| Your plugin assumes another plugin's MCP server is registered | ✅ |
| You want users to get a related plugin auto-installed alongside yours | ✅ |
| You want to *recommend* another plugin in your README | ❌ no formal mechanism — document it manually |
| You want to avoid duplicating someone else's content | ✅ |

The official `plugin-dev` plugin is a common dependency target — your plugin can build on its authoring skills without re-shipping them.

## Shape

The `dependencies` field in `plugin.json` is an array. Each entry is either a **bare string** (just the plugin name) or an **object**:

```json
{
  "name": "deploy-kit",
  "version": "3.1.0",
  "dependencies": [
    "audit-logger",
    { "name": "secrets-vault", "version": "~2.1.0" },
    { "name": "plugin-dev", "marketplace": "claude-plugins-official" }
  ]
}
```

### Object form fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Plugin name. Resolves within the same marketplace as the declaring plugin unless `marketplace` is set |
| `version` | optional | Semver range — see below |
| `marketplace` | optional | Different marketplace to resolve `name` in. Only allowed if the **root** marketplace's `allowCrossMarketplaceDependenciesOn` lists this marketplace |

A bare string `"audit-logger"` is equivalent to `{ "name": "audit-logger" }`: no version constraint, resolves in the same marketplace. There is no `optional` field — a declared dependency must resolve or the dependent plugin fails to install.

## Semver ranges

The `version` field accepts any expression supported by Node's `semver` package:

| Range | Matches |
|---|---|
| `~2.1.0` | `2.1.x` (any patch ≥ `2.1.0`) |
| `^2.0` | `2.x.x` (any minor/patch with major `2`) |
| `>=1.4` | Anything `1.4.0` or higher |
| `=2.1.0` | Exactly `2.1.0` |
| `>=1.4 <2.0` | A range with both ends |

Pre-release versions like `2.0.0-beta.1` are excluded unless the range opts in (`^2.0.0-0`).

The dependency is fetched at the **highest tagged version** that satisfies the range.

## Cross-marketplace dependencies

By default, Claude Code refuses to auto-install a dependency from a different marketplace than the plugin declaring it. This prevents one marketplace from silently pulling in plugins from sources you haven't reviewed.

To opt in, the **root** marketplace (the one hosting the plugin the user is installing) lists the target in `allowCrossMarketplaceDependenciesOn`:

```json
// In your marketplace's .claude-plugin/marketplace.json
{
  "name": "your-marketplace",
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    {
      "name": "your-plugin",
      "source": "./plugins/your-plugin",
      "dependencies": [
        { "name": "plugin-dev", "marketplace": "claude-plugins-official" }
      ]
    }
  ]
}
```

> [!important]
> **Trust doesn't chain.** Only the root marketplace's allowlist is consulted. Even if marketplace A allows B and B allows C, A's plugins can't transitively pull from C unless A also allows C. This is by design — every cross-marketplace dependency is explicitly approved by the root marketplace, not transitively trusted.

If the field is missing or the target isn't listed, install fails with a `cross-marketplace` error naming the field to set. Users can install the dependency manually first to satisfy the constraint without changing the allowlist.

## Tag-based version resolution

Version constraints resolve against **git tags on the marketplace repository**, with this naming convention:

```
{plugin-name}--v{version}
```

For `secrets-vault` at version `2.1.0`, the tag is `secrets-vault--v2.1.0`. The plugin-name prefix lets one marketplace repo host multiple plugins with independent version lines. The `--v` separator handles plugin names containing hyphens.

When resolving `{ "name": "secrets-vault", "version": "~2.1.0" }`, Claude Code:

1. Lists the marketplace's tags
2. Filters to `secrets-vault--v*`
3. Picks the highest version satisfying `~2.1.0`
4. Fetches that exact commit

If no matching tag exists, the dependent plugin is **disabled** with a `no-matching-tag` error listing the available versions.

For `npm` plugin sources, tag-based resolution does not apply — the constraint is checked at load time and the plugin is disabled with `dependency-version-unsatisfied` if the installed npm version falls outside the range.

### Tagging a release

From inside the plugin folder:

```bash
claude plugin tag --push
```

This:

- Derives the tag name from `plugin.json` and the marketplace entry
- Validates plugin contents
- Checks `plugin.json` and the marketplace entry agree on the version
- Requires a clean working tree under the plugin directory
- Refuses if the tag already exists
- (`--push`) pushes the tag to the remote

Add `--dry-run` to preview without creating. `--force` overrides the safety checks.

See [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) for the release loop.

## How constraints interact

When several installed plugins constrain the same dependency, Claude Code intersects their ranges and resolves to the highest version satisfying all of them. **Multiple versions of the same dependency can coexist in the cache** (the cache layout supports versioned subdirs), but only one resolved version is *active* at a time, decided by intersection.

| Plugin A requires | Plugin B requires | Result |
|---|---|---|
| `^2.0` | `>=2.1` | Highest `2.x` tag at or above `2.1.0`. Both plugins load |
| `~2.1` | `~3.0` | Plugin B install fails with `range-conflict`. A and the dependency stay as-is |
| `=2.1.0` | none | Dependency stays at `2.1.0`. Auto-update skips newer versions while A is installed |

Auto-update fetches the highest tag satisfying every installed plugin's range, not the marketplace's latest. If no tag satisfies all ranges, the update is skipped — the skip surfaces in `/doctor` and the `/plugin` Errors tab, naming the constraining plugin.

When you uninstall the last plugin constraining a dependency, the dependency resumes tracking the marketplace's latest on the next update.

## Common dependency errors

| Error | Meaning | Fix |
|---|---|---|
| `dependency-unsatisfied` | A declared dependency isn't installed (or is disabled) | Run the `claude plugin install` command shown in the error. Add the dependency's marketplace if missing |
| `range-conflict` | Combined version requirements don't intersect, or syntax is invalid | Uninstall/update one of the conflicting plugins, fix the bad range, or ask the upstream author to widen its constraint |
| `dependency-version-unsatisfied` | Installed dependency's version is outside this plugin's declared range | `claude plugin install <dep>@<marketplace>` to re-resolve |
| `no-matching-tag` | The dependency repo has no `{name}--v*` tag satisfying the range | Ask upstream to tag releases using the convention, or relax your range |
| `cross-marketplace` | Dependency lives in a marketplace not in the root's allowlist | Add the marketplace to `allowCrossMarketplaceDependenciesOn`, or install the dependency manually first |

To check programmatically: `claude plugin list --json` and read the `errors` field on each plugin.

## Orphan cleanup with `claude plugin prune`

When a dependency is auto-installed alongside a dependent plugin, it stays on disk after the dependent is uninstalled — in case you reinstall, or want to keep using the dependency directly. To clean up:

```bash
claude plugin prune
```

Lists auto-installed dependencies that no installed plugin requires, removes them after a confirmation prompt. **Plugins you installed yourself are never pruned** — only those pulled in via another plugin's `dependencies` array.

| Option | Effect |
|---|---|
| `--scope user\|project\|local` | Target a specific scope (default: user) |
| `--dry-run` | List what would be removed without removing |
| `-y` | Skip the confirmation prompt (required when stdin isn't a TTY) |

To prune as part of an uninstall:

```bash
claude plugin uninstall deploy-kit --prune
```

Removes `deploy-kit` plus any auto-installed deps it leaves orphaned.

## Worked example: extending `plugin-dev`

Suppose you want to publish `plugin-handbook` in your own marketplace `sids-plugin-marketplace`, and it should auto-install `plugin-dev@claude-plugins-official` alongside.

### 1. Allow the cross-marketplace dependency

`.claude-plugin/marketplace.json`:

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

### 2. Declare the dependency

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

### 3. Install

```
/plugin install plugin-handbook@sids-plugin-marketplace
```

Claude Code:

1. Reads `plugin-handbook`'s `dependencies`
2. Sees `plugin-dev@claude-plugins-official`
3. Checks the root marketplace's `allowCrossMarketplaceDependenciesOn` — finds `claude-plugins-official` listed → allowed
4. Resolves `plugin-dev`'s latest tag in `claude-plugins-official`
5. Installs both plugins
6. Lists the auto-installed dependency in the install output

When the user uninstalls `plugin-handbook`, `plugin-dev` stays unless they pass `--prune` or run `claude plugin prune` later.

## What dependencies don't do

- **Don't import individual skills/agents.** Composition is at the plugin level — the dependency's components become available alongside yours. Your plugin can reference them (delegate to a dep's agent, or document "use the foo skill from `plugin-dev`") but you can't pick-and-choose components.
- **Don't substitute for soft-forking.** If you need to *modify* upstream content, dependencies don't help — the dep's content is loaded verbatim from the dep's install. Soft-fork instead. See [`03_soft-fork.md`](./03_soft-fork.md).
- **Don't establish trust transitively.** "Plugin A depends on plugin B" doesn't grant B's plugins any privilege. Trust is enforced at install time per-plugin, scoped to the marketplace allowlist.

## See also

- [`01_hand-author.md`](./01_hand-author.md) — when there's no upstream worth depending on
- [`03_soft-fork.md`](./03_soft-fork.md) — when you'd rewrite upstream anyway, vendor instead
- [`../04_marketplaces/00_index.md`](../04_marketplaces/00_index.md) — `allowCrossMarketplaceDependenciesOn`
- [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) — semver discipline and the release loop
- [`../15_reference/00_index.md`](../15_reference/00_index.md) — the full error catalog
- Official: [Constrain plugin dependency versions](https://code.claude.com/docs/en/plugin-dependencies)
