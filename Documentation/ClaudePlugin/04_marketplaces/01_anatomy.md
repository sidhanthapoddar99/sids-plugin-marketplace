# Marketplace anatomy

Every marketplace is one file: `.claude-plugin/marketplace.json`. It declares the marketplace's identity and lists the plugins it catalogues.

## Minimal example

```json
{
  "name": "my-marketplace",
  "owner": { "name": "Your Name" },
  "plugins": [
    {
      "name": "plugin-a",
      "source": "./plugins/plugin-a",
      "description": "One-line description shown in /plugin"
    }
  ]
}
```

The standard repo layout puts the manifest at the root and the plugin folders next to it:

```
my-marketplace/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    ├── plugin-a/
    │   └── .claude-plugin/plugin.json
    └── plugin-b/
        └── .claude-plugin/plugin.json
```

Plugins listed by Git URL (rather than relative path) can live in entirely separate repos.

## Top-level fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Marketplace identifier. Kebab-case, no spaces. Public-facing — consumers reference plugins as `<plugin>@<marketplace>` |
| `owner` | yes | Object: `{ name (required), email (optional) }`. Display attribution |
| `plugins` | yes | Array of plugin entries |
| `$schema` | optional | JSON Schema URL for editor autocomplete; ignored at load time |
| `description` | optional | Marketplace-level description |
| `version` | optional | Marketplace manifest version (the marketplace itself, not its plugins) |
| `allowCrossMarketplaceDependenciesOn` | optional | Array of marketplace names whose plugins this marketplace's plugins are allowed to depend on. See [`08_cross-marketplace-deps.md`](./08_cross-marketplace-deps.md) |

`description` and `version` are also accepted under a `metadata` object for backward compatibility.

## Reserved marketplace names

These names are reserved for Anthropic and rejected by Claude.ai's marketplace sync: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `knowledge-work-plugins`, `life-sciences`. Names that impersonate official ones (like `official-claude-plugins` or `anthropic-tools-v2`) are also blocked.

## Plugin-entry fields

Each entry in `plugins` describes one plugin and where to fetch it. A marketplace entry can also include **any field from the plugin manifest schema** (`hooks`, `mcpServers`, `commands`, etc.) — those values supplement or override the plugin's own `plugin.json`.

### Required

| Field | Notes |
|---|---|
| `name` | Plugin identifier. Must match the `name` in the plugin's own `plugin.json` |
| `source` | Where to fetch the plugin from. Five forms — see [`02_source-types.md`](./02_source-types.md) |

### Standard metadata (optional)

| Field | Notes |
|---|---|
| `description` | Shown in the `/plugin` browser. Keep information-dense |
| `version` | Pin the plugin to this version string. See [`09_versioning-and-publishing/03_version-resolution.md`](../09_versioning-and-publishing/03_version-resolution.md) |
| `author` | Object: `{ name (required), email (optional) }` |
| `homepage` | Plugin homepage / docs URL |
| `repository` | Source code URL |
| `license` | SPDX identifier (`MIT`, `Apache-2.0`, …) |
| `category` | Free-form group (e.g. `"security"`, `"development"`). Used by the `/plugin` Discover tab for grouping |
| `tags` | Array of search hints |
| `keywords` | Discovery / categorization tags. Distinct from `tags` by convention; both supported |
| `strict` | Default `true`. See "Strict mode" below |
| `dependencies` | Override the plugin's own `dependencies` array. See [`08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) |

### Inline-component fields (optional)

A marketplace entry can declare components directly, without (or in addition to) a `plugin.json` in the source:

| Field | Type |
|---|---|
| `skills` | string \| array — paths to skill directories |
| `commands` | string \| array — paths to flat `.md` skill files or directories |
| `agents` | string \| array — paths to agent files |
| `hooks` | string \| object — hooks config or path |
| `mcpServers` | string \| object — MCP configs or path |
| `lspServers` | string \| object — LSP configs or path |

This lets a marketplace fully define a plugin inline, useful when the underlying source is a generic git repo with no `plugin.json` of its own.

## Strict mode

`strict` controls **component-definition authority**, not version pinning.

| Value | Behaviour |
|---|---|
| `true` (default) | `plugin.json` is the authority. Marketplace entry can supplement with extra components; both sources merge |
| `false` | Marketplace entry is the entire definition. If the plugin source also has a `plugin.json` declaring components, that's a conflict and the plugin fails to load |

Use `strict: false` when the marketplace wants full control over which files in a generic repo are exposed as skills/agents/hooks.

## See also

- [`02_source-types.md`](./02_source-types.md) — full source schemas
- [`05_catalogue-pattern.md`](./05_catalogue-pattern.md) — marketplaces that don't ship their own plugins
- [`05_plugin-anatomy/`](../05_plugin-anatomy/) — `plugin.json` schema (the manifest each entry references)
