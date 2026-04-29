---
title: Reference
description: Nomenclature index for plugin features the rest of these docs only mention in passing — one-paragraph entries with links to the canonical official docs
---

# Reference

The earlier pages cover the lifecycle and authoring story end-to-end at the depth most plugin authors need. This page is the catch-all: every term, capability, env var, and CLI command that exists in the Claude Code plugin system but isn't worth its own chapter — one paragraph each, with a link to the canonical official doc.

If you find yourself needing more than the paragraph here, the link is the source of truth.

---

## Built-in slash commands

### `/plugin`

Opens the interactive plugin manager. Tabbed UI with four tabs you cycle through with **Tab**/**Shift+Tab**: **Discover** (browse plugins from all your marketplaces), **Installed** (view/manage installed plugins), **Marketplaces** (add/remove/update marketplaces), **Errors** (load errors and unresolved dependencies). In the Installed list, press `f` to favorite a plugin, type to filter, Enter to open the plugin's detail view. The list sort prioritises errors, then favorites, then disables (collapsed at bottom). → [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins)

### `/plugin marketplace add | remove | list | update`

Manage marketplaces from the prompt. Shortcuts: `/plugin market` is an alias for `/plugin marketplace`, and `rm` is an alias for `remove`. `add` accepts five source forms (GitHub shorthand, SSH URL, HTTPS git URL, local path, URL to `marketplace.json`) and supports ref pinning via `#<branch-or-tag>` suffix on git URLs. → [Add marketplaces](https://code.claude.com/docs/en/discover-plugins#add-marketplaces)

### `/reload-plugins`

Re-read all active plugins from the cache without restarting the session. Picks up edits to skills, commands, agents, MCP servers, LSP servers. Does **not** pick up hook changes — hooks are loaded at session start and require a full restart.

### `/hooks`

Review hooks loaded in the current session. Useful when debugging which hooks fired and which didn't.

### `/mcp`

List all active MCP servers including those provided by plugins. Use after configuring a new server to verify it connected.

### `/agents`

Built-in guided scaffolder for subagents. Use this when you want to author a one-off agent at user/project scope without reaching for `plugin-dev`.

### `/theme`

Theme picker. Plugin-shipped themes appear here alongside built-in presets and the user's local themes. Press **Ctrl+E** on a plugin theme to copy it into `~/.claude/themes/` so you can edit the copy.

### `/doctor`

Surfaces plugin-related health issues including dependency resolution errors, range conflicts, missing tags, and skipped auto-updates with the constraining plugin named.

---

## CLI surface (`claude plugin <subcommand>`)

The interactive `/plugin` UI has a non-interactive equivalent for scripting and automation. All subcommands accept `--scope user|project|local` (`--scope managed` for `update`).

| Command | Purpose |
|---|---|
| `claude plugin install <plugin>[@<mkt>]` | Install. `--scope user` is default |
| `claude plugin uninstall <plugin>[@<mkt>]` | Remove. Aliases: `remove`, `rm`. `--keep-data` preserves `${CLAUDE_PLUGIN_DATA}`. `--prune` cleans orphan deps |
| `claude plugin enable | disable <plugin>[@<mkt>]` | Toggle without uninstalling |
| `claude plugin update <plugin>[@<mkt>]` | Re-fetch from marketplace |
| `claude plugin list [--json] [--available]` | List installed plugins. `--json` exposes structured `errors` field; `--available` adds plugins from marketplaces (requires `--json`) |
| `claude plugin tag [--push] [--dry-run] [-f]` | Create a release tag using the `{name}--v{version}` convention. Run from inside the plugin folder. See [Plugin Dependencies](./05_creating-plugins/07_dependencies.md) |
| `claude plugin prune [--dry-run] [-y]` | Remove auto-installed dependencies no installed plugin requires. Requires Claude Code v2.1.121+. Alias: `autoremove` |
| `claude plugin marketplace add | remove | list | update` | Same operations as the slash commands, scriptable |

→ [CLI commands reference](https://code.claude.com/docs/en/plugins-reference#cli-commands-reference)

---

## Other capability surfaces

These capabilities a plugin can ship are touched on briefly in [Capabilities](./05_creating-plugins/03_capabilities.md#beyond-the-five--other-capability-surfaces) and listed as manifest fields in [Plugin Structure](./05_creating-plugins/02_plugin-structure.md). The links below are the official deep dives.

### LSP servers

Configured via `.lsp.json` at plugin root or `lspServers` in `plugin.json`. Gives Claude **automatic diagnostics after every edit** plus go-to-definition, find-references, and hover via the Language Server Protocol. Required fields: `command`, `extensionToLanguage`. Optional: `args`, `transport`, `env`, `initializationOptions`, `settings`, `workspaceFolder`, `startupTimeout`, `shutdownTimeout`, `restartOnCrash`, `maxRestarts`. The language server binary itself must be installed separately on the user's machine. → [LSP servers (official)](https://code.claude.com/docs/en/plugins-reference#lsp-servers)

### Code-intelligence plugins (pre-built LSPs)

The official marketplace ships LSP plugins for 11 languages: `clangd-lsp`, `csharp-lsp`, `gopls-lsp`, `jdtls-lsp`, `kotlin-lsp`, `lua-lsp`, `php-lsp`, `pyright-lsp`, `rust-analyzer-lsp`, `swift-lsp`, `typescript-lsp`. Install one of these before writing your own `.lsp.json`. Press **Ctrl+O** when the "diagnostics found" indicator appears to view diagnostics inline. → [Code intelligence (official)](https://code.claude.com/docs/en/discover-plugins#code-intelligence)

### Background monitors

Configured via `monitors/monitors.json` (array) or `monitors` in `plugin.json`. Runs a shell command for the lifetime of the session; each stdout line becomes a notification the model sees. Required: `name`, `command`, `description`. Optional: `when` (`"always"` or `"on-skill-invoke:<skill>"` to gate startup on a specific skill being dispatched). Same trust level as hooks (unsandboxed). Doesn't stop mid-session if the plugin is disabled. Requires Claude Code v2.1.105+. → [Monitors (official)](https://code.claude.com/docs/en/plugins-reference#monitors)

### Themes

Configured via `themes/<name>.json`. Each theme is a JSON object with `name`, `base` (built-in preset name), and a sparse `overrides` map of color tokens. Plugin themes are read-only in `/theme`; users can press Ctrl+E to copy one into `~/.claude/themes/` for editing. Selecting a plugin theme persists `custom:<plugin-name>:<slug>` in the user's config. → [Themes (official)](https://code.claude.com/docs/en/plugins-reference#themes)

### Output styles

Configured via `outputStyles` in `plugin.json` (path string or array). Customise how Claude formats responses — example styles in the official marketplace include `explanatory-output-style` (educational annotations on code) and `learning-output-style` (interactive learning mode). → [Output styles category in marketplace](https://code.claude.com/docs/en/discover-plugins#output-styles)

### Channels

Configured via `channels` in `plugin.json`. An array of channel declarations, each binding to an MCP server in the plugin's `mcpServers` and injecting messages into the conversation (Telegram/Slack/Discord style). The required `server` field must match an MCP server key. Each channel can declare its own per-channel `userConfig` for bot tokens, owner IDs, etc. → [Channels (official)](https://code.claude.com/docs/en/plugins-reference#channels)

---

## Manifest fields beyond the basics

### `userConfig`

Object in `plugin.json` declaring values Claude Code prompts the user for when the plugin enables — replaces hand-editing `settings.json`. Keys must be valid identifiers. Each option supports `type` (`string`, `number`, `boolean`, `directory`, `file`), `title`, `description`, `sensitive` (masks input and stores in keychain), `required`, `default`, `multiple` (string-arrays), and `min`/`max` (numbers). Values are substituted as `${user_config.KEY}` in MCP/LSP server configs, hook commands, monitor commands, and (for non-sensitive values) skill and agent content. All values are also exported as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars to subprocesses. Sensitive values go to the OS keychain (~2 KB total cap, shared with OAuth tokens). Non-sensitive values live in `settings.json` under `pluginConfigs[<plugin-id>].options`. The modern alternative to the legacy `.claude/<plugin-name>.local.md` pattern. → [User configuration (official)](https://code.claude.com/docs/en/plugins-reference#user-configuration)

### Plugin-shipped `settings.json`

A `settings.json` file at the plugin root applies default Claude Code settings when the plugin is enabled. Currently only two keys are supported: `agent` (activates one of the plugin's custom agents as the main thread, applying its system prompt, tool restrictions, and model — effectively lets a plugin change Claude Code's identity when enabled) and `subagentStatusLine`. Takes priority over `settings` declared in `plugin.json`. Unknown keys are silently ignored. → [Ship default settings (official)](https://code.claude.com/docs/en/plugins#ship-default-settings-with-your-plugin)

### Component path overrides — replacement vs additive semantics

For `skills`, `commands`, `agents`, `outputStyles`, `themes`, `monitors`: setting a custom path in `plugin.json` **replaces** the default scan. To keep the default *and* add more, you must include both: `"skills": ["./skills/", "./extras/"]`. Hooks, MCP servers, and LSP servers have *additive* semantics — custom paths supplement defaults. → [Path behavior rules (official)](https://code.claude.com/docs/en/plugins-reference#path-behavior-rules)

### `disable-model-invocation` (skill/command frontmatter)

Boolean. Set to `true` to prevent the model from auto-invoking a skill or command — user-invoke only. Useful for utility commands that should only run when explicitly requested. → Used in the official quickstart's `hello` example

---

## Environment and behaviour

### `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}`

Two well-known plugin paths with opposite lifetimes. `${CLAUDE_PLUGIN_ROOT}` is replaced on every plugin update; use it for bundled scripts and config. `${CLAUDE_PLUGIN_DATA}` survives plugin updates; use it for installed dependencies (`node_modules`, Python venvs), generated code, and caches. Both substitute inline in skill/agent content, hook/monitor commands, and MCP/LSP configs, and both are exported as env vars to subprocesses. See [Storage and Scope](./02_storage-and-scope.md#two-plugin-paths-claude_plugin_root-vs-claude_plugin_data). → [Environment variables (official)](https://code.claude.com/docs/en/plugins-reference#environment-variables)

### Auto-update env vars

Marketplaces auto-update at startup by default for official Anthropic marketplaces; third-party and local-development marketplaces have auto-update disabled by default. Toggle per-marketplace in the `/plugin` UI. To globally disable Claude Code auto-updates including plugin updates, set `DISABLE_AUTOUPDATER`. To keep plugin auto-updates while disabling Claude Code core updates, set both `DISABLE_AUTOUPDATER=1` and `FORCE_AUTOUPDATE_PLUGINS=1`. → [Configure auto-updates (official)](https://code.claude.com/docs/en/discover-plugins#configure-auto-updates)

### Path traversal limitation

Plugins cannot reference files outside their own root after install. Paths like `../shared-utils` won't resolve because external files aren't copied into the cache. Bundle everything you need inside the plugin folder.

### Trust model

Plugins run **unsandboxed at the same privilege as your shell**. Only install from sources you trust. Hooks, monitors, and MCP servers can all execute arbitrary code. Organisations can restrict which marketplaces users may add via [managed marketplace restrictions](https://code.claude.com/docs/en/plugin-marketplaces#managed-marketplace-restrictions).

---

## Distribution

### Submission portals (official marketplace)

To submit a plugin to the official Anthropic marketplace, use one of the in-app forms: [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit) or [platform.claude.com/plugins/submit](https://platform.claude.com/plugins/submit). To distribute independently without going through the official marketplace, just [host your own](./04_marketplaces.md).

### `/plugin-hints` — recommend your plugin from your own CLI

If you maintain an external CLI tool that integrates with Claude Code, you can have it prompt Claude Code users to install your plugin. Once your plugin is listed in a marketplace, your CLI can emit hints that Claude Code picks up and surfaces as install suggestions. → [Recommend your plugin from your CLI (official)](https://code.claude.com/docs/en/plugin-hints)

### `extraKnownMarketplaces` (team distribution)

Object in a project's `.claude/settings.json` that pre-populates marketplace suggestions for teammates. When a teammate trusts the repo folder, Claude Code prompts them to add the listed marketplaces and install any plugins listed in `enabledPlugins`. Without this, they'd need to `/plugin marketplace add <url>` manually before the project's plugins can install. The shape mirrors a marketplace `source` entry. → [Configure team marketplaces (official)](https://code.claude.com/docs/en/discover-plugins#configure-team-marketplaces)

---

## Legacy and migration

### `commands/` directory

The flat `commands/<name>.md` layout is the **legacy** way to ship slash commands. The current convention is `skills/<name>/SKILL.md`. Both formats still load identically — the only difference is file layout. New plugins should use the skills layout. The official `plugin-dev` plugin's `command-development` skill is annotated as legacy for this reason.

### `.claude/<plugin-name>.local.md` (per-project plugin settings)

Older pattern for per-project plugin configuration: a YAML-frontmatter + markdown file at `.claude/<plugin-name>.local.md`, gitignored, read by the plugin's hooks/commands/agents at runtime. Superseded by `userConfig` for most cases — `userConfig` integrates with `/plugin`'s enable flow and uses the OS keychain for secrets. The `.local.md` pattern is still useful for stateful per-session data the plugin writes back at runtime. The official `plugin-dev` plugin's `plugin-settings` skill documents this pattern.

---

## See also

- **[Overview](./01_overview.md)** — high-level mental model and the official plugins worth installing
- **[Storage and Scope](./02_storage-and-scope.md)** — cache layout and the two plugin paths
- **[Marketplaces](./04_marketplaces.md)** — full marketplace authoring story
- **[Plugin Dependencies](./05_creating-plugins/07_dependencies.md)** — the dependency system in depth
- Official: [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — full schemas
- Official: [Create plugins](https://code.claude.com/docs/en/plugins) — authoring tutorial
- Official: [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins) — consumer-side
