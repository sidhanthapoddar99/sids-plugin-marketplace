# Scope union

Claude Code reads `enabledPlugins` from every applicable scope at session start and computes the **union**. Each enabled plugin loads once even if multiple scopes enable it.

## The four scopes

| Scope | `settings.json` location | Visibility |
|---|---|---|
| **Managed** | Set by admin (platform-specific path) | Locked, can't be overridden |
| **User** | `~/.claude/settings.json` | All your projects, this machine |
| **Project** | `<repo>/.claude/settings.json` | This project, all team members (committed to git) |
| **Local** | `<repo>/.claude/settings.local.json` | This project, just you (gitignored) |

## Precedence

```
Managed > Local > Project > User
```

Higher-priority scopes' booleans win when they conflict.

| Conflict scenario | Outcome |
|---|---|
| User says `true`, project says `false` | Project wins → plugin disabled |
| Project says `true`, local says `false` | Local wins → plugin disabled |
| Project says `false`, managed says `true` | Managed wins → plugin enabled, can't override |
| Only one scope mentions the plugin at all | That scope wins by default |

In practice, conflicts are rare — most plugins are enabled in exactly one scope.

## Computing the active set

At session start, Claude Code:

1. Reads `enabledPlugins` from each settings file that exists
2. Walks the precedence chain — for each plugin id, the highest-priority scope that mentions it determines the boolean
3. The active set is `{plugin-id : true}` entries after precedence resolution
4. Each active plugin loads exactly once from the cache, regardless of how many scopes enabled it

## No duplication problem

A common worry: "if I enable a plugin at both user and project scope, will it load twice?" No. The plugin files live in one place (`~/.claude/plugins/cache/...`) and the union is computed before loading. Verified empirically: enabling `claude-md-management` at both user and project scope simultaneously results in exactly one cache folder, one set of skills, one entry in `/reload-plugins`'s output.

This means **multi-scope enable is harmless**. The common patterns:

| Pattern | Effect |
|---|---|
| User scope only | Plugin available everywhere on this machine |
| Project scope only | Plugin available to anyone who clones the repo (the **dogfood** pattern) |
| User + project | Both you (everywhere) and teammates (in this repo) get it |
| Local scope only | Plugin available only in this project, only to you |

## What gets unioned

The union model applies specifically to `enabledPlugins`. Other settings keys merge differently — see [`../../ClaudeSettings/01_settings-files-and-precedence.md`](../../ClaudeSettings/01_settings-files-and-precedence.md) for the full Claude Code settings precedence story.

For plugin-related keys specifically:

| Key | How it composes across scopes |
|---|---|
| `enabledPlugins` | Union with precedence (this page) |
| `extraKnownMarketplaces` | Union (project-level recommendations are added) |
| `pluginConfigs.<plugin-id>.options` | Higher-precedence scope wins per-key |

## Disable-via-settings is sometimes necessary

If a managed scope force-enables a plugin and you want it off in your particular project, you can't override managed. But if user scope enables a plugin and you want it off just in one project, set `"enabledPlugins": {"<plugin>@<mkt>": false}` at project or local scope — the higher-priority scope's `false` wins.

This is the mechanism behind `/plugin disable --scope project` — the slash command writes the `false` to the project scope's settings.

## See also

- [`04_settings-files.md`](./04_settings-files.md) — what each settings file contains, full shape of `enabledPlugins`
- [`05_env-vars.md`](./05_env-vars.md) — `userConfig` values follow the same precedence model
- [`../../ClaudeSettings/01_settings-files-and-precedence.md`](../../ClaudeSettings/01_settings-files-and-precedence.md) — broader settings file precedence
