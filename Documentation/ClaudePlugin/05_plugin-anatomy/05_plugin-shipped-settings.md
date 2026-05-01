# Plugin-shipped `settings.json`

A `settings.json` file at the plugin's **root** (sibling of `.claude-plugin/`, not nested inside it) applies default Claude Code settings when the plugin is enabled. This is distinct from the `settings` field in `plugin.json` — when both are present, the root-level file wins.

## File location

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── settings.json          ← THIS file
└── ...
```

Not to be confused with:

- `.claude-plugin/plugin.json` — the plugin manifest itself
- The user's `~/.claude/settings.json` — Claude Code's global config (untouched by plugins)
- A project's `<repo>/.claude/settings.json` — project-scope Claude Code config

The plugin-shipped file is *merged into* Claude Code's resolved settings only while the plugin is enabled. When the plugin is disabled or uninstalled, the merge is undone — values revert to whatever the user / project would have without the plugin.

## Recognised keys

Currently **two** keys are honoured. Unknown keys are silently ignored.

| Key | Type | Purpose |
|---|---|---|
| `agent` | string | Activate one of the plugin's custom agents as the **main thread**, applying its system prompt, tool restrictions, and model. Effectively lets a plugin change Claude Code's identity for the session |
| `subagentStatusLine` | string | Format string shown in the status line whenever a subagent is active. Plugin-bundled status formatting that follows the same template-substitution rules as user-set `subagentStatusLine` |

The `agent` key is the dramatic one — it transforms Claude Code from a generalist coding assistant into whatever the plugin's chosen agent specifies. `subagentStatusLine` is cosmetic but useful for plugins that spawn many subagents.

### `agent`

```json
{
  "agent": "release-manager"
}
```

Activates `agents/release-manager.md` as the main thread. The agent's frontmatter (system prompt, allowed tools, model selection) replaces Claude Code's defaults for the session:

```yaml
---
name: release-manager
description: Cuts releases and tags
tools: Bash, Read, Edit, Grep
model: claude-sonnet-4-5
---
You are a release engineer. Walk through the release checklist...
```

This is appropriate for plugins built around a single workflow (a release plugin, a code-review plugin) where the user explicitly opts in to that mode by enabling the plugin. It is *not* appropriate for general-purpose plugins — you'd be hijacking the user's Claude Code session.

### `subagentStatusLine`

```json
{
  "subagentStatusLine": "deploy-kit ▸ {agent}"
}
```

Substitutions follow Claude Code's normal status-line template syntax — see [`Documentation/ClaudeSettings/02_status-line.md`](../../ClaudeSettings/02_status-line.md) for the full token vocabulary.

## Priority over the manifest's `settings` field

`plugin.json` may also include a `settings` field with the same recognised keys:

```json
// .claude-plugin/plugin.json
{
  "name": "my-plugin",
  "settings": {
    "subagentStatusLine": "my-plugin ▸ {agent}"
  }
}
```

If both `plugin.json` `settings` and the root-level `settings.json` exist, the root-level file wins. This means:

- Authors writing the manifest by hand can use `settings` inline
- Authors who want to share `settings.json` between scopes (or generate it from a template) can ship the file directly

Most plugins use one or the other, not both. The root-level file is the more flexible option — it can carry future keys without requiring a manifest schema bump.

## Unknown keys are silent

Setting any key other than `agent` or `subagentStatusLine` does nothing. There's no warning, no error, no log. Future Claude Code versions may recognise additional keys; until then, anything you put there is dead weight.

This forward-compatibility means you can ship a `settings.json` referencing a key you expect a future Claude Code release to honour, and old Claude Code versions will simply ignore it.

## Worked example

A plugin that wraps Claude Code as a release-management tool:

```
release-kit/
├── .claude-plugin/
│   └── plugin.json
├── settings.json
├── agents/
│   └── release-manager.md
└── skills/
    └── release-checklist/
        └── SKILL.md
```

`settings.json`:

```json
{
  "agent": "release-manager",
  "subagentStatusLine": "release-kit ▸ {agent}"
}
```

When the user runs `/plugin enable release-kit`, the next session opens as the release-manager agent. The user is now talking to a release engineer, not generic Claude Code, until they disable the plugin.

## When NOT to ship a `settings.json`

- **Generic-purpose plugins.** Don't take over the main thread unless the plugin's whole purpose is the takeover.
- **Plugins shipped via dependencies.** A dependency that ships an `agent` setting can hijack the user's session unexpectedly. If you're a dependency target, leave `settings.json` empty or absent.
- **Plugins with multiple workflows.** If the plugin has 3 commands and 4 skills, none of them being "the workflow", `agent` doesn't make sense — let the user keep generic Claude Code as their main thread.

## See also

- [`02_manifest-fields.md`](./02_manifest-fields.md) — the `settings` field in `plugin.json` (precedence: root file beats manifest field)
- [`04_user-config.md`](./04_user-config.md) — the *other* config surface (user-prompted values, not defaults)
- [`Documentation/ClaudeSettings/02_status-line.md`](../../ClaudeSettings/02_status-line.md) — status-line template syntax for `subagentStatusLine`
- [`../06_capabilities/03_subagents.md`](../06_capabilities/03_subagents.md) — subagent frontmatter, what `agent` substitutes for the main thread
- Official: [Ship default settings with your plugin](https://code.claude.com/docs/en/plugins#ship-default-settings-with-your-plugin)
