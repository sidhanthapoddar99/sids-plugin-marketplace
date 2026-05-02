---
title: Slash commands
description: User-invoked templated prompts — frontmatter, argument substitution, the legacy commands/ layout, and the modern skills equivalent
---

# Slash commands

A **slash command** is a Markdown file containing a templated prompt. The user types `/<name>` (the model can also invoke); the file's body — with arguments substituted — becomes Claude's next instruction.

## Where it lives

```
my-plugin/
└── commands/
    ├── review.md              # /review
    ├── deploy.md              # /deploy
    └── ci/
        └── lint.md            # /lint (namespaced under ci)
```

Default scan: `commands/<name>.md`. Subdirectories namespace the command in `/help` output.

> **Note on layout convention.** The flat `commands/` directory is the **legacy** format. The modern convention for plugin authors is `skills/<name>/SKILL.md`. Both load identically — the difference is purely file layout. New plugins should prefer the skills layout where possible. The `commands/` folder remains fully supported. → [Skills](./01_skills.md), [`../15_reference/04_legacy-and-migration.md`](../15_reference/04_legacy-and-migration.md)

## Schema — frontmatter

All fields are optional. A command with no frontmatter and just a body works.

```markdown
---
description: Run a security review of the pending diff
allowed-tools: Read, Grep, Bash(git:*)
argument-hint: [base-branch]
model: sonnet
disable-model-invocation: false
---

Review the diff between the current branch and $1 (default: main) for OWASP Top 10 issues.
```

| Field | Notes |
|---|---|
| `description` | Shown in `/help`; the model uses it to decide whether to invoke. Defaults to first body line if omitted |
| `allowed-tools` | Comma-separated tool list, optionally with scoped permissions: `Bash(git:*)`, `Read, Write, Edit` |
| `argument-hint` | Autocomplete hint shown after the command name in the UI |
| `model` | Override the model: `opus`, `sonnet`, `haiku`. Defaults to inheriting from the parent conversation |
| `disable-model-invocation` | Boolean. If `true`, the model can't programmatically invoke; user must type `/<name>` explicitly |

## Argument substitution

| Syntax | Expands to |
|---|---|
| `$ARGUMENTS` | Full argument string |
| `$1`, `$2`, `$3`, … | Positional arguments split on whitespace |

```markdown
Review pull request #$1 with priority level $2.
```

`/review-pr 123 high` → `Review pull request #123 with priority level high.`

## File and bash interpolation

Inside command bodies (and `allowed-tools` frontmatter), the runtime template-expands two extra forms:

| Form | Expands to |
|---|---|
| `@<path>` | Inline contents of the file at `<path>` (relative to project root) |
| `` !`<cmd>` `` | Output of the shell command, captured at command-invoke time |
| `${CLAUDE_PLUGIN_ROOT}` | Absolute path to the plugin's installed cache root |

```markdown
---
allowed-tools: Bash(git:*)
---

Files changed: !`git diff --name-only`

Review @${CLAUDE_PLUGIN_ROOT}/templates/review-checklist.md against the diff.
```

Note: `${CLAUDE_PLUGIN_ROOT}` only expands inside command bodies, command frontmatter, hook commands, and MCP/LSP/monitor configs. It does **not** expand inside `SKILL.md` bodies. See [Bin Wrappers](./11_bin-wrappers.md) for the workaround.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Command registered on next session start |
| Session start | All enabled commands' descriptions loaded into the available-commands list |
| `/<name>` typed | Body read, arguments substituted, prompt injected into the conversation |
| `/reload-plugins` | Hot-swap: command-file edits picked up without restart |
| Plugin disabled | Command removed on next session start |

Hot-swappable. No restart required for command edits.

## Boundaries

A command can:

- Template-expand a prompt with arguments, file contents, and shell output
- Restrict which tools the model uses for this invocation (`allowed-tools`)
- Override the model for this invocation
- Reference plugin assets via `${CLAUDE_PLUGIN_ROOT}`

A command **cannot**:

- Persist state across invocations (use `${CLAUDE_PLUGIN_DATA}` for that)
- Block the model — the body becomes a prompt, not an authoritative gate
- Receive structured input beyond positional args

## Trust class

**Model-loaded** for the body itself. The `` !`<cmd>` `` interpolation runs shell commands at invoke time at the user's privilege — that part is unsandboxed. Use the same trust posture as `.git/hooks/`.

## When to use a slash command vs alternatives

| Goal | Use |
|---|---|
| One-line trigger for a workflow ("/deploy", "/review") | Slash command |
| Templated prompt with arguments | Slash command |
| Teach conventions / how-to | [Skill](./01_skills.md) |
| Run a script with no prompt overhead | [Bin wrapper](./11_bin-wrappers.md) |
| Auto-fire on lifecycle events | [Hook](./04_hooks.md) |

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/command-development/`
- [Skills](./01_skills.md) — the modern equivalent layout
- [Bin Wrappers](./11_bin-wrappers.md) — when shell tooling is the better fit
- [Capabilities index](./00_index.md)
