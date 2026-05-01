# Uninstall and cleanup

Two CLI commands handle the common cases: `/plugin uninstall` for individual plugins and `/plugin marketplace remove` for entire marketplaces. There's a non-obvious wrinkle around the cache that matters for plugin authors and anyone testing installs — covered at the end.

## Disable vs uninstall vs remove marketplace

| Action | Command | Effect on settings | Effect on cache | When to use |
|---|---|---|---|---|
| **Disable** | `/plugin disable <plugin>@<mkt>` | Sets the scope's boolean to `false` | Untouched | Temporary off — re-enable is instant |
| **Enable** | `/plugin enable <plugin>@<mkt>` | Sets the boolean to `true` | Untouched | Re-enable a previously disabled plugin |
| **Uninstall** | `/plugin uninstall <plugin>@<mkt>` | Removes the boolean from the current scope | Typically cleared (sometimes survives — see below) | Done with this plugin in this scope |
| **Remove marketplace** | `/plugin marketplace remove <mkt>` | Removes booleans for all plugins from this marketplace, all scopes | Typically cleared | Done with the entire marketplace |
| **Manual cache wipe** | `rm -rf ~/.claude/plugins/cache/<path>/` | Untouched | Cleared | Clean-install testing, debugging phantom plugins |

## Uninstall a single plugin

```
/plugin uninstall <plugin>@<marketplace>
```

This:

1. Removes `enabledPlugins[<plugin>@<marketplace>]: true` from the chosen scope's `settings.json`
2. Stops loading the plugin's skills, commands, agents, hooks, MCP servers, and `bin/` wrappers
3. **Typically** clears the plugin's folder under `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` — but not always; see the cache section below
4. Deletes the data dir at `~/.claude/plugins/data/<plugin-id>/` **if uninstalling from the last scope** where the plugin was enabled

After uninstall, run `/reload-plugins` to refresh the active set.

If the same plugin was enabled at multiple scopes, the uninstall only touches the scope you ran it from. The plugin stays enabled (and loaded) via the other scope's boolean. Use `--scope <user|project|local>` to target a specific scope.

### Flags

| Flag | Effect |
|---|---|
| `--scope user|project|local` | Target a specific scope (default: current resolved scope) |
| `--keep-data` | Preserve `~/.claude/plugins/data/<plugin-id>/` even when uninstalling from the last scope |
| `--prune` | Also remove auto-installed dependency plugins that no other plugin requires |

`--keep-data` is most useful when reinstalling a different version for testing — your generated state survives the reinstall.

`--prune` is the per-plugin form of `claude plugin prune`. It says "uninstall this and any deps that were only here for this plugin's sake".

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

For normal use this is harmless — it's just a few hundred KB of dead bytes. But there are two scenarios where you want a clean slate.

### Scenario 1: clean-install testing (plugin authors)

When you're iterating on a plugin and want to verify the install works *from scratch* (as a new consumer would experience it), the cache from a previous install can mask bugs:

- Stale skill bodies that wouldn't ship in the new release
- Old `bin/` wrappers that the new manifest doesn't include
- Orphaned scripts that the new code path no longer references

A truly clean test means wiping the cache before reinstalling.

### Scenario 2: troubleshooting "phantom plugins"

If `/reload-plugins` reports a plugin or skill that you thought you'd uninstalled, the cache folder is probably still there and something is still loading from it. Wipe and reinstall.

## How to wipe the cache

The cache lives at `~/.claude/plugins/cache/`. Three granularities:

**One specific plugin (one version):**

```bash
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
```

**One specific plugin (all versions):**

```bash
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

> Wiping the cache doesn't touch your `enabledPlugins` settings. If you wipe `<marketplace>/` but the project's `settings.json` still references plugins from that marketplace, you'll either re-download them on next install or get warnings about missing plugins. For a fully clean state, also remove the `enabledPlugins` entries from your settings files.

## Clean-install loop for plugin authors

Putting it together — the test flow when you want to verify a release works for new consumers:

```bash
# 1. Uninstall and remove from the marketplace (inside Claude Code)
/plugin uninstall <plugin>@<marketplace>
/plugin marketplace remove <marketplace>

# 2. Wipe the cache (in your shell, NOT inside Claude Code)
rm -rf ~/.claude/plugins/cache/<marketplace>/

# 3. Verify settings are clean
grep enabledPlugins ~/.claude/settings.json
grep enabledPlugins <repo>/.claude/settings.json   # if installed at project scope

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

| Situation | Right answer |
|---|---|
| Normal use | Leave it alone. Stale folders are cheap. |
| Just want to disable a plugin temporarily | `/plugin disable <plugin>@<mkt>` — sets the boolean to `false`, files stay cached, re-enable is instant |
| Want to switch versions | Let `/plugin update` handle it. Multiple versions coexist in the cache by design |
| Plugin's `${CLAUDE_PLUGIN_DATA}` is buggy | Just delete the data dir specifically (`rm -rf ~/.claude/plugins/data/<plugin-id>/`), not the cache |

The cache wipe is a debugging / clean-room-test tool, not a maintenance routine.

## Data dir lifecycle reminder

| Action | Data dir |
|---|---|
| `/plugin disable` | Untouched |
| `/plugin uninstall` (this is the last scope) | **Deleted** |
| `/plugin uninstall --keep-data` | Preserved |
| `/plugin uninstall` (other scopes still enable it) | Untouched |
| Cache wipe | **Untouched** — separate from cache |
| Manual `rm -rf ~/.claude/plugins/data/<id>/` | Whatever you typed |

The data dir at `~/.claude/plugins/data/<plugin-id>/` is independent from the cache. Wiping the cache doesn't affect it. See [`03_storage-and-scope/02_data-dir.md`](./03_storage-and-scope/02_data-dir.md).

## See also

- [`03_storage-and-scope/01_cache-layout.md`](./03_storage-and-scope/01_cache-layout.md) — what the cache actually contains
- [`03_storage-and-scope/02_data-dir.md`](./03_storage-and-scope/02_data-dir.md) — the persistent data dir, `--keep-data` semantics
- [`07_lifecycle-and-runtime/05_garbage-collection.md`](./07_lifecycle-and-runtime/05_garbage-collection.md) — automatic GC vs manual wipes
- [`11_testing-and-iteration/`](./11_testing-and-iteration/00_index.md) — `--plugin-dir` for iterating without uninstall/reinstall
- [`12_cli-and-ui/`](./12_cli-and-ui/00_index.md) — full `/plugin` and `claude plugin` CLI surface
