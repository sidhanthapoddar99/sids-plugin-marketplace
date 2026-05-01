---
title: Output styles
description: Response-shape rules appended to the system prompt — manifest field, definition file format, /output-style activation
---

# Output styles

An **output style** is a prompting policy that changes how Claude formats responses. The body of an output-style file is appended to Claude Code's system prompt while the style is active. Useful for tone overrides, verbosity policies, response-shape conventions.

## Where it lives

```
my-plugin/
├── .claude-plugin/plugin.json # `outputStyles` field
└── output-styles/
    ├── concise.md
    └── tutorial.md
```

Configured via `outputStyles` in `plugin.json`:

```json
{
  "outputStyles": "./output-styles/"
}
```

Or specific files:

```json
{
  "outputStyles": ["./styles/concise.md", "./styles/tutorial.md"]
}
```

The value is a **path string or array of paths**. Default scan resolves to `outputStyles/*.md`. The `outputStyles` field is path-replacement; include both default and custom if you want to keep scanning the default location.

## Schema — definition file

A Markdown file with frontmatter:

```markdown
---
name: concise
description: Direct, minimal-prose responses
---

You are operating in concise mode. Apply these rules:

- No preamble, no recap of the user's question
- Bullet points over prose where possible
- Skip code comments unless load-bearing
- One-line summary at the end of long responses
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Identifier shown in `/output-style` |
| `description` | yes | One-line description shown in the picker |

The body is appended to the system prompt while the style is active. Treat it like CLAUDE.md content — actionable rules the model internalizes.

## Activation

Users select via `/output-style`. The active style affects every prompt until changed. Plugin-shipped styles appear alongside built-in styles.

## Examples in the official marketplace

`claude-plugins-official` ships two reference styles:

| Plugin | Behavior |
|---|---|
| `explanatory-output-style` | Adds educational annotations on code |
| `learning-output-style` | Interactive learning-mode formatting |

Read those for worked examples of the convention.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Style(s) registered in next session's `/output-style` listing |
| Session start | All plugin styles scanned, indexed |
| `/output-style` selection | Body appended to system prompt; affects every subsequent prompt |
| `/reload-plugins` | Hot-swap: style edits picked up; if the active style was edited, next prompt picks up the new body |
| Plugin disabled | Styles removed from picker on next session |

Hot-swappable. No restart required.

## Boundaries

An output style can:

- Add prompting rules that override or supplement default behaviour
- Be combined with any theme, any skill, any tool config
- Be switched at any time without restart

An output style **cannot**:

- Add new tools the model can call (that's [MCP](./05_mcp-servers.md))
- Block tool calls (that's [Hooks](./04_hooks.md))
- Change which capabilities the plugin ships
- Run code at the OS level

## Trust class

**Model-loaded.** Output styles are data the model reads as part of its system prompt. No OS-level execution.

## When to use an output style vs alternatives

| Goal | Use |
|---|---|
| Tone, verbosity, response shape | Output style |
| Project conventions Claude should follow | [Skill](./01_skills.md) |
| Specialised reviewer system prompt | [Subagent](./03_subagents.md) |
| Color scheme | [Theme](./09_themes.md) |

## Common pitfalls

- **Over-prescribing.** A 500-word style is in *every* prompt — expensive and brittle. Aim for under ~100 words of concrete rules
- **Format-rigid rules.** Telling Claude "always use exactly 3 bullet points" produces weird outputs when 3 isn't natural. Specify shape only when it genuinely matters
- **Path-replacement gotcha.** `outputStyles` is path-replacement; setting a custom path replaces the default `outputStyles/*.md` scan unless you include both

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/theme-and-output-style/`
- [Themes](./09_themes.md) — the related but visually-scoped surface
- [Skills](./01_skills.md) — for project-specific behaviour rather than global response shape
- Official: [Output styles in marketplace](https://code.claude.com/docs/en/discover-plugins#output-styles)
- [Capabilities index](./00_index.md)
