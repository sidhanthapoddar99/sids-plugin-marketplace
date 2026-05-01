# Persistent data directory

The companion to the cache. While `${CLAUDE_PLUGIN_ROOT}` is replaced on every update, `${CLAUDE_PLUGIN_DATA}` survives — use it for anything you want to persist across plugin versions.

## Path

```
~/.claude/plugins/data/<plugin-id>/
```

The `<plugin-id>` is the install identifier (`<plugin>@<marketplace>`) with non-`[a-zA-Z0-9_-]` characters replaced with `-`.

| Install identifier | Resolved data dir |
|---|---|
| `formatter@my-marketplace` | `~/.claude/plugins/data/formatter-my-marketplace/` |
| `documentation-guide@documentation-template` | `~/.claude/plugins/data/documentation-guide-documentation-template/` |
| `claude-md-management@plugin-marketplace` | `~/.claude/plugins/data/claude-md-management-plugin-marketplace/` |

The directory is **created automatically the first time `${CLAUDE_PLUGIN_DATA}` is referenced** by any of the plugin's hooks, skills, agents, monitor commands, or MCP/LSP configs.

## Lifetime

| Event | Effect on data dir |
|---|---|
| `/plugin update` | Untouched — that's the whole point |
| `/plugin disable` then `/plugin enable` | Untouched |
| `/plugin uninstall` (last scope) | **Deleted** |
| `/plugin uninstall --keep-data` | Preserved |
| `/plugin uninstall` (other scopes still enable it) | Untouched |
| Cache wipe (`rm -rf ~/.claude/plugins/cache/`) | Untouched |

The data dir is deleted automatically when the plugin is uninstalled from the *last* scope where it's installed. If the plugin is enabled at user + project scope and you uninstall at user scope, the data dir survives.

`--keep-data` is useful when reinstalling a different version for testing — your generated state survives the reinstall.

## What to store there

Anything that should persist across plugin updates:

| Use case | Example |
|---|---|
| Installed dependencies | `node_modules/`, Python `venv/`, Rust `target/` |
| Generated code | Compiled binaries, transpiled outputs |
| Caches | Model downloads, indexed search trees, token budgets |
| Logs | Persistent diagnostic logs |
| Per-project state | Hashed-by-`$PWD` subdirs |
| Migration markers | `.last-migrated-version`, schema-version stamps |

Anti-patterns:

- **Writing to `${CLAUDE_PLUGIN_ROOT}`** — wiped on every update, your writes vanish
- **Hardcoding `~/.claude/plugins/data/...`** — the cache layout is internal; the env var is the contract
- **Putting the data dir under the project root** — won't survive `git clean`, won't share state across projects
- **Storing unencrypted secrets** — for credentials, prefer `userConfig` with `sensitive: true` (uses OS keychain)

## The diff-on-SessionStart pattern

The standard pattern for keeping `${CLAUDE_PLUGIN_DATA}` in sync with bundled assets in `${CLAUDE_PLUGIN_ROOT}`: on every SessionStart, diff the bundled manifest against a copy in the data dir, reinstall if they differ.

```bash
#!/usr/bin/env bash
set -euo pipefail

VENV="$CLAUDE_PLUGIN_DATA/venv"
REQ="$CLAUDE_PLUGIN_ROOT/requirements.txt"

if [[ ! -f "$VENV/.requirements.sha" ]] || \
   ! sha256sum -c --status <(echo "$(sha256sum < "$REQ") $VENV/.requirements.sha"); then
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet -r "$REQ"
  sha256sum < "$REQ" > "$VENV/.requirements.sha"
fi
```

`requirements.txt` ships with the plugin (in `ROOT`); the venv lives in `DATA` so it survives updates; the SHA tag triggers a rebuild only when requirements actually change.

## Version-bump migration

Because `DATA` survives updates, it may contain state shaped for an older version of the plugin. Three approaches:

- **Versioned subdirectories** — `$CLAUDE_PLUGIN_DATA/v1/`, `v2/`, with a `current` symlink
- **Migration scripts** — first SessionStart of a new version runs `migrate.sh <old> <new>`, idempotent
- **Wipe-and-rebuild** — if `DATA` is purely derived cache, nuke it on version mismatch

Migration scripts must be idempotent and forward-compatible (skip steps already applied).

## See also

- [`01_cache-layout.md`](./01_cache-layout.md) — the *other* plugin path, replaced on every update
- [`05_env-vars.md`](./05_env-vars.md) — full env var reference including `${CLAUDE_PLUGIN_DATA}`
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — `--keep-data` semantics
