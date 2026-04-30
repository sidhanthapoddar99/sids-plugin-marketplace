# Plugin dependencies

A plugin can declare it depends on other plugins. When installed, Claude Code resolves and auto-installs the dependency tree, and `/plugin update` keeps everything within the constraints you specify. Requires Claude Code v2.1.110+ for version constraints; v2.1.121+ for `claude plugin prune`.

## Shape

The `dependencies` field in `plugin.json` is an array. Each entry is either a **bare string** (just the plugin name) or an **object** with finer control:

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

A bare string `"audit-logger"` is equivalent to `{"name": "audit-logger"}`: no version constraint, resolves in the same marketplace.

There's no `optional` field. A declared dependency must resolve or the dependent plugin fails to install.

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

By default, Claude Code refuses to auto-install a dependency from a different marketplace than the plugin declaring it — preventing one marketplace from silently pulling in plugins from sources you haven't reviewed.

To opt in, the **root** marketplace (the one hosting the plugin the user is installing) lists the target in `allowCrossMarketplaceDependenciesOn`:

```json
// In your marketplace's .claude-plugin/marketplace.json
{
  "name": "your-marketplace",
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"]
}
```

> **Trust doesn't chain.** Only the root marketplace's allowlist is consulted. Even if A allows B and B allows C, A's plugins can't transitively pull from C unless A also allows C.

If the field is missing or the target isn't listed, install fails with a `cross-marketplace` error naming the field to set. Users can install the dependency manually first to satisfy the constraint without changing the allowlist.

## Tag-based version resolution

Version constraints resolve against **git tags on the marketplace repository**, with a specific naming convention:

```
{plugin-name}--v{version}
```

For `secrets-vault` at version `2.1.0`, the tag is `secrets-vault--v2.1.0`. The plugin-name prefix lets one marketplace repo host multiple plugins with independent version lines. The `--v` separator handles plugin names containing hyphens.

When resolving `{ "name": "secrets-vault", "version": "~2.1.0" }`, Claude Code:

1. Lists the marketplace's tags
2. Filters to `secrets-vault--v*`
3. Picks the highest version satisfying `~2.1.0`
4. Fetches that exact commit

If no matching tag exists, the dependent plugin is **disabled** with `no-matching-tag`, listing available versions.

For `npm` plugin sources, tag-based resolution does not apply — the constraint is checked at load time and the plugin is disabled with `dependency-version-unsatisfied` if the installed npm version falls outside the range.

## How constraints interact

When several installed plugins constrain the same dependency, Claude Code intersects their ranges and resolves to the highest version satisfying all of them. **Multiple versions of the same dependency can coexist in the cache** (the cache layout supports versioned subdirs), but only one resolved version is *active* at a time, decided by intersection.

| Plugin A requires | Plugin B requires | Result |
|---|---|---|
| `^2.0` | `>=2.1` | Highest `2.x` tag at or above `2.1.0`. Both load |
| `~2.1` | `~3.0` | Plugin B install fails with `range-conflict`. A and the dep stay as-is |
| `=2.1.0` | none | Dep stays at `2.1.0`. Auto-update skips newer versions while A is installed |

Auto-update fetches the highest tag satisfying every installed plugin's range, not the marketplace's latest. If no tag satisfies all ranges, the update is skipped — the skip surfaces in `/doctor` and the `/plugin` Errors tab, naming the constraining plugin.

When you uninstall the last plugin constraining a dependency, the dependency resumes tracking the marketplace's latest on the next update.

## Common dependency errors

| Error | Meaning | Fix |
|---|---|---|
| `dependency-unsatisfied` | A declared dependency isn't installed (or is disabled) | Run the `claude plugin install` command shown in the error. Add the dependency's marketplace if missing |
| `range-conflict` | Combined version requirements don't intersect, or syntax is invalid | Uninstall/update one of the conflicting plugins, fix the bad range, or ask the upstream author to widen its constraint |
| `dependency-version-unsatisfied` | Installed dep's version is outside this plugin's declared range | `claude plugin install <dep>@<marketplace>` to re-resolve |
| `no-matching-tag` | The dep repo has no `{name}--v*` tag satisfying the range | Ask upstream to tag releases using the convention, or relax your range |
| `cross-marketplace` | Dep lives in a marketplace not in the root's allowlist | Add the marketplace to `allowCrossMarketplaceDependenciesOn`, or install the dep manually first |

To check programmatically: `claude plugin list --json` and read `errors` on each plugin.

## Orphan cleanup with `claude plugin prune`

When a dep is auto-installed alongside a dependent plugin, it stays after the dependent is uninstalled — in case you reinstall, or want to keep using the dep directly. To clean up:

```bash
claude plugin prune
```

Lists auto-installed dependencies that no installed plugin requires, removes them after a confirmation prompt. **Plugins you installed yourself are never pruned** — only those pulled in via another plugin's `dependencies`.

| Option | Effect |
|---|---|
| `--scope user|project|local` | Target a specific scope (default: user) |
| `--dry-run` | List what would be removed without removing |
| `-y` | Skip the confirmation prompt (required when stdin isn't a TTY) |

To prune as part of an uninstall:

```bash
claude plugin uninstall deploy-kit --prune
```

Removes `deploy-kit` plus any auto-installed deps it leaves orphaned.

## What dependencies don't do

- **They don't import individual skills/agents.** Composition is at the plugin level — the dependency's components become available alongside yours. Your plugin can reference them (delegate to a dep's agent) but you can't pick-and-choose components.
- **They don't substitute for soft-forking.** If you need to *modify* upstream content, dependencies don't help — soft-fork instead.

## Reference

- Docs: `docs/Claude Plugins/05_creating-plugins/07_dependencies.md` (ground truth)
- Official: [Constrain plugin dependency versions](https://code.claude.com/docs/en/plugin-dependencies)
