# Trust and Security

Plugins run **unsandboxed at the same privilege as your shell**. Hooks, monitors, MCP servers, LSP servers, and `bin/` wrappers can all execute arbitrary code with the user's full filesystem and network access. Treat plugin install with the same caution you'd treat `git clone && ./install.sh`.

## The trust model in one paragraph

There is no plugin sandbox. Once a plugin is installed and enabled, anything it ships — a `PreToolUse` hook, a long-running monitor process, an MCP server subprocess, a script in `bin/` invoked from a slash command — runs with the user's shell privileges. If a plugin ships a hook that runs `rm -rf ~/`, the runtime will execute it. Trust authors and marketplaces, not individual files.

## Execution surfaces

Five surfaces a plugin can ship that execute code with shell privileges:

| Surface | When it runs | Sandboxed? |
|---|---|---|
| **Hook** (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `PreCompact`, `Notification`) | On lifecycle events — many fire automatically without user interaction | No |
| **Monitor** | At session start, lifetime of the session — long-running process | No |
| **MCP server** | At session init, lifetime of the session — subprocess | No |
| **LSP server** | At session init, lifetime of the session — subprocess | No |
| **`bin/` wrapper** | When the model calls it via `Bash`, or when a hook/command/skill body invokes it | No |

In addition, slash command bodies and skill bodies can instruct the model to run shell commands via `Bash`, with the model's `allowed-tools` policy as the only gate. Those commands also run unsandboxed.

> [!warning]
> A `SessionStart` hook fires automatically when Claude Code starts a session in any project where the plugin is enabled. There is no opportunity for the user to confirm the hook before it runs (apart from the initial trust prompt for the project folder). Treat plugin install as authorising every hook the plugin ships to run automatically.

## What `userConfig` does and doesn't protect

The `userConfig` system collects values from the user (API tokens, endpoints, etc.) at plugin enable time and exposes them to the plugin. Two storage tiers:

| Sensitivity | Storage | Where it can be substituted |
|---|---|---|
| `sensitive: false` (default) | `settings.json` under `pluginConfigs[<plugin-id>].options` | Inline in skill content, agent content, hook commands, monitor commands, MCP/LSP configs, and as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars |
| `sensitive: true` | OS keychain (~2 KB shared with OAuth tokens) | NOT substituted into skill or agent content. Available in hook commands, monitor commands, MCP/LSP configs, and as env vars to subprocesses |

Sensitive values are kept out of model context — but they're still passed to subprocesses the plugin spawns. A malicious plugin can read its own sensitive config (since the env var is exported to its hook/monitor/MCP subprocesses) and exfiltrate it. The `sensitive: true` flag protects against accidental leakage to model context, not against malicious plugins.

## Path-traversal limitation

Plugins **cannot reference files outside their own root** after install. Paths like `../shared-utils` won't resolve because external files aren't copied into the cache during install — only the plugin folder's contents are.

This isn't a security feature — it's a packaging limitation. The runtime makes no attempt to prevent a plugin from writing outside its root at runtime (a hook can `cd /` and do anything). The path-traversal restriction only applies to *plugin authoring*: when you reference assets from skills/commands/hooks, those references must point inside the plugin folder.

Concretely:

- ✅ `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` (resolves to inside the cache)
- ✅ `${CLAUDE_PLUGIN_DATA}/cache.db` (the data dir, also runtime-owned)
- ❌ `${CLAUDE_PLUGIN_ROOT}/../sibling-plugin/asset.json` (won't resolve; external)
- ❌ `../shared-utils/lib.js` (won't resolve)

Bundle everything you need inside the plugin folder.

## Marketplace-level trust

When a user adds a marketplace via `/plugin marketplace add <source>`, they're trusting:

1. The **marketplace** to list trustworthy plugins
2. The **plugins** the marketplace lists (the marketplace doesn't sandbox or verify them)
3. The **upstream sources** of those plugins (each `source` field can point at GitHub/GitLab/npm/etc.)

There's no signature, no code-review pipeline, no automated security scan. Trust is per-marketplace and per-plugin.

## Managed marketplace restrictions

Organisations can lock down which marketplaces users may add via the `strictKnownMarketplaces` setting in a managed `settings.json`. When enabled, users can only add marketplaces that appear in `extraKnownMarketplaces` — random `/plugin marketplace add owner/repo` calls are rejected.

This is the only built-in restriction surface for plugin install. The deep dive is in [04_marketplaces/07_managed-restrictions.md](./04_marketplaces/07_managed-restrictions.md).

## Auto-update considerations

Marketplaces auto-update at startup by default for **official Anthropic marketplaces**. Third-party and local-development marketplaces have auto-update **disabled** by default. The default leans toward "don't silently fetch new code from third parties without your explicit OK."

To globally disable Claude Code auto-updates including plugin updates: `DISABLE_AUTOUPDATER=1`. To keep plugin updates while disabling Claude Code core updates: `DISABLE_AUTOUPDATER=1 FORCE_AUTOUPDATE_PLUGINS=1`.

Because auto-update silently swaps in new code, a marketplace with auto-update enabled effectively gives the marketplace owner ongoing execution access on every consumer's machine. For high-trust environments, prefer pinning to a specific marketplace ref or sha (see [04_marketplaces/03_ref-and-sha-pinning.md](./04_marketplaces/03_ref-and-sha-pinning.md)).

## Practical guidance

| Action | Risk | Mitigation |
|---|---|---|
| Add a marketplace from a stranger | High — plugins from this marketplace get full shell access on install | Read the marketplace.json before adding; pin to a tag |
| Install a plugin you haven't read | Medium — every hook fires on lifecycle events | Inspect `hooks/`, `monitors/`, `.mcp.json`, `bin/` before enabling |
| Enable auto-update on a third-party marketplace | High — marketplace owner can ship new code anytime | Pin marketplace and plugins; disable auto-update for third parties |
| Use sensitive `userConfig` values | Low for accidental leakage; high for malicious plugins (they have the value) | Don't share secrets with plugins you don't fully trust |
| Run with a managed marketplace allowlist | Low | Use `strictKnownMarketplaces` for org policy |

## See also

- [04_marketplaces/07_managed-restrictions.md](./04_marketplaces/07_managed-restrictions.md) — `strictKnownMarketplaces` deep dive
- [04_marketplaces/03_ref-and-sha-pinning.md](./04_marketplaces/03_ref-and-sha-pinning.md) — pinning marketplaces and plugins for stable, auditable installs
- [03_storage-and-scope/02_data-dir.md](./03_storage-and-scope/02_data-dir.md) — `${CLAUDE_PLUGIN_DATA}` and what it doesn't sandbox
- [05_plugin-anatomy/04_user-config.md](./05_plugin-anatomy/04_user-config.md) — `userConfig` mechanics, sensitive flag
- [06_capabilities/04_hooks.md](./06_capabilities/04_hooks.md) — hooks and their execution model
- [14_distribution/03_auto-update-controls.md](./14_distribution/03_auto-update-controls.md) — auto-update env vars and per-marketplace toggles
- Official: [Plugins reference — environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
- Official: [Managed marketplace restrictions](https://code.claude.com/docs/en/plugin-marketplaces#managed-marketplace-restrictions)
