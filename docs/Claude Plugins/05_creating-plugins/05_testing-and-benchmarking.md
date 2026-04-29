---
title: Testing and Benchmarking
description: Iterating on a plugin with --plugin-dir, picking up edits with /reload-plugins, and benchmarking output / cost / latency via headless mode and subagents
---

# Testing and Benchmarking

## The dev loop primitive: `--plugin-dir`

```
claude --plugin-dir <path-to-plugin>
```

Loads a plugin folder directly from disk for that session — no marketplace registration, no cache copy, no install. If a plugin with the same name is already installed via a marketplace, the `--plugin-dir` copy **shadows it for the session**, so your normal install is left untouched.

Multiple flags allowed:

```
claude --plugin-dir ./plugin-a --plugin-dir ./plugin-b
```

Useful when you maintain several plugins at once, or want to A/B two versions of the same plugin side-by-side.

## Picking up edits mid-session

After editing a skill body, command body, script, or wrapper:

```
/reload-plugins
```

Re-scans active plugins and reports counts:

```
Reloaded: 5 plugins · 4 skills · 5 agents · 1 hook · 0 plugin MCP servers · 1 plugin LSP server
```

If your plugin's skill or command count goes missing from the totals, the load failed — check the manifest and try again.

## Verifying the plugin loaded

- Skills appear in the system reminder list as `<plugin>:<skill>`
- `/help` shows slash commands prefixed with `<plugin>:<command>`
- `which <wrapper>` resolves under the plugin's `bin/` (whether installed or via `--plugin-dir`)

## Benchmarking changes

Loading isn't the same as helping. To know whether a plugin actually changes outcomes — and at what cost — you need to compare runs with and without it.

### Headless one-shots

```
claude -p "<prompt>"
```

Runs Claude non-interactively and prints the result to stdout. Each run reports three numbers worth tracking:

- **Tokens** — total input + output. Compare to gauge "did the plugin make the prompt fatter?"
- **Wall time** — duration in ms. Compare to gauge "did the extra context slow things down?"
- **Cost** — USD. Compare to gauge "is the value worth the spend?"

A small shell script that fires the same prompt twice — once with `--plugin-dir`, once without — and captures the three numbers per run is enough to answer most "does this plugin actually help" questions on a single use case.

### Subagent comparison

For prompts that need a fuller agent loop than `-p` gives you, spawn two subagents on the same prompt: one with the plugin loaded, one without. Diff their outputs by hand, and capture the same three metrics (tokens, duration, cost) from each subagent's completion notification.

This is the right unit when the task involves multiple tool calls, file edits, or branching reasoning — anything that doesn't fit a one-shot answer.

### Automated eval loop — `skill-creator`

If you want a structured comparison across more than a handful of prompts — with grading, an eval viewer, and side-by-side metrics — install the `skill-creator` skill from the official marketplace:

```
/plugin install skill-creator@claude-plugins-official
```

It automates the with-plugin / baseline split end-to-end: parallel subagent runs, grading against per-prompt assertions, and a browser-based viewer that shows pass rates, token deltas, and timing for each configuration. It's targeted at skills specifically, but the pattern transfers cleanly to any plugin capability.

## Debugging when things don't work

| Symptom | Likely cause | Fix |
|---|---|---|
| `command not found: <wrapper>` | Plugin not loaded, or `bin/<wrapper>` not `chmod +x` | `which <wrapper>`, `chmod +x bin/*`, retry |
| Skill not triggering on relevant prompts | Description too narrow or too vague | Tighten the `description` frontmatter — include specific triggers and an explicit "use when…" line |
| Slash command doesn't appear in `/help` | Plugin not loaded, or filename has a typo | `/reload-plugins`; verify `commands/<name>.md` exists |
| `${CLAUDE_PLUGIN_ROOT}` shows as empty in a Bash tool call | Env var only resolves in commands/hooks, not skill bodies or shell tools | Use a `bin/` wrapper — see [Bin Wrappers](./04_bin-wrappers.md) |
| Multiple skill versions appear | Both `--plugin-dir` AND a marketplace install active | Expected — `--plugin-dir` shadows the install for the session |

## See also

- **[Bin Wrappers](./04_bin-wrappers.md)** — the `${CLAUDE_PLUGIN_ROOT}` workaround
- **[Versioning and Publishing](./06_versioning-and-publishing.md)** — going from local iteration to release
- **[Uninstalling](../06_uninstalling.md)** — cache reset patterns
