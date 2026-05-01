# Overview — The Three-Layer Architecture

A Claude Code plugin is *packaging*. The model never reasons about "the plugin"; it reasons about the unpacked capabilities the plugin happens to ship. Three distinct layers participate in plugin behaviour, and each sees a different slice of the system.

## The three layers

| Layer | What it is | Sees plugins as units? | Sees individual capabilities? |
|---|---|---|---|
| **Model** (Claude itself) | The LLM running in the session | No | Yes — skills, commands, subagents, MCP tools, bin scripts on `$PATH` |
| **Runtime** (Claude Code) | The CLI/host process | Yes — for install, enable/disable, update, GC | Yes — loads them, fires hooks, augments `$PATH`, validates schemas |
| **Packaging** (the plugin) | A folder with a manifest and capability sub-folders | Yes — *is* the unit | N/A — packaging is structural |

The split is load-bearing. Hand-authored skills at user scope (`~/.claude/skills/<name>/SKILL.md`) and plugin-shipped skills are indistinguishable to the model. The plugin system doesn't add new capability types — it makes those capabilities easier to distribute, version, and update.

## Layer responsibilities

### Model layer

- Reads skill descriptions (~50–100 words each) from a system reminder loaded into every session
- Reads slash command metadata in the available-commands list
- Reads subagent metadata in the available-agents list
- Sees MCP tools as `mcp__<server>__<tool>` in its tool list
- Calls `bin/` wrappers via the `Bash` tool, same as any system command
- **Never sees hooks** — hooks fire in the runtime, not in model context

The model decides *when* to use a capability. For skills and slash commands, that decision is description-driven: the model matches user intent against the description and triggers (or doesn't). The body of the skill or command is only loaded after triggering.

### Runtime layer

The runtime is what Claude Code itself does at session start and during the session:

- **Cache scan**: read `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` for every installed plugin
- **Scope union**: read `enabledPlugins` from Managed, Local, Project, and User `settings.json` files; compute the union; load each enabled plugin once
- **PATH augmentation**: prepend every enabled plugin's `bin/` to `$PATH`
- **Hook registration**: parse `hooks.json` (or inline `hooks` in `plugin.json`) and wire matchers to lifecycle events
- **MCP server startup**: spawn each registered server as a subprocess, reading `.mcp.json`
- **LSP server startup**: same, for `.lsp.json` and code-intelligence diagnostics
- **Monitor startup**: spawn long-running shell commands declared in `monitors/`
- **Schema validation**: validate `plugin.json` and `marketplace.json` against the bundled schemas; surface errors via `/plugin` Errors tab and `/doctor`
- **Updates and GC**: re-fetch on `/plugin update`, garbage-collect old version directories after 7 days
- **UI**: present `/plugin`'s tabbed Discover / Installed / Marketplaces / Errors interface

The runtime is also what enforces the plugin's `allowed-tools` lists, hook matchers, and other configuration that lives in the plugin's metadata.

### Packaging layer

The plugin is a folder shaped like:

```
my-plugin/
├── .claude-plugin/plugin.json    # manifest (optional if no overrides)
├── README.md                      # shown in /plugin UI
├── LICENSE
├── skills/<name>/SKILL.md
├── commands/<name>.md
├── agents/<name>.md
├── hooks/                         # or inline in plugin.json
├── .mcp.json
├── .lsp.json
├── monitors/monitors.json
├── themes/<name>.json
└── bin/<name>                     # auto-added to $PATH
```

The plugin layer is the only layer that ships, versions, and travels through marketplaces. It is the *unit of distribution*.

## Flow: from `/plugin install` to "the model sees a skill"

```
USER ──► /plugin install foo@bar
            │
            ▼
RUNTIME ──► fetch from marketplace (git/url/npm/path)
            ──► copy to ~/.claude/plugins/cache/bar/foo/<version>/
            ──► write enabledPlugins["foo@bar"] = true to scope's settings.json
            │
            ▼
USER ──► (next session, or /reload-plugins)
            │
            ▼
RUNTIME ──► scope union → foo@bar is enabled
            ──► validate plugin.json schema
            ──► add cache/.../bin/ to $PATH
            ──► register hooks, start MCP/LSP/monitors
            ──► load skill descriptions, command metadata, subagent metadata
            │
            ▼
MODEL ───► sees: skill descriptions in system reminder
                 commands in available-commands list
                 subagents in available-agents list
                 mcp__<server>__<tool> entries in tool list
                 PATH-resolvable bin wrappers
            ───► (does not see) hooks, the plugin folder, the manifest
```

The path from user action to model context is always: user → runtime → cache → load → unpack → present. The plugin folder never crosses into model context as a unit; only its unpacked capabilities do.

## What's *not* a layer

A few things commonly confused for layers:

- **Marketplaces** are not a runtime layer. They are a *source* the runtime fetches plugin folders from. Once a plugin is in the cache, the marketplace is metadata only (used by `/plugin update` to re-fetch).
- **Scopes** (Managed/User/Project/Local) are not a layer either. They are *where the `enabledPlugins` boolean lives*. The cache and the runtime are both scope-agnostic.
- **`${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}`** are runtime-substituted template variables, not layers. They give the plugin's code addresses to the cache (versioned, replaced on update) and persistent data dir (survives updates) respectively.

## See also

- [Mental Model](./02_mental-model/00_index.md) — deeper on each layer's POV
- [Storage and Scope](./03_storage-and-scope/00_index.md) — where plugin files live and the scope union mechanism
- [Plugin Anatomy](./05_plugin-anatomy/00_index.md) — what's actually in a plugin folder
- [Capabilities](./06_capabilities/00_index.md) — the unpacked behaviours the model sees
- [Lifecycle and Runtime](./07_lifecycle-and-runtime/00_index.md) — install / activation / update / GC mechanics
