# sids-plugin-marketplace — agent guidance

This is a **plugin marketplace** maintained by Sid. It ships to two hosts, Claude Code and Codex CLI. Plugins live under `plugins/`.

Skill authoring is done with the `skill-creator` skill that Claude Code ships. This repo does not carry its own authoring toolkit.

## Two host layers, both written by hand

Each host reads its own pair of files. There is no generator. When you edit one layer, edit the other in the same change.

| Item | Claude Code | Codex |
|---|---|---|
| Marketplace catalogue | `.claude-plugin/marketplace.json` | `.agents/plugins/marketplace.json` |
| Plugin manifest, in-repo plugin | `plugins/<name>/.claude-plugin/plugin.json` | `plugins/<name>/.codex-plugin/plugin.json` |
| Plugin manifest, plugin in another repo | that repo's `.claude-plugin/plugin.json` | inline `interface` on the Codex catalogue entry |
| Skill content | `plugins/<name>/skills/<skill>/SKILL.md` | same file |

The manual sync checklist. Run through it after any change to a plugin's name, version, description, author, license, keywords or source:

1. `version` in `.codex-plugin/plugin.json` must equal `version` in `.claude-plugin/plugin.json`. Codex needs strict semver.
2. Every plugin listed in the Codex catalogue must exist in the Claude catalogue with the same `name`.
3. A Claude relative-path source maps to a Codex `{"source": "local", "path": "./plugins/<name>"}`.
4. A Claude `git-subdir` source maps to a Codex `{"source": "url", "url": ..., "path": ...}`. Copy `ref` or `sha` if set.
5. A Codex entry needs `policy` and `category` on every plugin. Use `{"installation": "AVAILABLE", "authentication": "ON_INSTALL"}` and one of the official display buckets. See `Documentation/04_codex.md`.
6. A remote plugin has no `.codex-plugin/plugin.json` here, so its Codex entry carries `interface.displayName` and `interface.shortDescription` inline. Codex treats extra entry keys as a fallback manifest and reads the remote repo's own `plugin.json` at install.

Two Codex constraints that shape what can ship:

- Codex plugin manifests support no `commands`, no `dependencies`, and reject `hooks`. Keep those out of any plugin meant to ship to both hosts.
- Anything a skill needs at runtime must live **inside** its skill folder, because Codex packages only what `"skills": "./skills/"` points at.

Skill content is shared verbatim. `SKILL.md` frontmatter (`name`, `description`) and `references/` progressive disclosure work identically on both hosts.

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
- Do not edit one host layer without the other. Walk the checklist above.
- Do not add a generator or sync script for the Codex layer. Four plugins are cheaper to sync by hand than to keep a generator honest.
- Do not add an upstream-tracking or soft-fork mechanism. This repo vendors nothing.
- Do not expand `Documentation/` back into a many-file reference. Add to an existing file or replace one.
