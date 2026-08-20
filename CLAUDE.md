# sids-plugin-marketplace — agent guidance

This is a **Claude Code plugin marketplace** maintained by Sid. Plugins live under `plugins/` and the marketplace manifest is `.claude-plugin/marketplace.json`.

## When the user asks about upstream drift

Several plugins here use a **soft-fork + upstream tracking** pattern: content is vendored verbatim from upstream repos (mainly `anthropics/claude-plugins-official`), with provenance recorded in each plugin's `.upstream/manifest.json`.

If the user asks any of:

- "is the soft-fork up to date?"
- "check upstream"
- "any drift in plugin-dev / skill-creator / ai-toolkit-dev?"
- "should we sync from upstream?"
- "what changed upstream?"

→ run `./scripts/ai-toolkit-dev-check-upstream` from the marketplace root and report the results. The script reads `plugins/ai-toolkit-dev/.upstream/manifest.json` and prints a per-file drift table.

If the script reports no manifest, the soft-fork hasn't been performed yet — point the user at `plugins/ai-toolkit-dev/README.md` § 2 for the plan.

Drift checks are **per-plugin scoped**. If another plugin grows soft-fork tracking later, it gets its own `scripts/<plugin>-check-upstream`; do not retrofit one global script.

## The Codex layer is generated — never hand-edit it

This marketplace ships to two hosts. The **Claude layer is the source of truth**:
`.claude-plugin/marketplace.json` plus each plugin's `.claude-plugin/plugin.json`.
The **Codex layer is generated** from it by `./scripts/codex-sync`:

- `.agents/plugins/marketplace.json` — the path Codex discovers
- `plugins/<name>/.codex-plugin/plugin.json` — one per exported plugin

If you change a plugin's name, version, description, author, license, or keywords,
re-run `./scripts/codex-sync`. Run `./scripts/codex-sync --check` to verify the
generated files are current; it exits non-zero on drift.

Codex-only presentation data (display name, subtitle, category) lives in the
`OVERLAY` table inside the script. That is the one place to hand-write it. Adding
a plugin to Codex means adding one `OVERLAY` entry.

Two Codex constraints that shape what can ship:

- Codex marketplace entries accept **only `local` sources**. A `git` or `github`
  source is silently dropped from `codex plugin list` with no error, so plugins
  sourced from other repos (`agent-ks`, `uvenv`) cannot be exported. They stay
  Claude Code only.
- Codex plugin manifests support no `commands`, no `dependencies`, and reject
  `hooks`. Keep those out of any plugin meant to ship to both hosts.

Skill content is shared verbatim — `SKILL.md` frontmatter (`name`, `description`)
and `references/` progressive disclosure work identically on both hosts. Anything
a skill needs at runtime must live **inside** its skill folder, because Codex
packages only what `"skills": "./skills/"` points at.

## Doc reference

The structural reference for the plugin ecosystem lives in `Documentation/ClaudePlugin/` (16 chapters: overview, mental model, storage, marketplaces, anatomy, capabilities, lifecycle, composition, versioning, trust, testing, CLI, distribution, uninstall, examples, reference appendix). The companion `Documentation/ClaudeSettings/` covers settings-side keys. The soft-fork pattern is documented in `Documentation/ClaudePlugin/08_composition-patterns/03_soft-fork.md`.

Task-oriented authoring how-to lives in the plugin under `plugins/ai-toolkit-dev/skills/{marketplace,plugin-dev,skill-creator}/`.

## What to NOT do

- Do not edit vendored content (anything under a directory tracked by `.upstream/manifest.json`) without first explaining the modification to the user — vendored files should generally stay close to upstream so syncs remain mechanical.
- Do not add slash commands or upstream-tracking bins (`pf-upstream-status` and the like) to `ai-toolkit-dev`. Slash commands are excluded because plugin authoring is rare and they'd clutter every consumer's `/` menu; soft-fork tracking belongs at the marketplace level (`scripts/ai-toolkit-dev-check-upstream`), not on every consumer's `$PATH`. General-purpose bins that genuinely help plugin authors *can* be added — see `plugins/ai-toolkit-dev/README.md` § 1 "Out of scope" for the full reasoning.
- Do not ship upstream's `agent-creator` / `plugin-validator` / `skill-reviewer` agents in `ai-toolkit-dev`. We dropped them because we don't need them; their useful substance is folded into the relevant skill's references where helpful.
