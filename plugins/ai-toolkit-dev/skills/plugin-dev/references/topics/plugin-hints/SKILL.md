---
name: plugin-hints
description: Use when an external CLI / dev tool wants to recommend a Claude Code marketplace and plugin set to its users via the `/plugin-hints` mechanism. Brief — covers the recommendation channel from a plugin author's side. Triggers on "plugin hints", "/plugin-hints", "recommend plugin from CLI", "ship plugin recommendation with my tool".
---

# `/plugin-hints` — recommend plugins from a non-Claude-Code tool

A way for an external CLI or dev tool to suggest specific Claude Code plugins to its users. The mechanism: your CLI emits hints (a small JSON blob, typically printed at startup or on first run), and Claude Code surfaces them when the user enters a session. The user gets a one-step prompt to add the marketplace and install the recommended plugins.

This is the right channel when **your tool benefits from a Claude Code plugin** — e.g. a deploy CLI that pairs with a deploy-plugin, or a database tool that pairs with an MCP server published as a plugin. It's lighter than asking users to read your README.

## Setup pattern

1. **Publish your plugin to a marketplace** (this one or your own). It needs a stable `<plugin>@<marketplace>` identifier.
2. **Have your CLI emit the hint** when appropriate (first run, `--help`, or whenever you'd otherwise tell the user "by the way, install X"). Format and exact emission channel are documented in the deeper reference.
3. **Test the round-trip** by invoking your CLI from inside a Claude Code session and confirming the hint surfaces.

## Authoring guidance

Keep recommendations narrow:

- **One plugin, one situation.** Don't try to recommend three plugins at once.
- **Make the install reversible.** A user who installs your hinted plugin should be able to `/plugin uninstall` cleanly without leftover state.
- **Don't hint for every invocation.** First-run / on-demand only — repeated hints train users to dismiss them.

## Deep reference

Full mechanics — the JSON shape your CLI emits, how Claude Code consumes it, the user-facing prompt flow, and edge cases — live at the marketplace's reference docs: <https://github.com/sidhanthapoddar99/sids-plugin-marketplace/blob/main/Documentation/ClaudePlugin/14_distribution/02_plugin-hints.md>.

## See also

- [`../../../../marketplace/SKILL.md`](../../../../marketplace/SKILL.md) — publishing the plugin you'll be hinting at
- Marketplace's broader distribution docs (submission portals, auto-update controls): <https://github.com/sidhanthapoddar99/sids-plugin-marketplace/tree/main/Documentation/ClaudePlugin/14_distribution>
