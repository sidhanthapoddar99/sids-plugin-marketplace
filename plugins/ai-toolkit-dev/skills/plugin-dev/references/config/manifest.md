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
| `name` | string, required | Plugin identifier. Globally unique within a marketplace. Kebab-case. **The only strictly required field** — every other field is optional |
| `description` | string, optional | One-line description shown in `/plugin install` UI. Strongly recommended |
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
| `settings` | object | Default Claude Code settings the plugin applies when enabled (`agent`, `subagentStatusLine` only). A plugin-shipped root-level `settings.json` file takes priority over this field — see "Plugin-shipped settings.json" below |

## Path conventions

Inside any plugin file, two environment variables are interpolated:

| Variable | Resolves to | Survives plugin updates? |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | The plugin's installed root directory (e.g. `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`) | **No** — replaced on every version bump |
| `${CLAUDE_PLUGIN_DATA}` | The plugin's persistent data directory (e.g. `~/.claude/plugins/data/<plugin>/`) | **Yes** — survives updates |

Use `${CLAUDE_PLUGIN_ROOT}` for paths to bundled assets, scripts, or config that ship with the plugin (read-only at runtime). Use `${CLAUDE_PLUGIN_DATA}` for state that must persist: caches, learned models, user-modified data, dependency installs.

See `persistent-data.md` for design patterns and `development-cycle/lifecycle-and-storage.md` for the path resolution rules.

## Plugin-shipped `settings.json`

A `settings.json` file at the **plugin root** (alongside `.claude-plugin/`, *not* inside it) supplies default Claude Code settings that apply when the plugin is enabled. Two keys are honoured:

| Key | Effect |
|---|---|
| `agent` | Activates one of the plugin's `agents/<name>.md` agents as the **main thread** for the session. The agent's system prompt, tool restrictions, and model become Claude Code's identity while this plugin is enabled |
| `subagentStatusLine` | Configures the status line shown when a subagent is running. Same shape as the user-side [`subagentStatusLine`](https://code.claude.com/docs/en/statusline#subagent-status-lines) settings key |

**Other keys are silently ignored.** A plugin cannot ship default values for the user's main `statusLine`, `permissions`, `keybindings`, `model`, `theme`, `env`, or `hooks` — those belong to the user. The two keys above are the entire plugin-shippable settings surface.

### Worked example

```
my-plugin/
├── .claude-plugin/plugin.json
├── settings.json                  ← plugin-shipped defaults
├── agents/
│   └── security-reviewer.md
└── skills/
    └── ...
```

`my-plugin/settings.json`:

```json
{
  "agent": "security-reviewer",
  "subagentStatusLine": {
    "type": "command",
    "command": "echo 'sec-review: $(git rev-parse --short HEAD)'"
  }
}
```

When this plugin is enabled, every session activates the `security-reviewer` agent as the main thread until the plugin is disabled.

### Priority over the manifest's `settings` field

Both `plugin.json` (`"settings": {...}`) and a root-level `settings.json` file can carry the same keys. **The root-level file wins.** Practical implication: don't set the same key in both — pick one. Convention is to use the `settings.json` file when you have multiple keys (cleaner formatting in JSON), and the manifest field when you have just one (avoids an extra file).

### When to use this surface

| Plugin purpose | Use plugin-shipped settings? |
|---|---|
| A specialised assistant (security-only, docs-only, etc.) that should *replace* default Claude Code behaviour while enabled | Yes — set `agent` |
| A subagent-heavy workflow where the parent should see distinct status-line cues | Yes — set `subagentStatusLine` |
| Any other "I want my plugin to set X by default" need | No — those keys aren't honoured. Document the recommendation in your README and let the user opt in to their own `settings.json` |

## Frontmatter flags

These aren't `plugin.json` fields — they live in the YAML frontmatter at the top of `SKILL.md`, command markdown files, and agent markdown files. Each capability has its own set of recognised keys; unknown keys are silently ignored. Full reference: official [Plugins reference](https://code.claude.com/docs/en/plugins-reference). Two flags are commonly load-bearing for plugin authors:

### `disable-model-invocation` (skill / command)

```markdown
---
name: dangerous-utility
description: Reset all caches, clear sessions, and rebuild from scratch
disable-model-invocation: true
---
```

When `true`, the skill or slash command **cannot be triggered by the model autonomously** — only by the user typing `/dangerous-utility` (or whatever the name is). The skill is still loaded; the description still appears in the registry; but the model's own decision to fire it is suppressed.

Use for any capability that is destructive, expensive, or otherwise needs explicit user intent — anything where "the model decided to run this on a weak signal" is a regression you want to prevent. The description should still be informative so users know what the command does when they invoke it manually.

Default: `false` (model can fire when its description matches).

### `allowed-tools` (skill / command / agent)

Restricts the tools the capability is allowed to call. Different shape per surface:

- **Commands**: CSV string — `allowed-tools: Read, Edit, Bash`
- **Agents**: YAML array — `tools: [Read, Grep, Bash]`

(The asymmetry between command CSV and agent array is real — both are documented in the official frontmatter reference.)

A capability with no `allowed-tools` defaults to the agent's parent tool set. Setting an empty value (`allowed-tools:` with nothing after) revokes all tools.

## Common mistakes

- **Hard-coding `~/.claude/plugins/...`** in scripts. Always use the env vars; the cache layout is internal and may change.
- **Putting state in `${CLAUDE_PLUGIN_ROOT}`.** It's wiped on update. Anything the user might modify or that takes time to compute belongs in `${CLAUDE_PLUGIN_DATA}`.
- **Setting `version` without tagging.** A `version` field doesn't auto-create a tag. Run `claude plugin tag` (see `development-cycle/release.md`).
- **Conflating `name` collisions.** A plugin named `foo` in marketplace A and another named `foo` in marketplace B are two different plugins. They can both be installed; Claude Code disambiguates by marketplace.

## Validation

`plugin.json` is validated against a JSON schema at install time. If the schema URL is referenced via `$schema`, editors will validate live. Common validation failures:

- Missing required `name` (the only strictly-required field)
- `version` not a valid SemVer string (only fires when `version` is set; the field itself is optional)
- `dependencies` entry missing required `name`
- `userConfig` option's `type` not one of `string|number|boolean|directory|file`

Unknown top-level fields are typically ignored rather than rejected — the schema is permissive enough that consumers can attach metadata that older Claude Code versions won't recognise. Stick to the documented fields above.

See `development-cycle/lifecycle-and-storage.md` for what happens at load time when validation fails.
