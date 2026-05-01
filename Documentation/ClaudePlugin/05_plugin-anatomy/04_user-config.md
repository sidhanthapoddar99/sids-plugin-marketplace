# `userConfig`

The `userConfig` field declares values Claude Code prompts the user for when the plugin is enabled. It replaces the legacy pattern of hand-editing `settings.json` and gives plugin authors a structured way to expose configurable settings.

> [!important]
> `userConfig` is **NOT** standard JSON Schema. It uses a custom shape with a fixed set of types and option fields. The vocabulary on this page is the full set — `format: password`, `enum`, `oneOf`, `properties`, and other JSON Schema vocabulary are not recognised.

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

Each top-level key is the option's identifier. Identifiers must be valid (alphanumeric + underscore — no dashes). Each option value is an object describing one setting.

## Option types

| `type` | Stores |
|---|---|
| `string` | Free-form text |
| `number` | Numeric (integer or float, validated against `min`/`max`) |
| `boolean` | `true` or `false` |
| `directory` | Path to a directory; `/plugin` UI presents a directory picker |
| `file` | Path to a file; `/plugin` UI presents a file picker |

That's the full set. There are no `array`, `object`, `enum`, or composite types. For multi-value cases, use `multiple: true` on `string`, `directory`, or `file` (yields a flat array).

## Option fields

| Field | Type | Notes |
|---|---|---|
| `type` | string, **required** | One of the five types above |
| `title` | string, optional | Human-readable label shown in `/plugin` |
| `description` | string, optional | Help text shown in `/plugin` |
| `sensitive` | boolean, optional | Masks input. Stored in OS keychain rather than `settings.json` |
| `required` | boolean, optional | Plugin can't enable until this is set |
| `default` | matches `type`, optional | Pre-fill value. Type must match |
| `multiple` | boolean, optional | For `string`/`directory`/`file` — value becomes an array |
| `min` / `max` | number, optional | For `type: "number"` — range bounds |

## Where values live

| Kind | Storage |
|---|---|
| `sensitive: true` values | OS keychain (~2 KB total cap, shared with OAuth tokens) |
| All other values | `~/.claude/settings.json` under `pluginConfigs[<plugin-id>].options` |

`<plugin-id>` is the install identifier — typically `<plugin-name>` or `<plugin-name>@<marketplace>` slugified. Sensitive values never touch the on-disk `settings.json`; they're fetched from the keychain at substitution time.

## Substitution: `${user_config.KEY}`

Inline-substituted in:

| Surface | Notes |
|---|---|
| MCP server configs (`.mcp.json` and inline `mcpServers`) | All values, including `sensitive` |
| LSP server configs (`.lsp.json` and inline `lspServers`) | All values, including `sensitive` |
| Hook commands (`hooks/hooks.json`) | All values, including `sensitive` |
| Monitor commands (`monitors/monitors.json`) | All values, including `sensitive` |
| Skill content (`SKILL.md` body and frontmatter) | **Non-sensitive only** |
| Agent content (`agents/<name>.md` body and frontmatter) | **Non-sensitive only** |
| Command content (`commands/<name>.md`) | **Non-sensitive only** |

Sensitive values are deliberately excluded from skill/agent/command substitution because that content flows through the model's context. Substitution into MCP/LSP/hook/monitor commands is safe because those flow only to subprocesses that already have keychain access.

```json
// In .mcp.json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/server.js"],
      "env": {
        "API_KEY": "${user_config.apiKey}",
        "LOG_LEVEL": "${user_config.logLevel}"
      }
    }
  }
}
```

## Subprocess env vars: `CLAUDE_PLUGIN_OPTION_<KEY>`

All `userConfig` values are also exported as env vars to subprocesses launched by hooks, monitors, and MCP/LSP servers. Variable names are uppercased with non-alphanumerics replaced by `_`:

| `userConfig` key | Env var |
|---|---|
| `apiKey` | `CLAUDE_PLUGIN_OPTION_APIKEY` |
| `log_level` | `CLAUDE_PLUGIN_OPTION_LOG_LEVEL` |
| `scanDirs` (with `multiple: true`) | `CLAUDE_PLUGIN_OPTION_SCANDIRS` (newline-joined) |

In a hook script:

```bash
#!/usr/bin/env bash
api_key="$CLAUDE_PLUGIN_OPTION_APIKEY"
if [[ -z "$api_key" ]]; then
  echo "error: apiKey not set — run /plugin → Settings → my-plugin" >&2
  exit 3
fi
```

Sensitive values are passed via env var to subprocesses too — the model itself never sees them, but a hook script can read them.

## When values get prompted for

- **On enable** — user runs `/plugin install` or flips `enabledPlugins[<plugin>]: true`. Required values without defaults trigger an interactive prompt.
- **Through `/plugin` Settings tab** — at any time after install, the user can revisit and edit values.
- **Programmatically** — `claude plugin install` accepts a `--config <key>=<value>` flag for non-interactive setups.

If a `required: true` value is missing, the plugin loads but its components that reference the missing value behave as if the value were the empty string — typically failing fast with a useful error from the hook or MCP server.

## When you'd use `.claude/<plugin-name>.local.md` instead

The legacy pattern is a YAML-frontmatter + Markdown file at `.claude/<plugin-name>.local.md` (gitignored, project-local) read by the plugin's hooks/commands/agents at runtime. Superseded by `userConfig` for most cases — `userConfig` integrates with `/plugin`'s enable flow, uses the OS keychain for secrets, and unifies storage across projects.

The `.local.md` pattern is still useful for:

- Stateful per-session data the plugin writes back at runtime (`userConfig` is read-only from the plugin's perspective)
- Genuinely free-form prose (e.g. "describe your team's coding style") where structured fields are awkward
- Per-project config that should not be unified at user scope

See [`../15_reference/04_legacy-and-migration.md`](../15_reference/04_legacy-and-migration.md) for the legacy pattern's full shape.

## Common mistakes

- **Using JSON Schema vocabulary.** `format: password`, `oneOf`, `properties`, `enum`, etc. are not recognised. Use the option-field set above. For password-style input, set `sensitive: true`.
- **Defaulting credentials.** Don't put `default` on a `sensitive: true` field — the user should enter their own credential explicitly. Defaulting a credential leaks a placeholder into the keychain.
- **Logging resolved options wholesale.** Mask `sensitive` values before logging. The OS keychain entry exists precisely to keep these out of `settings.json` and casual logs.
- **Substituting `${user_config.SECRET_KEY}` into a SKILL.md body.** Sensitive values don't substitute into skill content; the literal `${user_config.SECRET_KEY}` string survives unchanged. Use the env var path or pass the secret only to subprocesses that need it.

## See also

- [`02_manifest-fields.md`](./02_manifest-fields.md) — `userConfig` as a manifest field
- [`05_plugin-shipped-settings.md`](./05_plugin-shipped-settings.md) — *not* the same thing; `settings.json` ships defaults, `userConfig` prompts the user
- [`../15_reference/01_env-vars.md`](../15_reference/01_env-vars.md) — `CLAUDE_PLUGIN_OPTION_<KEY>` and other plugin env vars
- [`../15_reference/04_legacy-and-migration.md`](../15_reference/04_legacy-and-migration.md) — the `.local.md` pattern
- Official: [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration)
