# Activation and loading

Once `enabledPlugins[<plugin>] = true` is set and Claude Code re-scans, the plugin's components are loaded into the session. This page covers what loads, in what order, and which loads can be re-done without a session restart.

## What gets loaded

For each enabled plugin, the runtime registers components in roughly the following order. Some components can be loaded only at session start; others can be hot-loaded on `/reload-plugins`.

| Component | Source | Loaded at session start? | Reloadable? |
|---|---|---|---|
| **Skills** | `skills/<name>/SKILL.md` | Yes | Yes — `/reload-plugins` re-reads them |
| **Slash commands** | `commands/<name>.md` (legacy) or `skills/<name>/SKILL.md` | Yes | Yes |
| **Subagents** | `agents/<name>.md` | Yes | Yes |
| **MCP servers** | `.mcp.json` or `mcpServers` in `plugin.json` | Yes — subprocess spawned | Yes — subprocess restarted on reload |
| **LSP servers** | `.lsp.json` or `lspServers` in `plugin.json` | Yes — subprocess spawned | Yes |
| **Hooks** | `hooks/hooks.json` or `hooks` in `plugin.json` | **Yes — only at session start** | **No — full restart required** |
| **Background monitors** | `monitors/monitors.json` or `monitors` in `plugin.json` | Yes — subprocess spawned for the session | Yes — subprocess restarted on reload |
| **Themes** | `themes/<name>.json` | Yes — appear in `/theme` picker | Yes |
| **Output styles** | `outputStyles/` or `outputStyles` in `plugin.json` | Yes | Yes |
| **Channels** | `channels` in `plugin.json` | Yes — subprocess spawned | Yes |
| **Bin scripts** | `bin/<name>` | Yes — added to `$PATH` | Yes |
| **Plugin-shipped `settings.json`** | Plugin root `settings.json` (`agent`, `subagentStatusLine`) | Yes — applied as defaults | Yes |

Hooks are the consistent exception. Everything else is hot-swappable; hooks require a session restart to pick up changes.

## Order of loading

Within a single plugin:

1. **`plugin.json` schema validation.** If invalid, the plugin is skipped and listed in the `/plugin` Errors tab. See [`06_schema-validation.md`](./06_schema-validation.md).
2. **`userConfig` resolution.** If the plugin declares `userConfig` and required values are missing, the user is prompted (interactive) or the plugin fails to enable (non-interactive). Resolved values are exposed as `${user_config.KEY}` and `CLAUDE_PLUGIN_OPTION_<KEY>`.
3. **Static registrations.** Skills, commands, agents, themes, output styles register synchronously.
4. **`bin/`.** Wrappers added to `$PATH`.
5. **MCP / LSP / monitor / channel subprocesses.** Spawned. If `command` substitution depends on `${user_config.KEY}`, that's resolved here.
6. **Hooks.** Loaded into the runtime's hook dispatcher (only at session start).

Across multiple plugins, the order between plugins is not part of the public contract. Plugin authors should not depend on another plugin's components being loaded first — except via explicit `dependencies[]` declarations, which are resolved in dependency-graph order.

## What "loaded" means per component

### Skills, commands, agents

The frontmatter and body are parsed once and held in memory. The model sees the `description` (and tool list, for agents) in its skill/command/agent inventory and can dispatch based on that. The body is rendered with env-var substitution applied when the skill is invoked, not at load time.

### MCP / LSP servers

A subprocess is spawned via the `command` and `args` declared in the config. Stdio (or the configured transport) connects to the runtime. The MCP server's tool list is fetched and added to the model's available tools. LSP servers are queried for diagnostics whenever the model edits a file in a matching language.

### Hooks

The runtime indexes the hook configuration into a dispatch table keyed by event (`PreToolUse`, `PostToolUse`, `SessionStart`, etc.). When the event fires, matching hooks run as subprocesses. Because the hook config is built into the dispatcher at session start, edits don't take effect until restart.

### Bin wrappers

Each file in `bin/` is symlinked or added to `$PATH` for the duration of the session. The model can invoke them via `Bash` calls; the user can use them in their own shell while the session is running. After the session ends, the `$PATH` modification is gone.

### Plugin-shipped `settings.json`

Currently supports two keys: `agent` (sets the active subagent for the main thread, effectively letting a plugin change Claude Code's identity when enabled) and `subagentStatusLine`. Takes priority over `settings` declared inside `plugin.json`. Unknown keys are silently ignored.

## Activation gating

Some components support gated activation:

- **Monitors** with `when: "on-skill-invoke:<skill>"` only spawn when that skill is dispatched, not at session start.
- **`disable-model-invocation: true`** in skill/command frontmatter prevents the model from auto-invoking — the user must explicitly trigger.

Otherwise, activation is binary: enabled means loaded for the session.

## SessionStart hook idiom

Many plugins use a `SessionStart` hook to run setup work (see [`02_data-dir.md`](../03_storage-and-scope/02_data-dir.md) — diff requirements, install deps if needed). Because hooks are only loaded at session start, this is the idiomatic place for "run once when this session begins" logic. Users who toggle the plugin on mid-session must restart to pick up the hook.

## See also

- [`03_hot-swap-matrix.md`](./03_hot-swap-matrix.md) — the per-component reload behaviour table
- [`07_multi-plugin-merging.md`](./07_multi-plugin-merging.md) — how multiple enabled plugins compose
- [`../06_capabilities/`](../06_capabilities/00_index.md) — what each component type does once loaded
- [`../03_storage-and-scope/05_env-vars.md`](../03_storage-and-scope/05_env-vars.md) — `userConfig` substitution at load time
