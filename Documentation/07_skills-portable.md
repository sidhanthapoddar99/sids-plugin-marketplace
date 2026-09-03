# 07. Writing one skill that runs everywhere

Write the skill to the Agent Skills standard and it runs unchanged on Claude Code, Codex, Hermes and OpenCode. A skill is a folder with a `SKILL.md` file inside it. The standard defines six frontmatter fields and nothing else. Every extra field a host invents is an extension. Extensions are the only thing that breaks portability, so a portable skill uses the six standard fields and keeps every runtime file inside its own folder.

This file covers the standard, the per-host differences, and the procedure to write and test a portable skill. For host-specific packaging see [02_claude-code-plugins.md](02_claude-code-plugins.md), [04_codex.md](04_codex.md), [05_hermes.md](05_hermes.md) and [06_opencode.md](06_opencode.md). For a side-by-side of the four hosts see [09_comparison.md](09_comparison.md).

## 1. What the standard is

The Agent Skills standard at agentskills.io defines the `SKILL.md` file format. Anthropic developed it and released it as an open standard.

The standard defines three things only:

1. The directory layout of a skill.
2. The YAML frontmatter fields and their limits.
3. The progressive disclosure model.

The standard does **not** say where skill folders live on disk. Each host picks its own discovery paths. Section 5 lists them.

## 2. Directory layout

A skill is one directory. The directory name must match the `name` field.

```
skill-name/
├── SKILL.md          # Required. Frontmatter plus instructions.
├── scripts/          # Optional. Executable code the agent runs.
├── references/       # Optional. Documents the agent reads on demand.
├── assets/           # Optional. Templates, images, data files.
└── ...               # Any other file or directory is allowed.
```

`scripts/` holds runnable code. Keep each script self-contained, or state its dependencies in the file.
`references/` holds long documents. The agent loads one only when `SKILL.md` points at it.
`assets/` holds static resources such as templates and lookup tables.

## 3. Frontmatter

`SKILL.md` starts with YAML frontmatter between two `---` lines. Markdown instructions follow it.

```markdown
---
name: pdf-processing
description: Extract PDF text, fill forms, merge files. Use when handling PDFs.
---

# PDF processing

## When to use
...
```

### The six standard fields

Two fields are required. Four are optional.

| Field | Required | Constraint |
|---|---|---|
| `name` | Yes | 1 to 64 characters. Lowercase `a-z`, digits and hyphens. No leading or trailing hyphen. No `--`. Must match the parent directory name. |
| `description` | Yes | 1 to 1024 characters. Says what the skill does and when to use it. |
| `license` | No | A license name, or the name of a bundled license file. |
| `compatibility` | No | Up to 500 characters. Environment requirements such as needed packages. |
| `metadata` | No | A map of string keys to string values. The sanctioned escape hatch for host-specific data. |
| `allowed-tools` | No | Space-separated list of pre-approved tools. Marked **experimental** by the standard. Support varies by host. |

### `name` and `description` rules

The `name` field is an identifier, not a title. Keep it equal to the folder name. A mismatch makes some hosts warn and others reject the skill.

The `description` field is the only text a host loads at startup. The agent decides from it whether to open the skill. Write both halves: what the skill does, and when to use it. Put the trigger words near the front. Codex shortens descriptions when its startup budget is tight, so a front-loaded trigger word still matches.

A poor description is `Helps with PDFs.` A good one names the actions and the trigger words.

## 4. Progressive disclosure

Progressive disclosure means the host loads more of the skill only as the task needs it. It is what keeps a large skill cheap. [01_concepts.md](01_concepts.md) holds the three-tier model and what loads at each tier. This section holds the authoring rules that follow from it.

Two limits from the standard:

- Keep the `SKILL.md` body under 5000 tokens. Keep it under 500 lines.
- Keep file references one level deep from `SKILL.md`. Do not chain a reference to another reference.

Use relative paths from the skill root when you link a file.

```markdown
See [the reference guide](references/REFERENCE.md) for the full field list.

Run the extraction script:
scripts/extract.py
```

Move detail out of `SKILL.md` into `references/`. Move parsing and transforms out of prose into `scripts/`. A script states the steps more precisely than instructions do, and it costs no context until the agent runs it.

## 5. Discovery paths per host

Each host scans its own set of directories. A portable skill still needs the right location, and this table gives it.

| Host | User scope | Project scope | Bundled or plugin scope | Reads `.agents/skills/` |
|---|---|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md`, plus nested `.claude/skills/` folders below the working directory | `<plugin>/skills/<name>/SKILL.md`, namespaced `/plugin:skill`. Enterprise path set by managed settings. | No |
| Codex | `$HOME/.agents/skills` | `$CWD/.agents/skills`, every parent, and `$REPO_ROOT/.agents/skills` | Admin `/etc/codex/skills`. Skills bundled with Codex. Plugin skills via `"skills": "./skills/"`. | Yes |
| Hermes | `~/.hermes/skills/` and `skills.external_dirs` from `config.yaml` | `<project>/.hermes/skills/` and `<project>/.agents/skills/` | Skills bundled in the Hermes repo. Plugin skills via `register_skill`. | Yes |
| OpenCode | `~/.config/opencode/skills/`, `~/.claude/skills/`, `~/.agents/skills/` | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/`, walking up to the git worktree | None. OpenCode plugins are code modules and bundle no skills. | Yes |

Three consequences:

1. `.agents/skills/` is the widest shared path. Three of the four hosts read it. The standard calls it "a widely-adopted convention for cross-client skill sharing" but does not mandate it.
2. Claude Code is the exception. It reads only its own `.claude/` paths and plugin paths. To reach Claude Code you either place the folder under `.claude/skills/` or ship it in a plugin.
3. OpenCode reads Claude Code's paths as well. Three environment variables turn that off. [06_opencode.md](06_opencode.md) lists them.

On a name collision, the standard's guidance and every host agree on one rule: a project-level skill overrides a user-level skill. Claude Code inverts this for its own levels. There, enterprise overrides personal, and personal overrides project. Plugin skills are namespaced, so they never collide.

## 6. Frontmatter compatibility table

`standard` means the host implements the field as the standard defines it. `extension` means the host adds behaviour beyond the standard. `ignored` means the host reads the file and drops the field. `not verified` means no official source states the behaviour.

### Standard fields across hosts

Each cell says how one host treats one standard field.

| Field | Claude Code | Codex | Hermes | OpenCode |
|---|---|---|---|---|
| `name` | standard, but Claude Code does not require it. Without it Claude Code uses the install directory name | standard | standard | standard |
| `description` | standard, but `description` plus `when_to_use` is truncated at 1536 characters in the listing | standard, shortened when the startup budget is tight | standard, truncated at 60 characters in the system-prompt skill index | standard, 1 to 1024 characters |
| `license` | standard, accepted and not acted on | not verified | standard | standard |
| `compatibility` | standard, accepted and not acted on, 500 characters | not verified | not verified | standard |
| `metadata` | standard. Do not reuse a frontmatter field name such as `paths` as a key | not verified | extension. Hermes reads a `metadata.hermes` block | standard, string to string only |
| `allowed-tools` | standard. Pre-approves tools for the invoking turn | not verified | not verified | ignored. Tool gating lives in `opencode.json` under `permission.skill` |

### Host extensions, all non-portable

Each host adds its own fields. None of them travels.

| Host | Extension fields |
|---|---|
| Claude Code | `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `disallowed-tools`, `model`, `effort`, `context`, `agent`, `background`, `hooks`, `paths`, `shell` |
| Codex | `disable-model-invocation` and the `disable_model_invocation` alias. Everything else goes in a sibling `agents/openai.yaml` file, not in frontmatter |
| Hermes | `version`, `author`, `platforms`, `required_environment_variables`, `required_credential_files`, and the `metadata.hermes` block |
| OpenCode | None. The docs state "Unknown frontmatter fields are ignored" |

Two facts govern how you use this table:

- OpenCode states plainly that it ignores unknown fields. How Codex and Hermes treat a Claude Code extension field is **not verified**. No official page for either host says whether they ignore, warn or reject.
- Claude Code itself rejects extension fields on the way out. Uploading to claude.ai, calling the Skills API, or packaging with `package_skill.py` allows only the six standard fields. An extra field is a hard error, not a warning: `Unexpected key(s) in SKILL.md frontmatter: argument-hint.`

That second fact is the strongest argument for the six-field rule. Even inside the Anthropic ecosystem, the six fields are the only ones that travel.

## 7. Rules for a portable skill

Follow these five rules and the skill folder works on every host without a per-host copy.

1. **Use the six standard fields only.** Put anything host-specific under `metadata` with a namespaced key such as `metadata.myorg-version`. Treat `allowed-tools` as optional, because it is experimental and OpenCode drops it.
2. **Keep everything at runtime inside the skill folder.** Scripts, references, assets and templates all live under the skill directory. Codex packages only what `"skills": "./skills/"` points at. Hermes copies `SKILL.md` plus only the files it explicitly references. A file outside the folder does not travel.
3. **Use no host-specific path.** Do not write `~/.claude/...` or `${CLAUDE_PLUGIN_ROOT}` or `${HERMES_SKILL_DIR}` in the body. Those variables exist on one host each. Use paths relative to the skill root instead.
4. **Ship no commands and no hooks.** A slash command is a Claude Code and OpenCode concept with different shapes on each. Hooks are host-specific and Codex's publishing validator rejects a `hooks` key outright. Neither is part of the skill standard.
5. **Assume no tool beyond read, write and shell.** Name the commands the skill needs in `compatibility`. Do not assume a host-specific tool such as `webfetch` exists.

What you give up by following these rules: Claude Code's `context: fork` and `paths` gating, Hermes' `` !`cmd` `` inline shell and `blueprint:` scheduling, and Codex's `agents/openai.yaml` policy block. On a foreign host those become inert text at best.

## 8. Procedure: write, test and package

Follow these steps in order.

1. **Create the folder.** Use the kebab-case name you want.
   ```bash
   mkdir -p my-skill/references my-skill/scripts
   ```
2. **Write `SKILL.md`.** Start with the two required fields. Add nothing else until you need it.
   ```markdown
   ---
   name: my-skill
   description: Does X and Y. Use when the user mentions X, Y, or Z.
   ---

   # My skill

   ## When to use
   ## Procedure
   ## Verification
   ```
3. **Check the length.** Keep the body under 500 lines. Move any long block into `references/`.
   ```bash
   wc -l my-skill/SKILL.md
   ```
4. **Validate against the standard.** The reference library lives in `github.com/agentskills/agentskills`.
   ```bash
   skills-ref validate ./my-skill
   ```
5. **Test on the shared path first.** Place the folder under `.agents/skills/` and start Codex, Hermes or OpenCode in that repository.
   ```bash
   mkdir -p .agents/skills && cp -r my-skill .agents/skills/
   ```
6. **Test on Claude Code.** Claude Code does not read `.agents/skills/`. Copy or symlink the folder, then invoke `/my-skill`.
   ```bash
   mkdir -p .claude/skills && ln -s ../../.agents/skills/my-skill .claude/skills/my-skill
   ```
7. **Check the trigger, not just the body.** Start a fresh session. Ask a question that should trigger the skill without naming it. If the agent does not load the skill, rewrite the `description`, not the body.
8. **Package it.** Choose one of three routes.

| Route | What you ship | Reach |
|---|---|---|
| Bare folder in a git repository | The skill folder alone | Any host, installed by hand or by `npx skills add <owner/repo>` |
| Claude Code plugin | The folder under `plugins/<name>/skills/` plus a marketplace entry | Claude Code, and Codex through the shared manifest paths |
| Codex plugin | The folder under `skills/` plus `.codex-plugin/plugin.json` | Codex |

For the plugin and marketplace routes see [03_claude-code-marketplaces.md](03_claude-code-marketplaces.md) and [04_codex.md](04_codex.md). For how this repository does it see [08_this-marketplace.md](08_this-marketplace.md).

Claude Code ships a `skill-creator` skill in the `claude-plugins-official` marketplace. It scaffolds a skill, writes test prompts, runs evaluations and tunes the description.

## 9. Cross-host installers

Two tools install a skill folder into several hosts at once.

| Tool | What it does |
|---|---|
| `npx skills add <owner/repo>` | Installs from a git repository into each detected host's own skills directory. From `vercel-labs/skills`. Its target table writes to `.claude/skills` for Claude Code, `.agents/skills` for Codex and OpenCode, and `.hermes/skills` for Hermes. |
| `skills.sh` | The companion catalog of skills hosted in GitHub repositories. It is a skills registry, not a plugin registry. |

Neither is an official product of any of the four hosts. Both install `SKILL.md` folders only. Neither installs hooks, agents or MCP servers. MCP is the Model Context Protocol, an open protocol for connecting an agent to external tool servers.

## Sources

- https://agentskills.io/specification
- https://agentskills.io/client-implementation/adding-skills-support.md
- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/plugins
- https://learn.chatgpt.com/docs/build-skills
- https://developers.openai.com/codex/plugins/build
- https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
- https://opencode.ai/docs/skills
- https://opencode.ai/docs/rules
- https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator
- https://github.com/vercel-labs/skills
- https://github.com/agentskills/agentskills
