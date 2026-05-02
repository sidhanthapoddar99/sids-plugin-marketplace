# Persistent data patterns

Patterns for using `${CLAUDE_PLUGIN_DATA}` correctly. For *where* the env var resolves on disk and how it interacts with the cache, see [`../development-cycle/lifecycle-and-storage.md`](../development-cycle/lifecycle-and-storage.md).

## The split

| Variable | Purpose | Survives plugin updates? |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | Bundled assets that ship with the plugin (read-only at runtime) | **No** — replaced on every version bump |
| `${CLAUDE_PLUGIN_DATA}` | Mutable state, caches, dependency installs, learned data | **Yes** — survives updates and clean reinstalls of the same plugin |

The mental model: `ROOT` is your install media (a pristine copy of the version you shipped), `DATA` is your home directory.

## Common patterns

### Pattern: bundled `node_modules` / `venv`

You want to ship a Python or Node tool with your plugin, but you don't want to commit `node_modules` to the repo.

**SessionStart hook script** (`hooks/session-start.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

VENV="$CLAUDE_PLUGIN_DATA/venv"
REQ="$CLAUDE_PLUGIN_ROOT/requirements.txt"

# Recreate venv if requirements have changed
if [[ ! -f "$VENV/.requirements.sha" ]] || \
   ! sha256sum -c --status <(echo "$(sha256sum < "$REQ") $VENV/.requirements.sha"); then
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet -r "$REQ"
  sha256sum < "$REQ" > "$VENV/.requirements.sha"
fi

# Export for downstream scripts
echo "PATH=$VENV/bin:$PATH"
```

The venv lives in `DATA` so it survives plugin updates. The requirements file is in `ROOT` (it ships with the plugin). The SHA tag in `DATA` triggers a rebuild only when requirements change.

### Pattern: diff-on-SessionStart

You ship a *template* config in `ROOT/template.json` but let users edit a copy in `DATA/config.json`. On every SessionStart you want to detect new fields the user hasn't seen.

```bash
TEMPLATE="$CLAUDE_PLUGIN_ROOT/template.json"
USER_CONFIG="$CLAUDE_PLUGIN_DATA/config.json"

if [[ ! -f "$USER_CONFIG" ]]; then
  cp "$TEMPLATE" "$USER_CONFIG"
fi

# Print fields present in template but missing from user config
jq -n --slurpfile a "$TEMPLATE" --slurpfile b "$USER_CONFIG" \
  '[$a[0] | keys[]] - [$b[0] | keys[]]' >&2
```

Useful when shipping a new version that adds optional config — you can warn users about new fields without overwriting their existing settings.

### Pattern: cache directory

A long-running operation (model download, index build) you want to keep across sessions.

```bash
CACHE="$CLAUDE_PLUGIN_DATA/cache"
mkdir -p "$CACHE"

if [[ ! -f "$CACHE/big-thing.bin" ]]; then
  curl -o "$CACHE/big-thing.bin" https://example.com/big-thing.bin
fi
```

Add a separate `claude plugin clear-cache <plugin>` flow if users need an escape hatch — see `development-cycle/cli.md`.

### Pattern: per-project state

`${CLAUDE_PLUGIN_DATA}` is shared across all projects. For per-project state, key by project path:

```bash
PROJECT_HASH=$(echo -n "$PWD" | sha256sum | cut -c1-8)
PROJECT_DIR="$CLAUDE_PLUGIN_DATA/projects/$PROJECT_HASH"
mkdir -p "$PROJECT_DIR"
echo "$PWD" > "$PROJECT_DIR/.path"  # for debuggability
```

Or store project state in the project itself (e.g. a `.claude/<plugin>/` directory under the user's repo). Either is fine; the per-project-hash pattern is cleaner if the user might rename or move directories.

## Version-bump migration

When the plugin version bumps, `ROOT` is replaced (new version's content) but `DATA` is left untouched. This means `DATA` may contain state shaped for an old version of the plugin.

Strategies:

### 1. Versioned subdirectories

```
$CLAUDE_PLUGIN_DATA/
├── v1/
│   └── ... old format ...
├── v2/
│   └── ... new format ...
└── current → v2
```

A SessionStart script reads the plugin version, ensures `DATA/v<X>` exists, and updates the `current` symlink. Old versions hang around for rollback.

### 2. Migration scripts

Run a migration on first SessionStart of a new version:

```bash
INSTALLED_VERSION=$(jq -r .version "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json")
LAST_MIGRATED=$(cat "$CLAUDE_PLUGIN_DATA/.last-migrated-version" 2>/dev/null || echo "0.0.0")

if [[ "$INSTALLED_VERSION" != "$LAST_MIGRATED" ]]; then
  "$CLAUDE_PLUGIN_ROOT/scripts/migrate.sh" "$LAST_MIGRATED" "$INSTALLED_VERSION"
  echo "$INSTALLED_VERSION" > "$CLAUDE_PLUGIN_DATA/.last-migrated-version"
fi
```

Migration scripts must be idempotent and forward-compatible (skip steps already applied).

### 3. Wipe-and-rebuild

If `DATA` contains only a derived cache, simplest approach is to nuke it and rebuild:

```bash
INSTALLED_VERSION=$(jq -r .version "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json")
LAST_VERSION=$(cat "$CLAUDE_PLUGIN_DATA/.version" 2>/dev/null || echo "")
if [[ "$INSTALLED_VERSION" != "$LAST_VERSION" ]]; then
  rm -rf "$CLAUDE_PLUGIN_DATA/cache"
  echo "$INSTALLED_VERSION" > "$CLAUDE_PLUGIN_DATA/.version"
fi
```

Only safe if the cache is genuinely derived — not user-modified data.

## Anti-patterns

- **Writing to `${CLAUDE_PLUGIN_ROOT}`.** It's wiped on update; your writes vanish.
- **Putting the data dir under the project root.** Shared across the plugin's installs in any project; doesn't survive `git clean`.
- **Creating absolute paths to `~/.claude/plugins/data/...`.** The cache layout is internal; the env var is the contract.
- **Storing secrets in `${CLAUDE_PLUGIN_DATA}` unencrypted.** It's outside the project tree but on local disk. For credentials, prefer `userConfig` with `sensitive: true` — Claude Code stores those values in the OS keychain (or `~/.claude/.credentials.json` where the keychain is unavailable) instead of `settings.json`. See [`user-config.md`](user-config.md).
