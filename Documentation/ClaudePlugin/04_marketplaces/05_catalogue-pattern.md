# The catalogue pattern

A marketplace doesn't have to ship plugins from its own repo. It can be a pure **catalogue of plugins from anywhere** — listing entries that point at other GitHub repos, other git hosts, monorepo subdirectories, or npm packages. This is how the official `claude-plugins-official` marketplace handles its `external_plugins/` partners.

The catalogue marketplace owns only the index, not the plugins.

## When to use the catalogue pattern

| Scenario | Use a catalogue |
|---|---|
| Curating a vetted set of third-party plugins for your team | Yes |
| Aggregating multiple existing marketplaces into one entry point | Yes (list each plugin individually with its source) |
| Recommending a partner's plugin alongside your own | Yes (mix of relative-path and remote sources is fine) |
| Hosting your own plugins | Use the standard layout (`plugins/` directory next to `marketplace.json`) |

There's no separate "merge two marketplaces" command — if you want a meta-marketplace, list each plugin one by one using its origin source.

## Repo layout

A pure catalogue marketplace doesn't need a `plugins/` directory locally:

```
team-curated-marketplace/
├── .claude-plugin/
│   └── marketplace.json     ← entirely external sources
└── README.md
```

If you mix curated + own plugins, it's a hybrid:

```
hybrid-marketplace/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   └── in-house-formatter/  ← listed via "./plugins/in-house-formatter"
│       └── .claude-plugin/plugin.json
└── README.md                 ← other entries point at github/url/npm
```

## Example: pure catalogue

```json
{
  "name": "team-curated",
  "owner": { "name": "Platform Team" },
  "description": "Plugins our platform team has vetted",
  "plugins": [
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

Most catalogue entries are object-shaped sources (`github`, `url`, `git-subdir`, `npm`) since by definition the plugins live elsewhere.

## Update flow for catalogues

When an upstream plugin tags a new release:

- Catalogues using `ref` pinned to a tag (`"ref": "v1.2.0"`): consumers stay on `v1.2.0` until the catalogue maintainer bumps the entry to `v1.3.0` and pushes
- Catalogues using `ref` pinned to a branch (`"ref": "main"`): consumers pick up the new release on next `/plugin update`, no catalogue change needed
- Catalogues without `ref` set: same as `ref: <default-branch>`

The catalogue's role is to decide *which version* the team sees, not necessarily to host the artifact.

## Trust implications

When a user adds a catalogue marketplace, they're trusting:

1. The **catalogue maintainer** (who chose what to list)
2. Each **plugin source** the catalogue points at (those run with the user's privileges)

Trust does not chain across marketplaces in dependency resolution — see [`08_cross-marketplace-deps.md`](./08_cross-marketplace-deps.md) — but it does flow at install time: adding a catalogue means accepting whatever its `source` URLs reach.

For organisations restricting which marketplaces users can add, see [`07_managed-restrictions.md`](./07_managed-restrictions.md).

## See also

- [`02_source-types.md`](./02_source-types.md) — the source forms catalogues use most
- [`06_extra-known-marketplaces.md`](./06_extra-known-marketplaces.md) — bootstrapping a catalogue for a team
- [`08_cross-marketplace-deps.md`](./08_cross-marketplace-deps.md) — when catalogue plugins depend on plugins in other marketplaces
