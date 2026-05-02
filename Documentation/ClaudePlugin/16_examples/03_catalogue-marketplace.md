# Catalogue marketplace

A marketplace that **lists third-party plugins it doesn't host**. Every entry's `source` points at an external repo, npm package, or URL. The marketplace itself ships nothing but the manifest.

This is the right pattern when you want to curate "the plugins I trust" or "plugins relevant to my team" without taking on the maintenance burden of mirroring them.

## File tree

```
my-catalogue/
├── .claude-plugin/
│   └── marketplace.json
├── README.md
└── LICENSE
```

That's it. No `plugins/` folder, because the plugins live elsewhere.

## `.claude-plugin/marketplace.json`

```json
{
  "name": "my-catalogue",
  "owner": {
    "name": "Your Name",
    "email": "you@example.com"
  },
  "metadata": {
    "description": "Curated list of plugins I trust",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "plugin-dev",
      "source": {
        "source": "git-subdir",
        "url": "https://github.com/anthropics/claude-plugins-official.git",
        "path": "plugins/plugin-dev"
      },
      "description": "Official plugin authoring toolkit"
    },
    {
      "name": "documentation-guide",
      "source": {
        "source": "github",
        "repo": "sidhantha/documentation-template",
        "ref": "main"
      },
      "description": "Documentation site authoring toolkit"
    },
    {
      "name": "ralph-loop",
      "source": {
        "source": "github",
        "repo": "sidhantha/ralph-loop",
        "ref": "v1.0.0"
      },
      "description": "Iteration-loop plugin"
    },
    {
      "name": "deploy-tools",
      "source": {
        "source": "npm",
        "package": "@acme/deploy-tools-claude-plugin",
        "version": "^2.0.0"
      },
      "description": "Deployment tooling published to npm"
    },
    {
      "name": "team-utils",
      "source": {
        "source": "url",
        "url": "https://gitlab.internal/devops/team-utils.git",
        "ref": "main"
      },
      "description": "Internal team utilities on a non-GitHub git host"
    }
  ]
}
```

The catalogue lists five plugins from four different source types — none of which live in this repo.

## Source types

| `source.source` | Required fields | Optional | Purpose |
|---|---|---|---|
| `github` | `repo` (`owner/name`) | `ref`, `sha` | Plugin in a GitHub repo |
| `url` | `url` | `ref`, `sha` | Plugin in any git repo (GitLab, Bitbucket, internal Gerrit, etc.) |
| `git-subdir` | `url`, `path` | `ref`, `sha` | Plugin in a subdirectory of a git monorepo (sparse clone) |
| `npm` | `package` | `version`, `registry` | Plugin published to npm |

(Plus the bare-string relative-path form for plugins in the same repo as the marketplace.)

See [`../04_marketplaces/02_source-types.md`](../04_marketplaces/02_source-types.md) for the full specification.

## Ref pinning and version resolution

Each source type supports its own version-resolution mechanism:

| Source | Pinning |
|---|---|
| `github`, `url`, `git-subdir` | `ref: "main"` (branch), `ref: "v1.2.3"` (tag); plus `sha: "<40-char>"` for an exact-commit pin. Combined with the `<plugin-name>--v<version>` tag convention for `dependencies` resolution |
| `npm` | `version` field accepts a semver range, like a normal npm dependency |

For tag-based dependency resolution to work, the upstream repo must follow the `<plugin-name>--v<version>` tag convention. If it doesn't, you can still install at a fixed `ref`/`sha` but `dependencies` constraints won't have version data to resolve against.

## Cross-marketplace dependencies

If any plugin in your catalogue declares `dependencies` against plugins in *other* marketplaces, you need to allow those marketplaces:

```json
{
  "name": "my-catalogue",
  "allowCrossMarketplaceDependenciesOn": [
    "claude-plugins-official"
  ],
  "plugins": [
    {
      "name": "my-team-plugin",
      "source": { ... },
      "dependencies": [
        { "name": "plugin-dev", "marketplace": "claude-plugins-official" }
      ]
    }
  ]
}
```

This applies to dependencies declared either in the marketplace entry (above) or in the upstream plugin's own `plugin.json`. Trust doesn't chain — see [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md).

## When to use this pattern

| Situation | Catalogue marketplace |
|---|---|
| Curate "plugins I trust" without mirroring | ✅ ideal |
| Internal team distribution: pre-populate marketplaces for teammates | ✅ |
| Bundle related third-party plugins under one install command | ✅ |
| Mix of hosted and externally-hosted plugins | ⚠️ works (mix object sources with relative-path sources) but rarer |
| You want to *modify* upstream content | ❌ — soft-fork in a dogfood marketplace instead |
| You want plugins versioned in lockstep | ❌ — a catalogue can't enforce cross-plugin coordination |

## Hybrid: dogfood + catalogue

A single marketplace can mix both — some entries with relative-path `source` (hosted in the same repo) and some with object `source` (third-party):

```json
{
  "name": "mixed-marketplace",
  "plugins": [
    {
      "name": "my-plugin",
      "source": "./plugins/my-plugin"
    },
    {
      "name": "external-plugin",
      "source": {
        "source": "github",
        "repo": "someone/their-plugin"
      }
    }
  ]
}
```

This is useful when you maintain some plugins yourself and want to curate a few external ones alongside.

## `extraKnownMarketplaces` for team distribution

If your catalogue is for a team, drop a snippet in your project's `.claude/settings.json` so teammates auto-add the marketplace when they trust the project:

```json
{
  "extraKnownMarketplaces": {
    "my-catalogue": {
      "source": {
        "source": "github",
        "repo": "your-org/my-catalogue"
      }
    }
  },
  "enabledPlugins": {
    "plugin-dev@my-catalogue": true
  }
}
```

Combined with `enabledPlugins`, this is the team-distribution recipe: a teammate clones the project, trusts the folder, gets prompted to add `my-catalogue` and install the listed plugins. See [`../14_distribution/00_index.md`](../14_distribution/00_index.md).

## See also

- [`02_dogfood-marketplace.md`](./02_dogfood-marketplace.md) — the alternative: marketplace + plugins in the same repo
- [`../04_marketplaces/02_source-types.md`](../04_marketplaces/02_source-types.md) — every source type's full schema
- [`../08_composition-patterns/02_depend.md`](../08_composition-patterns/02_depend.md) — cross-marketplace dependency rules
- [`../14_distribution/00_index.md`](../14_distribution/00_index.md) — `extraKnownMarketplaces` and team distribution
