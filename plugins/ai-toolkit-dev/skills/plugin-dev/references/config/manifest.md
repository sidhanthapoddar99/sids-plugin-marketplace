# `plugin.json` manifest reference

The plugin manifest at `.claude-plugin/plugin.json` is the single source of truth for what a plugin is. Most fields have sensible defaults; this page lists every field a current plugin can use.

## Minimum

```json
{
  "name": "my-plugin",
  "description": "What the plugin does"
}
```

That's enough to load. Claude Code will auto-discover `commands/`, `agents/`, `skills/`, `hooks/`, `bin/`, and `.mcp.json` if they exist.

## Identity

| Field | Type | Notes |
|---|---|---|
| `name` | string, required | Plugin identifier. Globally unique within a marketplace. Kebab-case |
| `description` | string, required | One-line description shown in `/plugin install` UI |
| `version` | string, optional | SemVer. Bumped per release; resolved via `<plugin-name>--v<version>` upstream tag |
| `author` | object, optional | `{ name, email, url? }`. Falls back to marketplace `owner` if absent |
| `homepage` | string, optional | Project URL — repo, docs, etc. |
| `repository` | string \| object, optional | Source repo URL (string form) or `{ type, url }` |
| `license` | string, optional | SPDX identifier (e.g. `Apache-2.0`, `MIT`) |
| `keywords` | array of strings, optional | Search tags |
| `$schema` | string, optional | JSON Schema URL for editor validation |

## Component path overrides — replacement vs additive

By default, components are auto-discovered at conventional paths. To point Claude Code at non-standard paths, use these fields. Path semantics differ depending on the field:

**Replacement** — setting a custom path **replaces** the default scan. To keep the default *and* add more, you must include both:

```json
{ "skills": ["./skills/", "./extras/"] }
```

Replacement applies to: `skills`, `commands`, `agents`, `outputStyles`, `themes`, `monitors`.

**Additive** — custom paths supplement the default scan. The default is always scanned in addition to whatever you list.

Additive applies to: `hooks`, `mcpServers`, `lspServers`.

| Field | Default discovery | Semantics |
|---|---|---|
| `commands` | `commands/*.md` | replacement |
| `agents` | `agents/*.md` | replacement |
| `skills` | `skills/*/SKILL.md` | replacement |
| `outputStyles` | `outputStyles/*.md` | replacement |
| `themes` | `themes/*.json` | replacement |
| `monitors` | `monitors/monitors.json` | replacement |
| `hooks` | `hooks/hooks.json` | additive |
| `mcpServers` | `.mcp.json` | additive |
| `lspServers` | `.lsp.json` | additive |

Most plugins should leave these unset and use the conventional layout.

## Modern manifest fields

These fields enable newer Claude Code capabilities. None are required.

| Field | Type | Purpose |
|---|---|---|
| `lspServers` | object | Bundle language servers — see [`../topics/lsp-integration/SKILL.md`](../topics/lsp-integration/SKILL.md) |
| `monitors` | array | Long-running watcher processes — see [`../topics/monitor-development/SKILL.md`](../topics/monitor-development/SKILL.md) |
| `themes` | path / array of paths | Color theme bundles — see [`../topics/theme-and-output-style/SKILL.md`](../topics/theme-and-output-style/SKILL.md) |
| `outputStyles` | path / array of paths | Response-formatting styles — see [`../topics/theme-and-output-style/SKILL.md`](../topics/theme-and-output-style/SKILL.md) |
| `channels` | array | Bind MCP servers to messaging surfaces — see [`../topics/channel-development/SKILL.md`](../topics/channel-development/SKILL.md) |
| `userConfig` | object | User-facing plugin settings — see [`user-config.md`](user-config.md) |
| `dependencies` | array | Other plugins this plugin depends on — see [`dependencies.md`](dependencies.md) |
| `settings` | object | Default Claude Code settings the plugin applies when enabled (`agent`, `subagentStatusLine` only). A plugin-shipped root-level `settings.json` takes priority over this field |

## Path conventions

Inside any plugin file, two environment variables are interpolated:

| Variable | Resolves to | Survives plugin updates? |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | The plugin's installed root directory (e.g. `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`) | **No** — replaced on every version bump |
| `${CLAUDE_PLUGIN_DATA}` | The plugin's persistent data directory (e.g. `~/.claude/plugins/data/<plugin>/`) | **Yes** — survives updates |

Use `${CLAUDE_PLUGIN_ROOT}` for paths to bundled assets, scripts, or config that ship with the plugin (read-only at runtime). Use `${CLAUDE_PLUGIN_DATA}` for state that must persist: caches, learned models, user-modified data, dependency installs.

See `persistent-data.md` for design patterns and `development-cycle/lifecycle-and-storage.md` for the path resolution rules.

## Common mistakes

- **Hard-coding `~/.claude/plugins/...`** in scripts. Always use the env vars; the cache layout is internal and may change.
- **Putting state in `${CLAUDE_PLUGIN_ROOT}`.** It's wiped on update. Anything the user might modify or that takes time to compute belongs in `${CLAUDE_PLUGIN_DATA}`.
- **Setting `version` without tagging.** A `version` field doesn't auto-create a tag. Run `claude plugin tag` (see `development-cycle/release.md`).
- **Conflating `name` collisions.** A plugin named `foo` in marketplace A and another named `foo` in marketplace B are two different plugins. They can both be installed; Claude Code disambiguates by marketplace.

## Validation

`plugin.json` is validated against a JSON schema at install time. If the schema URL is referenced via `$schema`, editors will validate live. Common validation failures:

- Missing required `name` or `description`
- `version` not a valid SemVer string
- Unknown top-level field (rejected — schema is closed)
- `dependencies` entry missing required `name`

See `development-cycle/lifecycle-and-storage.md` for what happens at load time when validation fails.
