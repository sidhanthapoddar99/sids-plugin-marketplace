---
title: Uninstalling
description: Removing plugins and marketplaces — and why the cache survives, plus when to wipe it manually for clean-install testing
---

# Uninstalling

Two CLI commands handle the common cases: `/plugin uninstall` for individual plugins and `/plugin marketplace remove` for entire marketplaces. There's a non-obvious wrinkle around the cache that matters for plugin authors and anyone testing installs — covered at the end.

## Uninstall a single plugin

```
/plugin uninstall <plugin>@<marketplace>
```

This:

1. Removes the `enabledPlugins[<plugin>@<marketplace>]: true` entry from the chosen scope's `settings.json`
2. Stops loading the plugin's skills, commands, agents, hooks, MCP servers, and `bin/` wrappers
3. **Typically** clears the plugin's folder under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` — but not always; see the cache section below

After uninstall, run `/reload-plugins` to refresh the active set.

If the same plugin was enabled at multiple scopes, the uninstall only touches the scope you ran it from. The plugin stays enabled (and loaded) via the other scope's boolean. Use `--scope <user|project|local>` to target a specific scope.

## Uninstall (remove) an entire marketplace

```
/plugin marketplace remove <marketplace-name>
```

This removes the marketplace registration from your user-scope settings. Important consequences:

- **All plugins installed from this marketplace get uninstalled automatically.** Their `enabledPlugins` entries are removed from every scope. The plugins stop loading.
- **The marketplace can no longer be referenced** by `/plugin install <foo>@<marketplace>` until you re-add it.

Use this when you're done with a marketplace entirely (e.g. removing a local-path marketplace after finishing development against it).

## The cache survives — what to do about it

Here's the wrinkle: **uninstalling a plugin or removing a marketplace does NOT always wipe the on-disk cache** at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. The folder can stick around even after the plugin is no longer enabled or referenced anywhere.

For normal use this is harmless — it's just a few hundred KB of dead bytes. But there are two scenarios where you want a clean slate:

### Scenario 1: clean-install testing (plugin authors)

When you're iterating on a plugin and want to verify the install works *from scratch* (as a new consumer would experience it), the cache from a previous install can mask bugs:

- Stale skill bodies that wouldn't ship in the new release
- Old `bin/` wrappers that the new manifest doesn't include
- Orphaned scripts that the new code path no longer references

A truly clean test means wiping the cache before reinstalling.

### Scenario 2: troubleshooting "phantom plugins"

If `/reload-plugins` reports a plugin or skill that you thought you'd uninstalled, the cache folder is probably still there and something is still loading from it. Wipe and reinstall.

### How to wipe the cache

The cache lives at `~/.claude/plugins/cache/`. Two granularities:

**One specific plugin:**

```bash
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
# OR all versions of one plugin:
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/
```

**Everything from one marketplace:**

```bash
rm -rf ~/.claude/plugins/cache/<marketplace>/
```

**Nuclear — wipe everything and start over:**

```bash
rm -rf ~/.claude/plugins/cache/
```

After any of these, run `/reload-plugins`. The runtime sees the empty (or partially empty) cache; any `enabledPlugins` booleans for the wiped plugins will be reported as missing until you reinstall.

> [!warning]
> Wiping the cache doesn't touch your `enabledPlugins` settings. If you wipe `<marketplace>/` but the project's `settings.json` still references plugins from that marketplace, you'll either re-download them on next install or get warnings about missing plugins. For a fully clean state, also remove the `enabledPlugins` entries from your settings files.

## Clean-install loop for plugin authors

Putting it together — the test flow when you want to verify a release works for new consumers:

```bash
# 1. Uninstall and remove from the marketplace
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
which <your-wrapper>
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/
```

Step 2 is the one most people skip. Without it, you're testing whatever's left over from your last iteration — not what a new consumer actually downloads.

## When *not* to wipe the cache

- **Normal use** — leave it alone. Stale folders are cheap.
- **You just want to disable a plugin temporarily** — use `/plugin disable <plugin>@<marketplace>` instead. Sets the boolean to `false`, files stay cached, re-enable is instant.
- **You want to switch versions** — let `/plugin update` handle it. Multiple versions coexist in the cache by design.

The cache wipe is a debugging / clean-room-test tool, not a maintenance routine.

## Summary

| Action | Command | Effect on settings | Effect on cache |
|---|---|---|---|
| Disable | `/plugin disable <plugin>@<marketplace>` | Sets boolean to `false` | Untouched |
| Uninstall plugin | `/plugin uninstall <plugin>@<marketplace>` | Removes boolean from current scope | Typically cleared, sometimes not |
| Remove marketplace | `/plugin marketplace remove <marketplace>` | Removes all booleans from this marketplace, all scopes | Typically cleared, sometimes not |
| Wipe cache (manual) | `rm -rf ~/.claude/plugins/cache/<path>/` | Untouched | Cleared |

Combine the last two for a guaranteed clean state.

## See also

- **[Storage and Scope](./02_storage-and-scope.md)** — what the cache and the per-scope booleans actually mean
- **[Installation](./03_installation.md)** — the inverse — adding marketplaces and installing plugins
- **[Testing and Benchmarking](./05_creating-plugins/05_testing-and-benchmarking.md)** — iterating on a plugin without going through full uninstall/reinstall every time
