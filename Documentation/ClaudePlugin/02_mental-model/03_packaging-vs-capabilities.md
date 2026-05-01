# Packaging vs. Capabilities

The plugin is *packaging*; the model only sees the unpacked capabilities. This is more than a metaphor — it has concrete consequences for naming, distribution, and the decision to package something at all.

## Indistinguishability

A skill at:

- `~/.claude/skills/foo/SKILL.md` (hand-authored at user scope)
- `<repo>/.claude/skills/foo/SKILL.md` (hand-authored at project scope)
- `~/.claude/plugins/cache/some-mkt/some-plugin/0.1.0/skills/foo/SKILL.md` (plugin-shipped)

is **identical to the model**. The runtime loads all three through the same pipeline, surfaces the description in the same system reminder, and triggers the body the same way. The model has no way to tell which one it's reading.

The same is true for slash commands, subagents, hooks (modulo the runtime's matcher routing), MCP servers, and `bin/` wrappers. The plugin system does not add new capability *types*; it adds a distribution and lifecycle mechanism around existing capability types.

| Capability type | Hand-authored location | Plugin-shipped location |
|---|---|---|
| Skill | `~/.claude/skills/<name>/SKILL.md` or `<repo>/.claude/skills/<name>/SKILL.md` | `<plugin-cache>/skills/<name>/SKILL.md` |
| Slash command | `~/.claude/commands/<name>.md` or `<repo>/.claude/commands/<name>.md` | `<plugin-cache>/commands/<name>.md` |
| Subagent | `~/.claude/agents/<name>.md` or `<repo>/.claude/agents/<name>.md` | `<plugin-cache>/agents/<name>.md` |
| Hook | declared in `~/.claude/settings.json` or `<repo>/.claude/settings.json` | `<plugin-cache>/hooks/` or inline in `plugin.json` |
| MCP server | `~/.claude/.mcp.json` or `<repo>/.mcp.json` | `<plugin-cache>/.mcp.json` |
| `bin/` wrapper | (no hand-author equivalent — `$PATH` is the user's shell) | `<plugin-cache>/bin/` (auto-PATH'd) |

The lone outlier is `bin/`: there's no built-in equivalent at user/project scope because PATH augmentation is a runtime responsibility tied to plugin enablement. A user can edit their own `$PATH`, but Claude Code doesn't manage that for them.

## What the plugin layer adds

If capabilities are indistinguishable, what does the plugin layer actually contribute?

| Plugin contribution | What it gives you |
|---|---|
| **Distribution** | `/plugin install` instead of "copy these 14 files into your `.claude/`" |
| **Versioning** | Multiple versions can coexist in the cache; semver in `plugin.json` |
| **Updates** | `/plugin update` re-fetches and switches versions |
| **Discovery** | Marketplaces and the `/plugin` Discover tab |
| **Trust** | Trust an author + marketplace combination, not individual files |
| **Persistent data** | `${CLAUDE_PLUGIN_DATA}` survives updates |
| **PATH augmentation** | `bin/` is auto-added (no hand-author equivalent) |
| **Hooks bundling** | Ship a hook with the capabilities it supports, in one unit |
| **MCP server bundling** | Same |

These are all *distribution* problems, not *capability* problems. Plugins solve "how do I get the same skill into 14 projects without copying?", not "how do I write a new kind of capability?"

## When to package as a plugin vs. hand-author

| Situation | Hand-author at user/project scope | Package as a plugin |
|---|---|---|
| One skill, one project | ✅ | overkill |
| Personal command for your own workflow | ✅ | overkill |
| Convention shared across 3+ projects | ⚠️ painful to keep in sync | ✅ |
| Need updates pushed to consumers | ❌ no mechanism | ✅ via `/plugin update` |
| Need discoverability for others | ❌ | ✅ marketplaces |
| Need versioning / multiple versions in cache | ❌ | ✅ |
| Need bundled `bin/` on `$PATH` | ❌ | ✅ |
| Bundling skills + hooks + MCP server together | ⚠️ split across 3 files | ✅ one unit |

The decision usually surfaces the second time you copy the same SKILL.md into a new project. That's the signal to package.

## Implications for naming

Because the model can't tell hand-authored from plugin-shipped, **collisions are real**. If you have:

- A hand-authored project skill: `<repo>/.claude/skills/list/SKILL.md`
- A plugin-shipped skill of the same name: `<plugin>/skills/list/SKILL.md`

…the runtime de-duplicates and the user sees one — but it's not always obvious *which one wins*. Best practice is to prefix everything in your plugin with the plugin's namespace (so `docs-list` rather than `list`).

This is covered in depth in [04_naming-and-namespacing.md](./04_naming-and-namespacing.md).

## Implications for distribution

Because the plugin folder is the distribution unit:

- **You ship the whole plugin or nothing.** There's no way to import a single skill from another plugin into your namespace. Three composition patterns exist: hand-author original, depend on the whole upstream plugin, or soft-fork (vendor + provenance manifest). See [Composition Patterns](../08_composition-patterns/00_index.md).
- **Manifest metadata is per-plugin.** `description`, `version`, `userConfig`, `dependencies`, etc. all apply at plugin granularity, not per-skill.
- **Versioning is per-plugin.** A plugin shipping 5 skills and a hook is one version. You can't release v2 of one skill while keeping v1 of another.

## Implications for hot-swap

The runtime's load timing differs by capability type, and packaging-as-a-plugin doesn't change those timings — it only changes the source folder.

| Capability | Hot-reload via `/reload-plugins` | Requires session restart |
|---|---|---|
| Skill | ✅ | — |
| Slash command | ✅ | — |
| Subagent | ✅ | — |
| MCP server | ✅ (re-read config; subprocess restart depends on impl) | — |
| LSP server | ✅ (similar to MCP) | — |
| Hook | ❌ | ✅ |
| Monitor | ❌ (start once) | ✅ |

The full matrix is in [Hot-swap matrix](../07_lifecycle-and-runtime/03_hot-swap-matrix.md).

## See also

- [01_what-the-model-sees.md](./01_what-the-model-sees.md) — the model's POV
- [02_what-the-runtime-sees.md](./02_what-the-runtime-sees.md) — the runtime's POV
- [04_naming-and-namespacing.md](./04_naming-and-namespacing.md) — collision rules
- [Composition Patterns](../08_composition-patterns/00_index.md) — three patterns for combining plugins
- [Capabilities](../06_capabilities/00_index.md) — depth on each capability type
