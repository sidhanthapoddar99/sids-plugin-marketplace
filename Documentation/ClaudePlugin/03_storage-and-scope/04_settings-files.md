# Settings files

There are four `settings.json` files Claude Code reads. Each one can carry plugin-related keys; the union with precedence determines the active set.

## The four files

| Scope | Path | Committed? | Who edits |
|---|---|---|---|
| **Managed** | Platform-specific (admin path) | n/a — admin-controlled | Org administrators only |
| **User** | `~/.claude/settings.json` | No (in your home dir) | You, for all your projects |
| **Project** | `<repo>/.claude/settings.json` | Yes — checked in | Team consensus (PR-reviewed) |
| **Local** | `<repo>/.claude/settings.local.json` | No — gitignored | You, only in this repo |

The managed path varies by platform — see the [Claude Code docs on managed settings](https://code.claude.com/docs/en/settings) for the per-OS path. It's typically `/Library/Application Support/ClaudeCode/managed-settings.json` on macOS or under `/etc/claude-code/` on Linux.

## What goes in each

The same JSON shape is valid in any of them, but conventions differ:

### User scope (`~/.claude/settings.json`)

Your personal defaults across all projects:

- Theme, status line, model, permissions defaults
- Personal `enabledPlugins` (plugins you use everywhere)
- Personal `extraKnownMarketplaces` (suggestions for repos you trust)
- Personal env vars

### Project scope (`<repo>/.claude/settings.json`)

Settings everyone working on this repo should have:

- The "dogfood" `enabledPlugins` — plugins this repo expects (e.g. its own first-party plugin in dev)
- `extraKnownMarketplaces` — pre-populates marketplace suggestions for teammates
- Project-specific permissions (e.g. allow `npm test`)
- Project hooks declared at the Claude Code level (not plugin hooks)

### Local scope (`<repo>/.claude/settings.local.json`)

Personal overrides for this repo:

- Disable a project-scope plugin you don't want locally (`"foo@mkt": false`)
- Personal env vars or permissions for just this repo
- Anything you don't want teammates to see

This file should be **gitignored** — Claude Code does not add it to `.gitignore` automatically.

### Managed scope

For organisations:

- Force-enable required plugins (compliance, security)
- Restrict allowed marketplaces via `strictKnownMarketplaces`
- Lock down permissions, env vars, model selection

Managed values can't be overridden by other scopes.

## The `enabledPlugins` shape

```json
{
  "enabledPlugins": {
    "documentation-guide@documentation-template": true,
    "rust-analyzer-lsp@claude-plugins-official": false,
    "my-internal-plugin@team-marketplace": true
  }
}
```

Keys are `<plugin-name>@<marketplace-name>`. Values are booleans:

- `true` — plugin loads at session start
- `false` — plugin does not load (registered as disabled)
- key absent — falls through to lower-priority scope

`/plugin install` adds an entry set to `true`. `/plugin enable | disable` flip the boolean. `/plugin uninstall` removes the entry entirely.

## Other plugin-related keys

| Key | Purpose | Where it lives |
|---|---|---|
| `enabledPlugins` | Boolean per `<plugin>@<mkt>` | Any scope |
| `extraKnownMarketplaces` | Marketplace source suggestions for this project | Typically project scope |
| `pluginConfigs.<plugin-id>.options` | Non-sensitive `userConfig` values | Where the user opted into the plugin |
| `strictKnownMarketplaces` | Array of marketplace source-pattern objects forming an allowlist (managed restriction) | Managed scope only |

The `pluginConfigs` block is what `userConfig` declarations write to after the user fills out the prompt. Sensitive values go to the OS keychain, not into the JSON.

## Inspection commands

```bash
grep enabledPlugins ~/.claude/settings.json
grep enabledPlugins <repo>/.claude/settings.json
grep enabledPlugins <repo>/.claude/settings.local.json
```

Or programmatically:

```bash
claude plugin list --json
```

`claude plugin list` returns the resolved active set, not the per-scope values — for the per-scope view, read the JSON files directly.

## Why a project's `.claude/` has no `plugins/` folder

A common source of confusion: project-scope folders only carry the `settings.json` (and optional `settings.local.json`). The plugin files themselves live in your user-level cache. There is **no per-project plugin cache by design** — the boolean is enough; the cache is shared.

When a teammate clones a repo with a project-scope `enabledPlugins`, they get the boolean from the committed JSON. The plugin files download to their user-level cache the first time they open the project (or run `/reload-plugins`).

## Cross-reference

For the broader picture of Claude Code settings — including non-plugin keys like `model`, `permissions`, `statusLine`, `hooks` (Claude Code level, not plugin level), keybindings, and env vars — see [`../../ClaudeSettings/01_settings-files-and-precedence.md`](../../ClaudeSettings/01_settings-files-and-precedence.md).

## See also

- [`03_scope-union.md`](./03_scope-union.md) — how the union is computed across scopes
- [`05_env-vars.md`](./05_env-vars.md) — `userConfig` values, env var substitution
- [`../../ClaudeSettings/`](../../ClaudeSettings/00_index.md) — full Claude Code settings reference
