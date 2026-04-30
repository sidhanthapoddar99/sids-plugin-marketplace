---
name: bin-development
description: Use when authoring scripts under a plugin's `bin/` directory — wrapper script conventions, `$PATH` exposure, env-var conventions (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_PROJECT_DIR}`, `CLAUDE_PLUGIN_OPTION_<KEY>` for `userConfig`), when to ship a bin vs a hook script, dispatcher patterns, OS portability, and naming to avoid collisions across plugins.
---

# Authoring `bin/` scripts

Files under a plugin's `bin/` directory get added to `$PATH` for any subprocess Claude Code launches in a session that has the plugin enabled. They're the right surface when you want a CLI tool that the user (or another script) can invoke directly.

## When to ship a bin

- The user might want to invoke the script themselves (`mytool --help`)
- A skill or agent's prompt instructs Claude to call a specific command (rather than embedding shell pipelines in the prompt)
- You want the script available to *other* plugins' hooks or scripts as well

When NOT to ship a bin:
- The script is only called by your own hooks/scripts → put it in `scripts/` (not auto-PATHed) and reference via `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`
- The "command" is really a slash command → `commands/<name>.md` instead, see `topics/command-development`

## Layout

```
my-plugin/
├── .claude-plugin/plugin.json
└── bin/
    ├── mytool              # main CLI
    └── mytool-helper       # related sub-tool
```

Files must be executable (`chmod +x`) on UNIX. No file extension in the name (UNIX convention) — the user invokes as `mytool`, not `mytool.sh`.

## Naming and collision avoidance

Every enabled plugin's `bin/` is on `$PATH`. Two plugins shipping the same bin name will conflict — whichever loads first wins. Conventions:

- **Plugin-prefix:** `pf-build`, `pf-validate` for plugin `plugin-foo`
- **Single dispatcher:** one bin `pf` that takes subcommands (`pf build`, `pf validate`) — keeps `$PATH` clean

Avoid generic names: `build`, `test`, `lint`, `serve` will collide with project tooling.

## Env vars available

| Variable | Resolves to | Use for |
|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | The plugin's installed cache root (`~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`) | Bundled assets, scripts, templates |
| `CLAUDE_PLUGIN_DATA` | The plugin's persistent data dir (`~/.claude/plugins/data/<plugin-id>/`) | Read/write state across plugin updates |
| `CLAUDE_PROJECT_DIR` | Current project working directory | Per-project state |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | Resolved value of a `userConfig` option (one env var per key) | Read user-set config — see [`../../config/user-config.md`](../../config/user-config.md) |

These are set by Claude Code before invoking your bin and propagate transitively to subprocesses. Don't `export` them yourself — they're already in the environment.

## Boilerplate

```bash
#!/usr/bin/env bash
# my-plugin's mytool — short description here

set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:?must be run by Claude Code}"
DATA="${CLAUDE_PLUGIN_DATA:?must be run by Claude Code}"

# Sub-script lookups
HELPER="$ROOT/scripts/helper.sh"

# Argument parsing
if [[ $# -eq 0 ]]; then
  echo "usage: mytool <subcommand> [args]" >&2
  exit 2
fi

case "$1" in
  build) shift; "$HELPER" build "$@" ;;
  test)  shift; "$HELPER" test "$@" ;;
  *)     echo "unknown subcommand: $1" >&2; exit 2 ;;
esac
```

The `${CLAUDE_PLUGIN_ROOT:?...}` form fails fast with a useful error if the bin is invoked outside Claude Code (e.g. from a stale `$PATH` after the plugin was uninstalled).

## Reading user config

```bash
api_key="${CLAUDE_PLUGIN_OPTION_APIKEY:-}"
if [[ -z "$api_key" ]]; then
  echo "error: apiKey not set — run /plugin and configure my-plugin" >&2
  exit 3
fi
```

For `multiple: true` options (string/directory/file arrays), values are newline-joined in the env var. Split with `IFS=$'\n'`.

See [`../../config/user-config.md`](../../config/user-config.md) for the full `userConfig` schema and substitution model.

## OS portability

If your plugin will be used on Windows (PowerShell or WSL):

- UNIX-only bins should be at `bin/<name>` with shebang `#!/usr/bin/env bash` — works in WSL, fails on raw Windows
- For native Windows support, ship `bin/<name>.cmd` or `bin/<name>.ps1` alongside; Claude Code adds them to `$PATH` and Windows shells pick them up
- Avoid bash-isms in any portable script — `[ ]` not `[[ ]]`, no process substitution, etc.

## Vs hooks

| Concern | Bin | Hook script |
|---|---|---|
| When invoked | User or other process explicitly calls it | Triggered by a Claude Code event (PreToolUse, etc.) |
| On `$PATH`? | Yes, always while plugin is enabled | No — referenced by absolute path in `hooks.json` |
| Receives JSON on stdin? | Optional | Yes (event payload) |
| Can return JSON to control behavior? | No (just exit code + stderr/stdout) | Yes (per the hook contract) |
| Naming | Plugin-prefixed by convention | Free-form |

A common pattern: a hook script in `scripts/` calls a bin in `bin/` for the actual work — keeps the hook config thin and the implementation reusable.

## Vs scripts

`scripts/` is for files NOT on `$PATH`. They're called via absolute path (`${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`) by hooks, agents, or other bins. Ship private helpers there to avoid `$PATH` clutter.

## Testing bins

```bash
# Direct invocation in a session that has the plugin enabled
claude --plugin-dir ./my-plugin
# Inside the session:
> !mytool subcommand args

# Or invoke from outside the session if the env vars are set:
CLAUDE_PLUGIN_ROOT=$PWD/my-plugin \
CLAUDE_PLUGIN_DATA=/tmp/my-plugin-data \
./my-plugin/bin/mytool subcommand args
```

For automated testing, the second form is easier — no Claude Code session needed.
