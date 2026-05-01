# Tagging convention

Claude Code resolves dependency version ranges against **git tags on the marketplace repository** using a specific format:

```
{plugin-name}--v{version}
```

For a plugin named `secrets-vault` at version `2.1.0`, the tag is `secrets-vault--v2.1.0`.

## Why this format

Two reasons to use a custom format rather than just `v2.1.0`:

| Reason | Detail |
|---|---|
| **Multiple plugins per repo** | One marketplace repo can host many plugins, each with its own version line. The plugin-name prefix scopes the tag |
| **Plugin names with hyphens** | Plugin names like `claude-deploy` would be ambiguous with a `v` prefix (`claude-deploy-v2.1.0` vs `claude-deploy--v2.1.0`). The double-hyphen `--v` separator is unambiguous |

Example coexistence in one marketplace repo:

```
claude-deploy--v1.0.0
claude-deploy--v1.1.0
secrets-vault--v2.0.0
secrets-vault--v2.1.0
audit-logger--v3.4.5
```

Each plugin moves on its own version line; users installing one plugin don't see versions for the others.

## How resolution uses tags

When resolving `{ "name": "secrets-vault", "version": "~2.1.0" }`, Claude Code:

1. Lists tags on the marketplace repo
2. Filters to `secrets-vault--v*`
3. Picks the highest version that satisfies `~2.1.0`
4. Fetches that exact commit

If no matching tag exists, the dependent plugin is **disabled** with an error listing the available versions.

## `claude plugin tag`

The CLI command that creates these tags. Run from inside the plugin folder:

```bash
claude plugin tag                  # create the tag locally
claude plugin tag --push           # create and push to remote
claude plugin tag --dry-run        # preview without creating
claude plugin tag --force          # override safety checks
```

Note: there's **no version argument**. The version is auto-derived from the plugin's `plugin.json` to ensure the tag matches the manifest.

### What it does

| Step | Detail |
|---|---|
| 1. Read `plugin.json` | Extract `name` and `version` |
| 2. Read marketplace entry | Confirm the plugin is listed in this repo's `marketplace.json` |
| 3. Cross-check versions | If marketplace entry has its own `version`, must agree with `plugin.json` |
| 4. Validate plugin contents | Run a lightweight validation pass |
| 5. Check working tree | Plugin directory must be clean |
| 6. Check tag uniqueness | Refuses if `<name>--v<version>` already exists (use `-f` to override) |
| 7. Create tag | `git tag <name>--v<version>` at HEAD |
| 8. (`--push`) Push to remote | `git push origin <name>--v<version>` |

### Safety flags

| Flag | Effect |
|---|---|
| `--push` | Push the new tag to the remote after creation |
| `--dry-run` | Print what would happen, create nothing |
| `-f`, `--force` | Override checks: clean tree, tag uniqueness, version agreement |

## Tag flow in a multi-plugin repo

```
my-marketplace/
├── .claude-plugin/marketplace.json
└── plugins/
    ├── alpha/.claude-plugin/plugin.json   ← version: 1.0.0
    └── beta/.claude-plugin/plugin.json    ← version: 2.3.1
```

Run `claude plugin tag --push` from `plugins/alpha/` to create `alpha--v1.0.0` and push.
Run `claude plugin tag --push` from `plugins/beta/` to create `beta--v2.3.1` and push.

The two tags are independent — bumping `alpha` to `1.0.1` and tagging it doesn't affect `beta`.

## When tag-based resolution does NOT apply

| Source type | Resolution mechanism |
|---|---|
| `github`, `url`, `git-subdir`, relative path | Tag-based — uses `<plugin>--v<version>` format |
| `npm` | npm's own version resolution. The `version` constraint is checked at load time but doesn't change which version is fetched |
| Local directory not in a git repo | Version is `unknown`; constraints can't apply |

For npm sources, if the installed npm version falls outside the constraint range, the plugin is disabled with `dependency-version-unsatisfied`. To control which npm version gets installed, set the `version` field on the source object itself (which goes to npm), not the dependency constraint.

## Pre-release tags

Pre-release versions follow the same prefix convention with the standard semver suffix:

```
deploy-kit--v2.0.0-rc.1
deploy-kit--v2.0.0-beta.3
plugin-name--v3.0.0-alpha.1
```

These are filtered out of regular range resolution unless the consuming range explicitly opts in (`^2.0.0-0`). See [`05_pre-releases-and-hotfixes.md`](./05_pre-releases-and-hotfixes.md).

## See also

- [`01_semver.md`](./01_semver.md) — the range syntax that resolves against these tags
- [`04_release-loop.md`](./04_release-loop.md) — the standard tag-then-push release flow
- [`05_pre-releases-and-hotfixes.md`](./05_pre-releases-and-hotfixes.md) — `-rc` tags and hotfix bumps
- [`08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — `claude plugin prune` and orphan cleanup
