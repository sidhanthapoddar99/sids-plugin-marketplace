# TODO — Documentation rewrite + plugin additions

Two streams of work, agreed on after the audit-driven revision pass.

- **Plugin documentation** (`Documentation/ClaudePlugin/`) — comprehensive "what exists / what's possible" reference. NOT a how-to guide. **DONE.**
- **Settings documentation** (`Documentation/ClaudeSettings/`) — small (6 files) reference for Claude Code's user-settings surface. **DONE.**
- **Plugin additions** (`plugins/ai-toolkit-dev/`) — minimal task-oriented additions that genuinely belong inside the plugin. **PENDING (B1–B6 below).**

---

## Status

| Phase | What | Status |
|---|---|---|
| Phase 1 | 7 parallel agents write `Documentation/ClaudePlugin/` (16 chapters, ~85 files) and `Documentation/ClaudeSettings/` (6 files) | ✅ Done |
| Phase 1.5a | Agent 8 — sanity verification (factual claims vs ground truth) | ✅ Done. Punch list returned. |
| Phase 1.5b | Agent 9 — topic-coverage audit (does new docs cover everything in old `docs/Claude Plugins/`?) | ✅ Done. Verdict: safe to delete after one `file://` rejection note. |
| Phase 1.5c | Apply fixes from Agent 8 punch list + bonus `commit`/`sha` synonym note | ✅ Done. 11 findings + bonus + stale-reference sweep all addressed. |
| Phase 1.5d | Delete `docs/Claude Plugins/` | ✅ Done. |
| Phase 1.5e | Agent 11 — plugin-content audit (`plugins/ai-toolkit-dev/skills/`) | ✅ Done. 9 CRITICAL + 10 HIGH + MEDIUM/LOW returned. |
| Phase 1.5f | Apply fixes from Agent 11 punch list | ✅ Done. All invented CLI surface (`bump`, `info`, `path`, `scope`, `--purge`, `--version`, `--verbose`, `/plugin validate`, `~/.claude/logs/plugins.log`) swept; `extensionToLanguage` leading-dot fixed; LSP count corrected to 12 (added `ruby-lsp`); `format: password` replaced with `sensitive: true`; `userConfig` `title`/`description` corrected to required; plugin-id derivation corrected; manifest `description` correctly marked optional; hot-swap matrix updated to include monitors as session-lifetime; reserved-marketplace-names softened. |
| Phase 2 | Plugin additions B1–B6 (see below) | ⏳ Pending |
| Phase 3 | Cross-link sweep between docs and plugin | ⏳ Pending |

---

## A. Documentation folder structure (`Documentation/ClaudePlugin/`) — DONE

Two-level structure. Each top-level item is either `XX_name.md` (single chapter) or `XX_name/` (folder with sub-pages and a `00_index.md`).

```
Documentation/ClaudePlugin/
├── 00_index.md                                    ← master TOC, reading order, what's where
├── 01_overview.md                                 ← layered architecture in one page
├── 02_mental-model/                               ← model / runtime / packaging split
│   ├── 00_index.md
│   ├── 01_what-the-model-sees.md
│   ├── 02_what-the-runtime-sees.md
│   ├── 03_packaging-vs-capabilities.md
│   └── 04_naming-and-namespacing.md
├── 03_storage-and-scope/
│   ├── 00_index.md
│   ├── 01_cache-layout.md
│   ├── 02_data-dir.md
│   ├── 03_scope-union.md                          ← Managed > Local > Project > User
│   ├── 04_settings-files.md
│   └── 05_env-vars.md
├── 04_marketplaces/
│   ├── 00_index.md
│   ├── 01_anatomy.md
│   ├── 02_source-types.md                         ← github / url / git-subdir / npm / relative
│   ├── 03_ref-and-sha-pinning.md
│   ├── 04_release-channels.md
│   ├── 05_catalogue-pattern.md
│   ├── 06_extra-known-marketplaces.md
│   ├── 07_managed-restrictions.md                 ← strictKnownMarketplaces (array of patterns)
│   └── 08_cross-marketplace-deps.md
├── 05_plugin-anatomy/
│   ├── 00_index.md
│   ├── 01_directory-layout.md
│   ├── 02_manifest-fields.md
│   ├── 03_path-replacement-vs-additive.md
│   ├── 04_user-config.md
│   ├── 05_plugin-shipped-settings.md              ← agent + subagentStatusLine only
│   └── 06_disable-model-invocation.md
├── 06_capabilities/                               ← every capability surface
│   ├── 00_index.md
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
│   ├── 01_install-flow.md
│   ├── 02_activation-and-loading.md
│   ├── 03_hot-swap-matrix.md
│   ├── 04_updates.md
│   ├── 05_garbage-collection.md
│   ├── 06_schema-validation.md
│   └── 07_multi-plugin-merging.md
├── 08_composition-patterns/
│   ├── 00_index.md
│   ├── 01_hand-author.md
│   ├── 02_depend.md
│   └── 03_soft-fork.md
├── 09_versioning-and-publishing/
│   ├── 00_index.md
│   ├── 01_semver.md
│   ├── 02_tagging-convention.md                   ← <plugin>--v<X.Y.Z>
│   ├── 03_version-resolution.md
│   ├── 04_release-loop.md
│   └── 05_pre-releases-and-hotfixes.md
├── 10_trust-and-security.md
├── 11_testing-and-iteration/
│   ├── 00_index.md
│   ├── 01_plugin-dir.md
│   ├── 02_headless.md
│   ├── 03_benchmarking.md
│   └── 04_clean-install-loop.md
├── 12_cli-and-ui/
│   ├── 00_index.md
│   ├── 01_claude-plugin-cli.md
│   ├── 02_built-in-slash-commands.md
│   └── 03_plugin-ui.md
├── 13_uninstall-and-cleanup.md
├── 14_distribution/
│   ├── 00_index.md
│   ├── 01_official-marketplace-submission.md
│   ├── 02_plugin-hints.md
│   └── 03_auto-update-controls.md
├── 15_reference/
│   ├── 00_index.md
│   ├── 01_env-vars-cheatsheet.md
│   ├── 02_settings-keys.md
│   ├── 03_frontmatter-flags.md
│   └── 04_legacy-and-migration.md
└── 16_examples/
    ├── 00_index.md
    ├── 01_minimal-plugin.md
    ├── 02_dogfood-marketplace.md
    ├── 03_catalogue-marketplace.md
    └── 04_soft-fork-plugin.md
```

**Tone:** comprehensive scope of "what exists / what's possible" — NOT a how-to. The plugin (`ai-toolkit-dev`) handles the how-to side.

---

## A2. Settings documentation (`Documentation/ClaudeSettings/`) — DONE

Companion doc set covering Claude Code's user-settings surface — the things plugins CANNOT ship.

```
Documentation/ClaudeSettings/
├── 00_index.md
├── 01_settings-files-and-precedence.md            ← managed / user / project / local
├── 02_status-line.md                              ← main statusLine (NOT plugin-shippable)
├── 03_permissions-and-keybindings.md
├── 04_environment-variables.md                    ← DISABLE_AUTOUPDATER, FORCE_AUTOUPDATE_PLUGINS
└── 05_plugin-related-settings.md                  ← enabledPlugins, extraKnownMarketplaces, strictKnownMarketplaces, pluginConfigs
```

---

## Audit findings — applied during Phase 1.5c

Agent 8's punch list, all fixed:

**CRITICAL** — `15_reference/02_settings-keys.md` (3 errors), `16_examples/03_catalogue-marketplace.md` (invented `git`/`github-release` source types and `path` field on `github`), `09_versioning-and-publishing/05_pre-releases-and-hotfixes.md` (invented `--version` flag), `07_lifecycle-and-runtime/06_schema-validation.md` (over-marked required fields).

**HIGH** — MCP tool naming missing `plugin_<plugin>_` infix in mental-model pages, monitor hot-swap behaviour contradicted across 4 pages, `enabledMarketplaces` typo, `/plugin-hints` missing from slash-command catalogue, subagent color list (`purple`/`pink` invented; `magenta` missing).

**MEDIUM** — broken cross-link to `01_env-vars.md`, soft-fork example clarification.

**Bonus** — added note to `04_marketplaces/02_source-types.md` that `commit` is observed in the wild as a synonym for `sha` (`sha` is canonical per official schema).

**Stale references** — `docs/Claude Plugins/` references swept from `Documentation/`, plugin reference files, `CLAUDE.md`, `README.md`. All replaced with official Anthropic doc links or in-repo `Documentation/` paths.

All claims verified against (1) official Anthropic docs at `code.claude.com/docs/en/plugins-reference` + `plugin-marketplaces`, (2) the upstream `anthropics/claude-plugins-official` repo cloned fresh, (3) the plugin's vendored skill content.

---

## B. Plugin additions — PENDING

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

- **Soft-fork pattern teaching** → docs only (`08_composition-patterns/03_soft-fork.md`)
- **"What the model actually sees" framing** → docs only (`02_mental-model/`)
- **Capability decision overview** → docs only (`06_capabilities/00_index.md`)
- **Trust model** → docs only (`10_trust-and-security.md`)
- **Submission process** → docs only (`14_distribution/01_official-marketplace-submission.md`)
- **"Pick the right scope" full guide** → docs only (referenced from plugin via the B5 callout)
- **Ecosystem mental model deep dive** → docs only (`02_mental-model/`)

---

## Decisions made (formerly open questions)

1. **16 top-level chapters** — used as designed; granularity holds up.
2. **B6 (`composition-decisions.md`)** — separate file in plugin's references.
3. **Word budget** — index pages 30–50 lines, sub-pages 80–200. Used as designed.
4. **Old `docs/Claude Plugins/`** — deleted after Agent 9 confirmed full topic coverage in new docs (one `file://` rejection note added before delete).
