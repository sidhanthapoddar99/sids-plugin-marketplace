# `claude plugin` CLI and `/plugin` UI reference

Two ways to manage plugins: the `claude plugin` shell CLI (scriptable) and the `/plugin` slash command UI (interactive). They expose the same operations.

## CLI surface

### Marketplace management

```
claude plugin marketplace add <ref> [--ref <branch|tag|commit>]
claude plugin marketplace remove <name>
claude plugin marketplace list [--json]
claude plugin marketplace update [<name>]            # update one or all
claude plugin marketplace validate <name>
```

`<ref>` accepts the same forms as `marketplace.json` source: `owner/repo`, full URL, etc.

### Plugin management

```
claude plugin install <plugin>[@<marketplace>] [--version <semver>]
claude plugin uninstall <plugin> [--purge]
claude plugin enable <plugin>
claude plugin disable <plugin>
claude plugin list [--json] [--scope <user|project|local|managed>]
```

`<plugin>@<marketplace>` is needed only when the same plugin name exists in multiple installed marketplaces.

### Versioning

```
claude plugin tag <version> [--push] [--no-commit]
claude plugin bump <patch|minor|major> [--push]
```

Run inside a plugin directory. `tag` creates `<plugin-name>--v<version>`. `bump` increments the version in `plugin.json` and tags it.

### Inspection

```
claude plugin scope <plugin>          # which scope a plugin is enabled at
claude plugin info <plugin>           # manifest summary, version, source
claude plugin path <plugin>           # absolute path to the cached plugin
claude plugin path <plugin> --data    # absolute path to the data dir
```

### Maintenance

```
claude plugin prune                    # GC orphaned cache, transitive deps
claude plugin validate [<path>]        # validate plugin.json (defaults to cwd)
claude plugin migrate <plugin>         # run plugin-provided migration scripts
```

### Development helpers

```
claude --plugin-dir <path> [...]       # session-scoped local plugin (see testing.md)
```

## `/plugin` UI

Interactive command, four tabs:

### 1. Browse

Lists plugins from all installed marketplaces, with a search box. Filter by category, tag, or name. Selecting a plugin shows its `description`, `author`, version, and an Install button.

### 2. Installed

Plugins currently enabled in the active scope. Shows version, source marketplace, and per-plugin actions: Disable / Uninstall / Update / View settings.

### 3. Marketplaces

Shows all added marketplaces. Per-marketplace actions: Update / Remove / View details. Includes a Refresh All button.

### 4. Settings

If a plugin declared `userConfig`, this tab renders the configuration UI (see `config/user-config.md`). Per-plugin tabs let you edit values; changes save to the active scope's settings file.

## Common workflows

### Install a plugin from a known marketplace

```
claude plugin install my-plugin
```

Resolves through every installed marketplace; errors on ambiguity.

### Install a specific version

```
claude plugin install my-plugin --version 1.2.3
```

### Try a plugin without installing

```
claude --plugin-dir /path/to/plugin
```

### Install without enabling

Not directly supported. Install, then immediately disable:

```
claude plugin install my-plugin && claude plugin disable my-plugin
```

Useful for staging a plugin in cache before flipping it on for a team.

### Switch between two installed versions

Multi-version coexistence in cache, but only one active per scope:

```
claude plugin install my-plugin --version 1.0.0
# later
claude plugin install my-plugin --version 2.0.0   # replaces v1 in active scope, both remain in cache until GC
```

### Bulk operations

```
# Disable everything except a whitelist
claude plugin list --json | jq -r '.enabledPlugins | keys[]' \
  | grep -v -E '^(plugin-a|plugin-b)$' \
  | xargs -I {} claude plugin disable {}

# Update all marketplaces and re-resolve installs
claude plugin marketplace update
claude plugin prune                    # GC outdated cache versions
```

## Environment variables affecting the CLI

| Variable | Effect |
|---|---|
| `CLAUDE_HOME` | Override default `~/.claude/` location |
| `CLAUDE_PLUGINS_CACHE` | Override default `~/.claude/plugins/cache/` |
| `CLAUDE_PLUGINS_DATA` | Override default `~/.claude/plugins/data/` |
| `CLAUDE_LOG_LEVEL=debug` | Verbose logging for any `claude plugin` command |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | General error |
| 2 | Validation failed |
| 3 | Network / fetch failed |
| 4 | Schema violation |
| 5 | Dependency resolution failed |
| 6 | Conflict (name or version) |

Useful for scripting: a `claude plugin install` returning 5 means a dependency couldn't be resolved — you can retry with `--ignore-optional` or surface the issue to the user.
