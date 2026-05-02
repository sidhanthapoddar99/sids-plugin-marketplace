# `marketplace.json` schema reference

Authoritative field reference for `.claude-plugin/marketplace.json`. Cross-checked against the official docs (`code.claude.com/docs/en/plugin-marketplaces`) and the Anthropic-published `claude-plugins-official` marketplace.

## Top-level fields

### Required

| Field | Type | Notes |
|---|---|---|
| `name` | string | Marketplace identifier. Kebab-case, no spaces. Public-facing — users see it as `plugin-name@marketplace-name` |
| `owner` | object | `{ name (required), email (optional) }`. Used for attribution |
| `plugins` | array | Plugin index — see "Plugin entries" below |

### Optional

| Field | Type | Notes |
|---|---|---|
| `$schema` | string | JSON Schema URL for editor autocomplete. Claude Code ignores it at load time |
| `description` | string | Brief marketplace description |
| `version` | string | Marketplace manifest version |
| `metadata.pluginRoot` | string | Base directory for relative-path plugin sources. With `"./plugins"`, `"source": "formatter"` resolves to `./plugins/formatter`. Without it, relative sources must start with `./` and resolve against the marketplace root (the directory containing `.claude-plugin/`) |
| `allowCrossMarketplaceDependenciesOn` | array of strings | Other marketplace names that plugins in *this* marketplace are allowed to depend on. See `referencing.md` |

`description` and `version` are also accepted under `metadata` for backward compatibility.

> **`extraKnownMarketplaces` is NOT a `marketplace.json` field.** It's a key in `.claude/settings.json` (or managed/user settings) used to recommend or auto-register marketplaces for a project or team. See `referencing.md` and `examples/team-recommendations.json`.

### Reserved marketplace names

Names that impersonate official Anthropic marketplaces (e.g. `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `claude-code-plugins`, anything prefixed `anthropic-` or matching the official catalogues) will be rejected if you submit them to the official marketplace registry. The exact list of reserved names isn't formally published — when in doubt, prefix with your org or username (`acme-tools`, `sid-plugins`) and avoid words like `official`, `anthropic`, `claude-code`.

## Plugin entries

Each entry in the `plugins` array describes one plugin. Marketplace entries can also include any field from the [plugin manifest](https://code.claude.com/docs/en/plugins-reference#plugin-manifest-schema) (`hooks`, `mcpServers`, etc.), so a marketplace can fully define a plugin inline (see `strict` below).

### Required

| Field | Type | Notes |
|---|---|---|
| `name` | string | Plugin identifier. Kebab-case. Globally unique within this marketplace |
| `source` | string \| object | Where to fetch the plugin — see "Source types" |

### Standard metadata fields (optional)

| Field | Type | Notes |
|---|---|---|
| `description` | string | Shown in `/plugin install` UI |
| `version` | string | Pin the plugin to this version string. See "Version resolution" |
| `author` | object | `{ name (required), email (optional) }` |
| `homepage` | string | Plugin homepage / docs URL |
| `repository` | string | Source code URL |
| `license` | string | SPDX identifier (`MIT`, `Apache-2.0`, …) |
| `keywords` | array of strings | Discovery / categorization tags |
| `category` | string | Free-form category for UI grouping |
| `tags` | array of strings | Search tags. Distinct from `keywords` by convention; both are supported |
| `strict` | boolean | Default `true`. Controls component-definition authority — see "Strict mode" |

### Component fields (optional, marketplace-defined)

These let a marketplace entry declare components directly, without (or in addition to) a `plugin.json` in the source. Each accepts a string (path to a config file) or an inline object/array.

| Field | Type | Notes |
|---|---|---|
| `skills` | string \| array | Custom paths to skill directories containing `<name>/SKILL.md` |
| `commands` | string \| array | Paths to flat `.md` skill files or directories |
| `agents` | string \| array | Paths to agent files |
| `hooks` | string \| object | Hooks config or path to a hooks file |
| `mcpServers` | string \| object | MCP server configs or path to MCP config |
| `lspServers` | string \| object | LSP server configs or path to LSP config |

See `examples/inline-plugin.json` for a marketplace entry that defines a plugin entirely without a `plugin.json`.

## Source types

Five forms. Object forms always include a `source` discriminator key naming the type.

### 1. Relative path (string)

Local directory inside the marketplace repo. The string must start with `./`. Resolves relative to the marketplace root (the directory containing `.claude-plugin/`), regardless of where `marketplace.json` itself lives.

```json
{ "name": "my-plugin", "source": "./plugins/my-plugin" }
```

If `metadata.pluginRoot` is set, a bare-name source like `"my-plugin"` resolves to `<pluginRoot>/my-plugin`. Without `pluginRoot`, the `./` prefix is required.

> Relative paths only work for marketplaces added via git (GitHub, git URL, local directory). They do **not** work when the marketplace is added via a static URL pointing at `marketplace.json` directly — only the JSON file is downloaded, not the surrounding repo.

### 2. `github`

```json
{
  "source": {
    "source": "github",
    "repo": "owner/plugin-repo",
    "ref": "v2.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `repo` | yes | `owner/repo` form |
| `ref` | no | Branch or tag (default: repo default branch) |
| `sha` | no | Full 40-char commit SHA for exact pinning |

### 3. `url` (git URL)

Any git URL — GitLab, Bitbucket, self-hosted, Azure DevOps, AWS CodeCommit. The `.git` suffix is optional.

```json
{
  "source": {
    "source": "url",
    "url": "https://gitlab.com/team/plugin.git",
    "ref": "main",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `url` | yes | Full git URL (`https://` or `git@`) |
| `ref` | no | Branch or tag |
| `sha` | no | Full commit SHA |

### 4. `git-subdir`

Plugin lives in a subdirectory of a git repo (typical for monorepos). Claude Code does a sparse, partial clone to fetch only that subdirectory.

```json
{
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/acme-corp/monorepo.git",
    "path": "tools/claude-plugin",
    "ref": "v2.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `url` | yes | Git URL, GitHub `owner/repo` shorthand, or SSH URL |
| `path` | yes | Subdirectory containing the plugin |
| `ref` | no | Branch or tag |
| `sha` | no | Full commit SHA |

### 5. `npm`

```json
{
  "source": {
    "source": "npm",
    "package": "@acme/claude-plugin",
    "version": "^2.0.0",
    "registry": "https://npm.example.com"
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `package` | yes | Package name (scoped or unscoped) |
| `version` | no | Version or semver range (`2.1.0`, `^2.0.0`, `~1.5.0`) |
| `registry` | no | Custom registry URL (default: system npm registry) |

## Strict mode

The `strict` field on a plugin entry controls **component-definition authority**, not version pinning.

| Value | Behavior |
|---|---|
| `true` (default) | `plugin.json` is the authority. Marketplace entry can supplement with extra components; both sources merge |
| `false` | Marketplace entry is the entire definition. If the plugin source also has a `plugin.json` declaring components, that's a conflict and the plugin fails to load |

Use `strict: false` when the marketplace operator wants full control over which files are exposed as skills/agents/hooks — typical for catalogues that re-curate someone else's repo.

## Version resolution

Plugin version determines cache identity. If the resolved version matches what a user already has cached, `/plugin update` is a no-op for that plugin.

Resolution order (first hit wins):

1. `version` in the plugin's own `plugin.json`
2. `version` in the marketplace entry
3. The git commit SHA of the plugin's source

> The plugin's `plugin.json` always wins over the marketplace entry. If you set `version` in both, a stale `plugin.json` value silently masks the marketplace pin. Avoid setting it in both places.

For git-based sources (`github`, `url`, `git-subdir`, relative paths in a git-hosted marketplace), omitting `version` entirely means every new commit is treated as a new version. This is the simplest setup for actively-developed plugins.

## Validation

The marketplace JSON gets validated when Claude Code reads it (at `marketplace add` time and at startup). To surface failures:

```bash
# Errors land in the /plugin UI's Errors tab, and in:
claude plugin list --json | jq '.errors'

# At session start, run with debug logging to see validation details:
claude --debug
```

`/doctor` also surfaces marketplace-related issues. There's no dedicated standalone validator command in the canonical CLI (older Claude Code versions referenced `claude plugin validate` in troubleshooting docs; treat its availability as version-dependent).

Common errors the validator catches:

- `File not found: .claude-plugin/marketplace.json`
- `Invalid JSON syntax: …` (missing/extra commas, unquoted strings)
- `Duplicate plugin name "x" found in marketplace`
- `plugins[0].source: Path contains ".."` — relative paths cannot escape the marketplace root
- `YAML frontmatter failed to parse: …` (skill / agent / command file)
- `Invalid JSON syntax: …` in `hooks/hooks.json` — a malformed hooks file blocks the whole plugin from loading

Non-blocking warnings:

- `Marketplace has no plugins defined`
- `No marketplace description provided`
- `Plugin name "x" is not kebab-case` — kebab-case is the convention enforced by the schema; non-kebab names will be rejected
