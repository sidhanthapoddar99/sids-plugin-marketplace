# Hand-author

The default. You're writing original content with no upstream plugin to draw from. Everything in your plugin lives in your namespace, ships in your install, and changes when you change it.

## When to pick this pattern

| Situation | Hand-author |
|---|---|
| The capability doesn't exist anywhere | ✅ |
| The capability exists upstream but is domain-specific to you | ✅ |
| You want one namespace, one install, one maintainer | ✅ |
| Upstream content exists and is good, and you only add net-new alongside | ⚠️ consider depending instead |
| Upstream content exists but is stale | ⚠️ consider soft-forking instead |

Hand-authoring is the right answer for the vast majority of first-time plugins. The two alternatives (depend, soft-fork) only become relevant when there's a specific upstream plugin you'd otherwise be duplicating.

## Plugin vs. hand-authored at user/project scope

Before you reach for "make a plugin", consider whether the content even needs packaging. The packaging-vs-hand-authored split:

| Situation | Hand-author at user/project scope | Package as a plugin |
|---|---|---|
| One skill, one project | ✅ | overkill |
| Personal command for your own workflow | ✅ | overkill |
| Convention shared across 3+ projects | ⚠️ painful to keep in sync | ✅ |
| Need updates pushed to consumers | ❌ no mechanism | ✅ `/plugin update` |
| Need discoverability for others | ❌ | ✅ marketplaces |
| Need versioning / multiple versions in cache | ❌ | ✅ |

The signal is usually the second time you copy the same `SKILL.md` into a new project. That's when packaging starts paying for itself.

User-scope hand-authoring lives at:

- `~/.claude/skills/<name>/SKILL.md`
- `~/.claude/commands/<name>.md`
- `~/.claude/agents/<name>.md`

Project-scope at:

- `<repo>/.claude/skills/<name>/SKILL.md` (etc.)

The model treats these identically to plugin-shipped equivalents — see [`../02_mental-model/03_packaging-vs-capabilities.md`](../02_mental-model/03_packaging-vs-capabilities.md).

## Naming

Hand-authored plugins still need to coexist in `$PATH`, in slash-command space, and in MCP server name space with every other enabled plugin on a user's machine. Naming is the only tool you have for collision avoidance.

| Surface | Convention |
|---|---|
| Plugin name | Globally unique within a marketplace. Kebab-case `[a-z][a-z0-9-]*`, 3–64 chars |
| Skill names | Unique within the plugin. Don't prefix with the plugin name — Claude Code displays them as `<plugin>:<skill>` already |
| Command names | Slash command space is *flat* across all enabled plugins. Prefix only if the verb is generic (`/test`, `/build`) |
| Agent names | Unique within the plugin. Avoid generic names that could collide across plugins (`reviewer`, `runner`) |
| Bin scripts | `bin/` entries from every enabled plugin coexist in `$PATH`. Plugin-prefix or use a single dispatcher binary |
| MCP server names | Unique across all enabled plugins. Prefix unless genuinely generic (`myplugin-fs`, not `fs`) |

The pragmatic rule: **prefix bin scripts and MCP server names**, don't prefix everything else. The slash-command palette has a flat namespace, so be deliberate about whether your verb is "common enough to deserve `/test`" or "specific enough that `/myplugin-test` is more honest".

See [`../02_mental-model/04_naming-and-namespacing.md`](../02_mental-model/04_naming-and-namespacing.md) for the full collision matrix.

## Versioning

Hand-authored plugins follow standard SemVer: `MAJOR.MINOR.PATCH` in the manifest's `version` field. The `claude plugin tag` command creates a `<plugin-name>--v<version>` git tag that the version-resolution machinery uses.

If you omit `version` entirely, Claude Code falls back to the git commit SHA — every commit is effectively a new version, and there's no semantic-version constraint anyone can use to depend on you.

Hand-authored plugins published to a marketplace should:

1. Set `version` in `plugin.json`.
2. Tag releases with `claude plugin tag --push`.
3. Bump the version on every release; never push two releases at the same version number.

See [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) for the release loop in detail.

## Hand-authored plus dependencies (or soft-forks)

Hand-authoring is the *baseline* of every plugin. Dependencies and soft-forks are *additions* on top — a plugin can declare both and still hand-author the rest of its content.

The PROVENANCE table convention (see [`03_soft-fork.md`](./03_soft-fork.md)) reserves `**in-house**` as the origin label for hand-authored components. A hybrid plugin's table looks like:

| Component | Origin |
|---|---|
| `code-formatter` | dependency: `formatter@my-marketplace` |
| `lint-runner` | soft-import: plugin-dev |
| `release-manager` | **in-house** |
| `marketplace-authoring` | **in-house** |

Most plugins are pure hand-authored — no dependencies, no soft-forks, just the manifest and your own content. The other two patterns are tools to reach for when the situation calls for them.

## Anti-patterns

- **Reinventing a well-maintained upstream skill verbatim.** If `plugin-dev` already has a `hook-development` skill that's fresh and accurate, depending or soft-forking is cheaper than rewriting it.
- **Generic command names that collide.** `/build`, `/test`, `/deploy` collide with every other plugin in the ecosystem. Either prefix (`/myplugin-build`) or accept that one plugin will silently win and the other won't.
- **No versioning.** Skipping the `version` field works for personal use, but no one else can pin to a stable release.
- **Multiple skills in one folder.** Each skill needs its own `skills/<name>/` directory with its own `SKILL.md`. Don't try to put two skills in one folder.

## See also

- [`02_depend.md`](./02_depend.md) — when upstream is fresh and you want to build on top
- [`03_soft-fork.md`](./03_soft-fork.md) — when upstream is stale and you'd rewrite anyway
- [`../02_mental-model/04_naming-and-namespacing.md`](../02_mental-model/04_naming-and-namespacing.md) — collision rules in detail
- [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) — the release loop for hand-authored plugins
- [`../16_examples/01_minimal-plugin.md`](../16_examples/01_minimal-plugin.md) — minimum-viable hand-authored plugin
