# `claude plugin` CLI

Non-interactive equivalent of the `/plugin` UI, for scripts, CI jobs, and bulk operations. Every interactive operation has a CLI form; not every CLI subcommand has an interactive form.

## Subcommand inventory

| Subcommand | Aliases | Purpose |
|---|---|---|
| `install <plugin>[@<mkt>]` | — | Install a plugin |
| `uninstall <plugin>[@<mkt>]` | `remove`, `rm` | Remove a plugin |
| `enable <plugin>[@<mkt>]` | — | Set the scope's `enabledPlugins` boolean to `true` |
| `disable <plugin>[@<mkt>]` | — | Set the scope's `enabledPlugins` boolean to `false` |
| `update [<plugin>[@<mkt>]]` | — | Re-fetch from marketplace. Without args: update all |
| `list` | — | List installed plugins |
| `tag` | — | Create a release tag using the `{name}--v{version}` convention |
| `prune` | `autoremove` | Remove auto-installed dependencies no installed plugin requires |
| `marketplace add\|remove\|list\|update` | — | Manage marketplaces |

### Subcommands that do NOT exist

These look plausible but aren't real. Don't write scripts that depend on them:

`bump`, `scope`, `info`, `path`, `migrate`, `validate`, `marketplace validate`.

To check a plugin is healthy, use `claude plugin list --json` and inspect the `errors` field, or run `/doctor` interactively.

## Scope flag

Every subcommand accepts `--scope`:

| Value | Where it writes |
|---|---|
| `user` (default) | `~/.claude/settings.json` |
| `project` | `<repo>/.claude/settings.json` (committed) |
| `local` | `<repo>/.claude/settings.local.json` (gitignored) |
| `managed` | Org-deployed settings — only valid on `update` |

Scope determines which `settings.json` the `enabledPlugins` boolean lands in. Plugin **files** always live once at `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/` regardless of scope.

## `install`

```
claude plugin install <plugin>[@<marketplace>] [--scope user|project|local]
```

| Flag | Effect |
|---|---|
| `--scope <user\|project\|local>` | Where the `enabledPlugins` boolean is written. Default: `user` |

Resolves through every installed marketplace if `@<marketplace>` is omitted. Use the disambiguator when the same plugin name exists in multiple marketplaces.

Examples:

```bash
claude plugin install my-plugin                              # user scope, any marketplace
claude plugin install my-plugin@my-mkt                       # specific marketplace
claude plugin install my-plugin@my-mkt --scope project       # commit to repo
```

## `uninstall` / `remove` / `rm`

```
claude plugin uninstall <plugin>[@<marketplace>]
  [--scope user|project|local]
  [--keep-data]
  [--prune]
```

| Flag | Effect |
|---|---|
| `--scope` | Which scope's `enabledPlugins` boolean to remove |
| `--keep-data` | Preserve `${CLAUDE_PLUGIN_DATA}` for this plugin (default behaviour wipes it) |
| `--prune` | After uninstall, also remove auto-installed dependencies no remaining plugin requires |

Removes the boolean from the chosen scope. If the same plugin is enabled at multiple scopes, the uninstall only touches the scope you specified — the plugin stays loaded via the others.

Cache-folder removal is best-effort and not guaranteed; see [`../11_testing-and-iteration/04_clean-install-loop.md`](../11_testing-and-iteration/04_clean-install-loop.md) for the manual wipe.

## `enable` / `disable`

```
claude plugin enable  <plugin>[@<marketplace>] [--scope ...]
claude plugin disable <plugin>[@<marketplace>] [--scope ...]
```

Toggle the `enabledPlugins` boolean without uninstalling. Files stay cached; re-enable is instant.

Use `disable` for "I'm not using this right now but might next week." Use `uninstall` when you're done with it.

## `update`

```
claude plugin update [<plugin>[@<marketplace>]]
  [--scope user|project|local|managed]
```

Without arguments: walks every installed plugin and checks for new versions in their respective marketplaces. With arguments: updates one.

The `managed` scope value applies only here — for organisation-deployed updates that bypass user/project settings.

```bash
claude plugin update                        # update all
claude plugin update my-plugin@my-mkt       # update one
```

## `list`

```
claude plugin list [--json] [--available]
```

| Flag | Effect |
|---|---|
| `--json` | Machine-readable output. Includes a structured `errors` field per plugin |
| `--available` | Adds plugins from configured marketplaces that aren't installed. Requires `--json` |

Output (without `--json`) lists installed plugins per scope. With `--json` you get full plugin metadata, version, source, scope, and per-plugin error state.

```bash
# Inspect the errors field
claude plugin list --json | jq '.[] | select(.errors | length > 0)'

# Names of every plugin available across marketplaces
claude plugin list --json --available | jq -r '.[].name'

# Disable everything except a whitelist
claude plugin list --json | jq -r '.enabledPlugins | keys[]' \
  | grep -v -E '^(plugin-a|plugin-b)$' \
  | xargs -I {} claude plugin disable {}
```

## `tag`

```
claude plugin tag [--push] [--dry-run] [-f]
```

| Flag | Effect |
|---|---|
| `--push` | Push the new tag to the remote after creating it |
| `--dry-run` | Print the tag name without creating it |
| `-f` | Force-overwrite an existing tag of the same name |

Run from inside the plugin folder. The tag name is **auto-derived** from `plugin.json` (`name`, `version`) using the `{name}--v{version}` convention — you don't pass it as an argument. Used by the dependency system for tag-based release resolution. See [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md).

## `prune` / `autoremove`

```
claude plugin prune [--dry-run] [-y]
```

| Flag | Effect |
|---|---|
| `--dry-run` | List what would be pruned without removing |
| `-y` | Skip the confirmation prompt |

Removes auto-installed dependencies no installed plugin requires. **Plugins you installed yourself are never pruned** — only deps the resolver pulled in. Requires Claude Code v2.1.121+.

```bash
claude plugin marketplace update    # refresh first
claude plugin prune --dry-run       # see what would go
claude plugin prune -y              # actually clean up
```

## `marketplace` subcommands

Same operations as the `/plugin marketplace …` slash commands.

```
claude plugin marketplace add <source>    [--scope ...]
claude plugin marketplace remove <name>   [--scope ...]
claude plugin marketplace list   [--json] [--scope ...]
claude plugin marketplace update [<name>] [--scope ...]
```

`add` accepts the same five source forms as the slash command:

- GitHub shorthand: `owner/repo`
- SSH URL: `git@github.com:owner/repo.git`
- HTTPS git URL
- Local path
- URL to `marketplace.json`

Pin a git-backed marketplace to a tag or branch with `#<ref>`:

```bash
claude plugin marketplace add owner/repo#v2.0
```

## Common workflows

### Inspect what's installed and where it lives

```bash
claude plugin list --json | jq '.[] | {name, version, marketplace, scope, source}'
```

For an *installed* plugin, the cache path is fixed: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.

### Refresh marketplaces and clean up orphans

```bash
claude plugin marketplace update
claude plugin prune
```

### Install at project scope and verify

```bash
claude plugin install my-plugin --scope project
git diff .claude/settings.json    # check what got committed
```

### Headless install in CI

```bash
claude plugin marketplace add https://github.com/org/our-marketplace
claude plugin install our-tooling@our-marketplace --scope project
claude plugin list --json | jq -e '.[] | select(.name == "our-tooling")'
```

## See also

- [`02_built-in-slash-commands.md`](./02_built-in-slash-commands.md) — interactive equivalents
- [`../11_testing-and-iteration/04_clean-install-loop.md`](../11_testing-and-iteration/04_clean-install-loop.md) — using these commands as the verification loop
- [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) — env vars that affect `update` behaviour
- Official: [CLI commands reference](https://code.claude.com/docs/en/plugins-reference#cli-commands-reference)
