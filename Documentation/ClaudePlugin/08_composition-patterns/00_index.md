# Composition patterns

Three patterns for relating a new plugin to existing ones. The choice is per-component (a single plugin can mix all three).

The composition primitive at runtime is **the whole plugin** — there's no way to import a single skill from another plugin into your namespace. Depending pulls in the entire upstream plugin alongside yours. Soft-forking copies content into your plugin's own namespace. Hand-authoring writes original content with no upstream relationship.

## Decision matrix

| Situation | Hand-author | Depend | Soft-fork |
|---|---|---|---|
| Net-new content with no upstream | ✅ | n/a | n/a |
| Upstream is fresh, well-maintained, evolves fast | ❌ ignores prior art | ✅ free updates | ❌ maintenance treadmill |
| Upstream is good but stale, you'd rewrite anyway | ⚠️ ignores prior art | ❌ stuck with stale | ✅ best fit |
| You want everything in *your* plugin's namespace | ✅ | ❌ upstream's namespace | ✅ |
| You want to edit descriptions for triggering control | ✅ | ❌ can't edit upstream | ✅ |
| Cross-marketplace allowlist friction | ✅ none | ❌ requires opt-in | ✅ none |
| Single install, single namespace for users | ✅ | ❌ two installs | ✅ |
| You'd contribute fixes back upstream | n/a | ✅ natural | ❌ harder to PR |
| You only need to *reference* upstream's components | ⚠️ duplication | ✅ best fit | ⚠️ overkill |

The two clean signals:

- **Upstream is fresh and you only add net-new content** → depend.
- **Upstream is stale and you'd rewrite anyway** → soft-fork.

Hand-authoring is what you do when there's no upstream to consider, and the dominant pattern for the first plugin most authors write.

## Sub-pages

| File | Pattern |
|---|---|
| [`01_hand-author.md`](./01_hand-author.md) | Net-new content. Naming, versioning, when to package vs. hand-author at user/project scope |
| [`02_depend.md`](./02_depend.md) | Declare a `dependencies` entry. Bare strings vs. objects, semver ranges, cross-marketplace allowlists, tag-based resolution, range intersection, error catalog, `claude plugin prune` |
| [`03_soft-fork.md`](./03_soft-fork.md) | Vendor upstream content into your plugin with a provenance manifest. `.upstream/manifest.json`, the README PROVENANCE table, the three small bin scripts, SessionStart hook, license handling, hybrid soft-fork+depend |

## Mixing patterns within one plugin

A single plugin can soft-fork some skills, write originals for others, and depend on a different plugin for an MCP server it can't replicate. The patterns are not exclusive — they apply at the component level (skill, agent, command, hook, MCP server, theme) within the plugin.

Example: a plugin that soft-forks 5 authoring skills from `plugin-dev`, hand-authors 3 marketplace-specific skills, and depends on a separate `secrets-vault` plugin for a credentials MCP server.

The PROVENANCE table in the README documents which-came-from-where; see [`03_soft-fork.md`](./03_soft-fork.md).

## See also

- [`../05_plugin-anatomy/00_index.md`](../05_plugin-anatomy/00_index.md) — how the plugin is shaped, regardless of composition pattern
- [`../09_versioning-and-publishing/00_index.md`](../09_versioning-and-publishing/00_index.md) — relevant for both `depend` (version constraints) and `soft-fork` (sync schedule)
- [`../16_examples/04_soft-fork-plugin.md`](../16_examples/04_soft-fork-plugin.md) — worked soft-fork plugin
