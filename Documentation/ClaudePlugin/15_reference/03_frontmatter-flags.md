# Frontmatter flags

YAML frontmatter recognised by Claude Code at the top of `SKILL.md`, command markdown files, and agent markdown files. Each capability has its own set of recognised keys; unknown keys are silently ignored.

## Skills (`skills/<name>/SKILL.md`)

```yaml
---
name: my-skill
description: |
  Use this skill when … TRIGGER on … SKIP only when …
disable-model-invocation: false
---
```

| Key | Type | Purpose |
|---|---|---|
| `name` | string | Skill identifier — appears in system reminder as `<plugin>:<name>` |
| `description` | string (long) | What the skill does and when to use it. The model reads this on every session; **the most important field** |
| `disable-model-invocation` | bool | When `true`, the model cannot auto-invoke this skill — user-only via `/skill` or explicit reference. Defaults to `false` |

### `description` writing rules

- State what the skill does
- List specific triggers (file patterns, user phrases, intents)
- Tell the model when to *skip* the skill
- Be a little pushy — the default is to under-trigger

A vague description (`"Helps with documentation"`) means the skill never triggers. A specific one (`"Use this skill for ANY work in this Astro-based docs project — writing markdown, working with the issue tracker, configuring site.yaml … TRIGGER eagerly — documentation work in this project almost always benefits from this skill."`) means it triggers exactly when needed.

## Slash commands (`commands/<name>.md`)

```yaml
---
description: Run a security review of the pending changes on the current branch
allowed-tools: Read, Grep, Bash(git:*)
argument-hint: [base-branch]
model: sonnet
disable-model-invocation: false
---
```

| Key | Type | Purpose |
|---|---|---|
| `description` | string | What the command does — shown in `/help`, used by the model when deciding whether to invoke |
| `allowed-tools` | string (CSV) | Comma-separated tool list. Can include scoped permissions: `Bash(git:*)`, `Read(./docs/**)` |
| `argument-hint` | string | UI hint for completion, shown after the command name |
| `model` | string | Optional model override — `opus`, `sonnet`, `haiku` |
| `disable-model-invocation` | bool | When `true`, the model cannot auto-invoke this command — user types `/<name>` only. Useful for utility commands that should only run when explicitly requested |

### Argument substitution

Inside the body:

| Token | Resolves to |
|---|---|
| `$ARGUMENTS` | The full argument string |
| `$1`, `$2`, … | Positional args |

`/lint src/foo.ts` with `Run the linter on $1.` body becomes `Run the linter on src/foo.ts.`

### `allowed-tools` shape

| Form | Meaning |
|---|---|
| `Read` | Allow `Read` tool unrestricted |
| `Bash(git:*)` | Allow `Bash` only for `git ...` invocations |
| `Read(./docs/**)` | Allow `Read` only for files matching the glob |
| `Read, Grep, Bash(git:*)` | Combined |

The exact glob and prefix syntax follows the broader Claude Code permission grammar; see [`../../ClaudeSettings/`](../../ClaudeSettings/) for `permissions` rules that reuse the same shape.

## Agents (`agents/<name>.md`)

```yaml
---
name: code-reviewer
description: Independent code review for security and correctness
tools: [Read, Grep, Bash]
model: sonnet
color: blue
---
```

| Key | Type | Purpose |
|---|---|---|
| `name` | string | Agent identifier — used by the main agent in `Agent({ subagent_type: "name", … })` |
| `description` | string | When to invoke this agent — read by the main agent when deciding to spawn |
| `tools` | array | Tool allowlist for this agent's context |
| `model` | string | Model override (`opus` / `sonnet` / `haiku`) |
| `color` | string | UI accent color in the subagent status line |

The body of the file is the agent's **system prompt** — what it should be expert at, what conventions to follow, what to refuse.

## `disable-model-invocation` — the most-asked flag

Set `disable-model-invocation: true` to prevent autonomous use:

| Capability | Effect |
|---|---|
| Skill | Model can't auto-invoke; user types `/skill <name>` or refers to it explicitly |
| Slash command | Model can't auto-invoke; user types `/<name>` |
| Agent | (n/a — agents are always model-spawned via `Agent` tool) |

Use it for utility skills/commands that should only run when explicitly requested:

```yaml
---
name: dangerous-cleanup
description: Wipe and rebuild the cache. ONLY when explicitly requested.
disable-model-invocation: true
---
```

Without the flag, a sufficiently determined model could trigger the skill on a tangentially related prompt. With the flag, only an explicit user invocation works.

## Path-replacement vs. additive frontmatter (manifest, not skill/command)

Worth noting because it's frontmatter-adjacent: the **manifest** `plugin.json` capability paths follow these rules:

| Field | Semantics |
|---|---|
| `skills`, `commands`, `agents`, `outputStyles`, `themes`, `monitors` | **Replacement** — setting these overrides the default scan |
| `hooks`, `mcpServers`, `lspServers` | **Additive** — these supplement defaults |

To keep the default *and* add more for replacement-semantics fields:

```json
{
  "skills": ["./skills/", "./extras/"]
}
```

Not strictly frontmatter, but a frequent confusion source — documented in detail at [`../05_plugin-anatomy/01_directory-layout.md`](../05_plugin-anatomy/01_directory-layout.md).

## Common pitfalls

- **`description` too vague** — skill never triggers. Be specific and pushy.
- **`allowed-tools` typo** — silent. The skill loads but no tools are permitted; the model gets stuck.
- **Forgetting `disable-model-invocation` on a destructive utility** — the model fires it on weak signals.
- **`tools` on agents written as a CSV string** — must be a YAML array (`tools: [Read, Grep]`) for agents, while commands use a CSV string. The asymmetry is real.
- **`color` invalid value** — the agent loads but no accent shows. Valid values are `blue`, `cyan`, `green`, `yellow`, `magenta`, `red`.

## See also

- [`../06_capabilities/`](../06_capabilities/00_index.md) — full capability reference
- [`02_settings-keys.md`](./02_settings-keys.md) — `pluginConfigs` for `userConfig` values
- [`04_legacy-and-migration.md`](./04_legacy-and-migration.md) — old flat-commands layout
- Official: [Plugins reference — frontmatter](https://code.claude.com/docs/en/plugins-reference)
