---
title: Subagents
description: Specialised Claude configurations spawned by the main agent — frontmatter, fresh-context model, tool restrictions
---

# Subagents

A **subagent** is a specialised Claude configuration the main agent can spawn via the `Agent` tool. Each invocation runs in a **fresh context** with its own system prompt, tool allowlist, and (optionally) model. Useful for parallel investigations, bulk reads, and specialised reviewers whose context the main agent shouldn't pollute.

## Where it lives

```
my-plugin/
└── agents/
    ├── code-reviewer.md
    ├── test-generator.md
    └── security-analyzer.md
```

Default scan: `agents/<name>.md`. Override via `"agents"` in `plugin.json` (path-replacement field).

## Schema — frontmatter

```markdown
---
name: code-reviewer
description: Use this agent when reviewing code changes. Typical triggers include "/review", "review this PR", or after a large refactor. See "When to invoke" in the agent body for worked scenarios.
model: inherit
color: blue
tools: ["Read", "Grep", "Bash"]
---

You are an experienced code reviewer specializing in security and correctness.

## When to invoke

- **Pre-merge review.** A teammate has authored a diff and asks for an OWASP-style audit.
- **Post-refactor sanity check.** The main agent has done a large refactor and wants a fresh pair of eyes.

**Your Core Responsibilities:**
1. Identify security vulnerabilities (OWASP Top 10)
2. Flag correctness issues
3. Suggest test coverage gaps

**Output Format:**
A markdown report with severity levels.
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Identifier. Lowercase letters, numbers, hyphens. 3-50 chars. Must start and end with alphanumeric |
| `description` | yes | When the main agent should dispatch this subagent. The single most critical field — see below |
| `model` | yes | `inherit` (default), `sonnet`, `opus`, `haiku` |
| `color` | yes | UI marker: `blue`, `cyan`, `green`, `yellow`, `magenta`, `red` |
| `tools` | no | Array of allowed tool names. Omit for full access. Principle of least privilege applies |

## Description-as-trigger

Like skills, the agent's description is always loaded; the body becomes the agent's system prompt only when invoked. Cover:

1. Triggering conditions ("Use this agent when…")
2. 2-4 trigger scenarios as prose
3. A pointer to a "When to invoke" section in the body for worked scenarios

The body itself becomes the subagent's system prompt — write it in second person ("You are…", "You will…").

## Invocation

The main agent calls:

```
Agent({
  subagent_type: "code-reviewer",
  prompt: "Review the diff in src/auth/."
})
```

The subagent runs to completion in its own context window and returns its result to the main agent. The main agent's context only sees the result, not the subagent's intermediate reasoning.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | Agent registered on next session start |
| Session start | Description loaded so the main agent knows the agent exists |
| `Agent({subagent_type})` called | Fresh context spawned with agent's system prompt + tool allowlist |
| Agent completes | Result returned to main agent; subagent context discarded |
| `/reload-plugins` | Hot-swap on **next invocation** — already-running subagents finish with the old config |
| Plugin disabled | Agent removed on next session start |

Hot-swappable per-invocation. No mid-flight reload.

## Boundaries

A subagent can:

- Use any tools allowed by `tools` (or all tools if omitted)
- Read files, run shells, call MCP tools — same surface as the main agent
- Be invoked in parallel — the main agent can dispatch 3 subagents and gather results

A subagent **cannot**:

- See the main agent's conversation history
- Spawn its own subagents (no recursion)
- Persist state across invocations (each call is a fresh context)
- Inject context into the main agent's prompt — only its return value flows back

## Trust class

**Model-loaded** for the body. The agent runs at the same trust level as the main agent — it can call the same tools, including unsandboxed ones (Bash, MCP). Restrict via `tools:` for least-privilege.

## When to use a subagent vs alternatives

| Goal | Use |
|---|---|
| Bulk reads ("read 30 files and summarize") that would pollute main context | Subagent |
| Specialised expertise (security review, debugger) the main agent shouldn't impersonate | Subagent |
| Parallel independent investigations | Subagent (spawn 3 in parallel) |
| Teach conventions Claude follows in normal flow | [Skill](./01_skills.md) |
| One-shot trigger for a routine | [Slash command](./02_slash-commands.md) |

## Frontmatter quick reference

| Field | Format | Example |
|---|---|---|
| `name` | lowercase-hyphens | `code-reviewer` |
| `description` | Prose with trigger scenarios | "Use this agent when… Typical triggers include… See When to invoke." |
| `model` | inherit/sonnet/opus/haiku | `inherit` |
| `color` | Color name | `blue` |
| `tools` | Array | `["Read", "Grep"]` |

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/agent-development/`
- [Skills](./01_skills.md) — the description-as-trigger pattern works the same way
- [`/agents` slash command](../12_cli-and-ui/) — built-in scaffolder for one-off agents
- [Capabilities index](./00_index.md)
