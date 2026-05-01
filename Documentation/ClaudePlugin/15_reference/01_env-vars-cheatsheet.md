# Environment variables cheat sheet

Every env var that affects plugin loading, plugin runtime, or user-side controls — what it expands to, where it substitutes, and how long it lives.

## Plugin-side (used inside plugins)

| Variable | Set by | Substitutes in | Lifetime |
|---|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | Claude Code at session start | Skill bodies (limited), commands, hooks, monitors, MCP/LSP configs, `allowed-tools` frontmatter; exported to subprocesses | **Replaced** on every `/plugin update` |
| `${CLAUDE_PLUGIN_DATA}` | Claude Code at session start | Same surfaces as `CLAUDE_PLUGIN_ROOT` | **Survives** plugin updates; cleared on uninstall (unless `--keep-data`) |
| `${CLAUDE_PROJECT_DIR}` | Claude Code at session start | Hooks, monitors, MCP/LSP configs, command bodies | Per-session; equals the project root |
| `${CLAUDE_PLUGIN_OPTION_<KEY>}` | `userConfig` value entry | Exported to subprocesses (hooks, MCP/LSP, monitors, `bin/` scripts) | Persists in user's settings; updates when the user re-prompts |
| `${user_config.KEY}` | `userConfig` value entry | Inline-substituted in MCP/LSP server configs, hook commands, monitor commands, and (for non-sensitive values) skill / agent content | Same as `CLAUDE_PLUGIN_OPTION_<KEY>` |

### `${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_PLUGIN_DATA}` — the rule

```
~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/   ← CLAUDE_PLUGIN_ROOT
~/.claude/plugins/data/<plugin-id>/                          ← CLAUDE_PLUGIN_DATA
```

| Use `CLAUDE_PLUGIN_ROOT` for | Use `CLAUDE_PLUGIN_DATA` for |
|---|---|
| Bundled scripts (`scripts/foo.py`) | Installed Python venvs, `node_modules` |
| Bundled config (`templates/site.yaml`) | Generated code, caches |
| Read-only assets shipped with the plugin | Anything you want to keep across `/plugin update` |

The split exists because cache folders are versioned and replaced wholesale. Data folders are not.

### Substitution surface — what expands where

| Surface | `${CLAUDE_PLUGIN_ROOT}` | `${user_config.KEY}` | `${CLAUDE_PLUGIN_OPTION_<KEY>}` env |
|---|---|---|---|
| Skill body (`SKILL.md` content) | **No** (use a `bin/` wrapper) | Yes (non-sensitive only) | N/A — env vars are subprocess-only |
| Command body | Yes | Yes (non-sensitive only) | N/A |
| Command `allowed-tools` frontmatter | Yes | Yes | N/A |
| Hook commands | Yes | Yes | Yes (in subprocess) |
| Monitor commands | Yes | Yes | Yes (in subprocess) |
| MCP server config (`.mcp.json`) | Yes | Yes | Yes (in subprocess) |
| LSP server config | Yes | Yes | Yes (in subprocess) |
| Subprocess env (any tool call) | Available as env var | Not template-expanded; available as `CLAUDE_PLUGIN_OPTION_<KEY>` | Yes |

### `userConfig` substitution — sensitive values

For `userConfig` options marked `sensitive: true`:

- The value goes to the OS keychain rather than `settings.json`
- It still substitutes in MCP/LSP/hook/monitor commands
- It does **NOT** substitute in skill or agent content (to avoid sensitive material leaking into model context unnecessarily)
- It's exported as `CLAUDE_PLUGIN_OPTION_<KEY>` to subprocesses — your script can read it from env

The keychain has a ~2 KB total cap shared with OAuth tokens. Don't use `userConfig` for storing large secrets.

## User-side (control Claude Code behaviour)

| Variable | Effect | Where set |
|---|---|---|
| `DISABLE_AUTOUPDATER` | Globally disables Claude Code auto-updates **and** plugin auto-updates | Shell environment |
| `FORCE_AUTOUPDATE_PLUGINS` | With `DISABLE_AUTOUPDATER=1`, keeps plugin auto-updates while disabling Claude Code core | Shell environment |

See [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) for the complete decision matrix.

For non-plugin-specific Claude Code env vars (auth tokens, network proxies, log paths, etc.), see [`../../ClaudeSettings/04_environment-variables.md`](../../ClaudeSettings/04_environment-variables.md).

## Read-time vs. expansion-time

Worth distinguishing:

| When | What happens |
|---|---|
| **Manifest read time** (session start, `/reload-plugins`) | `${CLAUDE_PLUGIN_ROOT}` and `${user_config.KEY}` in `plugin.json` get substituted into the loaded config |
| **Tool-call time** | Subprocess receives the env vars (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_OPTION_*`, etc.) in its environment |
| **Skill body load** | Inline substitution happens for `${user_config.KEY}` (non-sensitive); `${CLAUDE_PLUGIN_ROOT}` does NOT expand here |
| **Command body fire** | Inline substitution happens for both `${CLAUDE_PLUGIN_ROOT}` and `${user_config.KEY}` |

The asymmetry between skill bodies (no `CLAUDE_PLUGIN_ROOT` expansion) and command bodies (yes) is the most-tripped-on rule. The workaround for skills is the `bin/` wrapper — a shell script in `bin/` that resolves the path itself.

## Pitfalls

- **`${CLAUDE_PLUGIN_ROOT}` empty in a skill body** — expected. Use a `bin/` wrapper.
- **`${user_config.KEY}` not substituting in a skill body** — check whether the option is `sensitive: true`. Sensitive options don't substitute in skills.
- **`CLAUDE_PLUGIN_OPTION_<KEY>` not in env** — only exported to subprocesses launched by Claude Code (hooks, MCP, LSP, monitors, tool calls). Not visible in the model's reasoning context.
- **`DISABLE_AUTOUPDATER` set but plugins still updating** — likely `FORCE_AUTOUPDATE_PLUGINS=1` is also set. Unset it to fully disable.
- **`${CLAUDE_PLUGIN_DATA}` wiped after uninstall** — default behaviour. Use `--keep-data` on `claude plugin uninstall` to preserve.

## See also

- [`../03_storage-and-scope/05_env-vars.md`](../03_storage-and-scope/05_env-vars.md) — the storage-side view of these vars
- [`02_settings-keys.md`](./02_settings-keys.md) — the settings file equivalents
- [`../14_distribution/03_auto-update-controls.md`](../14_distribution/03_auto-update-controls.md) — `DISABLE_AUTOUPDATER` / `FORCE_AUTOUPDATE_PLUGINS` in context
- [`../../ClaudeSettings/04_environment-variables.md`](../../ClaudeSettings/04_environment-variables.md) — non-plugin Claude Code env vars
- Official: [Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
