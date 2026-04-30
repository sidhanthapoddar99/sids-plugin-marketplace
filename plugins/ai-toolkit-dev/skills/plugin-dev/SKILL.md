---
name: plugin-dev
description: Use when authoring, configuring, testing, or shipping a Claude Code plugin. Covers the `plugin.json` manifest (all fields including `lspServers`, `monitors`, `themes`, `outputStyles`, `userConfig`, `channels`, `dependencies`, `$schema`), naming conventions, plugin lifecycle and storage (`${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}`, scope union, hot-swap, GC, `--keep-data`), local testing with `--plugin-dir`, headless benchmarking, the `claude plugin` CLI, releases, troubleshooting, and per-capability authoring (agents, commands, hooks, MCP, bins, LSP, monitors, themes, output styles, channels). Triggers on "create plugin", "build a plugin", "scaffold plugin", "plugin manifest", "plugin.json", "${CLAUDE_PLUGIN_ROOT}", "${CLAUDE_PLUGIN_DATA}", "add a hook", "add a command", "add an agent", "add a skill to my plugin", "make a skill", "bundle MCP server", "add LSP", "plugin dependencies", "test my plugin locally", "plugin not loading".
---

# Claude Code plugin development

A **plugin** is a directory with a `.claude-plugin/plugin.json` manifest plus capability folders. Claude Code discovers components by convention; the manifest names the plugin and declares optional fields.

## Quick essentials

### Minimum plugin

```
my-plugin/
└── .claude-plugin/
    └── plugin.json
```

```json
{
  "name": "my-plugin",
  "description": "What this plugin does"
}
```

That's enough to load via `claude --plugin-dir ./my-plugin`. Auto-discovered conventional layout adds capabilities:

```
my-plugin/
├── .claude-plugin/plugin.json
├── commands/         # slash commands (.md per command)
├── agents/           # subagents (.md per agent)
├── skills/           # skills (subdir per skill, with SKILL.md inside)
├── hooks/hooks.json  # event handlers
├── bin/              # CLI scripts (auto-PATHed)
├── .mcp.json         # MCP server defs
└── ...
```

### The two env vars

| Variable | Lifetime | Use for |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | replaced on every plugin update | bundled assets that ship with the plugin |
| `${CLAUDE_PLUGIN_DATA}` | survives plugin updates | mutable state, deps installs, caches |

Both substitute in skill / agent content, hook / monitor commands, and MCP / LSP configs; both are exported as env vars to subprocesses.

### Hot-swap one-liner

`/reload-plugins` picks up edits to skills, commands, agents, MCP, LSP. **Hooks always require a full session restart.** See [`references/development-cycle/lifecycle-and-storage.md`](references/development-cycle/lifecycle-and-storage.md) for details.

### When you're really creating a skill

The top-level [`skill-creator`](../skill-creator/SKILL.md) skill is the canonical entry point for skill authoring (description tuning, progressive disclosure, evals). This `plugin-dev` skill covers plugin-level concerns; for *just* writing a skill, use `skill-creator` instead.

---

## Routing — deeper references

| If the user wants to… | Read |
|---|---|
| Configure the plugin | [`references/config/`](references/config/) — manifest, deps, naming, settings, persistent data |
| Test, iterate on, debug, or ship | [`references/development-cycle/`](references/development-cycle/) — `--plugin-dir`, CLI, releases, troubleshooting, runtime mechanics |
| Author a specific capability | [`references/topics/`](references/topics/) — agents, commands, hooks, MCP, bins, LSP, monitors, themes, channels |

### `references/config/`

| File | When to read |
|---|---|
| [`config/manifest.md`](references/config/manifest.md) | Every `plugin.json` field, including modern ones, plus path-replacement vs additive semantics |
| [`config/dependencies.md`](references/config/dependencies.md) | The `dependencies` array — semver ranges, tag-based resolution, cross-marketplace deps, `claude plugin prune` |
| [`config/naming.md`](references/config/naming.md) | Naming conventions for plugins, skills, commands, agents, bins |
| [`config/user-config.md`](references/config/user-config.md) | The `userConfig` field — schema (NOT JSON Schema), `${user_config.KEY}` substitution, `CLAUDE_PLUGIN_OPTION_<KEY>` env vars |
| [`config/persistent-data.md`](references/config/persistent-data.md) | Patterns for using `${CLAUDE_PLUGIN_DATA}` — node_modules / venv, diff-on-SessionStart, version-bump migration |

### `references/development-cycle/`

| File | When to read |
|---|---|
| [`development-cycle/lifecycle-and-storage.md`](references/development-cycle/lifecycle-and-storage.md) | **Foundational.** Cache layout (`~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`), data dir, scope union (Managed > Local > Project > User), hot-swap matrix, orphan-marking GC, `.mcp.json` merging |
| [`development-cycle/testing.md`](references/development-cycle/testing.md) | `--plugin-dir` for fast iteration, headless `claude -p`, A/B benchmarking |
| [`development-cycle/cli.md`](references/development-cycle/cli.md) | Full `claude plugin` CLI, the `/plugin` 4-tab UI (Discover / Installed / Marketplaces / Errors), built-in slash commands |
| [`development-cycle/release.md`](references/development-cycle/release.md) | Cutting a release — `claude plugin tag`, version resolution, dogfood loop |
| [`development-cycle/troubleshooting.md`](references/development-cycle/troubleshooting.md) | Clean-install verification + failure-mode walkthroughs |

### `references/topics/` — per-capability

Six are vendored verbatim from upstream `claude-plugins-official` (Apache 2.0, see the plugin's README § 2 for provenance). The rest are in-house.

| Topic | Source | When |
|---|---|---|
| [`topics/plugin-structure/`](references/topics/plugin-structure/) | upstream | Big-picture plugin layout and discovery |
| [`topics/agent-development/`](references/topics/agent-development/) | upstream | Authoring `agents/*.md` |
| [`topics/command-development/`](references/topics/command-development/) | upstream | Authoring `commands/*.md` |
| [`topics/hook-development/`](references/topics/hook-development/) | upstream | Hook events, JSON I/O, prompt-based hooks |
| [`topics/mcp-integration/`](references/topics/mcp-integration/) | upstream | Bundling MCP servers via `.mcp.json` |
| [`topics/plugin-settings/`](references/topics/plugin-settings/) | upstream | Legacy `.claude/<name>.local.md` settings |
| [`topics/bin-development/`](references/topics/bin-development/) | in-house | Authoring `bin/` — wrappers, `$PATH`, env vars |
| [`topics/lsp-integration/`](references/topics/lsp-integration/) | in-house | `lspServers` (`extensionToLanguage`, etc.) |
| [`topics/monitor-development/`](references/topics/monitor-development/) | in-house | `monitors` (`when: always`/`on-skill-invoke:<x>`) |
| [`topics/theme-and-output-style/`](references/topics/theme-and-output-style/) | in-house | `themes` (`base` + `overrides`) and `outputStyles` |
| [`topics/channel-development/`](references/topics/channel-development/) | in-house | `channels` — bind MCP servers to messaging surfaces |
| [`topics/skill/`](references/topics/skill/) | redirect | **Stub — go to the top-level [`skill-creator`](../skill-creator/SKILL.md) skill instead** |

## Load order recommendation

For a brand-new author, fastest path to a working mental model:
1. The "Quick essentials" section above (already loaded if you're reading this)
2. [`topics/plugin-structure/SKILL.md`](references/topics/plugin-structure/SKILL.md) — directory layout + discovery (vendored upstream content)
3. [`config/manifest.md`](references/config/manifest.md) — every `plugin.json` field
4. [`development-cycle/lifecycle-and-storage.md`](references/development-cycle/lifecycle-and-storage.md) — what happens at runtime
5. The specific capability topic the user is authoring
