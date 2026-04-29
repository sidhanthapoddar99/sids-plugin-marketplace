---
title: Marketplaces
description: What a marketplace is, what marketplace.json contains, and how to host one
---

# Marketplaces

A **marketplace** is a Git repository (or local directory) that catalogues one or more plugins. Users add a marketplace once, then install any plugin it ships. Marketplaces are how plugins reach consumers.

## Marketplace structure

The minimum:

```
my-marketplace/
└── .claude-plugin/
    └── marketplace.json     ← the catalogue
```

In practice, the marketplace usually also contains the plugin folders it lists (so the marketplace and plugins live in one repo):

```
my-marketplace/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    ├── plugin-a/            ← each plugin is a folder
    │   ├── .claude-plugin/plugin.json
    │   └── skills/
    └── plugin-b/
        └── ...
```

Plugins can also be hosted in separate repos and referenced from the marketplace by Git URL.

## marketplace.json schema

Minimal:

```json
{
  "name": "my-marketplace",
  "owner": { "name": "Your Name" },
  "plugins": [
    {
      "name": "plugin-a",
      "source": "./plugins/plugin-a",
      "description": "One-line description shown in the /plugin browser"
    }
  ]
}
```

### Top-level fields

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Marketplace identifier; consumers reference it as `<plugin>@<marketplace>` |
| `owner.name` | yes | Display name of the maintainer |
| `plugins` | yes | Array of plugin entries (see below) |
| `description` | optional | Marketplace-level description |
| `version` | optional | Marketplace manifest version |
| `metadata.pluginRoot` | optional | Base directory prepended to relative plugin source paths. Setting `"./plugins"` lets entries write `"source": "formatter"` instead of `"source": "./plugins/formatter"` |
| `allowCrossMarketplaceDependenciesOn` | optional | Array of other marketplace names whose plugins this marketplace's plugins are allowed to depend on. See [Plugin Dependencies](./05_creating-plugins/07_dependencies.md) |

### Plugin entry fields

Each entry in `plugins` describes a plugin and where to fetch it. Marketplace entries can include **any field from the plugin manifest schema** (`description`, `version`, `author`, `commands`, `hooks`, etc.) — those values supplement or override the plugin's own `plugin.json`. Marketplace-specific fields:

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Must match the `name` in the plugin's `plugin.json` |
| `source` | yes | Where to fetch the plugin from. Five forms supported — see [Plugin source types](#plugin-source-types) below |
| `description` | recommended | Shown in the `/plugin` browser; keep it information-dense |
| `category` | optional | Used by the `/plugin` Discover tab for grouping (`"security"`, `"development"`, etc.) |
| `tags` | optional | Array of search hints |
| `strict` | optional | If `false`, allows the marketplace entry and the plugin's own `plugin.json` to both define components without conflict errors |
| `dependencies` | optional | Override the plugin's own `dependencies` array. See [Plugin Dependencies](./05_creating-plugins/07_dependencies.md) |

## Plugin source types

The `source` field accepts one string form or one of four object forms. Choose based on where the plugin lives.

| Form | Shape | Use for |
|---|---|---|
| **Relative path** | `"./plugins/foo"` (string, must start with `./`) | Plugin in the same repo as the marketplace |
| **`github`** | `{"source": "github", "repo": "owner/name", "ref?": "...", "sha?": "..."}` | Plugin in another GitHub repo |
| **`url`** | `{"source": "url", "url": "https://...", "ref?": "...", "sha?": "..."}` | Plugin on a non-GitHub git host (GitLab, Bitbucket, Azure DevOps, AWS CodeCommit, internal Gerrit) |
| **`git-subdir`** | `{"source": "git-subdir", "url": "...", "path": "tools/plugin", "ref?": "...", "sha?": "..."}` | Plugin in a subdirectory of a monorepo. Uses sparse clone to fetch only the subdirectory |
| **`npm`** | `{"source": "npm", "package": "@org/name", "version?": "^2.0.0", "registry?": "..."}` | Plugin distributed as an npm package |

All git-based source forms accept:

- `ref` — branch or tag (defaults to repository default branch)
- `sha` — full 40-character commit SHA for exact pinning

`ref` and `sha` pin **independently** of the marketplace's own ref. So a marketplace at `acme/catalog#v1.0.0` can list a plugin at `acme/formatter#v2.3.0` — the marketplace and the plugin track different versions.

Examples of each form:

```json
// Relative path (same repo)
{ "name": "formatter", "source": "./plugins/formatter" }

// GitHub repo, pinned to a tag and SHA
{
  "name": "deploy-tools",
  "source": {
    "source": "github",
    "repo": "acme/deploy-tools",
    "ref": "v2.0.0",
    "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
  }
}

// GitLab via git URL
{
  "name": "internal-lint",
  "source": {
    "source": "url",
    "url": "https://gitlab.com/team/internal-lint.git",
    "ref": "main"
  }
}

// Subdirectory of a monorepo
{
  "name": "ci-helpers",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/acme/monorepo.git",
    "path": "tools/ci-helpers"
  }
}

// npm package with version range
{
  "name": "my-plugin",
  "source": {
    "source": "npm",
    "package": "@acme/claude-plugin",
    "version": "^2.0.0",
    "registry": "https://npm.example.com"
  }
}
```

> [!note]
> **Marketplace source vs plugin source.** They're different things. *Marketplace source* is what users pass to `/plugin marketplace add` — it points at the `marketplace.json` catalogue. *Plugin source* is the `source` field inside an individual plugin entry — it points at one specific plugin. Marketplace sources support `ref` only (no `sha`); plugin sources support both.

> [!warning]
> **Relative paths break URL-distributed marketplaces.** If users add your marketplace via a direct `https://` URL to `marketplace.json` (not via Git), `./...` plugin sources won't resolve. For URL-distributed marketplaces, use `github`/`url`/`npm` sources instead.

## Hosting options

### GitHub repo (most common)

Push the marketplace to GitHub. Consumers add it with the GitHub URL:

```
/plugin marketplace add https://github.com/sidhanthapoddar99/documentation-template
```

Or the GitHub shorthand:

```
/plugin marketplace add sidhanthapoddar99/documentation-template
```

Updates flow naturally — `/plugin update` re-fetches from `main` (or whichever branch the marketplace tracks).

### Local path

For developing against an in-flight marketplace:

```
/plugin marketplace add /home/you/repos/my-marketplace
/plugin marketplace add ./my-marketplace
```

> [!warning]
> `file://` URLs are rejected with `"Invalid marketplace source format"` despite being a natural guess. Use a plain absolute or relative path.

### Private / self-hosted Git

Any Git URL works — GitLab, Bitbucket, internal Gerrit, anything Claude Code can `git clone` from. The CLI uses your local Git auth.

For private GitHub or SSH-only hosts, use the SSH URL form:

```
/plugin marketplace add git@github.com:your-org/your-marketplace.git
```

### Direct URL to marketplace.json

If your marketplace isn't backed by a Git repo (e.g. a static file hosted on a CDN or internal server), point at the manifest directly:

```
/plugin marketplace add https://example.com/marketplace.json
```

Claude Code fetches the manifest and resolves plugin sources from the URLs listed inside. The plugins themselves can still be in any backend the manifest references.

## The dogfood pattern

A framework repo can be **both** a marketplace and the source of its own plugin. The same repo is added as a marketplace and then installs its own plugin. The maintainer is consumer #1, so any breakage shows up in their own development immediately.

```
my-framework/
├── .claude-plugin/
│   └── marketplace.json     ← repo IS a marketplace
├── .claude/
│   └── settings.json        ← committed; enables the plugin in this project
├── plugins/
│   └── my-plugin/           ← repo is also the plugin source
│       ├── .claude-plugin/plugin.json
│       ├── bin/
│       └── skills/
└── (rest of the framework)
```

The `documentation-template` repo (this one) does exactly this — see `.claude-plugin/marketplace.json` at the repo root, and `plugins/documentation-guide/` as the only plugin it ships.

## Listing multiple plugins

A marketplace can ship many plugins:

```json
{
  "name": "my-marketplace",
  "owner": { "name": "Acme Corp" },
  "plugins": [
    {
      "name": "core-tools",
      "source": "./plugins/core-tools",
      "description": "Core CLI wrappers for Acme dev workflow"
    },
    {
      "name": "deploy",
      "source": "./plugins/deploy",
      "description": "Deployment scripts and pre-flight hooks"
    }
  ]
}
```

Each plugin keeps its own `plugin.json`, version, and update cadence. Consumers install them independently:

```
/plugin install core-tools@my-marketplace
/plugin install deploy@my-marketplace
```

## Listing external plugins (catalogue pattern)

A marketplace doesn't have to ship plugins from its own repo. It can be a **catalogue of plugins from anywhere** — listing entries that point at other GitHub repos, other git hosts, monorepo subdirectories, or npm packages. This is how the official `claude-plugins-official` marketplace handles its `external_plugins/` partners.

```json
{
  "name": "team-curated",
  "owner": { "name": "Platform Team" },
  "plugins": [
    {
      "name": "in-house-formatter",
      "source": "./plugins/formatter",
      "description": "Our own formatter"
    },
    {
      "name": "github",
      "description": "GitHub MCP integration",
      "source": {
        "source": "github",
        "repo": "anthropics/claude-code-github-plugin",
        "ref": "v1.2.0"
      }
    },
    {
      "name": "internal-deploy",
      "description": "GitLab-hosted deploy plugin",
      "source": {
        "source": "url",
        "url": "https://gitlab.internal/devops/claude-deploy.git"
      }
    },
    {
      "name": "tools-from-monorepo",
      "description": "Plugin from a shared monorepo",
      "source": {
        "source": "git-subdir",
        "url": "https://github.com/acme/monorepo.git",
        "path": "tools/claude-plugin"
      }
    },
    {
      "name": "registry-plugin",
      "source": {
        "source": "npm",
        "package": "@acme/claude-tools",
        "version": "^1.0.0"
      }
    }
  ]
}
```

This is the "marketplace as a curated index" pattern: you don't own the plugins, you just decide which ones your team or community should see together. Updates flow naturally — when an upstream plugin tags a new release, your marketplace's consumers pick it up on `/plugin update`.

There's no separate "merge two marketplaces" command. If you want a meta-marketplace that aggregates several existing marketplaces' plugins, list each plugin individually using its source repo. Alternatively, use [`extraKnownMarketplaces`](#team-distribution-via-extraknownmarketplaces) to make multiple marketplaces auto-suggested for your team.

## Pinning a marketplace at `add` time

When adding a Git-backed marketplace, append `#<ref>` to the URL to pin to a specific branch or tag:

```
/plugin marketplace add https://gitlab.com/team/plugins.git#v1.0.0
```

The `ref` controls which version of `marketplace.json` is fetched. It only supports `ref` (branch/tag), not `sha`. To track the latest, omit `#<ref>` — Claude Code uses the repo's default branch.

To refresh an already-added marketplace, run `/plugin marketplace update <name>`. To list all configured marketplaces, run `/plugin marketplace list`.

## Team distribution via `extraKnownMarketplaces`

Marketplaces themselves only register at **user scope** — there's no per-project marketplace registration. But you can pre-populate marketplace suggestions for teammates by adding them to a project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/team-plugins"
      }
    }
  }
}
```

When a teammate trusts the repo folder, Claude Code prompts them to add the marketplace and install any plugins listed in `enabledPlugins`. Without this, they'd need to `/plugin marketplace add <url>` manually before the project's plugin install can succeed.

## Cross-marketplace dependencies

A plugin in one marketplace can declare a dependency on a plugin in a *different* marketplace, but the root marketplace must opt in. Add the target marketplace to `allowCrossMarketplaceDependenciesOn` at the marketplace.json top level:

```json
{
  "name": "acme-tools",
  "allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"],
  "plugins": [
    {
      "name": "deploy-kit",
      "source": "./deploy-kit",
      "dependencies": [
        { "name": "audit-logger", "marketplace": "claude-plugins-official" }
      ]
    }
  ]
}
```

Without the allowlist entry, the install fails with a `cross-marketplace` error. Trust does not chain — only the *root* marketplace's allowlist is consulted (the marketplace hosting the plugin the user is installing). See [Plugin Dependencies](./05_creating-plugins/07_dependencies.md) for the full story.

## See also

- **[Storage and Scope](./02_storage-and-scope.md)** — what happens after `/plugin install`
- **[Plugin Structure](./05_creating-plugins/02_plugin-structure.md)** — what goes inside each plugin folder the marketplace lists
- **[Plugin Dependencies](./05_creating-plugins/07_dependencies.md)** — the dependency system this references
- **[Soft Fork and Upstream Tracking](./05_creating-plugins/08_soft-fork-and-upstream-tracking.md)** — vendoring upstream content with a provenance manifest
- **[Versioning and Publishing](./05_creating-plugins/06_versioning-and-publishing.md)** — semver, releases, and the dogfood loop
- **[Reference](./07_reference.md)** — full nomenclature index for everything else
- Official: [Plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
