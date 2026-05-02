# ai-toolkit-dev

Toolkit for authoring Claude Code plugins, marketplaces, and skills — consolidated into three triggerable skills with progressive disclosure.

> [!note]
> **First release scaffolded** on 2026-05-01. All three skills are present with substantive content; soft-fork content is vendored from upstream `claude-plugins-official` at commit `0742692`. License decision still pending before public release.

---

## 1. Overview

This plugin is rarely loaded — most projects don't author plugins — but when it *is* loaded, it should cover the whole authoring lifecycle without cluttering Claude's context the rest of the time. The design:

- **Three top-level skills**, each with a focused trigger description. Once a skill loads, sub-content is read from `references/` on demand (progressive disclosure). Skills are named plainly (`marketplace`, `plugin-dev`, `skill-creator`); they're already namespaced by the plugin (`ai-toolkit-dev:plugin-dev`) so no extra prefix is needed.
- **No agents, no slash commands, no bin wrappers** ship inside the plugin. Plugin authoring is rare enough that those would be context noise. The few project-level operations we do need (upstream drift check) live at the *marketplace* root, not inside the plugin — see [`../../CLAUDE.md`](../../CLAUDE.md) and [`../../scripts/`](../../scripts/).
- **Soft-fork pattern** for everything we vendor: upstream files keep their original layout under `references/topics/` (or as a top-level skill, in the case of `skill-creator`), with provenance recorded in `.upstream/manifest.json` and a sync date table in this README.

### In scope (what this plugin does)

| Concern | How it's covered |
|---|---|
| Marketplace setup, publishing, cross-marketplace references | `marketplace` skill |
| Plugin manifest, capabilities, hooks, MCP, agents, commands, dependencies, lifecycle | `plugin-dev` skill |
| Authoring an individual skill (description tuning, progressive disclosure, scripts) | `skill-creator` skill |

### Out of scope (deliberately not shipped here)

| Not shipped | Why |
|---|---|
| Slash commands | Plugin authoring is rare; commands clutter the `/` menu of every project that loads this plugin |
| Upstream's agents (`agent-creator`, `plugin-validator`, `skill-reviewer`) | We don't need them for the soft-fork. Their useful substance, if any, is folded into the relevant skill's reference material |
| Soft-fork tracking bins (e.g. `pf-upstream-status`) | Soft-fork drift is a **marketplace-maintainer** concern, not something plugin consumers should worry about. Maintainers sync upstream **manually, roughly monthly**; that tooling lives at the marketplace root (`scripts/ai-toolkit-dev-check-upstream`), not on every consumer's `$PATH` |
| The upstream `skill-development` skill from `plugin-dev@claude-plugins-official` | Duplicates `skill-creator`; we drop it to avoid two skill-authoring entry points |

> General-purpose bins that genuinely help plugin authors (scaffolders, test runners, etc.) *can* be added later if there's a real need — the exclusion above is specific to soft-fork tracking, which is a maintainer concern.

---

## 2. Soft forks to maintain

Soft-forked content is maintained manually. The schedule is **roughly monthly** — the maintainer pulls upstream, diffs, and refreshes the vendored copies plus `.upstream/manifest.json`. Plugin consumers don't see this work; they just get whatever was last vendored.

- **Last upstream check:** 2026-05-01
- **Last local modification:** 2026-05-01 (initial vendor + in-house authoring)
- **Vendored at:** upstream HEAD `0742692` (2026-04-29)

### Upstream sources

| Source ID | Repo URL | License |
|---|---|---|
| `claude-plugins-official` | <https://github.com/anthropics/claude-plugins-official> | Apache 2.0 |

(All vendored content currently comes from this single source. Adding another source means appending a row here and a `source` field in `.upstream/manifest.json`.)

### Vendored content

SHAs are **per-file last-modification** (the commit that last touched the upstream path). Drift = "Source commit" differs from "Latest upstream".

| Name | Status | Local path | Source | Source commit | Latest upstream | Last updated |
|---|---|---|---|---|---|---|
| `plugin-structure` | Up to date | `skills/plugin-dev/references/topics/plugin-structure/` | `plugins/plugin-dev/skills/plugin-structure/` | `2438937` | `2438937` (2026-02-05) | 2026-05-01 |
| `agent-development` | Up to date | `skills/plugin-dev/references/topics/agent-development/` | `plugins/plugin-dev/skills/agent-development/` | `ce721c1` | `ce721c1` (2026-04-28) | 2026-05-01 |
| `command-development` | Up to date | `skills/plugin-dev/references/topics/command-development/` | `plugins/plugin-dev/skills/command-development/` | `6b70f99` | `6b70f99` (2026-03-17) | 2026-05-01 |
| `hook-development` | Up to date | `skills/plugin-dev/references/topics/hook-development/` | `plugins/plugin-dev/skills/hook-development/` | `2438937` | `2438937` (2026-02-05) | 2026-05-01 |
| `mcp-integration` | Up to date | `skills/plugin-dev/references/topics/mcp-integration/` | `plugins/plugin-dev/skills/mcp-integration/` | `2438937` | `2438937` (2026-02-05) | 2026-05-01 |
| `plugin-settings` | Up to date | `skills/plugin-dev/references/topics/plugin-settings/` | `plugins/plugin-dev/skills/plugin-settings/` | `2438937` | `2438937` (2026-02-05) | 2026-05-01 |
| `skill-creator` | Up to date | `skills/skill-creator/` | `plugins/skill-creator/skills/skill-creator/` | `2a40fd2` | `2a40fd2` (2026-04-23) | 2026-05-01 |
| ~~`skill-development`~~ | Dropped | — | `plugins/plugin-dev/skills/skill-development/` | — | — | — |

Column meanings:
- **Status** — `Pending sync` (not vendored yet), `Up to date` (matches upstream), `Drift` (upstream has moved), `Dropped` (intentionally not vendored).
- **Source commit** — SHA we vendored at; `—` while pending.
- **Latest upstream** — current upstream HEAD for this path (target of the next sync).
- **Last updated** — local sync date; `—` while pending.

`skill-development` is dropped because `skill-creator` covers the same ground better. See § 4.3 for how the topics table redirects to it.

Per-file provenance is also recorded in `plugins/ai-toolkit-dev/.upstream/manifest.json` once syncing begins; this table and that file are kept in agreement.

---

## 3. `marketplace` skill

In-house skill. Triggers on marketplace authoring, publishing, and cross-marketplace composition.

```
skills/marketplace/
  SKILL.md                       # entry; description triggers on marketplace work
  references/
    setup.md                     # marketplace.json schema, 5 source types, dogfood pattern
    publishing.md                # hosting, ref pinning, claude plugin tag, version resolution
    referencing.md               # extraKnownMarketplaces, allowCrossMarketplaceDependenciesOn, listing external plugins, "merger" patterns
```

Status: **planned**, not yet authored.

---

## 4. `plugin-dev` skill

The umbrella skill for plugin authoring and lifecycle. SKILL.md is small; the substantive content lives in three reference folders that get loaded only when relevant.

```
skills/plugin-dev/
  SKILL.md                       # entry; routes to references/{config, development-cycle, topics}
  references/
    config/                      # § 4.1
    development-cycle/           # § 4.2
    topics/                      # § 4.3
```

The SKILL.md should also cross-link to `skill-creator` so authors who land here for plugin work get steered to the right place when they're really creating a skill.

### 4.1 `references/config/` — in-house

How to wire a plugin's manifest, dependencies, and conventions. **All in-house, not soft-forked.**

| File | Covers |
|---|---|
| `manifest.md` | All `plugin.json` fields incl. modern ones (`lspServers`, `monitors`, `themes`, `outputStyles`, `userConfig`, `channels`, `$schema`, `${CLAUDE_PLUGIN_DATA}`) |
| `dependencies.md` | Array shape, semver ranges, cross-marketplace allowlist, tag-based resolution (`{plugin}--v{x}`), conflicts, `claude plugin prune` |
| `naming.md` | Plugin / skill / command / agent naming conventions |
| `user-config.md` | `userConfig` (modern) vs `.claude/<name>.local.md` (legacy) |
| `persistent-data.md` | Patterns for using `${CLAUDE_PLUGIN_DATA}` — node_modules / venv layout, diff-on-SessionStart, version-bump migration. Cross-links to `development-cycle/lifecycle-and-storage.md` for where the env vars actually resolve on disk |

### 4.2 `references/development-cycle/` — in-house

How to test, iterate on, and ship a plugin. **All in-house, not soft-forked.**

| File | Covers |
|---|---|
| `lifecycle-and-storage.md` | Foundational reference. Install → activate → GC flow; cache layout (`~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`); data dir (`~/.claude/plugins/data/<plugin>/`); settings (`~/.claude/settings.json`'s `enabledPlugins`, `extraKnownMarketplaces`); scope union (Managed > Local > Project > User); hot-swap vs restart split per component type; schema validation at load; multi-plugin `.mcp.json` merging behavior |
| `testing.md` | `--plugin-dir` for fast iteration + headless `claude -p`, subagent A/B, multi-run benchmarking with metric capture. Storage-layout details live in `lifecycle-and-storage.md` |
| `cli.md` | Full `claude plugin` CLI surface, `/plugin` 4-tab UI, env vars |
| `release.md` | Version resolution order, `claude plugin tag`, dogfood release loop |
| `troubleshooting.md` | Verification (clean-install loop) + failure-mode walkthroughs (load issues, stale state, dep resolution, MCP conflicts, etc.). Hot-swap and GC mechanics live in `lifecycle-and-storage.md` |

### 4.3 `references/topics/` — capability authoring (mixed source)

One topic per plugin capability. Six are soft-forked from upstream `plugin-dev`; the rest are in-house, filling gaps upstream doesn't cover (newer manifest fields, the `bin/` surface, and a redirect for skill authoring). Each topic folder keeps its own `SKILL.md` so it can be loaded as standalone reference content; folder name = reference identifier.

| Topic | Source | Status | Description |
|---|---|---|---|
| `plugin-structure` | soft-fork (upstream) | Up to date | Plugin directory layout, `.claude-plugin/plugin.json`, how Claude discovers plugin components |
| `agent-development` | soft-fork (upstream) | Up to date | Authoring `agents/*.md` — frontmatter, tools, when descriptions trigger proactive use |
| `command-development` | soft-fork (upstream) | Up to date | Authoring `commands/*.md` slash commands — frontmatter, argument parsing, exec model |
| `hook-development` | soft-fork (upstream) | Up to date | Hook events, JSON I/O contract, exit codes, prompt-based hooks, env vars (`$CLAUDE_PLUGIN_DATA`, `$CLAUDE_ENV_FILE`) |
| `mcp-integration` | soft-fork (upstream) | Up to date | Bundling MCP servers via `.mcp.json`, transports (stdio/HTTP/SSE/WebSocket), tool naming, `/mcp` UI |
| `plugin-settings` | soft-fork (upstream) | Up to date | Settings file (`.claude/<name>.local.md`, legacy) and how it relates to `userConfig` (modern, see § 4.1) |
| `bin-development` | in-house | Authored | Authoring the `bin/` folder — wrapper script conventions, `$PATH` exposure, `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}` use, when to ship a bin vs a hook script |
| `lsp-integration` | in-house | Authored | The `lspServers` manifest field — bundling a language server, launch flags, common LSP integration pitfalls |
| `monitor-development` | in-house | Authored | The `monitors` manifest field — long-running watchers, lifecycle, output handling |
| `theme-and-output-style` | in-house | Authored | The `themes` and `outputStyles` manifest fields — what they each control, authoring patterns |
| `channel-development` | in-house | Authored | The `channels` manifest field — notification routing surfaces |
| `skill` | redirect | Authored | Stub topic that points readers to the top-level `skill-creator` skill — the canonical entry point for skill authoring (we deliberately don't duplicate that content here) |

> Soft-fork rows are summarised in § 2's vendored-content table; their per-file provenance lives in `.upstream/manifest.json`. In-house rows are tracked only by status here.

---

## 5. `skill-creator` skill

Soft-forked verbatim from `plugins/skill-creator/skills/skill-creator/` in `claude-plugins-official` (Apache 2.0), then extended with our additions where useful. **Top-level skill, not nested under `plugin-dev`** — skill authoring is a frequent enough standalone task to warrant its own trigger.

```
skills/skill-creator/
  SKILL.md                       # vendored, possibly with a local-additions section appended
  references/                    # vendored sub-files
  scripts/                       # vendored helper scripts (init-skill.py, package-skill.py, etc.)
  ...                            # whatever else upstream ships
```

The upstream `plugin-dev`'s `skill-development` skill is dropped (see § 2) — `skill-creator` is the canonical entry point for skill authoring.

---

## Upstream tracking (project-level, not plugin-level)

Drift detection is a *marketplace maintainer* concern, not something every consumer of this plugin needs on `$PATH`. So it lives outside the plugin:

- [`../../scripts/ai-toolkit-dev-check-upstream`](../../scripts/ai-toolkit-dev-check-upstream) — reports drift between vendored `topics/` + `skill-creator/` and the latest upstream commits (per-plugin scoped — if another plugin adopts soft-fork tracking later, it gets its own `<plugin>-check-upstream`)
- [`../../CLAUDE.md`](../../CLAUDE.md) — instructs Claude to run that check when the user asks about upstream status

When a sync is performed: update `.upstream/manifest.json`, bump the "Last our update" rows in § 2, and refresh the "Last upstream check" date.

---

## Installation (when complete)

```
/plugin marketplace add sidhanthapoddar99/sids-plugin-marketplace
/plugin install ai-toolkit-dev@sids-plugin-marketplace
```

## Provenance

Vendored content originates from Anthropic's [`claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) repo (Apache 2.0):
- `plugins/plugin-dev/skills/{plugin-structure, agent-development, command-development, hook-development, mcp-integration, plugin-settings}` → `plugin-dev/references/topics/`
- `plugins/skill-creator/skills/skill-creator` → `skill-creator/`

Per-file upstream commit SHA, vendor date, and any local modifications are tracked in `.upstream/manifest.json` once the soft-fork is performed.

## License

TBD — pending decision before first release. Vendored upstream content remains Apache 2.0; in-house content's license to be set.
