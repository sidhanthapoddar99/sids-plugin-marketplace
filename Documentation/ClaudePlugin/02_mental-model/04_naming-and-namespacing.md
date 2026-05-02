# Naming and Namespacing

Names matter for collision avoidance. The plugin system uses three different name forms in three different contexts, and getting them confused leads to install errors and unexpected resolution.

## The three name forms

| Form | Where it appears | Example |
|---|---|---|
| **Plugin identifier** | `enabledPlugins`, `/plugin install` arg, marketplace `dependencies` | `documentation-guide@documentation-template` |
| **Plugin install ID** | Filesystem-safe form for cache and data dir paths | `documentation-guide-documentation-template` |
| **Skill display name** | The skill name the model sees in its system reminder | `documentation-guide:documentation-guide` |

All three derive from the same source — the plugin's `name` in `plugin.json` plus the marketplace's `name` in `marketplace.json` — but they're applied at different layers.

### Plugin identifier — `<plugin>@<marketplace>`

The `@<marketplace>` suffix disambiguates plugins with the same `name` from different marketplaces. A user could have:

- `formatter@team-tools` (from `team-tools` marketplace)
- `formatter@public-tools` (from `public-tools` marketplace)

…both installed simultaneously without collision. The runtime tracks them as distinct units. `enabledPlugins` keys carry the full identifier:

```json
{
  "enabledPlugins": {
    "formatter@team-tools": true,
    "formatter@public-tools": true
  }
}
```

### Plugin install ID — for filesystem paths

For paths that must be filesystem-safe, the runtime derives an install ID by replacing all non-`[a-zA-Z0-9_-]` characters with `-`. So `formatter@team-tools` becomes `formatter-team-tools` when used as the data-dir path:

```
~/.claude/plugins/data/formatter-team-tools/      ← ${CLAUDE_PLUGIN_DATA}
```

This same install ID is used in `pluginConfigs[<plugin-id>].options` in `settings.json` for non-sensitive `userConfig` values.

### Skill display name — `<plugin>:<skill>`

For skills shipped by plugins, the model sees the skill name prefixed with the plugin's namespace using a `:` separator. The official `documentation-guide` plugin's `documentation-guide` skill appears to the model as:

```
documentation-guide:documentation-guide
```

The prefix is purely for collision avoidance — the model treats the prefix as part of the name, not as a structural relationship.

Hand-authored skills at user/project scope appear without a prefix (just `<skill-name>`), since they have no plugin namespace.

## Collision rules

### Skill / command / subagent name collisions

The runtime handles same-name capabilities from multiple sources by de-duplicating, but **which one wins is not always obvious**. Sources are roughly:

1. Plugin-shipped (under `~/.claude/plugins/cache/.../skills/<name>/`)
2. User-scope hand-authored (`~/.claude/skills/<name>/`)
3. Project-scope hand-authored (`<repo>/.claude/skills/<name>/`)

If a hand-authored project skill and a plugin-shipped skill have the same name, the user sees one — but the resolution order isn't guaranteed across Claude Code releases. **Best practice: prefix everything in your plugin with the plugin's namespace.** Use `docs-list` rather than `list`, `docs-init` rather than `init`.

The runtime adds the `<plugin>:<skill>` display prefix automatically for plugin-shipped skills, which mostly avoids in-plugin collisions. The risk is between *plugin-shipped* and *hand-authored* names, where only the hand-authored side lacks a prefix.

### `bin/` wrapper collisions

Every enabled plugin's `bin/` is prepended to `$PATH`. If two plugins both ship a `bin/format`, the resolution is **PATH order** — first plugin wins. PATH order is not guaranteed across plugins, so:

- **Always prefix `bin/` wrapper names with your plugin's namespace.** Use `docs-list`, `docs-show`, etc., never bare `list`, `show`.
- **Don't shadow common system commands.** A `bin/git` wrapper would shadow the system `git`. Don't do that.

### MCP server name collisions

In `.mcp.json`, server names are keys in the `mcpServers` object. Plugin-shipped tools are namespaced by the plugin: the model sees them as `mcp__plugin_<plugin-name>_<server-name>__<tool-name>`. The `plugin_<plugin>_` infix means two plugins can each ship a server named `puppeteer` without their tools colliding — they appear as `mcp__plugin_a-tools_puppeteer__click` and `mcp__plugin_b-tools_puppeteer__click`.

Non-plugin MCP servers (configured by the user directly in `~/.claude/settings.json` or a project `.mcp.json` outside any plugin) lack the infix and appear as `mcp__<server>__<tool>`. A plugin server and a user server with matching names won't share a tool namespace.

Practical guidance:

- **Prefix MCP server names within your plugin** for clarity even though the plugin infix already prevents tool collisions — server names show up in `/mcp` listings and debug output.
- **For widely-used MCP servers** (e.g. `@modelcontextprotocol/server-puppeteer`), expect users to install them via a single dedicated plugin, not bundled into multiple.

### LSP server collisions

LSPs are keyed by `extensionToLanguage` mapping. Two plugins both registering an LSP for `.py` files compete; resolution behaviour matches MCP's.

### Theme name collisions

Themes appear in `/theme` keyed as `custom:<plugin-name>:<slug>` — the plugin namespace is part of the persisted identifier, so collisions are inherently namespaced.

### Marketplace name collisions

Two marketplaces can't share a `name` in the same Claude Code install (the runtime keys marketplaces by `name`). If you `add` a second marketplace with the same `name`, the runtime errors. Choose unique marketplace names.

## Plugin-prefix conventions

| Surface | Convention | Example |
|---|---|---|
| Plugin name | kebab-case, descriptive of the domain | `documentation-guide`, `claude-md-management` |
| Skill name | Often duplicates the plugin name when there's one primary skill | `documentation-guide:documentation-guide` |
| Multi-skill plugin: skill names | Prefix with plugin domain | `docs-edit`, `docs-issue`, `docs-blog` |
| Slash command name | Prefix with plugin domain | `/docs-init`, `/docs-add-section` |
| Subagent name | Prefix with plugin domain or descriptive role | `docs-reviewer`, `security-reviewer` |
| `bin/` wrapper name | Prefix with plugin domain | `docs-list`, `docs-show`, `docs-issue` |
| MCP server name (in `.mcp.json`) | Prefix with plugin domain if not a widely-known server | `docs-mcp`, `mytool-server` |
| Theme name | Plugin namespace handled by runtime; the slug is yours | `dark-prose`, `solarized-soft` |

The general rule: anywhere a name from your plugin lands in a global namespace (`$PATH`, the model's tool list, the model's skill list), prefix it.

## What names look like end-to-end

Take the `documentation-guide` plugin in the `documentation-template` marketplace. The user installs it:

```
/plugin install documentation-guide@documentation-template
```

The runtime then:

| Layer | Form |
|---|---|
| `enabledPlugins` key | `documentation-guide@documentation-template` |
| Cache path | `~/.claude/plugins/cache/documentation-template/documentation-guide/0.1.1/` |
| Data dir path | `~/.claude/plugins/data/documentation-guide-documentation-template/` |
| Skill display name (model sees) | `documentation-guide:documentation-guide` |
| Bin wrappers on `$PATH` | `docs-list`, `docs-show`, `docs-issue`, … |

Five different forms of the same identity, each appropriate to its layer.

## See also

- [01_what-the-model-sees.md](./01_what-the-model-sees.md) — what the prefixes look like in context
- [02_what-the-runtime-sees.md](./02_what-the-runtime-sees.md) — how the runtime tracks plugin identity
- [03_packaging-vs-capabilities.md](./03_packaging-vs-capabilities.md) — why hand-authored vs. plugin-shipped collisions happen
- [Storage and Scope](../03_storage-and-scope/00_index.md) — install ID derivation in the cache
- [Marketplaces](../04_marketplaces/00_index.md) — marketplace naming
