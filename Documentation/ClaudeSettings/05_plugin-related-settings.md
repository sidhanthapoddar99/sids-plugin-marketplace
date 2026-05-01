---
title: Plugin-Related Settings
description: Settings keys that are about plugins but live in settings.json — enabledPlugins, extraKnownMarketplaces, strictKnownMarketplaces, pluginConfigs
---

# Plugin-Related Settings

Four `settings.json` keys are *about* plugins but **don't live in plugin manifests** — they live in the user's, project's, local's, or managed-scope `settings.json`. Each captures a decision the user (or their team, or their org) makes about plugins, separate from anything any individual plugin author can ship.

| Key | Lives in | Purpose |
|---|---|---|
| `enabledPlugins` | any of the 4 scopes | Boolean per `<plugin>@<marketplace>` — turns plugins on/off |
| `extraKnownMarketplaces` | project / user / managed | Suggests marketplaces to teammates so the project's plugins can install |
| `strictKnownMarketplaces` | **managed only** | Allowlist of marketplace sources the org permits |
| `pluginConfigs[<plugin-id>].options` | written by `/plugin` enable flow | Non-sensitive `userConfig` values for plugins; sensitive ones go to OS keychain |

## `enabledPlugins`

A flat object mapping `<plugin>@<marketplace>` identifiers to booleans:

```json
{
  "enabledPlugins": {
    "documentation-guide@documentation-template": true,
    "ai-toolkit-dev@sids-plugin-marketplace": true,
    "experimental-thing@some-other-mkt": false
  }
}
```

### Per-scope behaviour

The runtime computes the **union** across all four scopes (Managed + Local + Project + User), then resolves conflicts by [precedence](./01_settings-files-and-precedence.md#precedence): Managed > Local > Project > User. A plugin enabled at *any* scope (and not disabled at a higher-precedence scope) is active for that session.

Worked-example walk-through and the empirical proof that "multi-scope enabled" doesn't duplicate the cache: see [Storage and Scope — Scope Union](../ClaudePlugin/03_storage-and-scope/03_scope-union.md).

### What "installing" actually does

`/plugin install foo@mkt` and the `claude plugin install` CLI both reduce to:

1. Download the plugin source into `~/.claude/plugins/cache/mkt/foo/<version>/` (user-level, single copy).
2. Set `"foo@mkt": true` in the chosen scope's `settings.json`.

The choice of scope is a `--scope` flag on the CLI (`user`, `project`, `local`) and an interactive prompt in the `/plugin` UI. The plugin files themselves go to user-level cache regardless of scope.

### Pinning a version

`enabledPlugins` accepts version specifiers as a value form on top of the boolean:

```json
{
  "enabledPlugins": {
    "foo@mkt": "^1.2.0"
  }
}
```

The exact syntax depends on the Claude Code release; see the official plugin docs. Most users keep it as `true` and pin via the marketplace's `ref`/`sha` instead.

## `extraKnownMarketplaces`

Object mapping marketplace name → source spec. Lives at **project**, **user**, or **managed** scope (project is the common case). Pre-populates marketplace suggestions for teammates so that when they trust the repo folder, Claude Code prompts them to add the listed marketplaces and install any plugins listed in `enabledPlugins`.

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/team-plugins"
      }
    },
    "vendor-marketplace": {
      "source": {
        "source": "url",
        "url": "https://gitlab.internal/devops/plugin-catalog.git"
      }
    }
  }
}
```

The `source` field uses the same shapes as a marketplace `source` in [marketplace.json](../ClaudePlugin/04_marketplaces/02_source-types.md): `github`, `url`, `git-subdir`, `npm`, or a relative path. (Marketplace sources support `ref` but not `sha`.)

### Why it exists

Without `extraKnownMarketplaces`, a teammate cloning a repo whose `.claude/settings.json` has `"foo@team-tools": true` in `enabledPlugins` will see an error: `team-tools` isn't registered as a marketplace on their machine. They'd need to `/plugin marketplace add <url>` manually before the project's plugin install can succeed.

`extraKnownMarketplaces` closes that gap: when the teammate trusts the repo folder, Claude Code reads `extraKnownMarketplaces`, prompts to add `team-tools` as a marketplace, and on approval the `enabledPlugins` entries resolve and install.

### Per-scope behaviour

| Scope | Why you'd put it here |
|---|---|
| **Project** | The common case: ship marketplace suggestions alongside the repo so teammates auto-prompt |
| **User** | Personal — marketplaces you want suggested across all your projects |
| **Managed** | Org-wide — admin-set marketplaces that should always appear as known |

It's never local-scope (no point — local-scope is gitignored, the suggestions wouldn't reach teammates).

For full context on team distribution and how this composes with `enabledPlugins`, see [extraKnownMarketplaces in ClaudePlugin docs](../ClaudePlugin/04_marketplaces/06_extra-known-marketplaces.md).

## `strictKnownMarketplaces` (managed-only)

An array of marketplace source specs that the org permits. **Only honoured at managed scope** — setting it at user / project / local scope is ignored.

```json
{
  "strictKnownMarketplaces": [
    {
      "source": "github",
      "repo": "your-org/approved-marketplace"
    },
    {
      "source": "github",
      "repo": "anthropics/claude-plugins-official"
    }
  ]
}
```

When this is set, users **cannot add marketplaces outside the allowlist**. Attempts to `/plugin marketplace add <url>` with a non-listed source fail. This is the org-restriction primitive — the way IT/SecOps locks down which marketplaces (and therefore which plugin sources) employees can install from.

> [!important]
> `strictKnownMarketplaces` is *additive* with the user's normal known-marketplaces — but it makes the list **the only permitted set**. Users can still see and use any marketplace already added (those become read-only); they just can't add new ones outside the allowlist.

For policy guidance and the threat-model rationale, see [Managed Marketplace Restrictions](../ClaudePlugin/04_marketplaces/07_managed-restrictions.md).

## `pluginConfigs[<plugin-id>].options`

When a plugin declares `userConfig` in its `plugin.json`, Claude Code prompts the user for the values during `/plugin` enable. The non-sensitive values are stored here:

```json
{
  "pluginConfigs": {
    "formatter-my-marketplace": {
      "options": {
        "preferredStyle": "minimal",
        "verbose": true,
        "extraDirs": ["./tools", "./scripts"]
      }
    }
  }
}
```

| Aspect | Value |
|---|---|
| Key (plugin-id) | The install identifier with non-`[a-zA-Z0-9_-]` characters replaced with `-`. For `formatter@my-marketplace`, the id is `formatter-my-marketplace` |
| `options` | Map of userConfig key → value. Types match the `type` declared in `userConfig` (`string`, `number`, `boolean`, `directory`, `file`, or arrays via `multiple: true`) |
| Sensitive values | **Not here.** Sensitive userConfig values (`sensitive: true` in the manifest) live in the OS keychain |
| Substitution | Values are substituted as `${user_config.KEY}` in MCP/LSP server configs, hook commands, monitor commands, and (for non-sensitive only) skill and agent content |
| Env-var export | All values are also exported to subprocesses as `CLAUDE_PLUGIN_OPTION_<KEY>` |

### Sensitive values and the keychain

If a `userConfig` option declares `sensitive: true`:

- The user's input is masked at prompt time
- The value is stored in the OS keychain, **not** in `settings.json`
- Skill and agent content cannot reference it via `${user_config.KEY}` (skills are markdown the model sees, so plumbing secrets through them would expose them)
- MCP / LSP / hook / monitor commands *can* reference it — those execute outside the model's context

The keychain is shared with OAuth tokens and has a roughly 2 KB total cap. Don't try to stuff binary blobs in there.

### Why it lives in `settings.json` and not in the manifest

The plugin manifest declares the **shape** of `userConfig` (what to ask, what type, whether sensitive). The values are user-supplied — they belong to the *user's* settings, not the plugin's source. This keeps the plugin source byte-identical across users and lets each user have different values. It also lets a single user have different values per scope (e.g. project-scope `verbose: true` for one repo, user-scope `verbose: false` everywhere else).

## Quick reference

| Decision | Where to set it |
|---|---|
| "Enable this plugin for me, all projects" | `enabledPlugins` in `~/.claude/settings.json` (user) |
| "Enable this plugin for everyone on the team" | `enabledPlugins` in `<repo>/.claude/settings.json` (project, committed) |
| "Suggest this marketplace to teammates so the above install works" | `extraKnownMarketplaces` in `<repo>/.claude/settings.json` (project) |
| "Restrict our org to a specific marketplace allowlist" | `strictKnownMarketplaces` at managed scope |
| "Save the verbosity option I picked when enabling this plugin" | Auto-written to `pluginConfigs[<id>].options` by the enable flow |
| "Save the API key the plugin asked for" | Auto-written to OS keychain (not `settings.json`) |

## See also

- [Settings Files and Precedence](./01_settings-files-and-precedence.md) — the four scopes these keys live in
- [Storage and Scope — Scope Union](../ClaudePlugin/03_storage-and-scope/03_scope-union.md) — the `enabledPlugins` union rule with a worked example
- [extraKnownMarketplaces (plugin-side context)](../ClaudePlugin/04_marketplaces/06_extra-known-marketplaces.md) — team distribution patterns
- [Managed Marketplace Restrictions](../ClaudePlugin/04_marketplaces/07_managed-restrictions.md) — `strictKnownMarketplaces` threat model
- [Plugin-Shipped Settings](../ClaudePlugin/05_plugin-anatomy/05_plugin-shipped-settings.md) — the *other* settings.json (the one a plugin's root may carry, with only `agent` / `subagentStatusLine`)
- Official: [Configure team marketplaces](https://code.claude.com/docs/en/discover-plugins#configure-team-marketplaces)
- Official: [Managed marketplace restrictions](https://code.claude.com/docs/en/plugin-marketplaces#managed-marketplace-restrictions)
- Official: [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration)
