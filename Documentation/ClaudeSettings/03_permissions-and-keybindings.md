---
title: Permissions and Keybindings
description: The permissions key in settings.json and the separate ~/.claude/keybindings.json file — both user-controlled, neither plugin-shippable
---

# Permissions and Keybindings

Two related user-controlled surfaces:

- **Permissions** — the `permissions` key inside `settings.json` (any of the four scopes). Controls which tools Claude is allowed to invoke.
- **Keybindings** — a **separate file** at `~/.claude/keybindings.json`. Controls keyboard shortcuts in the Claude Code UI.

Neither is plugin-shippable. A plugin can never silently grant itself a permission, and a plugin cannot rebind a user's keys.

## Permissions

### Format

```json
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(npm run test:*)",
      "Read(./src/**)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(curl:*)",
      "Write(/etc/**)"
    ],
    "additionalDirectories": [
      "../shared-libs"
    ]
  }
}
```

| Key | Effect |
|---|---|
| `allow` | Patterns that auto-approve a tool call without prompting |
| `deny` | Patterns that block a tool call outright |
| `additionalDirectories` | Extra filesystem roots Claude is allowed to read/write outside the current project |

### Pattern shape

`<ToolName>(<argument-pattern>)` — the tool name is a Claude Code tool (`Bash`, `Read`, `Write`, `Edit`, an MCP tool like `mcp__github__create_issue`, etc.), and the argument pattern is a glob-style match against the tool's serialised arguments.

For `Bash`, the argument pattern is the command line. The conventions:

| Pattern | Matches |
|---|---|
| `Bash(git status:*)` | `git status`, `git status -s`, anything starting `git status` |
| `Bash(git diff)` | Exactly `git diff`, no arguments |
| `Bash(npm:*)` | Any `npm` invocation |
| `Bash(*)` | Any bash command (effectively, "trust all bash") |

For `Read` / `Write` / `Edit`, the argument pattern matches a file path glob.

### Precedence

`deny` always beats `allow`. Across scopes, [Managed > Local > Project > User](./01_settings-files-and-precedence.md#precedence). A managed-scope `deny` cannot be overridden.

### Why permissions are user-only

A plugin shipping `permissions` would amount to the plugin granting itself trust. That's why even a plugin's root-level `settings.json` cannot contain a `permissions` block — it would be silently ignored. Plugins declare their *intent* via `allowed-tools` in skill/command frontmatter, but the **user** decides whether each tool call is approved at runtime, and which patterns to fast-path via their own `settings.json`.

When a plugin installs and starts asking for permissions you'd rather not grant repeatedly, the right answer is to add the patterns to your own `permissions.allow` (and consider scoping them to project or local rather than user, so the trust doesn't leak across projects).

## Keybindings

### File location

```
~/.claude/keybindings.json
```

This is a **separate file** at user scope only — there is no project-scope or managed-scope override file for keybindings. The path is fixed.

### Format

```json
{
  "bindings": [
    {
      "key": "ctrl+s",
      "command": "save"
    },
    {
      "key": "ctrl+k ctrl+s",
      "command": "show-shortcuts"
    },
    {
      "key": "alt+enter",
      "command": "submit"
    }
  ]
}
```

| Field | Notes |
|---|---|
| `key` | Single key (`enter`), modifier+key (`ctrl+s`), or chord (`ctrl+k ctrl+s` — two keystrokes in sequence) |
| `command` | A built-in editor command name |

Chord bindings split on space; both halves are pressed in sequence. Modifiers stack with `+`.

### Why keybindings live in their own file

`settings.json` is the place where settings can be *overridden by scope* (project beats user, managed beats everything). Keybindings are inherently per-user — there's no useful "this project uses different keys" semantics for the same person — so they get a single user-level file with no scoping machinery. The file is also re-read on save, unlike `settings.json` which generally requires a session restart for some keys.

### Not plugin-shippable

A plugin cannot ship `keybindings.json`. The file lives in the user's home directory, not in any scope a plugin can write to. If a plugin wants to suggest a workflow that benefits from a keybinding, it documents the suggestion in its README — the user adds the binding manually.

## What plugins *can* declare

Plugins declare their tool needs in skill/command frontmatter via `allowed-tools`. That's a *declaration of intent*, not a grant — it tells the model "this skill is permitted to call these tools" but the user still gates each call via the runtime permission prompt (or auto-approves via their own `settings.json` `permissions.allow`).

```yaml
# In a plugin's skill SKILL.md frontmatter
allowed-tools:
  - Bash(git:*)
  - Read
  - Write
```

This does not bypass the user's `permissions.deny`. It only narrows what the model is told it has access to within the skill — `deny` rules in the user's `settings.json` still apply.

## See also

- [Settings Files and Precedence](./01_settings-files-and-precedence.md) — where the `permissions` key goes and how scopes resolve
- [Environment Variables](./04_environment-variables.md) — runtime knobs that aren't permission-related but affect what tools can do
- Official: [Claude Code settings — permissions](https://code.claude.com/docs/en/settings#permissions)
- Official: [Keybindings](https://code.claude.com/docs/en/keybindings)
