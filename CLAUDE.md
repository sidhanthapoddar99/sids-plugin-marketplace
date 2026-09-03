# sids-plugin-marketplace — agent guidance

This is a **plugin marketplace** maintained by Sid. It ships to two hosts, Claude Code and Codex CLI. Plugins live under `plugins/`. The marketplace manifest is `.claude-plugin/marketplace.json`.

Skill authoring is done with the `skill-creator` skill that Claude Code ships. This repo does not carry its own authoring toolkit.

## The Codex layer is generated — never hand-edit it

The **Claude layer is the source of truth**:
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

Two constraints that shape what can ship:

- `codex-sync` exports **only `local` sources**. Codex itself resolves `url`,
  `git-subdir` and `npm` sources since 0.131 (verified on 0.149.1, see
  `Documentation/04_codex.md`). The script has not been extended, so plugins
  sourced from other repos (`agent-ks`, `uvenv`) are not generated for Codex.
  Extending the script is the way to change that. Do not hand-add entries.
- Codex plugin manifests support no `commands`, no `dependencies`, and reject
  `hooks`. Keep those out of any plugin meant to ship to both hosts.

Skill content is shared verbatim — `SKILL.md` frontmatter (`name`, `description`)
and `references/` progressive disclosure work identically on both hosts. Anything
a skill needs at runtime must live **inside** its skill folder, because Codex
packages only what `"skills": "./skills/"` points at.

## Doc reference

`Documentation/` is a ten-file reference on plugins, marketplaces and skills across
Claude Code, Codex, Hermes and OpenCode. Start at `Documentation/00_index.md`. It is
written in simple technical English so a human and an AI can read the whole set in
one go. Keep it that way: short sentences, defined terms, tables and diagrams, and
no growth beyond ten files without a reason.

| Question | File |
|---|---|
| What is a skill, plugin, marketplace | `Documentation/01_concepts.md` |
| Claude Code plugin anatomy, storage, install | `Documentation/02_claude-code-plugins.md` |
| Claude Code marketplace.json, sources, pinning | `Documentation/03_claude-code-marketplaces.md` |
| Codex plugins and marketplaces | `Documentation/04_codex.md` |
| Hermes skills | `Documentation/05_hermes.md` |
| OpenCode plugins and skills | `Documentation/06_opencode.md` |
| One skill for every host | `Documentation/07_skills-portable.md` |
| How this repo is wired | `Documentation/08_this-marketplace.md` |
| Side-by-side tables | `Documentation/09_comparison.md` |

## What to NOT do

- Do not add slash commands, agents, or hooks to plugins meant for both hosts. Codex rejects hooks and has no commands.
- Do not hand-edit generated Codex files. Edit the Claude layer or `OVERLAY`, then run `./scripts/codex-sync`.
- Do not add an upstream-tracking or soft-fork mechanism. This repo vendors nothing.
- Do not expand `Documentation/` back into a many-file reference. Add to an existing file or replace one.
