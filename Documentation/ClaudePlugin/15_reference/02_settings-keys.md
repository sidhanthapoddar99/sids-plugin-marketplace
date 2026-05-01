# Settings keys reference

Every key Claude Code reads from `settings.json` (and equivalents) that's **plugin-related** or **plugin-shippable**. Non-plugin keys (status line, permissions, keybindings, network) live in [`../../ClaudeSettings/`](../../ClaudeSettings/).

## Three places `settings.json` lives

| Path | Scope | Committed? |
|---|---|---|
| `~/.claude/settings.json` | User | No |
| `<repo>/.claude/settings.json` | Project | Yes |
| `<repo>/.claude/settings.local.json` | Local | No (gitignored) |

Plus the plugin-shipped variant:

| Path | Scope | Committed? |
|---|---|---|
| `<plugin-root>/settings.json` | Plugin (applies when the plugin enables) | Whatever the plugin author commits |

The four files merge at session start by scope precedence (Local > Project > User; Plugin-shipped supplies defaults).

## Plugin-related keys — read by Claude Code from any of the user-facing scopes

### `enabledPlugins`

```json
{
  "enabledPlugins": {
    "<plugin-name>@<marketplace>": true
  }
}
```

Object mapping `<plugin>@<marketplace>` keys to booleans. `true` means enabled at this scope; `false` means explicitly disabled. Missing means "this scope doesn't have an opinion."

The runtime computes the union across scopes (Local OR Project OR User). One scope flipping to `false` disables the plugin even if another has it enabled — explicit `false` overrides implicit `true` *within the same scope chain* (consult [`../03_storage-and-scope/03_scope-union.md`](../03_storage-and-scope/03_scope-union.md) for the precise rule).

### `extraKnownMarketplaces`

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "type": "github",
      "owner": "acme-corp",
      "repo": "claude-marketplace"
    }
  }
}
```

Object that pre-populates marketplace suggestions for teammates. When a teammate trusts the repo folder, Claude Code prompts them to add the listed marketplaces and install any plugins listed in `enabledPlugins`. Without this, they'd need to `/plugin marketplace add <url>` manually.

The shape mirrors a marketplace `source` entry. See [`../04_marketplaces/06_extra-known-marketplaces.md`](../04_marketplaces/06_extra-known-marketplaces.md).

Typically lives in the project's `.claude/settings.json` (committed).

### `strictKnownMarketplaces`

Boolean. When `true`, Claude Code treats `extraKnownMarketplaces` as an **allowlist** — only those marketplaces (plus official Anthropic marketplaces) can be added in this scope. Used by managed/org deployments to restrict which marketplaces users can install plugins from.

Pairs with the managed-restrictions feature; see [`../04_marketplaces/07_managed-restrictions.md`](../04_marketplaces/07_managed-restrictions.md).

### `pluginConfigs`

```json
{
  "pluginConfigs": {
    "<plugin-id>": {
      "options": {
        "API_BASE": "https://api.example.com",
        "REGION": "us-east-1"
      }
    }
  }
}
```

Where non-sensitive `userConfig` values land. Sensitive values (marked `sensitive: true` in the plugin's `userConfig`) go to the OS keychain instead, not here.

`<plugin-id>` is the plugin's name (without the `@<marketplace>` suffix). The key under `options` matches the `userConfig` declaration's identifier.

Generally Claude Code writes this for you when the user enables a plugin — hand-editing is rare. The modern alternative to the legacy `.claude/<plugin-name>.local.md` pattern; see [`04_legacy-and-migration.md`](./04_legacy-and-migration.md).

## Plugin-shipped — root-level `settings.json`

A `settings.json` at the plugin's root applies default Claude Code settings when the plugin is **enabled**. Two keys are currently honoured:

### `agent`

```json
{
  "agent": "my-custom-agent"
}
```

Activates one of the plugin's custom agents (under `agents/<name>.md`) as the **main thread**. The agent's system prompt, tool restrictions, and model become Claude Code's identity for the session.

This is how a plugin can effectively *replace* Claude Code's default behaviour while enabled — useful for highly specialised plugins (a security-review-only assistant, a docs-only assistant, etc.).

### `subagentStatusLine`

Configures the status line shown when a subagent is running. Same shape as the Claude Code `subagentStatusLine` settings key (see [`../../ClaudeSettings/`](../../ClaudeSettings/) for the non-plugin context).

### Unknown keys are silently ignored

A plugin-shipped `settings.json` with other keys (e.g., main `statusLine`, `allowedTools`, `permissions`) is loaded but those keys are dropped. Plugins **cannot** ship those settings as defaults — they're user-controlled by design.

To prevent confusion for plugin authors: only `agent` and `subagentStatusLine` are plugin-shippable. Everything else belongs to the user.

## Non-plugin keys — listed for orientation

These are valid in `settings.json` but **not plugin-shippable**. Documented fully in [`../../ClaudeSettings/`](../../ClaudeSettings/):

| Key | Purpose | Where to set |
|---|---|---|
| `statusLine` | Main thread status line config | User / project `settings.json` |
| `allowedTools` | Per-session tool allowlist | User / project / local `settings.json` |
| `permissions` | Permission preset rules | User / project / local `settings.json` |
| `model` | Default model | User `settings.json` |
| `theme` | Color theme selection | User `settings.json` |
| `keybindings` | Custom keymap path | User `settings.json` |
| `env` | Custom env vars | User `settings.json` |
| `hooks` | User-scoped hooks (separate from plugin hooks) | User / project `settings.json` |

Plugins influence many of these indirectly (a plugin's hooks add to the merged hook set; a plugin's themes appear in `/theme`; etc.) but cannot **set** them as defaults.

## Per-marketplace auto-update toggles

Stored in user-scope settings as a per-marketplace flag managed via the `/plugin` UI's Marketplaces tab. Schema is internal — don't hand-edit; toggle through the UI.

See [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md).

## Precedence summary

For any plugin-related setting:

1. **Plugin-shipped `settings.json`** — supplies defaults (only `agent` / `subagentStatusLine`)
2. **User `~/.claude/settings.json`** — user-wide
3. **Project `<repo>/.claude/settings.json`** — committed, repo-wide
4. **Local `<repo>/.claude/settings.local.json`** — uncommitted, per-developer

Later layers override earlier. `enabledPlugins` is **unioned** rather than overridden — see [`../03_storage-and-scope/03_scope-union.md`](../03_storage-and-scope/03_scope-union.md).

## See also

- [`01_env-vars-cheatsheet.md`](./01_env-vars-cheatsheet.md) — the env-var equivalents
- [`../03_storage-and-scope/04_settings-files.md`](../03_storage-and-scope/04_settings-files.md) — settings file paths and merge order
- [`04_legacy-and-migration.md`](./04_legacy-and-migration.md) — `.claude/<plugin-name>.local.md` predecessor of `pluginConfigs`
- [`../../ClaudeSettings/`](../../ClaudeSettings/) — non-plugin settings keys
- Official: [Plugins reference — settings](https://code.claude.com/docs/en/plugins-reference)
