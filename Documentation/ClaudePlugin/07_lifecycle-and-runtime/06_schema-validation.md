# Schema validation

`plugin.json` is validated against Claude Code's plugin schema at install time and at every `/reload-plugins`. Validation failures abort the install or disable the plugin with a specific field error.

## When validation runs

| Trigger | What's validated | Failure behaviour |
|---|---|---|
| `/plugin install` | New plugin's `plugin.json` | **Aborts the install.** No `enabledPlugins` boolean is written. Specific field error reported. |
| `/plugin update` | New version's `plugin.json` | **Old version stays active.** New version is not switched in. The plugin keeps working at the old version. |
| `/reload-plugins` | All enabled plugins' manifests | **Plugin is disabled for this session** and listed in `/plugin` Errors tab. Other plugins keep loading. |
| Session start | All enabled plugins' manifests | Same as `/reload-plugins`: plugin disabled, error logged |

The validator runs on the manifest only. Skill bodies, command bodies, agent definitions, hook commands etc. aren't strictly schema-validated — malformed content there typically surfaces at runtime as a tool error rather than a validation abort.

## What the schema enforces

The full schema is published at the [official plugin reference](https://code.claude.com/docs/en/plugins-reference). Key constraints:

| Field | Constraint |
|---|---|
| `name` | **Required.** String, kebab-case. The only strictly required field — every other field is optional. Used as the plugin's identifier (combined with marketplace name) |
| `version` | Optional. Semver string. If omitted, Claude Code falls back to the git commit SHA, so every commit is treated as a new version |
| `description` | Optional. String. Shown in the `/plugin install` UI |
| `author` | Optional. Object with `name`, `email`, `url` |
| `commands`, `agents`, `skills`, `hooks`, `mcpServers`, `lspServers`, `monitors`, `outputStyles`, `themes`, `channels` | Optional. Each has its own sub-schema |
| `userConfig` | Optional. Object; each key must be a valid identifier; each value is an option declaration |
| `dependencies` | Optional. Array of dependency declarations |
| `settings` | Optional. Inline default settings (limited keys) |

## Failure examples

| Error | Cause |
|---|---|
| `"name" is required` | Missing top-level `name` field |
| `"version" must match semver pattern` | `version: "1.0"` instead of `"1.0.0"` (only fires when `version` is set; the field itself is optional) |
| `"userConfig.api_key.type" must be one of [string, number, boolean, directory, file]` | Typo in the type field |
| `"commands[0].path" does not exist` | Pointed at a missing file |
| `"hooks.events[0]" must be one of [...]` | Hook event name typo |
| `"dependencies[0].marketplace" not in allowCrossMarketplaceDependenciesOn` | Cross-marketplace dep without permission |

## Closed vs open schema — silently ignored keys

The schema is **mostly closed** — most field-level typos are caught. There are exceptions:

- The plugin-shipped `settings.json` (at the plugin root) currently supports only `agent` and `subagentStatusLine`. **Other keys are silently ignored.** See [official: ship default settings](https://code.claude.com/docs/en/plugins#ship-default-settings-with-your-plugin).
- Some component-config sections (e.g. `monitors[].when`) accept a small enum but don't currently fail-fast on unknown values in older Claude Code versions.

The practical implication: if a plugin "doesn't seem to be doing the thing", check that you're using a key the current Claude Code version recognises. The official reference tracks the supported keys.

## How to inspect failures

The `/plugin` UI's **Errors** tab is the primary surface. From the CLI:

```bash
claude plugin list --json | jq '.errors'
```

This exposes a structured `errors` field with per-plugin error objects. `/doctor` also surfaces plugin-related health issues including dependency resolution errors, range conflicts, missing tags, and skipped auto-updates.

## Schema-validation isn't security validation

Validation checks the manifest's shape, not its safety. Plugins run unsandboxed at the same privilege as your shell — see [`../10_trust-and-security.md`](../10_trust-and-security.md). A plugin with a perfectly valid `plugin.json` can still execute arbitrary commands via hooks, monitors, and MCP servers.

## See also

- [`01_install-flow.md`](./01_install-flow.md) — where validation sits in the install sequence
- [`../05_plugin-anatomy/`](../05_plugin-anatomy/00_index.md) — the manifest fields in detail
- [`../10_trust-and-security.md`](../10_trust-and-security.md) — schema-validation vs trust
- Official: [Plugins reference](https://code.claude.com/docs/en/plugins-reference) — full schema
