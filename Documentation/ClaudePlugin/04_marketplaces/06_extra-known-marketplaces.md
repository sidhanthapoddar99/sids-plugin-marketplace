# `extraKnownMarketplaces`

`extraKnownMarketplaces` is a **settings key**, not a `marketplace.json` field. It lives in `.claude/settings.json` (project, user, or managed scope). It pre-populates marketplace suggestions for teammates so they don't need to run `/plugin marketplace add <url>` manually before a project's plugins can install.

> This is the team-bootstrap mechanism. It's how a project ships "to use this repo, these are the marketplaces you should have" without forcing a manual setup step.

## Where it lives

| Scope | File | Audience |
|---|---|---|
| Project | `<repo>/.claude/settings.json` | Anyone who opens this repo |
| User | `~/.claude/settings.json` | Just this user, across all projects |
| Managed | OS-specific managed-settings path | Whole organisation, locked-down |

For the full settings layout, see [`Documentation/ClaudeSettings/05_plugin-related-settings.md`](../../ClaudeSettings/05_plugin-related-settings.md).

## Shape

`extraKnownMarketplaces` is an object keyed by marketplace name, where each value mirrors a marketplace `source` entry:

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/team-plugins"
      }
    },
    "internal-catalogue": {
      "source": {
        "source": "url",
        "url": "https://gitlab.internal/devops/marketplace.git",
        "ref": "stable"
      }
    }
  }
}
```

The marketplace-name key (`"team-tools"`) is what consumers will see and what plugins will reference as `<plugin>@team-tools`.

## How the prompt flow works

When a user opens a project that ships `extraKnownMarketplaces` and trusts the folder:

1. Claude Code reads the project's `settings.json`
2. For each marketplace listed in `extraKnownMarketplaces` that the user doesn't already have registered:
   - Claude Code prompts: "This project recommends adding marketplace `team-tools` from `your-org/team-plugins`. Add?"
3. If accepted, the marketplace is added at user scope (marketplaces always register at user scope — there's no per-project marketplace registration)
4. If `enabledPlugins` in the same settings file lists plugins from those marketplaces, Claude Code prompts to install them

Without `extraKnownMarketplaces`, a teammate who just clones a repo with `enabledPlugins` set would hit a "marketplace not registered" error and have to discover the right `add` command from documentation.

## Using it with `enabledPlugins`

The two settings work together. `extraKnownMarketplaces` tells Claude Code where to find the marketplace; `enabledPlugins` tells it which plugins to enable from there:

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/team-plugins"
      }
    }
  },
  "enabledPlugins": {
    "deploy-kit@team-tools": true,
    "audit-logger@team-tools": true
  }
}
```

A new teammate cloning the repo gets prompted to add `team-tools`, then to install both plugins, in two prompts.

## Pinning a recommended marketplace

The `source` object inside `extraKnownMarketplaces` accepts the same `ref` field as a `/plugin marketplace add` URL pin:

```json
{
  "extraKnownMarketplaces": {
    "stable-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/team-plugins",
        "ref": "v3.0.0"
      }
    }
  }
}
```

This freezes the marketplace itself to a tag for everyone using the project. It's stricter than just adding `your-org/team-plugins#v3.0.0` manually — the project commits the pin, so all teammates run against the same marketplace ref.

## Why register at user scope

Marketplaces themselves don't have a project-scope registration. The reason is sandboxing: plugins are installed to user-scoped cache directories under `~/.claude/plugins/`, and a per-project marketplace would still need to write into that user-scoped cache. The compromise is: the **prompt** is project-driven (so trusting the project triggers it), but the **registration** ends up user-scoped (one cache, shared across projects).

## What it does NOT do

- It doesn't auto-install marketplaces or plugins without user consent — every prompt is opt-in
- It doesn't override managed-scope `strictKnownMarketplaces` allowlists. Those take priority. See [`07_managed-restrictions.md`](./07_managed-restrictions.md)
- It doesn't enable plugins by itself — pair it with `enabledPlugins` for that

## See also

- [`07_managed-restrictions.md`](./07_managed-restrictions.md) — the managed-scope companion `strictKnownMarketplaces`
- [`Documentation/ClaudeSettings/05_plugin-related-settings.md`](../../ClaudeSettings/05_plugin-related-settings.md) — full settings layout for plugin-related keys
- [`03_storage-and-scope/`](../03_storage-and-scope/) — why marketplaces register at user scope
