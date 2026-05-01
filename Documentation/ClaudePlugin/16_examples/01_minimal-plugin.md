# Minimal plugin

The smallest valid plugin: a directory with one manifest file containing two fields. Everything else is auto-discovered.

## File tree

```
hello-plugin/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    └── hello-skill/
        └── SKILL.md
```

That's it. No `README.md`, no `LICENSE`, no `bin/`, no `commands/`, no agents, hooks, MCP servers, themes, monitors, or output styles.

## `.claude-plugin/plugin.json`

```json
{
  "name": "hello-plugin",
  "description": "A minimal example plugin that greets the user"
}
```

Two fields:

- `name` — kebab-case, 3–64 characters, the only strictly required field
- `description` — recommended for any published plugin; informs the user and (loosely) the model about what the plugin does

No `version` (Claude Code falls back to the git commit SHA), no `author`, no `homepage`, no nothing.

## `skills/hello-skill/SKILL.md`

```markdown
---
name: hello-skill
description: |
  Greets the user warmly. Trigger when the user says hello, hi, hey,
  or any other greeting at the start of a session.
---

# Hello skill

Reply to the user's greeting with a warm, single-sentence response.
Do not be sycophantic; just be polite.

If the user asked a question alongside the greeting, answer the question
after the greeting.
```

The skill is auto-discovered from the conventional `skills/` folder. The `name` in frontmatter must match the folder name (`hello-skill`).

## Loading it

From the parent directory:

```bash
claude --plugin-dir ./hello-plugin
```

Claude Code:

1. Reads `.claude-plugin/plugin.json`
2. Sees no component path overrides — falls back to default discovery
3. Scans the conventional folders, finds `skills/hello-skill/SKILL.md`
4. Loads the skill metadata (name + description) into context
5. Starts the session normally

The skill is now available. The next time the user says "hello", the model sees the skill description in its index and triggers it.

## What auto-discovery picks up

Even with just the two-line manifest, Claude Code scans every conventional folder. If you add any of these directly, they'll be picked up without further manifest changes:

```
hello-plugin/
├── .claude-plugin/plugin.json
├── bin/                       ← auto-added to $PATH
│   └── hello                  ← chmod +x
├── commands/
│   └── greet.md               ← becomes /greet
├── agents/
│   └── greeter.md             ← available as Agent type
├── skills/
│   └── hello-skill/SKILL.md
├── hooks/
│   └── hooks.json             ← runtime hooks
├── monitors/
│   └── monitors.json
├── themes/
│   └── warm.json
├── outputStyles/
│   └── friendly.md
├── .mcp.json                  ← MCP server registrations
└── .lsp.json
```

You only need a manifest field if you want to:

- Override the default scan path (e.g., `"skills": ["./skills/", "./extras/"]`)
- Set identity metadata (`version`, `author`, `homepage`, `license`)
- Declare `userConfig`, `dependencies`, or `channels`
- Inline an `mcpServers` / `lspServers` / `hooks` block instead of using a separate file

## Going beyond minimal

The next steps as the plugin grows:

| Add | When |
|---|---|
| `version` field | Before publishing to a marketplace |
| `author` field | When attribution matters |
| `README.md` | Before publishing — shown in `/plugin` UI |
| `LICENSE` | Before public distribution |
| Marketplace entry | When you want others to install via `/plugin install` |

See [`02_dogfood-marketplace.md`](./02_dogfood-marketplace.md) for the next step: hosting the plugin in a marketplace.

## See also

- [`../05_plugin-anatomy/01_directory-layout.md`](../05_plugin-anatomy/01_directory-layout.md) — the conventional folders auto-discovery scans
- [`../05_plugin-anatomy/02_manifest-fields.md`](../05_plugin-anatomy/02_manifest-fields.md) — every field the manifest accepts
- [`../11_testing-and-iteration/00_index.md`](../11_testing-and-iteration/00_index.md) — `--plugin-dir` and the iteration loop
- [`../06_capabilities/01_skills.md`](../06_capabilities/01_skills.md) — skill frontmatter in detail
