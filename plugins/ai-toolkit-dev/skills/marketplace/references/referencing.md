# Marketplace composition and cross-references

A marketplace can list plugins it doesn't host, recommend other marketplaces (via settings, not the manifest), and let its plugins depend on plugins from elsewhere. This document covers those patterns.

## Pattern 1: Catalogue (listing third-party plugins)

A marketplace can be a pure index pointing at plugins hosted in other repos:

```json
{
  "name": "curated",
  "description": "A curated catalogue of Claude Code plugins",
  "owner": { "name": "Curator" },
  "plugins": [
    {
      "name": "useful-plugin-from-someone-else",
      "source": {
        "source": "github",
        "repo": "third-party/useful-plugin",
        "ref": "v1.4.2"
      },
      "description": "What it does"
    }
  ]
}
```

The catalogue repo doesn't need a `plugins/` directory at all if every entry uses an object source — it's just the index file.

**When to use:** you want to provide a curated entry point for users without re-hosting every plugin you recommend.

Full file: [`../examples/catalogue.json`](../examples/catalogue.json).

## Pattern 2: Recommending other marketplaces (`extraKnownMarketplaces`)

> **`extraKnownMarketplaces` is a settings key, not a `marketplace.json` field.** It lives in `.claude/settings.json` (project, user, or managed). A `marketplace.json` cannot recommend other marketplaces directly.

To bootstrap a team with a known set of marketplaces, commit `.claude/settings.json` to the project repo:

```json
// .claude/settings.json
{
  "extraKnownMarketplaces": {
    "team-foundation": {
      "source": { "source": "github", "repo": "myteam/foundation-marketplace" }
    },
    "team-frontend": {
      "source": { "source": "github", "repo": "myteam/frontend-marketplace" }
    }
  }
}
```

When a user trusts the project, they're prompted to add the listed marketplaces. Combine with `enabledPlugins` to also pre-enable specific plugins:

```json
{
  "extraKnownMarketplaces": {
    "team-foundation": { "source": { "source": "github", "repo": "myteam/foundation-marketplace" } }
  },
  "enabledPlugins": {
    "code-formatter@team-foundation": true,
    "deployment-tools@team-foundation": true
  }
}
```

**When to use:** distributing a known set of trusted marketplaces across a team. The `marketplace.json` files themselves stay sovereign over their own plugin lists.

Full file: [`../examples/team-recommendations.json`](../examples/team-recommendations.json).

### Locking down which marketplaces users can add

Admins can restrict the set of allowed marketplaces via `strictKnownMarketplaces` in **managed settings** (not user settings):

```json
{
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "acme-corp/approved-plugins" },
    { "source": "hostPattern", "hostPattern": "^github\\.example\\.com$" }
  ]
}
```

| Value | Behavior |
|---|---|
| Undefined (default) | No restrictions |
| `[]` | Complete lockdown — users cannot add any marketplaces |
| List of sources | Allowlist — exact match required for `repo`/`url`, regex for `hostPattern`/`pathPattern` |

Pair with `extraKnownMarketplaces` to both register and restrict in the same managed settings file.

## Pattern 3: Cross-marketplace plugin dependencies

A plugin in marketplace A can depend on a plugin in marketplace B, but **only if both sides opt in**:

- The depending plugin's `plugin.json` lists the dependency with `marketplace: "<other>"`.
- The depending plugin's *marketplace* declares `"allowCrossMarketplaceDependenciesOn": ["<other>"]`.

Without both, install fails.

### Marketplace side (in `marketplace.json`)

```json
{
  "name": "sids-plugin-marketplace",
  "owner": { "name": "Sid" },
  "allowCrossMarketplaceDependenciesOn": [
    "claude-plugins-official"
  ],
  "plugins": [...]
}
```

This says: "plugins in *my* marketplace are allowed to depend on plugins in `claude-plugins-official`."

### Plugin side (in `plugin.json`)

```json
{
  "name": "ai-toolkit-dev",
  "version": "1.0.0",
  "dependencies": [
    {
      "name": "skill-creator",
      "marketplace": "claude-plugins-official",
      "version": "^1.0"
    }
  ]
}
```

Version constraints follow the `{plugin-name}--v{version}` git-tag convention — see [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies) for range syntax and combination rules.

**When to use:** you want to depend on an upstream plugin's coexistence rather than vendor it. Note: dependency satisfies *coexistence* only — Claude Code installs the dependency alongside, but does not import individual skills/agents from it. Plugin composition is at the *plugin* level, not the component level.

If you need to *modify* upstream content, use the soft-fork pattern in the `plugin-dev` skill.

Full file: [`../examples/cross-marketplace-deps.json`](../examples/cross-marketplace-deps.json).

## Pattern 4: "Merger" marketplace

A marketplace that exists purely to combine others. Two flavors:

### 4a. Catalogue-merger

Lists plugins from multiple sources in a single index:

```json
{
  "name": "everything",
  "owner": { "name": "Aggregator" },
  "plugins": [
    { "name": "plugin-x", "source": { "source": "github", "repo": "team-a/plugin-x" }, "description": "..." },
    { "name": "plugin-y", "source": { "source": "github", "repo": "team-b/plugin-y" }, "description": "..." }
  ]
}
```

Pros: one `/plugin install` UI to browse everything. Cons: the merger has to track upstream version changes manually.

### 4b. Recommender-merger (via `extraKnownMarketplaces` in settings)

A project-level `.claude/settings.json` that adds multiple trusted marketplaces at once:

```json
{
  "extraKnownMarketplaces": {
    "marketplace-a": { "source": { "source": "github", "repo": "team-a/marketplace" } },
    "marketplace-b": { "source": { "source": "github", "repo": "team-b/marketplace" } }
  }
}
```

Pros: each underlying marketplace stays sovereign over its own plugins. Cons: users see multiple marketplaces, not one merged catalogue.

**Pick 4a** for a unified UX. **Pick 4b** when each underlying marketplace must remain independently authoritative.

## Field-level cheat sheet

| Where to put what | In which file | What it does |
|---|---|---|
| `allowCrossMarketplaceDependenciesOn` | the depending plugin's `marketplace.json` | Lets *its* plugins target plugins in named other marketplaces |
| `dependencies[].marketplace` | a plugin's `plugin.json` | Names which marketplace a dependency comes from |
| `extraKnownMarketplaces` | `.claude/settings.json` (project / user / managed) | Recommends marketplaces for users to add |
| `enabledPlugins` | `.claude/settings.json` | Pre-enables specific plugins by `name@marketplace` |
| `strictKnownMarketplaces` | **managed** settings only | Allowlists which marketplaces users may add |
| Plugin entry with `source: { source: "github", … }` | any `marketplace.json` | Lists a plugin hosted elsewhere (catalogue) |

## What this isn't

- **It isn't a way to import a single skill or agent from another plugin.** Plugin composition is at the plugin level. To use someone else's skill, install their plugin (you get all components) or soft-fork the skill into your own plugin.
- **It isn't transitive trust.** A user installing your marketplace doesn't automatically install the marketplaces in `extraKnownMarketplaces` — they're prompted. Cross-marketplace dependencies require the user to have both marketplaces installed and the dependency opt-ins to be in place.
- **It isn't a replacement for forking.** If an upstream plugin diverges from what you need, depending on it doesn't help. Soft-fork it instead — see the `plugin-dev` skill.
