---
name: plugin-dev
description: Use when authoring, configuring, testing, or shipping Claude Code plugins. Covers the `plugin.json` manifest (all fields including modern ones — `lspServers`, `monitors`, `themes`, `outputStyles`, `userConfig`, `channels`, `dependencies`, `$schema`), naming conventions, plugin lifecycle and storage (cache layout, `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}`, scope union, hot-swap, GC), local testing with `--plugin-dir`, headless benchmarking, the `claude plugin` CLI, releases and version resolution, troubleshooting, and per-capability authoring (agents, commands, hooks, MCP, bins, LSP, monitors, themes, output styles, channels). Triggers on "create plugin", "scaffold plugin", "plugin.json", "${CLAUDE_PLUGIN_ROOT}", "${CLAUDE_PLUGIN_DATA}", "add a hook", "add a command", "add an agent", "bundle MCP server", "add LSP", "plugin dependencies", "test my plugin locally", "plugin not loading", "plugin cache", "claude plugin install".
---

# Claude Code plugin development

A **plugin** is a directory with a `.claude-plugin/plugin.json` manifest plus capability folders (`commands/`, `agents/`, `skills/`, `hooks/`, `bin/`, `.mcp.json`, etc.). Claude Code discovers components by convention; the manifest names the plugin, declares optional fields, and points at non-standard layouts when needed.

This is an **umbrella skill** — the SKILL.md you're reading is small, and the substantive content lives under `references/`. Load the right reference for the task.

## Routing

| If the user wants to… | Read |
|---|---|
| Configure the plugin — manifest fields, dependencies, naming, settings, persistent data | [`references/config/`](references/config/) — see the file table below |
| Test, iterate on, debug, or ship a plugin — workflow, CLI, releases, runtime mechanics | [`references/development-cycle/`](references/development-cycle/) — see the file table below |
| Author a specific capability — agents, commands, hooks, MCP, bins, LSP, etc. | [`references/topics/`](references/topics/) — see the routing table below |
| Author a *skill* specifically (description tuning, progressive disclosure, evals) | The top-level `skill-creator` skill — **not** this one. `references/topics/skill/SKILL.md` redirects there |

### `references/config/` — manifest and naming

| File | When to read |
|---|---|
| [`config/manifest.md`](references/config/manifest.md) | Authoring `plugin.json` — every field, including modern ones (`lspServers`, `monitors`, `themes`, `outputStyles`, `userConfig`, `channels`, `dependencies`, `$schema`) and the `${CLAUDE_PLUGIN_DATA}` convention |
| [`config/dependencies.md`](references/config/dependencies.md) | Adding `dependencies` to a plugin — array shape, semver ranges, tag-based resolution, conflicts, `claude plugin prune` |
| [`config/naming.md`](references/config/naming.md) | Naming conventions for plugins, skills, commands, agents — what's enforced vs idiomatic |
| [`config/user-config.md`](references/config/user-config.md) | Plugin-author settings: the `userConfig` field (modern) and `.claude/<name>.local.md` (legacy) |
| [`config/persistent-data.md`](references/config/persistent-data.md) | Patterns for using `${CLAUDE_PLUGIN_DATA}` — node_modules / venv layout, diff-on-SessionStart, version-bump migration. Cross-links to `development-cycle/lifecycle-and-storage.md` for path resolution |

### `references/development-cycle/` — testing, runtime, shipping

| File | When to read |
|---|---|
| [`development-cycle/lifecycle-and-storage.md`](references/development-cycle/lifecycle-and-storage.md) | **Foundational reference.** Install → activate → GC flow; cache layout; data dir; settings file; scope union; hot-swap mechanics; schema validation at load; multi-plugin `.mcp.json` merging |
| [`development-cycle/testing.md`](references/development-cycle/testing.md) | `--plugin-dir` for fast iteration; headless `claude -p`; subagent A/B and benchmarking |
| [`development-cycle/cli.md`](references/development-cycle/cli.md) | The full `claude plugin` CLI surface and the `/plugin` 4-tab UI |
| [`development-cycle/release.md`](references/development-cycle/release.md) | Cutting a release — version resolution order, `claude plugin tag`, dogfood loop |
| [`development-cycle/troubleshooting.md`](references/development-cycle/troubleshooting.md) | Verification (clean-install loop) + failure-mode walkthroughs (load issues, stale state, dep resolution, MCP collisions, etc.) |

### `references/topics/` — capability authoring

Each capability has its own folder under `topics/<capability>/SKILL.md`. Six are vendored verbatim from upstream `claude-plugins-official` (Apache 2.0, see the plugin's README § 2 for provenance); the rest are in-house, filling gaps upstream doesn't cover yet.

| Topic | Source | When to read |
|---|---|---|
| `topics/plugin-structure/` | upstream | Big-picture plugin layout and discovery |
| `topics/agent-development/` | upstream | Authoring `agents/*.md` |
| `topics/command-development/` | upstream | Authoring `commands/*.md` slash commands |
| `topics/hook-development/` | upstream | Hook events, JSON I/O, prompt-based hooks |
| `topics/mcp-integration/` | upstream | Bundling MCP servers via `.mcp.json` |
| `topics/plugin-settings/` | upstream | Settings file (legacy) and `userConfig` interplay |
| `topics/bin-development/` | in-house | Authoring the `bin/` folder — wrappers, `$PATH`, env vars |
| `topics/lsp-integration/` | in-house | The `lspServers` manifest field |
| `topics/monitor-development/` | in-house | The `monitors` manifest field |
| `topics/theme-and-output-style/` | in-house | The `themes` and `outputStyles` manifest fields |
| `topics/channel-development/` | in-house | The `channels` manifest field |
| `topics/skill/` | redirect | **Don't read this — go to the top-level `skill-creator` skill instead** |

## Load order recommendation

For a brand-new author, the fastest path to a working mental model is:
1. `topics/plugin-structure/SKILL.md` — directory layout + discovery
2. `config/manifest.md` — all manifest fields with current names
3. `development-cycle/lifecycle-and-storage.md` — what happens at runtime
4. The specific capability topic the user is authoring

For an experienced author hitting a specific question, route directly via the tables above.
