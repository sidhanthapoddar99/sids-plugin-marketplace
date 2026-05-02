# Uninstalling a plugin

How to remove a plugin cleanly, when the cache survives uninstall, and what to wipe by hand for clean-install testing.

## The single-plugin uninstall

```bash
claude plugin uninstall <plugin>[@<marketplace>]
```

What this does:

1. Removes the `enabledPlugins["<plugin>@<marketplace>"]` entry from the active scope's `settings.json` (default scope: `user`; pass `--scope project|local` to target a specific scope).
2. Stops loading the plugin's skills, commands, agents, hooks, MCP servers, LSP servers, monitors, and `bin/` wrappers from the next session start (or the next `/reload-plugins`).
3. **By default deletes the plugin's `${CLAUDE_PLUGIN_DATA}` directory** when uninstalling from the last scope where it was enabled.

Aliases: `claude plugin remove`, `claude plugin rm`.

### Flags

| Flag | Behaviour |
|---|---|
| `--scope user|project|local` | Which scope's `enabledPlugins` to remove from. Default `user` |
| `--keep-data` | Preserve `${CLAUDE_PLUGIN_DATA}` instead of wiping it (useful when reinstalling after testing a new version) |
| `--prune` | Also remove auto-installed dependencies that no other plugin requires. Same effect as `claude plugin prune` afterward |
| `-y, --yes` | Skip the `--prune` confirmation prompt (required when stdin is not a TTY) |

### Multi-scope nuance

If the plugin is enabled at multiple scopes, `uninstall` only removes the entry from the scope you target. The plugin stays active via the other scope's flag. Run uninstall once per scope to fully remove it; the data dir is deleted only when the *last* scope is uninstalled.

## Removing an entire marketplace

```bash
claude plugin marketplace remove <marketplace>
```

Or the slash equivalent: `/plugin marketplace remove <marketplace>` (alias `rm`).

Important consequences:

- **Every plugin installed from this marketplace is uninstalled automatically.** Their `enabledPlugins` entries are removed from every scope.
- **The marketplace can no longer be referenced** by `/plugin install <foo>@<marketplace>` until you re-add it.
- The marketplace registration is removed from `~/.claude/plugins/known_marketplaces.json`.

Use this when you're done with a marketplace entirely (e.g. removing a local-path marketplace after finishing development against it).

## The cache-survives-uninstall wrinkle

Uninstalling a plugin or removing its marketplace **does not always wipe the on-disk plugin cache** at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. The folder can stick around even after the plugin is no longer enabled or referenced anywhere.

The runtime's GC (orphan-marking on install/update, 7-day removal window) eventually cleans these up — but it only triggers on plugin operations, not on uninstall. For normal use the leftover bytes are harmless. Two scenarios where you want a clean slate:

### Scenario 1: clean-install testing (plugin authors)

When iterating on a plugin and verifying the install works *from scratch* (as a new consumer would experience it), the cache from a previous install can mask bugs:

- Stale skill bodies that wouldn't ship in the new release
- Old `bin/` wrappers that the new manifest doesn't include
- Orphaned scripts that the new code path no longer references

A truly clean test means wiping the cache before reinstalling. See the clean-install loop in [`troubleshooting.md`](troubleshooting.md).

### Scenario 2: troubleshooting "phantom plugins"

If `/reload-plugins` reports a plugin or skill that you thought you'd uninstalled, the cache folder is probably still there and something is still loading from it. Wipe and reinstall.

## Wipe procedures

The cache lives at `~/.claude/plugins/cache/`. Three granularities:

```bash
# One specific version of one plugin
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/

# All versions of one plugin
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/

# Everything from one marketplace
rm -rf ~/.claude/plugins/cache/<marketplace>/

# Nuclear — wipe all plugin caches and start over
rm -rf ~/.claude/plugins/cache/
```

After any of these, run `/reload-plugins`. The runtime sees the empty (or partially empty) cache; any `enabledPlugins` booleans for the wiped plugins will surface as missing-plugin errors in the `/plugin` Errors tab until you reinstall.

> **Wiping the cache doesn't touch your `enabledPlugins` settings.** If you wipe `<marketplace>/` but a project's `settings.json` still references plugins from that marketplace, you'll either re-download them on next install or get warnings about missing plugins. For a fully clean state, also remove the relevant `enabledPlugins` entries from your settings files.

## Clean-install testing recipe

Putting it together — verifying a release works for new consumers:

```bash
# 1. Uninstall and remove from the marketplace (in Claude Code)
/plugin uninstall <plugin>@<marketplace>
/plugin marketplace remove <marketplace>

# 2. Wipe the cache (in your shell, NOT inside Claude Code)
rm -rf ~/.claude/plugins/cache/<marketplace>/

# 3. Verify settings are clean
grep enabledPlugins ~/.claude/settings.json
grep enabledPlugins <repo>/.claude/settings.json   # if you'd installed at project scope

# 4. Re-add the marketplace and install fresh
/plugin marketplace add <source>
/plugin install <plugin>@<marketplace>
/reload-plugins

# 5. Sanity-check
which <your-bin-wrapper>
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/
```

Step 2 is the one most authors skip. Without it, you're testing whatever's left over from your last iteration — not what a new consumer downloads.

## When NOT to wipe

- **Normal use** — leave it alone. Stale folders are cheap and the GC handles them within 7 days.
- **You just want to disable a plugin temporarily** — `/plugin disable <plugin>@<marketplace>` flips the boolean to `false`. Files stay cached, re-enable is instant.
- **You want to switch versions** — let `/plugin update` handle it. Multiple versions coexist in the cache by design.

The cache wipe is a debugging / clean-install-test tool, not a maintenance routine.

## Summary table

| Action | Effect on `enabledPlugins` | Effect on cache | Effect on data dir |
|---|---|---|---|
| `/plugin disable` | Set boolean to `false` | Untouched | Untouched |
| `/plugin uninstall` | Remove entry from current scope | Typically cleared, sometimes not | **Deleted** when uninstalling the last scope (use `--keep-data` to preserve) |
| `/plugin marketplace remove` | Remove entries for every plugin from that marketplace, all scopes | Typically cleared, sometimes not | Deleted alongside each plugin's uninstall |
| `rm -rf ~/.claude/plugins/cache/<path>/` | Untouched | Cleared at the path | Untouched |

## See also

- [`lifecycle-and-storage.md`](lifecycle-and-storage.md) — cache layout, scope union, `${CLAUDE_PLUGIN_DATA}` lifecycle
- [`troubleshooting.md`](troubleshooting.md) — the full clean-install loop and "phantom plugin" diagnostics
- [`cli.md`](cli.md) — every `claude plugin` subcommand and flag
- Official: [Plugin uninstall](https://code.claude.com/docs/en/plugins-reference#plugin-uninstall) — canonical CLI surface
- Marketplace reference docs: <https://github.com/sidhanthapoddar99/sids-plugin-marketplace/blob/main/Documentation/ClaudePlugin/13_uninstall-and-cleanup.md>
