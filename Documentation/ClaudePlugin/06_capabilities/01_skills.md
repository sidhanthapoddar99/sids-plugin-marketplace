---
title: Skills
description: Description-triggered context bundles loaded on demand — frontmatter, progressive disclosure, lifecycle, boundaries
---

# Skills

A **skill** is a markdown file with YAML frontmatter that the model loads into context when its `description` matches user intent. Skills teach project conventions, document workflows, and bundle references the model reads on demand.

## Where it lives

```
my-plugin/
├── .claude-plugin/plugin.json
└── skills/
    └── my-skill/
        ├── SKILL.md            # required — frontmatter + body
        ├── references/         # optional — files the body cites
        ├── examples/           # optional — worked examples
        └── scripts/            # optional — helper scripts
```

Default scan: `skills/<name>/SKILL.md`. Override via `"skills"` in `plugin.json` (path-replacement field — include `"./skills/"` if you want to keep the default and add more).

## Schema — frontmatter

```yaml
---
name: my-skill
description: Use this skill when the user asks about X, Y, or Z. TRIGGER on phrases like "...". SKIP when the task is unrelated to ...
---
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Identifier. Lowercase, hyphens, 3-64 chars |
| `description` | yes | The trigger string. ~50-100 words, always loaded into context |
| `disable-model-invocation` | no | Boolean. If `true`, skill is user-only — model can't auto-invoke. See [`../05_plugin-anatomy/06_disable-model-invocation.md`](../05_plugin-anatomy/06_disable-model-invocation.md) |

The body is freeform Markdown. Convention: keep it under ~500 lines and use it as a triage table that points at `references/<topic>.md` files.

## Description-as-trigger

This is the most important field in the skill. The runtime always shows the description in a system reminder; the body loads only when the model decides the description matches.

| Bad | Good |
|---|---|
| `Helps with documentation` | `Use this skill for ANY work in this Astro docs project — markdown writing, frontmatter, issue tracker, site.yaml. TRIGGER eagerly when the user mentions docs, content, or the data folder. SKIP only for pure framework code under astro-doc-code/src/.` |

The pattern: state purpose → list specific triggers (file patterns, user phrases) → tell the model when to skip.

## Progressive disclosure

A skill stays cheap to ship even when it's large because content loads in three tiers:

| Tier | What loads | When |
|---|---|---|
| 1 | `name` + `description` (~50-100 words) | Always — every session |
| 2 | The `SKILL.md` body | When the description matches user intent |
| 3 | `references/`, `examples/`, `scripts/` files | On demand, when the body cites them |

A 5,000-line skill costs ~50 words of context until it triggers. After triggering, only the body is loaded; references are read individually as needed.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Description registered in next session-start manifest |
| Session start | All enabled skills' descriptions loaded into system reminder |
| User prompt | Model decides whether description matches; if yes, body is loaded |
| `/reload-plugins` | Hot-swap: edits to `SKILL.md` and references picked up without restart |
| Plugin disabled | Description removed on next session start |

Hot-swappable. No restart required for skill content edits.

## Boundaries

A skill can:

- Inject context (its body becomes part of the active conversation)
- Reference files under its own folder via relative paths
- Cite scripts the model can shell into via bash tool calls

A skill **cannot**:

- Execute shell commands directly — that's hooks or bins
- Make tool calls with effects on its own — only the model can call tools
- Receive structured input or return structured output to the runtime
- Use `${CLAUDE_PLUGIN_ROOT}` interpolation in its body (that's commands/hooks only — see [Bin Wrappers](./11_bin-wrappers.md))

## Trust class

**Model-loaded.** A skill is data the model reads. It runs nothing at the OS level. The model decides, based on the body, what tool calls to make — those go through the normal permission system.

## When to use a skill vs alternatives

| Goal | Use |
|---|---|
| Teach project conventions Claude should follow | Skill |
| Document a multi-step workflow with steps | Skill (or a slash command if it's truly one-shot) |
| Provide a one-shot named trigger (`/deploy`) | [Slash command](./02_slash-commands.md) |
| Run a shell command on an event | [Hook](./04_hooks.md) |
| Spawn a specialist for a parallel investigation | [Subagent](./03_subagents.md) |

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/skill-development/`
- [Slash commands](./02_slash-commands.md) — the user-invoked sibling
- [`../05_plugin-anatomy/06_disable-model-invocation.md`](../05_plugin-anatomy/06_disable-model-invocation.md) — opting a skill out of auto-invoke
- [Capabilities index](./00_index.md)
