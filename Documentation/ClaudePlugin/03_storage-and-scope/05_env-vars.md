# Environment variables and substitution

Plugins reference paths and config values through a small set of well-known variables. They substitute inline in plugin content, and most are also exported as env vars to subprocesses (hooks, monitors, MCP/LSP servers).

## The two plugin paths

| Variable | Resolves to | Lifetime |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/` | **Replaced on every plugin update** |
| `${CLAUDE_PLUGIN_DATA}` | `~/.claude/plugins/data/<plugin-id>/` | **Survives plugin updates** |

`${CLAUDE_PLUGIN_ROOT}` is your install media (a pristine copy of the version you shipped). `${CLAUDE_PLUGIN_DATA}` is your home directory.

Use `ROOT` for: bundled scripts, executables, config files, templates, anything that ships with the plugin and should change when the plugin updates.

Use `DATA` for: installed dependencies (`node_modules`, Python venvs), generated code, caches, log files, anything you want to persist across plugin updates.

For details on each, see [`01_cache-layout.md`](./01_cache-layout.md) and [`02_data-dir.md`](./02_data-dir.md).

## `${CLAUDE_PROJECT_DIR}`

Resolves to the absolute path of the project Claude Code is currently working in (typically the directory `claude` was invoked from, or the workspace root). Useful in hooks and monitors that need to operate on project files.

Unlike the plugin paths, this changes per session (per project), not per plugin.

## `userConfig` values: `${user_config.KEY}` and `CLAUDE_PLUGIN_OPTION_<KEY>`

When a plugin declares `userConfig` in `plugin.json`, each option is exposed in two ways:

| Surface | Form | Example |
|---|---|---|
| Inline substitution | `${user_config.KEY}` | `${user_config.api_endpoint}` |
| Env var to subprocesses | `CLAUDE_PLUGIN_OPTION_<KEY>` (uppercased) | `CLAUDE_PLUGIN_OPTION_API_ENDPOINT` |

Where `${user_config.KEY}` works:

- MCP server `command`, `args`, `env`
- LSP server `command`, `args`, `env`
- Hook `command`
- Monitor `command`
- Skill content (non-sensitive values only)
- Agent content (non-sensitive values only)

Where the env var form works:

- Inside any subprocess Claude Code spawns for the plugin (hook scripts, monitor commands, MCP/LSP servers)

**Sensitive values** (declared with `sensitive: true` in `userConfig`) are stored in the OS keychain and **not substituted into skill or agent content** — they're available only to subprocesses (via the env var form) and to `command`/`args` substitution. This prevents leaking secrets through the visible model context.

## Where each variable substitutes

| Variable | Skill content | Agent content | Hook command | Monitor command | MCP/LSP config | Subprocess env |
|---|---|---|---|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | Yes | Yes | Yes | Yes | Yes | `CLAUDE_PLUGIN_ROOT` |
| `${CLAUDE_PLUGIN_DATA}` | Yes | Yes | Yes | Yes | Yes | `CLAUDE_PLUGIN_DATA` |
| `${CLAUDE_PROJECT_DIR}` | Yes | Yes | Yes | Yes | Yes | `CLAUDE_PROJECT_DIR` |
| `${user_config.KEY}` (non-sensitive) | Yes | Yes | Yes | Yes | Yes | `CLAUDE_PLUGIN_OPTION_<KEY>` |
| `${user_config.KEY}` (sensitive) | **No** | **No** | Yes | Yes | Yes | `CLAUDE_PLUGIN_OPTION_<KEY>` |

## Auto-update environment variables

These control plugin auto-update behaviour at the Claude Code process level:

| Variable | Effect |
|---|---|
| `DISABLE_AUTOUPDATER` | Globally disables Claude Code auto-updates *including* plugin updates |
| `FORCE_AUTOUPDATE_PLUGINS` | When set together with `DISABLE_AUTOUPDATER`, keeps plugin auto-updates running while disabling Claude Code core updates |

Default behaviour:

- Marketplaces auto-update at startup **by default for official Anthropic marketplaces**
- **Third-party and local-development marketplaces have auto-update disabled by default**
- Toggle per-marketplace in the `/plugin` UI

This means most third-party plugins won't auto-update unless explicitly enabled in `/plugin marketplace` for that marketplace.

## Discoverability of variables

There is no `claude plugin env` listing — the canonical list is the official [Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables) page. The variables documented above are the ones declared part of the plugin contract; other Claude Code env vars (`ANTHROPIC_API_KEY`, etc.) are visible to subprocesses but aren't plugin-specific.

## Anti-patterns

- **Hardcoding `~/.claude/plugins/...` paths** — the cache layout is internal; substitute through the env var
- **Reading `$CLAUDE_PLUGIN_ROOT` from inside skill content for runtime decisions** — skill content is rendered before the model sees it; the substitution happens at render time, not at runtime. For runtime branching, use a hook or bin script
- **Assuming `${user_config.KEY}` works in a `README.md` or other non-loaded files** — substitution only happens for content loaded by the plugin runtime
- **Storing sensitive `userConfig` values into skill content thinking they'd be redacted** — they aren't substituted at all into skill/agent content; you must read them from the env var inside a subprocess

## See also

- [`01_cache-layout.md`](./01_cache-layout.md) — what `${CLAUDE_PLUGIN_ROOT}` points at
- [`02_data-dir.md`](./02_data-dir.md) — what `${CLAUDE_PLUGIN_DATA}` points at
- [`../05_plugin-anatomy/`](../05_plugin-anatomy/00_index.md) — declaring `userConfig` in `plugin.json`
- [`../07_lifecycle-and-runtime/04_updates.md`](../07_lifecycle-and-runtime/04_updates.md) — auto-update behaviour
- Official: [Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
