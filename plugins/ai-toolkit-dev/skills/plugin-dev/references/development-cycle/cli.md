# `claude plugin` CLI and `/plugin` UI

Two surfaces for the same operations: the interactive `/plugin` command (and friends) and the non-interactive `claude plugin <subcommand>` CLI for scripting.

## Slash commands

### `/plugin`

Tabbed UI, four tabs you cycle with **Tab** / **Shift+Tab**:

| Tab | What it shows |
|---|---|
| **Discover** | Plugins available across all your installed marketplaces |
| **Installed** | Plugins currently registered in `enabledPlugins` (any scope). Press `f` to favorite, type to filter, **Enter** for plugin detail |
| **Marketplaces** | Add / remove / update marketplaces |
| **Errors** | Load errors and unresolved dependencies |

The Installed list sorts: errors first, favorites next, disabled last.

### `/plugin marketplace add | remove | list | update`

Manage marketplaces from the prompt. Aliases: `/plugin market` for `/plugin marketplace`, `rm` for `remove`. `add` accepts five source forms:

- GitHub shorthand: `owner/repo`
- SSH URL: `git@github.com:owner/repo.git`
- HTTPS git URL
- Local path
- URL to `marketplace.json`

Pin a git-backed marketplace to a tag or branch with `#<ref>`:

```
/plugin marketplace add owner/repo#v2.0
```

### Other built-in slash commands

| Command | Use |
|---|---|
| `/reload-plugins` | Re-read all active plugins from cache without restarting. Picks up edits to skills, commands, agents, MCP servers, LSP servers. **Does NOT pick up hook changes** — hooks load at session start, restart required |
| `/hooks` | List hooks loaded in the current session |
| `/mcp` | List active MCP servers (including those provided by plugins) |
| `/agents` | Built-in scaffolder for one-off agents at user/project scope |
| `/theme` | Theme picker. Plugin-shipped themes appear alongside built-in presets. **Ctrl+E** copies a plugin theme into `~/.claude/themes/` for editing |
| `/doctor` | Surfaces plugin-related health issues: dep resolution errors, range conflicts, missing tags, skipped auto-updates with the constraining plugin named |

## CLI surface (`claude plugin <subcommand>`)

All subcommands accept `--scope user|project|local`. `update` also accepts `--scope managed`.

| Command | Notes |
|---|---|
| `claude plugin install <plugin>[@<mkt>]` | Install. Default scope: `user` |
| `claude plugin uninstall <plugin>[@<mkt>]` | Remove. Aliases: `remove`, `rm`. `--keep-data` preserves `${CLAUDE_PLUGIN_DATA}`; `--prune` cleans orphan auto-installed deps |
| `claude plugin enable <plugin>[@<mkt>]` | Set the scope's `enabledPlugins` boolean to `true` |
| `claude plugin disable <plugin>[@<mkt>]` | Set the scope's `enabledPlugins` boolean to `false` |
| `claude plugin update [<plugin>[@<mkt>]]` | Re-fetch from marketplace. Without args: update all |
| `claude plugin list [--json] [--available]` | List installed plugins. `--json` exposes a structured `errors` field; `--available` adds plugins from marketplaces (requires `--json`) |
| `claude plugin tag [--push] [--dry-run] [-f]` | Create the release tag. Run from inside the plugin folder. Tag name is **auto-derived** from `plugin.json` and the marketplace entry — not given as an arg. See [release.md](release.md) |
| `claude plugin prune [--dry-run] [-y]` | Remove auto-installed dependencies no installed plugin requires. Alias: `autoremove`. **Plugins you installed yourself are never pruned.** Requires Claude Code v2.1.121+ |
| `claude plugin marketplace add | remove | list | update` | Same as the slash variants |

### Subcommands that do NOT exist

These are commonly assumed but aren't real: `bump`, `scope`, `info`, `path`, `migrate`, `validate`, `marketplace validate`. To check a plugin is healthy, install it and look at `claude plugin list --json` for the `errors` field, or use `/doctor`.

## Common workflows

### Install from a known marketplace

```
claude plugin install my-plugin
```

Resolves through every installed marketplace. Use `<plugin>@<marketplace>` to disambiguate when the same plugin name exists in multiple installed marketplaces.

### Install at project scope

```
claude plugin install my-plugin --scope project
```

Writes the `enabledPlugins` boolean to `<repo>/.claude/settings.json` (committed).

### Try a plugin without installing

```
claude --plugin-dir /path/to/plugin
```

See [`testing.md`](testing.md).

### Inspect what's installed and where it lives

```bash
claude plugin list --json
```

For an *installed* plugin, the cache path is fixed by convention: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` (see [`lifecycle-and-storage.md`](lifecycle-and-storage.md)).

### Bulk operations

```bash
# Disable everything except a whitelist
claude plugin list --json | jq -r '.enabledPlugins | keys[]' \
  | grep -v -E '^(plugin-a|plugin-b)$' \
  | xargs -I {} claude plugin disable {}

# Refresh marketplaces and prune orphans
claude plugin marketplace update
claude plugin prune
```

## Auto-update behavior

Marketplaces auto-update at startup by default for **official Anthropic marketplaces**. Third-party and local-development marketplaces have auto-update **disabled** by default. Toggle per-marketplace in the `/plugin` UI.

| Env var | Effect |
|---|---|
| `DISABLE_AUTOUPDATER` | Globally disables Claude Code auto-updates *including* plugin updates |
| `FORCE_AUTOUPDATE_PLUGINS` | With `DISABLE_AUTOUPDATER=1` set, keeps plugin auto-updates enabled while disabling Claude Code core updates |

## Reference

- Official: [CLI commands reference](https://code.claude.com/docs/en/plugins-reference#cli-commands-reference)
- Official: [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)
