---
name: marketplace
description: Use when authoring, publishing, or composing Claude Code plugin marketplaces. Covers `marketplace.json` schema and field reference, the five plugin source types (relative path, github, url, git-subdir, npm), `category`, `tags`, `keywords`, `strict` mode, hosting and ref/sha pinning, version resolution, release channels, listing external plugins as a catalogue or plugin catalog, recommending marketplaces via `extraKnownMarketplaces`, and cross-marketplace dependencies via `allowCrossMarketplaceDependenciesOn`. Triggers on "create marketplace", "publish marketplace", "register a marketplace", "host a marketplace", "marketplace.json", "marketplace structure", "add plugin to marketplace", "share plugins with my team", "list someone else's plugin in my marketplace", "combine multiple marketplaces", "cross-marketplace dependency", "release channels", "stable vs latest plugin".
---

# Claude Code marketplace authoring

A **marketplace** is a catalogue of plugins. It's a single JSON file (`.claude-plugin/marketplace.json`) at the root of a git repo, served as a static URL, or kept on a local path. Users add the marketplace once; afterwards every plugin in it is installable by `name@marketplace`.

## Quick mental model

- A marketplace **owns the index**, not the plugins. Most marketplaces point at plugins hosted elsewhere (GitHub repos, git URLs, npm packages).
- Plugins are referenced by `name`. The **`source`** field tells Claude Code how to fetch each one. Five source forms exist (string, `github`, `url`, `git-subdir`, `npm`).
- All git-based source types (`github`, `url`, `git-subdir`) share the same pinning fields: `ref?` (branch/tag) and `sha?` (exact commit).
- A marketplace can list **plugins it doesn't host** (catalogue) and **plugins from other marketplaces** can be depended on if both sides opt in via `allowCrossMarketplaceDependenciesOn`.
- A marketplace can dogfood itself: list its own plugins via relative-path sources (`"./plugins/<name>"`).

## When to use which reference

| If the user wants to… | Read |
|---|---|
| Look up a field name, source-type schema, or `strict`/version semantics | [`references/schema.md`](references/schema.md) |
| Build a new marketplace from scratch — pick a layout, write the file, validate | [`references/setup.md`](references/setup.md) |
| Ship a marketplace — host it, pin plugin versions, set up release channels, manage cache | [`references/publishing.md`](references/publishing.md) |
| Compose marketplaces — list third-party plugins, recommend other marketplaces, allow cross-marketplace deps, build a "merger" marketplace | [`references/referencing.md`](references/referencing.md) |

## Worked examples

Full, valid `marketplace.json` files in [`examples/`](examples/) — copy and adapt:

| File | Pattern |
|---|---|
| [`minimal.json`](examples/minimal.json) | Smallest valid marketplace |
| [`dogfood.json`](examples/dogfood.json) | Self-hosted, plugins in same repo via `"./plugins/<name>"` sources |
| [`catalogue.json`](examples/catalogue.json) | Third-party listings; one of every source type |
| [`release-channels.json`](examples/release-channels.json) | Two marketplaces pointing at stable vs latest refs |
| [`cross-marketplace-deps.json`](examples/cross-marketplace-deps.json) | `allowCrossMarketplaceDependenciesOn` opt-in |
| [`team-recommendations.json`](examples/team-recommendations.json) | `.claude/settings.json` snippet (not a marketplace file) showing `extraKnownMarketplaces` |
| [`inline-plugin.json`](examples/inline-plugin.json) | Marketplace entry that declares components inline (`strict: false`) |

## When NOT to use this skill

- Authoring an individual plugin's `plugin.json` → use the `plugin-dev` skill.
- Authoring an individual skill → use the `skill-creator` skill.
- Resolving "which plugin version do I get?" from the *consumer* side — `plugin-dev` covers that. This skill covers the publisher side.
