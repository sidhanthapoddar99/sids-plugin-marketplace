# Plugin user configuration

The `userConfig` field in `plugin.json` declares values Claude Code prompts the user for when the plugin is enabled. It replaces hand-editing `settings.json` and gives plugin authors a structured way to expose configurable settings.

> [!important]
> `userConfig` is **NOT** standard JSON Schema. It uses a custom shape with a fixed set of types and option fields. The vocabulary below is the full set.

## Shape

```json
{
  "name": "my-plugin",
  "userConfig": {
    "apiKey": {
      "type": "string",
      "title": "API key",
      "description": "Token for the upstream service",
      "sensitive": true,
      "required": true
    },
    "logLevel": {
      "type": "string",
      "default": "info",
      "description": "One of: debug, info, warn, error"
    },
    "scanDirs": {
      "type": "directory",
      "multiple": true,
      "description": "Directories to scan"
    },
    "timeoutSeconds": {
      "type": "number",
      "default": 30,
      "min": 1,
      "max": 600
    }
  }
}
```

Each top-level key is the option's identifier. Identifiers must be valid (alphanumeric + underscore). Each option is an object describing one setting.

## Option fields

| Field | Type | Notes |
|---|---|---|
| `type` | required | One of: `string`, `number`, `boolean`, `directory`, `file` |
| `title` | required | Human-readable label shown in `/plugin` |
| `description` | required | Help text shown in `/plugin` |
| `sensitive` | boolean, optional | Masks input. Stored in OS keychain (not `settings.json`) |
| `required` | boolean, optional | Plugin can't enable until this is set |
| `default` | optional | Pre-fill value. Type must match `type` |
| `multiple` | boolean, optional | For `type: "string"` — value is an array of strings |
| `min` / `max` | number, optional | For `type: "number"` — range bounds |

There is no `enum`, no `format: password` (use `sensitive: true`), no `oneOf`/`anyOf`/`allOf`, no nested object shapes. Stay within the vocabulary above.

## Where values live

| Kind | Storage |
|---|---|
| `sensitive: true` values | OS keychain (~2 KB total cap, shared with OAuth tokens) |
| All other values | `~/.claude/settings.json` under `pluginConfigs[<plugin-id>].options` |

`<plugin-id>` is the install identifier `<plugin-name>@<marketplace>` slugified with non-`[a-zA-Z0-9_-]` characters replaced by `-`. So `formatter@my-marketplace` becomes `formatter-my-marketplace`. See [`../development-cycle/lifecycle-and-storage.md`](../development-cycle/lifecycle-and-storage.md).

## Reading values from plugin code

Two ways:

### 1. Inline substitution: `${user_config.KEY}`

Substituted in:
- Skill content (the body of `SKILL.md`, including frontmatter values)
- Agent content
- Hook commands
- Monitor commands
- MCP and LSP server configs

```json
// In .mcp.json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["server.js"],
      "env": {
        "API_KEY": "${user_config.apiKey}"
      }
    }
  }
}
```

For `sensitive: true` values, substitution does NOT happen in skill or agent content (they're kept out of model-facing context). They DO substitute in commands, env vars, and MCP/LSP configs that flow only to subprocess.

### 2. Subprocess env vars: `CLAUDE_PLUGIN_OPTION_<KEY>`

All `userConfig` values are exported as env vars to subprocesses launched by hooks, monitors, and MCP/LSP servers. Variable names are uppercased with non-alphanumerics replaced by `_`:

| `userConfig` key | Env var |
|---|---|
| `apiKey` | `CLAUDE_PLUGIN_OPTION_APIKEY` |
| `log_level` | `CLAUDE_PLUGIN_OPTION_LOG_LEVEL` |
| `scanDirs` | `CLAUDE_PLUGIN_OPTION_SCANDIRS` (newline-joined for `multiple: true`) |

In a hook script:

```bash
#!/usr/bin/env bash
api_key="$CLAUDE_PLUGIN_OPTION_APIKEY"
if [[ -z "$api_key" ]]; then
  echo "error: apiKey not set — run /plugin → Settings → my-plugin" >&2
  exit 3
fi
```

## When you'd use `.claude/<plugin-name>.local.md` instead

The legacy pattern is a YAML-frontmatter + Markdown file at `.claude/<plugin-name>.local.md` (gitignored, project-local) read by the plugin's hooks/commands/agents at runtime. Superseded by `userConfig` for most cases — `userConfig` integrates with `/plugin`'s enable flow and uses the OS keychain for secrets.

The `.local.md` pattern is still useful for:
- Stateful per-session data the plugin writes back at runtime (`userConfig` is read-only from the plugin's perspective)
- Genuinely free-form prose (e.g. "describe your team's coding style") where structured fields are awkward

The vendored `topics/plugin-settings/` skill (under `references/topics/`) covers the legacy pattern in depth — go there if you specifically need to use it.

## Migration notes

- A plugin that previously used `.local.md` can add `userConfig` for new fields and keep reading the legacy file for existing ones, with a deprecation warning. Claude Code does not provide an automatic migration helper — plugin authors must hand-roll the conversion.
- `.local.md` is gitignored by Claude Code; `userConfig` values live in `~/.claude/settings.json` (or the keychain for sensitive). Neither pattern leaks values into the project repo.

## Common mistakes

- **Using JSON Schema vocabulary.** `format: password`, `oneOf`, `properties`, etc. are not recognized. Use the option-field set above.
- **Defaulting credentials.** Don't put `default` on a `sensitive: true` field — the user should enter their own credential explicitly.
- **Logging resolved options wholesale.** Mask `sensitive` values before logging. The OS keychain entry exists precisely to keep these out of `settings.json` and casual logs.

## Reference

- Official: [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) (ground truth)
