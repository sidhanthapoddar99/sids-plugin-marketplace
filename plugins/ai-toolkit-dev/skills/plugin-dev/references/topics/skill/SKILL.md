---
name: skill
description: Stub — redirects readers to the top-level `skill-creator` skill for skill authoring. Not a real topic; do not load this in lieu of `skill-creator`.
---

# Skill authoring → use `skill-creator`

This is a redirect stub. The substantive content for authoring Claude Code skills lives in the **top-level `skill-creator` skill** (also part of `ai-toolkit-dev`).

## Why a redirect

`skill-creator` is soft-forked from upstream `claude-plugins-official` and ships verbatim with this plugin. It covers:

- Writing a skill from scratch (frontmatter, body, references)
- Iterating on skill descriptions (the matcher-targeting they need)
- Running evals against alternative skill drafts
- Measuring trigger rate and quantitative quality
- Optimizing description text via a dedicated improver script

Duplicating that into a `topics/skill/` reference would mean keeping two skill-authoring docs in sync — one of them would inevitably go stale.

## What to do

If you landed here because you were routed from `plugin-dev/SKILL.md`'s topic table:

→ Stop reading this file. Open `skills/skill-creator/SKILL.md` instead.

If you're invoking this plugin's `plugin-dev` skill and need to author a skill, the top-level `skill-creator` skill in the same plugin will activate independently for skill-authoring prompts. You don't need to load anything from this `topics/skill/` folder.

## What this folder is *not*

- Not a wrapper around `skill-creator`
- Not a customization layer
- Not a Claude-Code-specific extension of the upstream skill

If `ai-toolkit-dev` ever ships local additions to skill authoring (e.g. plugin-specific conventions for skill description tuning), those would be appended to `skills/skill-creator/SKILL.md` directly, not inserted here.
