# Naming conventions

What's enforced by Claude Code, and what's idiomatic but flexible.

## Plugin names

**Enforced:**
- Must be unique within its marketplace
- Kebab-case, ASCII — `[a-z][a-z0-9-]*` is the typical shape
- No leading or trailing dashes; no consecutive dashes (the schema rejects "ugly" forms)

(Length bounds aren't formally documented in the official schema; in practice keep it short — the name appears in `<plugin>@<marketplace>` identifiers, in `/plugin install` UI rows, and in the cache directory path.)

**Idiomatic:**
- Descriptive, not branded — `markdown-tools` over `mdx-pro`
- `-dev` suffix for plugin authoring tools (`plugin-dev`, `agent-sdk-dev`)
- `-lsp` suffix for LSP integrations (`pyright-lsp`, `typescript-lsp`)
- Avoid prefixing with the marketplace name; the marketplace already namespaces

## Skill names

**Enforced:** `[a-z][a-z0-9-]*`, kebab-case. Must be unique within a plugin.

**Idiomatic:**
- Use the verb-or-noun the user would say: `code-review`, `debug-rust`, `pdf-fill`
- Don't prefix with the plugin name — Claude Code displays them as `<plugin>:<skill>` already (e.g. `ai-toolkit-dev:plugin-dev`)
- Match the directory: skill at `skills/foo-bar/SKILL.md` should have `name: foo-bar` in frontmatter

## Command names

**Enforced:**
- File at `commands/<name>.md` becomes slash command `/<name>`
- Lowercase, alphanumeric, dashes
- Must be unique within a plugin (and effectively across all installed plugins, since `/` namespace is flat)

**Idiomatic:**
- Short verb: `/test`, `/lint`, `/release`
- Plugin-prefix only if collision likely: `/pf-release` for a plugin-foo command. Most authors should NOT prefix unless their command's verb is generic (`/test`, `/build`)
- Avoid `/help`, `/clear`, `/exit` and other CLI-builtin names

## Agent names

**Enforced:**
- File at `agents/<name>.md` registers an agent with name `<name>`
- Match `[a-z][a-z0-9-]*`
- Unique within a plugin

**Idiomatic:**
- Role-based: `code-reviewer`, `test-runner`, `release-manager`
- Avoid `bot`/`assistant` suffixes — every agent is one
- Avoid generic names that could collide across plugins (`reviewer`, `runner`)

## Hook config

The hook config file is `hooks/hooks.json` by convention. The names *inside* the JSON are event names (`PreToolUse`, `Stop`, etc.) and aren't author-chosen. See `topics/hook-development/SKILL.md`.

## Bin scripts

**Enforced:**
- Files in `bin/` get added to `$PATH` for any subprocess launched from a session that has the plugin enabled
- Must be executable (`chmod +x`) on UNIX
- Naming follows OS conventions: lowercase, dashes, no extension

**Idiomatic:**
- Plugin-prefix to avoid global `$PATH` collisions: `pf-validate`, `pf-bench` for a plugin-foo plugin
- Or use a single dispatcher binary with subcommands: one bin `pf` that takes `pf validate`, `pf bench`
- The prefix matters because `bin/` entries from every enabled plugin coexist in `$PATH`

## MCP server names

**Enforced:** Set in `.mcp.json` — must be unique across all enabled plugins (collision = error at load).

**Idiomatic:**
- Plugin-prefix unless the server is genuinely generic: `myplugin-fs`, not `fs`
- Match the upstream server's published name when possible

## File and directory names

| Path | Convention |
|---|---|
| `.claude-plugin/plugin.json` | Required — exact name |
| `commands/*.md` | Lowercase filename = command name |
| `agents/*.md` | Lowercase filename = agent name |
| `skills/*/SKILL.md` | `SKILL.md` is uppercase, required exactly |
| `hooks/hooks.json` | Lowercase, exact |
| `bin/*` | OS-conventional (no extension on UNIX) |
| `.mcp.json` | Lowercase, exact |
| `scripts/*` | Free-form — not auto-discovered, called by your other components |
| `assets/*` | Free-form — bundle data, templates, etc. |

## Versioning

`plugin.json` `version` field follows SemVer: `MAJOR.MINOR.PATCH`. Tags created by `claude plugin tag` are `<plugin-name>--v<version>` — the `--v` separator is required (it disambiguates plugin tags from any other repo tags in monorepos).

## Branding vs identity

Plugin names go in URLs, command palettes, and config files. They're *identifiers*, not marketing. Save the marketing for `description`, README, and `/plugin install` UI text.
