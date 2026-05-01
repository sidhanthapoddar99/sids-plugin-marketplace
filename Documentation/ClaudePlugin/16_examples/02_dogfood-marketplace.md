# Dogfood marketplace

A self-hosted marketplace where the plugins it lists live in the **same repo** as the marketplace manifest. This is the layout used by `sids-plugin-marketplace` itself, and the most common pattern for solo authors who want one repo to track everything.

## File tree

```
my-marketplace/
├── .claude-plugin/
│   └── marketplace.json          ← marketplace manifest
├── README.md
├── LICENSE
└── plugins/
    ├── plugin-a/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── README.md
    │   └── skills/
    │       └── skill-a/SKILL.md
    └── plugin-b/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── README.md
        └── commands/
            └── do-thing.md
```

The marketplace's `.claude-plugin/marketplace.json` lives at the repo root, and its plugins are sub-directories under `plugins/`.

## `.claude-plugin/marketplace.json`

```json
{
  "name": "my-marketplace",
  "owner": {
    "name": "Your Name",
    "email": "you@example.com"
  },
  "metadata": {
    "description": "Your personal plugin marketplace",
    "version": "1.0.0",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "plugin-a",
      "source": "./plugins/plugin-a",
      "description": "What plugin-a does"
    },
    {
      "name": "plugin-b",
      "source": "./plugins/plugin-b",
      "description": "What plugin-b does"
    }
  ]
}
```

Key fields:

| Field | Purpose |
|---|---|
| `name` | Marketplace identifier — used in install commands as `<plugin>@<marketplace>` |
| `owner` | Falls through as the `author` for any plugin that doesn't set its own |
| `metadata.pluginRoot` | Directory under the marketplace root containing plugins. `./plugins` is conventional |
| `plugins[]` | One entry per plugin. Each `source` is a relative path under `pluginRoot` (or absolute) |

`metadata.pluginRoot` is documentation for the discovery convention — it tells consumers (and humans browsing the repo) where the plugins live. The `source` field on each entry is what actually points to the plugin.

## Plugin manifests

Each plugin under `plugins/<name>/` has its own `.claude-plugin/plugin.json`:

```json
// plugins/plugin-a/.claude-plugin/plugin.json
{
  "name": "plugin-a",
  "description": "What plugin-a does",
  "version": "0.1.0",
  "author": {
    "name": "Your Name"
  }
}
```

The plugin's `name` field must match the marketplace entry's `name`. The two manifests are independent — you can update the marketplace's listing metadata (`description`, etc.) without bumping the plugin's `version`, and vice versa. At install time, the marketplace's `description` shows in `/plugin install` UI; the plugin's `description` shows in the installed list.

## Worked example: `sids-plugin-marketplace`

The repository this documentation lives in is itself a dogfood marketplace. Its real layout (abbreviated):

```
sids-plugin-marketplace/
├── .claude-plugin/
│   └── marketplace.json
├── README.md
├── LICENSE
├── docs/                       ← project docs (not part of the marketplace)
├── Documentation/              ← reference docs (not part of the marketplace)
├── scripts/                    ← marketplace-level tooling (e.g. drift-check)
└── plugins/
    ├── ai-toolkit-dev/
    │   ├── .claude-plugin/plugin.json
    │   ├── .upstream/manifest.json    ← provenance for soft-forked content
    │   ├── README.md
    │   └── skills/
    │       ├── marketplace/
    │       ├── plugin-dev/
    │       └── skill-creator/
    └── ... other plugins ...
```

This pattern lets one git repo track:

- The marketplace manifest
- All the plugins in the marketplace
- Marketplace-level tooling (scripts, docs)
- Cross-cutting documentation

A single `git push` ships marketplace updates plus plugin updates atomically.

## Adding the marketplace

Users add the marketplace once:

```
/plugin marketplace add <github-shorthand>
# or
/plugin marketplace add /local/path/to/my-marketplace
# or
/plugin marketplace add https://github.com/you/my-marketplace
```

Then install plugins from it:

```
/plugin install plugin-a@my-marketplace
/plugin install plugin-b@my-marketplace
```

The `@my-marketplace` suffix is the marketplace name (from `marketplace.json`'s `name` field, **not** the GitHub repo name).

## Releasing

For each plugin, when you bump its `version`:

```bash
cd plugins/plugin-a
claude plugin tag --push
```

This creates a `plugin-a--v0.1.0` tag (note: `--v` separator) and pushes it. The version-resolution machinery (see [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md)) uses these tags to satisfy `dependencies` constraints.

Each plugin in the dogfood marketplace tags independently. There's no marketplace-wide version — every plugin has its own version line.

## When to use this pattern

| Situation | Dogfood marketplace |
|---|---|
| Solo author, multiple plugins | ✅ ideal |
| Want one repo to track everything | ✅ |
| Plugins share tooling or docs | ✅ |
| Need to atomically ship marketplace + plugin updates | ✅ |
| Plugins have wildly different release cadences | ⚠️ still works — each plugin tags independently |
| Hosting third-party plugins you don't maintain | ❌ — see [`03_catalogue-marketplace.md`](./03_catalogue-marketplace.md) |

## See also

- [`03_catalogue-marketplace.md`](./03_catalogue-marketplace.md) — the alternative: a marketplace that lists plugins it doesn't host
- [`04_soft-fork-plugin.md`](./04_soft-fork-plugin.md) — a worked plugin under a dogfood marketplace
- [`../04_marketplaces/00_index.md`](../04_marketplaces/00_index.md) — marketplace anatomy
- [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) — the per-plugin tag-and-release loop
