# Composition decisions: depend / soft-fork / hand-author

Quick decision reference for "should this plugin build on top of an existing one, vendor its content, or stand alone?" Three patterns, picked per-component (a single plugin can mix all three).

## The decision table

| Situation | Hand-author | Depend | Soft-fork |
|---|---|---|---|
| Capability doesn't exist anywhere upstream | ✅ | ❌ | ❌ |
| Upstream is fresh and well-maintained, you only need to *reference* it | ⚠️ duplicates effort | ✅ | ⚠️ maintenance treadmill |
| Upstream is stale or wrong, you'd rewrite anyway | ⚠️ ignores prior art | ❌ stuck with stale | ✅ |
| You want everything in *your* plugin's namespace | ✅ but no baseline | ❌ upstream's namespace | ✅ |
| You want to edit upstream descriptions for triggering control | ✅ | ❌ can't edit | ✅ |
| Single install, single namespace for users | ✅ | ❌ two installs | ✅ |
| You'd contribute fixes back upstream | n/a | ✅ natural PR target | ❌ harder to PR |
| Cross-marketplace allowlist friction | ✅ none | ❌ requires opt-in | ✅ none |
| Upstream evolves fast and you'd rather inherit changes | ❌ | ✅ free updates | ❌ manual sync |

## The three patterns at a glance

**Hand-author** — Net-new content with no upstream relationship. You write everything from scratch. Use when the capability doesn't exist or is domain-specific to you.

**Depend** — Declare a `dependencies` entry in your `plugin.json`; both plugins coexist at install time. You cooperate by *referencing* upstream's skills/agents/commands from your own (your skill says "delegate to the X agent from `upstream-plugin`"). See [`config/dependencies.md`](config/dependencies.md). Cross-marketplace deps require both sides to opt-in via `allowCrossMarketplaceDependenciesOn`.

**Soft-fork** — Vendor upstream content into your plugin (so it lives in your namespace, ships in your install) with a `.upstream/manifest.json` provenance file recording where each piece came from. Tooling tells you when upstream changes; you decide when to merge. Use when upstream is stale, you'd rewrite anyway, or one-namespace-for-users matters.

## Mixing patterns

A single plugin can use all three at once — soft-fork some skills, write originals for others, depend on a different plugin for an MCP server you can't replicate. The composition primitive at runtime is *the whole plugin* — you can't import a single skill from another plugin's namespace. Depending pulls in the whole upstream plugin alongside yours; soft-forking copies content into your plugin's own namespace.

## Default lean

When the choice isn't obvious, lean toward:

1. **Hand-author** for net-new, domain-specific things.
2. **Depend** for "I just need X to be installed alongside mine" — it's the lightest commitment.
3. **Soft-fork** for "I need upstream's content but I'm going to rewrite half of it" — accept the maintenance treadmill knowingly.

## See also

- [`config/dependencies.md`](config/dependencies.md) — `dependencies` array, semver, tag resolution, cross-marketplace
- Marketplace reference docs (full treatment of each pattern, with worked examples): <https://github.com/sidhanthapoddar99/sids-plugin-marketplace/tree/main/Documentation/ClaudePlugin/08_composition-patterns>
- Official: [Plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies) — semver, tag resolution, cross-marketplace allowlist
