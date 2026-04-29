---
title: Capabilities
description: The five capability types — skills, slash commands, subagents, hooks, MCP servers — and the description-as-trigger pattern
---

# Capabilities

A plugin can ship any combination of five capability types. Each has its own runtime semantics, its own author conventions, and its own role in the ecosystem.

| Capability | Who/what fires it | When it loads |
|---|---|---|
| **Skill** | Model — when the description matches user intent | Body loaded on trigger; references on demand |
| **Slash command** | User typing `/<name>` (or model invoking) | Body injected when fired |
| **Subagent** | Main agent invoking via the `Agent` tool | Spawned per invocation in fresh context |
| **Hook** | Runtime, on lifecycle events | Always loaded; fires per matched event |
| **MCP server** | Model calls a tool the server registered | Server starts at session init; tools always visible |

## Description-as-trigger — the most important pattern

Skills and slash commands both depend on a `description` field that the model uses to decide *when to use them*. The runtime ensures these descriptions are visible in the model's context from the start of every session — for skills, the description sits in a system reminder (~50-100 words always loaded); for commands, the description appears in the available-commands list.

**The model never sees the body until the description matches.** This is the single biggest lever you have when authoring a skill or command. A vague description means the skill never triggers; a tight, specific description means it triggers exactly when needed.

Bad description (vague):

```
description: Helps with documentation
```

Better (specific, includes triggers):

```
description: Use this skill for ANY work in this Astro-based docs project — writing markdown,
working with the issue tracker, configuring site.yaml, blog posts, or any file under
dynamic_data/. Triages the task to a domain-specific reference. TRIGGER eagerly — documentation
work in this project almost always benefits from this skill.
```

The pattern: state what the skill does, list specific triggers (file patterns, user phrases, intents), and tell the model when to *skip* the skill. Be a little pushy — Claude Code's default is to under-trigger skills.

## 1. Skills

A skill is a markdown file with YAML frontmatter:

```markdown
---
name: my-skill
description: Use this skill when … TRIGGER on … SKIP only when …
---

# My Skill

Body — instructions, examples, conventions, references.

## Triage

| If the task involves… | Read |
|---|---|
| Frontmatter, custom tags | `references/writing.md` |
| Issue tracker | `references/issue-layout.md` |
```

### Progressive disclosure — context retention

This is how skills stay cheap to ship even when they're large:

1. **Always loaded** (~50-100 words): the skill's `name` + `description` from frontmatter
2. **Loaded on trigger** (when the model decides this skill applies): the SKILL.md body
3. **Loaded on demand** (only when the body cites them): files under `references/`, `scripts/`

A 5,000-line skill costs ~50 words of context until it triggers. After triggering, only the body is loaded. References are read individually as the model needs them. This means a skill can be deeply detailed without bloating sessions where it's irrelevant.

Best practice: keep `SKILL.md` body itself under ~500 lines and use it as a triage table that points at `references/<topic>.md` files. The model reads only what it needs.

### When to use a skill

| Goal | Use a skill |
|---|---|
| Teach project conventions Claude should follow | ✅ |
| Document a specific workflow with steps | ⚠️ slash command might be tighter |
| Provide one-shot trigger for a routine | ❌ slash command |
| Run shell commands automatically | ❌ hook or bin wrapper |

## 2. Slash commands

A slash command is a markdown file with YAML frontmatter:

```markdown
---
description: Run a security review of the pending changes on the current branch
allowed-tools: Read, Grep, Bash(git:*)
argument-hint: [base-branch]
---

Review the diff between the current branch and $1 (default: main) for OWASP Top 10 issues.
Focus on: input validation, auth, injection, secret leakage, dependency upgrades.

Output a markdown summary with severity levels.
```

### Frontmatter fields

| Field | Purpose |
|---|---|
| `description` | What this command does — shown in `/help`, used by the model when deciding whether to invoke |
| `allowed-tools` | Comma-separated tool list. Can include scoped permissions (`Bash(git:*)`) |
| `argument-hint` | UI hint for completion, shown after the command name |
| `model` | Optional model override (`opus`, `sonnet`, `haiku`) |

### Argument substitution

Use `$ARGUMENTS` for the full argument string, `$1`, `$2`, … for positional args:

```markdown
Run the linter on $1 and report errors.
```

`/lint src/foo.ts` expands to "Run the linter on src/foo.ts and report errors."

### `${CLAUDE_PLUGIN_ROOT}` interpolation

Inside slash command bodies, `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installed cache folder. Use this for referencing bundled assets or scripts:

```markdown
Read the template at ${CLAUDE_PLUGIN_ROOT}/templates/site.yaml and …
```

This **does not work** in `SKILL.md` bodies — the env var is only template-expanded for commands, hooks, and `allowed-tools` frontmatter. For shell scripts, use `bin/` wrappers instead (see [Bin Wrappers](./04_bin-wrappers.md)).

### When to use a slash command

| Goal | Use a slash command |
|---|---|
| One-line trigger for a workflow ("/review", "/deploy") | ✅ |
| User-facing UX entry point | ✅ |
| Templated prompt with arguments | ✅ |
| Teaching conventions / how-to | ❌ skill |

## 3. Subagents

A subagent is a markdown file describing a specialised Claude config:

```markdown
---
name: code-reviewer
description: Independent code review for security and correctness
tools: [Read, Grep, Bash]
model: sonnet
---

# System prompt for this specialist

You are an experienced code reviewer specialising in OWASP Top 10 issues. When invoked, …
```

The main agent invokes via the `Agent` tool:

```
Agent({ subagent_type: "code-reviewer", prompt: "..." })
```

The subagent runs in a fresh context with its own system prompt and tool allowlist. Useful for:

- **Bulk reads**: "read these 30 files and summarise" — keeps the main context clean
- **Specialised expertise**: critic, security reviewer, debugger
- **Parallelism**: spawn 3 subagents to investigate 3 independent questions

## 4. Hooks

Hooks are shell commands the runtime fires on lifecycle events:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "echo 'about to run bash'" }
        ]
      }
    ]
  }
}
```

Events include `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `Notification`, `SessionStart`, and more.

Hooks can:

- **Block** a tool call (exit code 1 + reason on stderr)
- **Inject context** (stdout becomes a system reminder for the model)
- **Side effects** (post to Slack, log, run a linter)

Hooks run with your shell permissions. Treat hook authorship like writing a `.git/hooks/` script — same trust model.

## 5. MCP servers

An MCP server is a separate process exposing tools, resources, and prompts over the Model Context Protocol. Registered via `.mcp.json`:

```json
{
  "mcpServers": {
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
    }
  }
}
```

Tools are namespaced as `mcp__<server>__<tool>`. The puppeteer server's `click` tool appears in the model's tool list as `mcp__puppeteer__puppeteer_click`.

Use MCP when you need to add **new tools** the model can call (database queries, browser automation, custom APIs). Use hooks when you want to inject *behaviour* without adding tools.

## Beyond the five — other capability surfaces

The five above are the conceptual core, but a plugin can also ship four other surface types. Each is its own opt-in folder/manifest field. We don't go deep on these here — the [Reference](../07_reference.md) page has nomenclature pointers and links to the canonical official docs.

### LSP servers (`.lsp.json` or `lspServers`)

Configure a Language Server Protocol connection so Claude gets **automatic diagnostics after every edit** and code-navigation primitives (go-to-definition, find-references, hover, symbols). The official marketplace ships pre-built LSP plugins for 11 languages (`pyright-lsp`, `typescript-lsp`, `gopls-lsp`, `rust-analyzer-lsp`, etc.) — install one of those before authoring your own. Custom `.lsp.json` is for languages not already covered. The language server binary must be installed separately on the user's machine. → [LSP servers (official)](https://code.claude.com/docs/en/plugins-reference#lsp-servers)

### Background monitors (`monitors/monitors.json` or `monitors`)

Long-running shell commands the runtime starts at session begin. Each stdout line becomes a notification the model sees as the session runs — useful for tailing logs, polling deploy status, or watching external state. Same trust level as hooks (unsandboxed). Supports a `when` field to gate startup on a specific skill being invoked. → [Monitors (official)](https://code.claude.com/docs/en/plugins-reference#monitors)

### Themes (`themes/`)

Color schemes that appear in `/theme` alongside the built-in presets. Each theme is a JSON file with a `base` preset and a sparse `overrides` color map. Plugin themes are read-only; users can press Ctrl+E in `/theme` to copy one into `~/.claude/themes/` for editing. → [Themes (official)](https://code.claude.com/docs/en/plugins-reference#themes)

### Output styles (`outputStyles`)

Customise how Claude formats responses. The official marketplace ships `explanatory-output-style` (educational annotations) and `learning-output-style` (interactive learning mode) as examples. → [Reference](../07_reference.md#output-styles)

### Channels (`channels`)

Declare message-injection channels backed by an MCP server — Telegram/Slack/Discord-style content piped into the conversation. Each channel binds to a key in `mcpServers` and can prompt for its own per-channel `userConfig` (bot tokens, owner IDs). → [Channels (official)](https://code.claude.com/docs/en/plugins-reference#channels)

These five surfaces plus the original five, together with `bin/` wrappers ([Bin Wrappers](./04_bin-wrappers.md)) and `userConfig` ([Reference](../07_reference.md#userconfig)), are the full menu of what a plugin can carry.

## Picking the right capability

| Goal | Capability |
|---|---|
| Teach Claude project conventions / domain knowledge | Skill |
| One-line trigger for a common workflow | Slash command |
| Auto-format on save / block dangerous commands / log every tool call | Hook |
| Add new tools the model can call (database, browser, custom API) | MCP server |
| Specialised reviewer / researcher with a different system prompt | Subagent |
| Cheap shell access to bundled scripts | `bin/` wrapper (see [Bin Wrappers](./04_bin-wrappers.md)) |

Skills and commands often pair: a skill teaches the *concepts* (what, why, when); a slash command provides the *one-shot trigger* for the most common operations the skill describes. The skill body can reference the commands it ships alongside.

## See also

- **[Bin Wrappers](./04_bin-wrappers.md)** — the PATH-augmentation pattern (mechanically a PATH trick, not a capability type)
- **[Plugin Structure](./02_plugin-structure.md)** — folder layout for each capability type
- **[Plugin Dependencies](./07_dependencies.md)** — building on top of another plugin's capabilities instead of duplicating
- **[Testing and Benchmarking](./05_testing-and-benchmarking.md)** — iterating on capabilities during development
- **[Reference](../07_reference.md)** — full nomenclature index for the surfaces touched on above
