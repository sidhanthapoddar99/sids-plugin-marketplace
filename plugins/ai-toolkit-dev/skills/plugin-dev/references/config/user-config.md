# Plugin user configuration

Two ways to expose plugin settings to users: the modern `userConfig` field in `plugin.json`, and the legacy `.claude/<plugin-name>.local.md` pattern. Use `userConfig` for new plugins.

## `userConfig` (modern)

The `userConfig` field declares a JSON Schema that Claude Code uses to render a settings UI for the plugin. Values entered by the user are persisted per-scope and exposed to the plugin at runtime.

### Declaration

```json
{
  "name": "my-plugin",
  "userConfig": {
    "type": "object",
    "properties": {
      "apiKey": {
        "type": "string",
        "description": "API key for the external service",
        "format": "password"
      },
      "logLevel": {
        "type": "string",
        "enum": ["debug", "info", "warn", "error"],
        "default": "info"
      },
      "enableExperimentalFeatures": {
        "type": "boolean",
        "default": false
      }
    },
    "required": ["apiKey"]
  }
}
```

### What Claude Code does with this

- Renders a settings panel in `/plugin` UI (the Settings tab)
- Validates user input against the schema before saving
- Persists per-scope: User > Project > Local > Managed (last write wins per scope)
- Passes the resolved config to plugin components at runtime

### Reading config at runtime

In a script run by the plugin:

```bash
# The merged config is exposed as JSON at $CLAUDE_PLUGIN_CONFIG
api_key=$(jq -r .apiKey "$CLAUDE_PLUGIN_CONFIG")
```

In a hook script, the config is also passed in the JSON payload on stdin (see `topics/hook-development/SKILL.md`).

In an agent or skill's prompt content, you can interpolate `${CLAUDE_PLUGIN_CONFIG.apiKey}` — Claude Code substitutes before loading the prompt.

### Schema features supported

- All standard JSON Schema types: `string`, `number`, `integer`, `boolean`, `object`, `array`, `null`
- `enum`, `default`, `description`, `required`
- `format`: `password` (input masked), `date`, `email`, `uri`, `path`
- Nested `object` properties (rendered as expandable groups)
- `oneOf` / `anyOf` / `allOf` for conditional fields
- `$schema` for live editor validation

### Validation failures

If a user enters config that doesn't match the schema, Claude Code rejects the save and shows the validation errors. Plugin code receives only schema-valid config — no runtime validation needed.

## `.claude/<plugin-name>.local.md` (legacy)

Older plugins use a free-form Markdown file to surface settings:

```
~/.claude/<plugin-name>.local.md
```

The plugin loaded the file at runtime, parsed its own conventions out of the markdown, and applied them. This pattern predates `userConfig`.

### Why it's deprecated

- No schema validation — plugins had to hand-roll parsing
- No UI integration — users edited the markdown by hand
- Per-scope merging was ad-hoc; many plugins only honored User scope
- Path was outside `${CLAUDE_PLUGIN_DATA}`, so it didn't survive a clean reinstall

### When you'd still use it

- Maintaining a plugin that's already shipped with this pattern and you don't want to break existing users mid-version
- The setting is intentionally free-form prose (e.g. "describe your team's coding style"), in which case JSON Schema is awkward

### Migration path

If you have a plugin using `.local.md` and want to move to `userConfig`:

1. Add `userConfig` to `plugin.json` for new fields
2. Keep reading the legacy file for one major version, with a deprecation warning
3. Provide a `claude plugin migrate-config <plugin>` script (or a SessionStart hook) that reads the legacy file and writes equivalent `userConfig` values
4. Remove the legacy reader in the next major version

## Choosing between the two

- **New plugin?** `userConfig`, always.
- **Existing plugin with `.local.md`?** Migrate when you do a major version bump.
- **Setting is genuinely a free-form chunk of prose?** Keep `.local.md` for that field; use `userConfig` for the rest.

## Security considerations

- Mark sensitive fields with `"format": "password"` so the UI masks input
- Avoid `default` values for credentials — let the user enter them explicitly
- Don't log resolved config wholesale; mask `password`-format values before logging
- Never check resolved config into git — `.local.md` is gitignored by Claude Code; `userConfig` values live in `~/.claude/settings.json` which is similarly outside the project tree
