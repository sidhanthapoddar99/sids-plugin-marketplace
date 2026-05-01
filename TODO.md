# TODO — Documentation rewrite + plugin additions

Two streams of work, agreed on after the audit-driven revision pass.

- **Plugin documentation** (`Documentation/ClaudePlugin/`) — a comprehensive, two-level "what exists / what's possible" reference. NOT a how-to guide.
- **Settings documentation** (`Documentation/ClaudeSettings/`) — small (6 files) reference for Claude Code's user-settings surface (the boundary that complements plugins).
- **Plugin additions** (`plugins/ai-toolkit-dev/`) — minimal, task-oriented additions for things that genuinely belong inside the plugin. Most ecosystem knowledge stays in docs only.

---

## A. Documentation folder structure (`Documentation/ClaudePlugin/`)

Two-level structure. Each top-level item is either `XX_name.md` (single self-contained chapter) or `XX_name/` (folder with sub-pages and a `00_index.md`).

```
Documentation/ClaudePlugin/
├── 00_index.md                                    ← master TOC, reading order, what's where

├── 01_overview.md                                 ← the layered architecture in one page
│                                                    (model layer / runtime layer / packaging layer)

├── 02_mental-model/                               ← a careful walk through the conceptual split
│   ├── 00_index.md
│   ├── 01_what-the-model-sees.md                  ← skills, commands, agents, MCP tools, bin in $PATH
│   ├── 02_what-the-runtime-sees.md                ← cache, settings.json booleans, hooks, PATH augmentation
│   ├── 03_packaging-vs-capabilities.md            ← plugin = bundling, model only sees capabilities
│   └── 04_naming-and-namespacing.md               ← collision rules, prefix conventions, plugin@marketplace IDs

├── 03_storage-and-scope/
│   ├── 00_index.md
│   ├── 01_cache-layout.md                         ← ~/.claude/plugins/cache/<mkt>/<plugin>/<version>/
│   ├── 02_data-dir.md                             ← ~/.claude/plugins/data/<plugin-id>/, slugification
│   ├── 03_scope-union.md                          ← Managed > Local > Project > User precedence
│   ├── 04_settings-files.md                       ← settings.json, settings.local.json, managed
│   └── 05_env-vars.md                             ← CLAUDE_PLUGIN_ROOT/DATA, PROJECT_DIR, OPTION_<KEY>

├── 04_marketplaces/
│   ├── 00_index.md
│   ├── 01_anatomy.md                              ← marketplace.json fields, owner, plugins array
│   ├── 02_source-types.md                         ← all 5 source forms with examples
│   ├── 03_ref-and-sha-pinning.md                  ← #ref vs sha, marketplace-vs-plugin pin
│   ├── 04_release-channels.md                     ← stable / latest pattern
│   ├── 05_catalogue-pattern.md                    ← listing third-party plugins
│   ├── 06_extra-known-marketplaces.md             ← settings.json key, team distribution
│   ├── 07_managed-restrictions.md                 ← strictKnownMarketplaces, allowlist
│   └── 08_cross-marketplace-deps.md               ← allowCrossMarketplaceDependenciesOn

├── 05_plugin-anatomy/
│   ├── 00_index.md
│   ├── 01_directory-layout.md                     ← every conventional folder
│   ├── 02_manifest-fields.md                      ← exhaustive plugin.json reference
│   ├── 03_path-replacement-vs-additive.md         ← which fields replace, which supplement
│   ├── 04_user-config.md                          ← types, sensitive, multiple, min/max, substitution
│   ├── 05_plugin-shipped-settings.md              ← root-level settings.json (agent, subagentStatusLine)
│   └── 06_disable-model-invocation.md             ← frontmatter flag for user-only triggering

├── 06_capabilities/                               ← every capability surface, what it IS
│   ├── 00_index.md                                ← decision table: which capability for which goal
│   ├── 01_skills.md
│   ├── 02_slash-commands.md
│   ├── 03_subagents.md
│   ├── 04_hooks.md
│   ├── 05_mcp-servers.md
│   ├── 06_lsp-servers.md
│   ├── 07_monitors.md
│   ├── 08_channels.md
│   ├── 09_themes.md
│   ├── 10_output-styles.md
│   └── 11_bin-wrappers.md

├── 07_lifecycle-and-runtime/
│   ├── 00_index.md
│   ├── 01_install-flow.md                         ← resolve → fetch → validate → activate → load
│   ├── 02_activation-and-loading.md               ← when components register, in what order
│   ├── 03_hot-swap-matrix.md                      ← /reload-plugins behavior per component type
│   ├── 04_updates.md                              ← /plugin update mechanics
│   ├── 05_garbage-collection.md                   ← orphan-marking, 7-day window
│   ├── 06_schema-validation.md                    ← when plugin.json is checked
│   └── 07_multi-plugin-merging.md                 ← .mcp.json collisions, name conflicts

├── 08_composition-patterns/
│   ├── 00_index.md                                ← decision matrix: depend / soft-fork / hand-author
│   ├── 01_hand-author.md
│   ├── 02_depend.md                               ← deep dive on dependencies system
│   └── 03_soft-fork.md                            ← deep dive on vendor-with-provenance pattern

├── 09_versioning-and-publishing/
│   ├── 00_index.md
│   ├── 01_semver.md
│   ├── 02_tagging-convention.md                   ← <plugin>--v<X.Y.Z>
│   ├── 03_version-resolution.md                   ← plugin.json vs marketplace entry, range intersection
│   ├── 04_release-loop.md                         ← bump → tag → push → marketplace update
│   └── 05_pre-releases-and-hotfixes.md

├── 10_trust-and-security.md                       ← unsandboxed model, path-traversal limit, managed allowlist

├── 11_testing-and-iteration/
│   ├── 00_index.md
│   ├── 01_plugin-dir.md                           ← --plugin-dir for fast iteration
│   ├── 02_headless.md                             ← claude -p, --json envelope
│   ├── 03_benchmarking.md                         ← multi-trial A/B
│   └── 04_clean-install-loop.md                   ← preemptive verification

├── 12_cli-and-ui/
│   ├── 00_index.md
│   ├── 01_claude-plugin-cli.md                    ← every subcommand and flag
│   ├── 02_built-in-slash-commands.md              ← /plugin, /reload, /hooks, /mcp, /agents, /theme, /doctor
│   └── 03_plugin-ui.md                            ← Discover / Installed / Marketplaces / Errors tabs

├── 13_uninstall-and-cleanup.md                    ← uninstall, cache wipe, --keep-data, --prune

├── 14_distribution/
│   ├── 00_index.md
│   ├── 01_official-marketplace-submission.md      ← claude.ai forms
│   ├── 02_plugin-hints.md                         ← /plugin-hints CLI integration
│   └── 03_auto-update-controls.md                 ← DISABLE_AUTOUPDATER, FORCE_AUTOUPDATE_PLUGINS

├── 15_reference/                                  ← nomenclature catch-all
│   ├── 00_index.md
│   ├── 01_env-vars-cheatsheet.md
│   ├── 02_settings-keys.md
│   ├── 03_frontmatter-flags.md                    ← disable-model-invocation, etc.
│   └── 04_legacy-and-migration.md                 ← .local.md pattern, flat commands/, migration paths

└── 16_examples/
    ├── 00_index.md
    ├── 01_minimal-plugin.md                       ← worked, runnable
    ├── 02_dogfood-marketplace.md
    ├── 03_catalogue-marketplace.md
    └── 04_soft-fork-plugin.md
```

**Scope:** 16 top-level chapters, ~85 files total.

**Tone:** comprehensive scope of "what exists / what's possible" — NOT a how-to. The plugin (`ai-toolkit-dev`) handles the how-to, task-oriented side.

---

## A2. Settings documentation folder structure (`Documentation/ClaudeSettings/`)

Companion doc set, small. Covers Claude Code's user-settings surface — the things plugins CANNOT ship. Defines the boundary that complements `Documentation/ClaudePlugin/`.

```
Documentation/ClaudeSettings/
├── 00_index.md                                    ← scope, who it's for, the plugin/settings boundary
├── 01_settings-files-and-precedence.md            ← managed / user / project / local; settings.json vs settings.local.json
├── 02_status-line.md                              ← main statusLine config (NOT plugin-shippable; subagentStatusLine IS)
├── 03_permissions-and-keybindings.md              ← allowedTools, denylist, keybindings file
├── 04_environment-variables.md                    ← DISABLE_AUTOUPDATER, FORCE_AUTOUPDATE_PLUGINS, plugin cache overrides
└── 05_plugin-related-settings.md                  ← enabledPlugins, extraKnownMarketplaces, strictKnownMarketplaces, pluginConfigs
```

**Scope:** 6 files. Each ~50–150 lines. Reference style.

---

## B. Plugin additions (minimal, task-oriented)

Just the things that genuinely belong in plugin-as-a-skill. The rest stays in docs.

### B1. Add `references/development-cycle/uninstalling.md`

Currently scattered across `cli.md` and `troubleshooting.md`'s clean-install loop.

- The cache-survives-uninstall wrinkle
- Wipe procedures (per-plugin, per-marketplace, nuclear)
- `--keep-data` vs default
- `/plugin marketplace remove` cascade
- When NOT to wipe

### B2. Add `references/topics/plugin-hints/SKILL.md` (in-house topic)

Brief — not a deep dive (deep dive lives in docs `14_distribution/02_plugin-hints.md`).

- The `/plugin-hints` mechanism
- How an external CLI emits hints Claude Code picks up
- Setup pattern (one paragraph) + link to docs

### B3. Add `disable-model-invocation` to plugin

- Add a section to `config/manifest.md` under "Frontmatter flags" (skill / command frontmatter)
- Mention in `plugin-dev/SKILL.md` Quick essentials where relevant

### B4. Expand plugin-shipped root-level `settings.json` in `config/manifest.md`

Currently a one-liner; make it a proper section:

- The two supported keys (`agent`, `subagentStatusLine`)
- Priority over `settings` field in `plugin.json`
- One worked example

### B5. Add scope-decision callout

- Add to `plugin-dev/SKILL.md` Quick essentials: "Where to write?" decision note
- Tells the model: when scaffolding a skill / agent / command, ask whether the user wants user / project / local scope, or to package as a plugin
- Brief explainer of each + cross-link to docs for full decision matrix

### B6. Add `references/composition-decisions.md` (brief reference, not a teaching doc)

- Just the depend / soft-fork / hand-author decision table
- Enough so the model can answer "should I depend or soft-fork?" without reading docs
- Cross-link to docs `08_composition-patterns/` for the deep treatment

---

## C. Things explicitly NOT in plugin (docs only)

Per the discussion:

- **Soft-fork pattern teaching** → docs only (`08_composition-patterns/03_soft-fork.md`)
- **"What the model actually sees" framing** → docs only (`02_mental-model/`)
- **Capability decision overview** → docs only (`06_capabilities/00_index.md`)
- **Trust model** → docs only (`10_trust-and-security.md`)
- **Submission process** → docs only (`14_distribution/01_official-marketplace-submission.md`)
- **"Pick the right scope" full guide** → docs only (referenced from plugin via the B5 callout)
- **Ecosystem mental model deep dive** → docs only (`02_mental-model/`)

---

## D. Execution plan (proposed)

1. **Phase 1: docs** — spawn 6 parallel agents, each owning a contiguous chunk of the docs structure. Each agent writes substantive, accurate content using `docs/Claude Plugins/` (existing user-authored, fact-checked content), the vendored upstream skills under `plugins/ai-toolkit-dev/skills/`, and `07_reference.md` as ground truth.

2. **Phase 2: plugin additions** — once docs are settled, add the 6 plugin items (B1–B6) referencing the new docs.

3. **Phase 3: cross-link sweep** — verify all cross-links between docs and plugin resolve.

### Phase 1 agent split (7 parallel writers)

| Agent | Chapters owned | Files |
|---|---|---|
| **Agent 1** | `00_index.md` + `01_overview.md` + `02_mental-model/` + `10_trust-and-security.md` | 8 |
| **Agent 2** | `03_storage-and-scope/` + `07_lifecycle-and-runtime/` + `13_uninstall-and-cleanup.md` | 15 |
| **Agent 3** | `04_marketplaces/` + `09_versioning-and-publishing/` | 15 |
| **Agent 4** | `05_plugin-anatomy/` + `08_composition-patterns/` + `16_examples/` | 17 |
| **Agent 5** | `06_capabilities/` | 12 |
| **Agent 6** | `11_testing-and-iteration/` + `12_cli-and-ui/` + `14_distribution/` + `15_reference/` | 18 |
| **Agent 7** | `Documentation/ClaudeSettings/` (entire folder) | 6 |

**Total:** 91 files / 7 agents ≈ 13 files each.

Each agent gets:
- Their assigned files list with one-line description per file
- Full TODO.md folder structure (so they know where cross-link targets live)
- Pointers to ground-truth sources (`docs/Claude Plugins/`, vendored upstream skills, `07_reference.md`)
- The plugin context (`plugins/ai-toolkit-dev/`) as task-oriented complement
- Tone guidance (comprehensive reference, not how-to)
- Cross-link conventions (relative paths between chapters)
- Word-budget guidance (index pages 30–50 lines; sub-pages 80–200)
- "Don't invent" rule (use ground truth, flag uncertainty)

### Phase 1.5: verification agent (launches AFTER all 7 complete)

| Agent | Job |
|---|---|
| **Agent 8 (verification)** | Read every file written by Agents 1–7. Cross-check factual claims against ground truth. Flag invented API surface, contradictions between chapters, broken cross-links, missing index entries. Report findings as a punch list. Does NOT fix — only verifies and reports. |

---

## Open questions before starting

1. Are 16 top-level chapters the right granularity, or should some merge? (e.g. could fold `lifecycle-and-runtime` into `storage-and-scope`)
2. The plugin-side B6 (`composition-decisions.md`) — separate file or section in `plugin-dev/SKILL.md`?
3. Word budget for docs — terse like `07_reference.md` (one paragraph per term) or substantive like `02_storage-and-scope.md` (~150 lines)? Probably mix: index pages terse, sub-pages substantive.
4. Should the existing `docs/Claude Plugins/` stay (as a more concise version) or be deleted once `Documentation/ClaudePlugin/` is complete?
