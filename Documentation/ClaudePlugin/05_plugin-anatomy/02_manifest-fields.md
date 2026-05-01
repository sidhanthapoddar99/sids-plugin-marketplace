# Manifest fields

Exhaustive reference for `.claude-plugin/plugin.json`. Fields are grouped by purpose. Every field is optional except `name`; in practice `description` is also expected for any plugin published to a marketplace.

## Minimum viable manifest

```json
{
  "name": "my-plugin",
  "description": "What the plugin does"
}
```

That's enough to load. Claude Code will auto-discover all conventional folders. The manifest can be omitted entirely (see [`01_directory-layout.md`](./01_directory-layout.md)) but for anything published to a marketplace ship at least these two fields.

## Identity and metadata

| Field | Type | Notes |
|---|---|---|
| `name` | string, **required** | Plugin identifier. Globally unique within a marketplace. Kebab-case `[a-z][a-z0-9-]*`. 3–64 characters, no leading/trailing/consecutive dashes |
| `description` | string, recommended | One-paragraph TL;DR shown in `/plugin install` UI. Also helpful when the model reasons about which plugin's tools/skills to use. Keep it information-dense |
| `version` | string, optional | SemVer (`MAJOR.MINOR.PATCH`). Falls back to git commit SHA if omitted (every commit becomes a new version). Resolved via the `<plugin-name>--v<version>` tag convention. See [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) |
| `author` | object, optional | `{ name, email?, url? }`. Falls back to marketplace `owner` if absent |
| `homepage` | string, optional | URL — typically the repo or a docs site |
| `repository` | string \| object, optional | Source repo URL (string form) or `{ type, url }` |
| `license` | string, optional | SPDX identifier (`Apache-2.0`, `MIT`, etc.) |
| `keywords` | array of strings, optional | Search hints for the marketplace browser |
| `$schema` | string, optional | JSON Schema URL for editor autocomplete. Ignored at load time |

## Component path overrides

Each of these fields *replaces or supplements* the auto-discovered default scan path. Replacement vs additive semantics differ by field — see [`03_path-replacement-vs-additive.md`](./03_path-replacement-vs-additive.md) for the rule.

| Field | Type | Default scanned | Semantics | Purpose |
|---|---|---|---|---|
| `skills` | string \| array | `skills/*/SKILL.md` | replacement | Skill folder roots |
| `commands` | string \| array | `commands/*.md` | replacement | Slash command files (legacy layout) |
| `agents` | string \| array | `agents/*.md` | replacement | Subagent files |
| `outputStyles` | string \| array | `outputStyles/*.md` | replacement | Response-formatting style files |
| `themes` | string \| array | `themes/*.json` | replacement | Color theme JSON files |
| `monitors` | string \| array | `monitors/monitors.json` | replacement | Background watcher configs |
| `hooks` | string \| array \| object | `hooks/hooks.json` | additive | Hook config paths or inline config |
| `mcpServers` | string \| array \| object | `.mcp.json` | additive | MCP server configs or inline |
| `lspServers` | string \| array \| object | `.lsp.json` | additive | LSP server configs or inline |
| `channels` | array | `channels/*.json` | n/a (declarative) | Channel declarations bound to MCP servers |

Inline config example (avoids a separate `.mcp.json`):

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/mcp-server.js"]
    }
  }
}
```

Path-array example for replacement fields (keeps the default *and* adds more):

```json
{ "skills": ["./skills/", "./extras/"] }
```

## User-facing configuration

| Field | Type | Notes |
|---|---|---|
| `userConfig` | object | Values Claude Code prompts the user for when the plugin enables. Custom shape — *not* JSON Schema. See [`04_user-config.md`](./04_user-config.md) |

## Composition

| Field | Type | Notes |
|---|---|---|
| `dependencies` | array | Other plugins this plugin requires. Bare strings or `{ name, version?, marketplace? }` objects. See [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) |

There is no manifest field for soft-forking — the soft-fork pattern uses an `.upstream/manifest.json` file outside the plugin manifest, by convention only. See [`../08_composition-patterns/03_soft-fork.md`](../08_composition-patterns/03_soft-fork.md).

## Defaults

| Field | Type | Notes |
|---|---|---|
| `settings` | object | Default Claude Code settings the plugin applies when enabled. Currently only `agent` and `subagentStatusLine` recognised. Unknown keys silently ignored. A plugin-shipped root-level `settings.json` takes priority over this field. See [`05_plugin-shipped-settings.md`](./05_plugin-shipped-settings.md) |

## Worked example

A real manifest from a multi-skill plugin (`ai-toolkit-dev`):

```json
{
  "name": "ai-toolkit-dev",
  "description": "Toolkit for authoring Claude Code plugins, marketplaces, and skills",
  "author": {
    "name": "Sid",
    "email": "developer@neuralabs.org"
  },
  "skills": [
    "./skills/marketplace/",
    "./skills/plugin-dev/",
    "./skills/skill-creator/"
  ]
}
```

Note: explicit `skills` array (replacement semantics) — the plugin's authors chose to be explicit about which skill folders ship rather than rely on auto-discovery. No `version` field, so Claude Code uses the git commit SHA as the version.

A heavier example with most fields populated:

```json
{
  "name": "deploy-kit",
  "version": "3.1.0",
  "description": "Templated deployment workflows with audit logging",
  "author": { "name": "Acme Corp", "email": "support@acme.com" },
  "homepage": "https://github.com/acme/deploy-kit",
  "repository": "https://github.com/acme/deploy-kit",
  "license": "Apache-2.0",
  "keywords": ["deploy", "ci", "audit"],
  "skills": ["./skills/", "./extras/"],
  "userConfig": {
    "auditEndpoint": {
      "type": "string",
      "title": "Audit log endpoint",
      "required": true
    }
  },
  "dependencies": [
    "audit-logger",
    { "name": "secrets-vault", "version": "~2.1.0" }
  ],
  "settings": {
    "subagentStatusLine": "deploy-kit ▸ {agent}"
  }
}
```

## Validation

`plugin.json` is validated at install time. Common failures:

| Failure | Cause |
|---|---|
| Missing `name` | The only strictly required field |
| `version` not valid SemVer | Use `MAJOR.MINOR.PATCH` |
| Unknown top-level field | Schema is closed; typos in field names are rejected |
| `dependencies` entry missing `name` | Bare string or object with `name` required |
| Duplicate skill / agent / command names | Within the plugin |

Editor validation is available by setting `$schema` to the published JSON Schema URL — the schema reference is purely for IDEs; load-time validation runs against the in-process schema regardless.

## See also

- [`01_directory-layout.md`](./01_directory-layout.md) — folder shape and conventional paths
- [`03_path-replacement-vs-additive.md`](./03_path-replacement-vs-additive.md) — replacement vs additive semantics in detail
- [`04_user-config.md`](./04_user-config.md) — `userConfig` shape and substitution
- [`05_plugin-shipped-settings.md`](./05_plugin-shipped-settings.md) — root-level `settings.json` (separate from `settings` field)
- [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — `dependencies` in depth
- [`../15_reference/00_index.md`](../15_reference/00_index.md) — settings keys, env vars, frontmatter flags
