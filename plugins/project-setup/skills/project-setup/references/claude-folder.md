# `.claude/` folder conventions

Every repo gets a `.claude/` folder. **Empty initially.** We build up agents, commands, hooks, and skills as patterns emerge. The bootstrapper just creates the folder and the adjacent `CLAUDE.md`.

## Initial contents

```
my-app/
├── .claude/              # empty
└── CLAUDE.md             # agent-facing brief
```

That's it. No `settings.local.json`, no agents, no commands. They land when there's a real use case.

## What may go in `.claude/` over time

| Subdirectory | Contents | When to add |
|---|---|---|
| `agents/` | Project-specific custom agents | When a workflow needs an agent the marketplace doesn't ship |
| `commands/` | Project-specific slash commands | When a repeated multi-step operation deserves a `/<name>` shortcut |
| `hooks/` | Pre-tool / post-tool hooks (settings.json) | Rare — usually for safety guardrails, formatters |
| `skills/` | Project-local skills | When a knowledge pattern is project-specific and shouldn't ship as a plugin |
| `output-styles/` | Custom output styles | Rare |
| `settings.local.json` | Local permissions / model overrides | When a user has personal preferences for this repo |

Everything plugin-provided still works without these — `.claude/` is the **project-local override layer**, not the source of plugin capabilities.

## `CLAUDE.md` template

Place next to `.claude/`, at repo root.

```markdown
# <project-name>

<one-paragraph elevator pitch — what the project does, who uses it>

## Architecture

<one or two paragraphs — the major components and how they talk>

## Project structure

\`\`\`
my-app/
├── apps/
│   ├── backend/        # <one-line description>
│   └── frontend/       # <one-line description>
├── docker/
├── infra/
├── data/
└── ...
\`\`\`

## Hard rules

- <List 3-7 hard rules that override defaults: "Rust never writes DDL", "every component uses var(--token)", etc.>

## Get started

See [README.md](README.md#get-started). Quick:

\`\`\`bash
mise install
cp .env.example .env
./dev
\`\`\`

## Where to learn more

- Design docs: <link>
- Issue tracker: <link>
- Plugin / skill: <link>
```

The CLAUDE.md is **agent-first**. Designed for an LLM agent walking into the repo cold. README is human-first; both exist.

## Why empty by default

- **No premature structure.** Most repos never need a custom agent or command. Pre-creating folders gives a false impression that they're expected.
- **Build up as you discover repetition.** Same rule as "extract on third use" — don't make scaffolding for hypothetical needs.
- **Plugin capabilities cover the common case.** `documentation-guide`, `project-setup`, `ai-toolkit-dev` ship via plugin; project-local additions are the exception.

## What about `.claude/settings.local.json`?

If a project consistently triggers a permission prompt for a known-safe operation (e.g. `Bash(./dev:*)`), commit a `.claude/settings.local.json` that allows it:

```json
{
  "permissions": {
    "allow": [
      "Bash(./dev:*)",
      "Bash(./dev *)",
      "Bash(docker compose:*)",
      "Bash(uv run:*)",
      "Bash(bun *:*)"
    ]
  }
}
```

Trade-off: committed settings are shared with everyone. Don't commit anything controversial.

## Anti-patterns

- Pre-creating `.claude/agents/`, `.claude/commands/`, `.claude/skills/` with empty placeholders — clutter
- Putting plugin behaviour in `.claude/` when it should be a plugin — generalise, ship via the marketplace
- Sharing personal `settings.local.json` choices via commits — gitignore the file if it's personal
- Forgetting to gitignore `.claude/projects/`, `.claude/cache/` — Claude Code's runtime state directories, never commit
