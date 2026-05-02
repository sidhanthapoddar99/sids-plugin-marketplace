# Built-in slash commands

The interactive surface for plugin operations. Each command works inside an active Claude Code session; most have a non-interactive `claude plugin` equivalent for scripts.

## Catalogue

| Command | Purpose |
|---|---|
| `/plugin` | Open the tabbed plugin manager UI |
| `/plugin install\|uninstall\|enable\|disable\|update <plugin>[@<mkt>]` | Same operations as the `claude plugin` CLI, prompt-line form |
| `/plugin marketplace add\|remove\|list\|update` | Manage marketplaces from the prompt (alias `/plugin market`, `rm` for `remove`) |
| `/reload-plugins` | Re-read active plugins from cache without restarting |
| `/hooks` | List hooks loaded in the current session |
| `/mcp` | List active MCP servers (including plugin-provided) |
| `/agents` | Built-in scaffolder for one-off agents at user/project scope |
| `/theme` | Theme picker — built-in presets plus plugin-shipped themes |
| `/doctor` | Surface plugin-related health issues |
| `/plugin-hints` | Recommend a marketplace + plugins to other Claude Code users from the prompt. See [`../14_distribution/02_plugin-hints.md`](../14_distribution/02_plugin-hints.md) |

## `/plugin`

Opens the interactive plugin manager. Tabbed UI with four tabs cycled with **Tab** / **Shift+Tab**:

| Tab | What it shows |
|---|---|
| **Discover** | Plugins available across all installed marketplaces |
| **Installed** | Plugins currently registered in `enabledPlugins` (any scope) |
| **Marketplaces** | Add / remove / update marketplaces |
| **Errors** | Load errors and unresolved dependencies |

Detailed UI behaviour — sort priority, favorites, filtering — is in [`03_plugin-ui.md`](./03_plugin-ui.md).

## `/plugin install | uninstall | enable | disable | update`

Same operations as the corresponding `claude plugin` subcommands, in slash form. The prompt-line variant is convenient when you already know the plugin name and want to avoid leaving the session.

```
/plugin install my-plugin@my-marketplace
/plugin uninstall my-plugin@my-marketplace
/plugin disable my-plugin@my-marketplace
/plugin update my-plugin@my-marketplace
```

For flags (`--scope`, `--keep-data`, etc.), see [`01_claude-plugin-cli.md`](./01_claude-plugin-cli.md).

## `/plugin marketplace add | remove | list | update`

Manage marketplaces from the prompt. Aliases:

- `/plugin market` is short for `/plugin marketplace`
- `rm` is short for `remove`

`add` accepts five source forms:

- GitHub shorthand: `owner/repo`
- SSH URL: `git@github.com:owner/repo.git`
- HTTPS git URL
- Local path
- URL to a `marketplace.json` file

Pin a git-backed marketplace to a tag or branch with `#<ref>`:

```
/plugin marketplace add owner/repo#v2.0
```

## `/reload-plugins`

Re-read all active plugins from the cache without restarting the session. Reports counts:

```
Reloaded: 5 plugins · 4 skills · 5 agents · 1 hook · 0 plugin MCP servers · 1 plugin LSP server
```

Picks up edits to:

- Skills, commands, agents
- MCP server configs
- LSP server configs
- `bin/` wrappers

Does **NOT** pick up:

- Hook config changes (hooks load at session start; restart required)
- Monitor changes (monitors are session-lifetime)

If a count is missing or lower than expected, the load failed — check the manifest for that plugin and try again.

## `/hooks`

Lists hooks loaded in the current session, grouped by event (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionStart`, `Notification`, etc.).

Useful when debugging which hooks fired and which didn't. If a hook you expect isn't listed, the plugin's manifest didn't register it correctly — fix and restart.

## `/mcp`

Lists all active MCP servers including those provided by plugins. For each server: name, transport (stdio / SSE / HTTP / WebSocket), connection state, and the tools it registered.

Use after configuring a new server to verify it connected. If a plugin's server doesn't appear, common causes:

- The plugin isn't enabled
- `.mcp.json` references `${CLAUDE_PLUGIN_ROOT}` somewhere it isn't expanded
- The server binary failed to start (check stderr)

## `/agents`

Built-in guided scaffolder for subagents. Walks through `name`, `description`, allowed `tools`, and optionally a starting system prompt — writes the result to `~/.claude/agents/` (user scope) or `<repo>/.claude/agents/` (project scope).

Use this for one-off agents you don't want to ship as part of a plugin. For agents that belong inside a plugin, just author the markdown directly under `agents/` in the plugin folder.

## `/theme`

Theme picker. Plugin-shipped themes appear here alongside built-in presets and the user's local themes (under `~/.claude/themes/`).

| Key | Action |
|---|---|
| Up / Down | Navigate themes |
| Enter | Apply selected theme |
| **Ctrl+E** | Copy a plugin theme into `~/.claude/themes/` so you can edit the copy |

Selecting a plugin theme persists the choice as `custom:<plugin-name>:<slug>` in the user's config. Plugin themes themselves are read-only — Ctrl+E is the path to forking one.

## `/doctor`

Surfaces plugin-related health issues:

- Dependency resolution errors
- Range conflicts (two plugins requiring incompatible versions of a dep)
- Missing tags (a dep referenced by tag that doesn't exist on the remote)
- Skipped auto-updates with the constraining plugin named (so you know which plugin is holding up an upgrade)

Run after a `marketplace update` cycle if you suspect something didn't resolve cleanly. The output names the specific plugin and dependency causing each issue.

## See also

- [`01_claude-plugin-cli.md`](./01_claude-plugin-cli.md) — the non-interactive equivalents
- [`03_plugin-ui.md`](./03_plugin-ui.md) — what `/plugin` opens
- [`../15_reference/03_frontmatter-flags.md`](../15_reference/03_frontmatter-flags.md) — `disable-model-invocation` for slash commands you want user-only
- Official: [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)
