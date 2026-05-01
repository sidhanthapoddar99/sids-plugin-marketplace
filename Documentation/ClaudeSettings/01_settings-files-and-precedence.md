---
title: Settings Files and Precedence
description: The four settings.json locations, JSON format, and the Managed > Local > Project > User precedence rule
---

# Settings Files and Precedence

Claude Code reads settings from up to four files at session start. They share the same JSON shape; what differs is *whose* configuration they represent and *how strongly* their values bind. The active configuration is computed as a **union** across all four with conflicts resolved by precedence.

## The four files

| Scope | Path | Committed? | Audience |
|---|---|---|---|
| **User** | `~/.claude/settings.json` | n/a (lives in `$HOME`) | All your projects on this machine |
| **Project** | `<repo>/.claude/settings.json` | yes | This project, all teammates |
| **Local** | `<repo>/.claude/settings.local.json` | no (gitignored) | This project, only you |
| **Managed** | platform-specific, set by an admin | n/a | Locked org-wide policy |

The managed-settings path is platform-specific and provisioned by IT/MDM tooling; it is not normally edited by the user. The remaining three files are plain JSON the user (or a teammate) writes by hand or via `/config`.

## Precedence

```
Managed  >  Local  >  Project  >  User
```

More-specific scopes win. So a permission denied at managed scope cannot be re-granted by user scope, and a personal `statusLine` at local scope overrides the project-committed default.

This is the same precedence used by `enabledPlugins` for plugin enablement (covered in [Plugin-Related Settings](./05_plugin-related-settings.md)) — it applies to **every** key in `settings.json`.

## JSON format

All four files share one shape — a flat JSON object with the following well-known keys (see the dedicated pages for each):

```json
{
  "statusLine": { "type": "command", "command": "..." },
  "permissions": {
    "allow": ["Bash(git status:*)"],
    "deny":  ["Bash(rm -rf:*)"]
  },
  "enabledPlugins": {
    "documentation-guide@documentation-template": true
  },
  "extraKnownMarketplaces": { /* see page 05 */ },
  "strictKnownMarketplaces": [ /* managed-only, see page 05 */ ],
  "pluginConfigs": {
    "<plugin-id>": { "options": { /* userConfig non-sensitive values */ } }
  },
  "env": {
    "MY_TOOL_FLAG": "1"
  }
}
```

Unknown keys are silently ignored. Comments are not allowed (it's plain JSON, not JSONC).

> [!note]
> **Keybindings live in their own file**, not in `settings.json`. See [Permissions and Keybindings](./03_permissions-and-keybindings.md).

## The union rule

For aggregate keys like `enabledPlugins`, `permissions.allow`, `permissions.deny`, and `extraKnownMarketplaces`, the active set is the **union of all four scopes**, then conflicts are resolved by precedence.

For a plugin enabled at user scope and disabled at project scope, project wins (project beats user). But a plugin enabled *only* at project scope is still active for users who clone the repo — they don't need to re-enable it at user scope. This is what makes `enabledPlugins` portable across teams: write it once in `<repo>/.claude/settings.json`, commit, and every collaborator picks it up.

A worked example for `enabledPlugins`:

| File | Says |
|---|---|
| `~/.claude/settings.json` (User) | `{"foo@mkt": true, "bar@mkt": true}` |
| `<repo>/.claude/settings.json` (Project) | `{"baz@mkt": true, "bar@mkt": false}` |
| `<repo>/.claude/settings.local.json` (Local) | `{"qux@mkt": true}` |

After the union with Local > Project > User precedence, the runtime activates `foo`, `baz`, `qux`, and **does not** activate `bar` (project's `false` overrides user's `true`).

For details on how this composes with the plugin cache (which is *always* user-level on disk regardless of registration scope), see [Storage and Scope — Scope Union](../ClaudePlugin/03_storage-and-scope/03_scope-union.md).

## Working with the files

| Operation | How |
|---|---|
| Edit user settings | `~/.claude/settings.json` directly, or run `/config` |
| Edit project settings | `<repo>/.claude/settings.json` directly; commit the change |
| Edit local settings | `<repo>/.claude/settings.local.json` directly; never commit |
| Reload after edit | Restart the session — most settings are read at session start |
| See active state | `/config` opens the in-app config viewer |

> [!important]
> **`.claude/settings.local.json` must be gitignored.** It carries developer-specific overrides (auth tokens, personal `allow` rules, experimental flags) that should never reach the team's repo. Most project templates ship a `.gitignore` entry for this.

## What does NOT live here

A few things look like settings but are stored elsewhere:

| Thing | Where it lives |
|---|---|
| Keybindings | `~/.claude/keybindings.json` (separate file — see [page 03](./03_permissions-and-keybindings.md)) |
| OAuth tokens | OS keychain |
| Sensitive `userConfig` values | OS keychain (`sensitive: true` in plugin's `userConfig`) |
| Plugin files themselves | `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/` (see [Cache Layout](../ClaudePlugin/03_storage-and-scope/01_cache-layout.md)) |
| Per-plugin runtime state | `~/.claude/plugins/data/<plugin-id>/` (the `${CLAUDE_PLUGIN_DATA}` dir) |

## See also

- [Status Line](./02_status-line.md) — the `statusLine` key
- [Permissions and Keybindings](./03_permissions-and-keybindings.md) — the `permissions` key, plus the separate keybindings file
- [Plugin-Related Settings](./05_plugin-related-settings.md) — `enabledPlugins`, `extraKnownMarketplaces`, etc.
- [Storage and Scope — Scope Union](../ClaudePlugin/03_storage-and-scope/03_scope-union.md) — the union rule, with an `enabledPlugins` worked example
- Official: [Claude Code settings](https://code.claude.com/docs/en/settings)
