# Claude Code Plugin Ecosystem — Reference

A comprehensive reference for the Claude Code plugin ecosystem. Answers "what exists" and "what's possible" — not a tutorial. For task-oriented authoring guidance, see the companion `ai-toolkit-dev` plugin.

The companion doc set [Documentation/ClaudeSettings/](../ClaudeSettings/00_index.md) covers Claude Code-level settings (status line, permissions, keybindings, env vars, plugin-related keys like `enabledPlugins` and `extraKnownMarketplaces`).

## Reading order

**New readers** — start at `01_overview.md`, then chapter `02_mental-model/`. Skim `03_storage-and-scope/` and `06_capabilities/00_index.md`. Other chapters are reference, not narrative.

**Plugin authors** — read `05_plugin-anatomy/`, `06_capabilities/`, `08_composition-patterns/`, then `09_versioning-and-publishing/`. Use `15_reference/` as a cheat-sheet.

**Marketplace operators** — `04_marketplaces/`, `09_versioning-and-publishing/`, `14_distribution/`.

**Claude Code admins / managed users** — `04_marketplaces/07_managed-restrictions.md`, `10_trust-and-security.md`, `15_reference/02_settings-keys.md`.

## Chapter index

| # | Chapter | Topic |
|---|---|---|
| 01 | [Overview](./01_overview.md) | Three-layer architecture: model / runtime / packaging |
| 02 | [Mental Model](./02_mental-model/00_index.md) | What the model sees vs. what the runtime sees vs. what the plugin packages |
| 03 | [Storage and Scope](./03_storage-and-scope/00_index.md) | Cache layout, the data dir, scope union, settings files, env vars |
| 04 | [Marketplaces](./04_marketplaces/00_index.md) | Anatomy, source types, ref/sha pinning, channels, catalogues, managed restrictions, cross-marketplace deps |
| 05 | [Plugin Anatomy](./05_plugin-anatomy/00_index.md) | Directory layout, manifest fields, path replacement vs. additive, user config, plugin-shipped settings |
| 06 | [Capabilities](./06_capabilities/00_index.md) | Skills, slash commands, subagents, hooks, MCP, LSP, monitors, channels, themes, output styles, bin wrappers |
| 07 | [Lifecycle and Runtime](./07_lifecycle-and-runtime/00_index.md) | Install flow, activation, hot-swap matrix, updates, GC, schema validation, multi-plugin merging |
| 08 | [Composition Patterns](./08_composition-patterns/00_index.md) | Hand-author / depend / soft-fork |
| 09 | [Versioning and Publishing](./09_versioning-and-publishing/00_index.md) | Semver, tag convention, version resolution, release loop, pre-releases |
| 10 | [Trust and Security](./10_trust-and-security.md) | Unsandboxed execution model, path-traversal limit, managed restrictions overview |
| 11 | [Testing and Iteration](./11_testing-and-iteration/00_index.md) | `--plugin-dir`, headless mode, benchmarking, clean-install loop |
| 12 | [CLI and UI](./12_cli-and-ui/00_index.md) | `claude plugin` CLI, built-in slash commands, the `/plugin` UI |
| 13 | [Uninstall and Cleanup](./13_uninstall-and-cleanup.md) | Disable / uninstall / cache lifetime |
| 14 | [Distribution](./14_distribution/00_index.md) | Official-marketplace submission, plugin hints, auto-update controls |
| 15 | [Reference](./15_reference/00_index.md) | Env vars, settings keys, frontmatter flags, legacy/migration |
| 16 | [Examples](./16_examples/00_index.md) | Minimal plugin, dogfood marketplace, catalogue, soft-fork |

## Cross-link conventions

Every chapter has a `00_index.md` that introduces the chapter and lists its sub-pages. Cross-links use relative paths from the linking file. See `02_mental-model/01_what-the-model-sees.md` for examples of intra-chapter and cross-chapter links.

## Authority

Where this doc disagrees with the [official Claude Code documentation](https://code.claude.com/docs/en/plugins-reference), the official docs win. The plugin-side how-to surface (task-oriented authoring guidance) lives in [`plugins/ai-toolkit-dev/skills/`](../../plugins/ai-toolkit-dev/skills/) — `marketplace/`, `plugin-dev/`, and `skill-creator/` — which this reference set links to where appropriate.
