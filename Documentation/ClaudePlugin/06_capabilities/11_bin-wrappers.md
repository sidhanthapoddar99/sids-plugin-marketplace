---
title: Bin wrappers
description: PATH-augmented executables — auto-PATH lifecycle, env vars available, naming conventions, multi-runtime fallback
---

# Bin wrappers

The `bin/` folder is the cleanest way to expose plugin-bundled scripts to the model and the user's shell. At session start, Claude Code adds **every enabled plugin's `bin/` folder to `$PATH`** — the model can invoke any wrapper by its bare name with no path knowledge required.

## Where it lives

```
my-plugin/
├── .claude-plugin/plugin.json
└── bin/
    ├── mytool                 # main CLI on $PATH
    └── mytool-helper          # related sub-tool
```

Files must be executable (`chmod +x`) on UNIX. No file extension in the name (UNIX convention) — the user invokes `mytool`, not `mytool.sh`.

## $PATH behaviour

Verified live in a Claude Code session:

```bash
$ echo $PATH | tr ':' '\n' | grep claude
/home/you/.claude/plugins/cache/claude-plugins-official/pyright-lsp/1.0.0/bin
/home/you/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/bin
/home/you/.claude/plugins/cache/documentation-template/documentation-guide/0.1.1/bin
…
```

Every enabled plugin's `bin/` is on `$PATH`. The model can invoke wrappers as `<wrapper-name>` directly via Bash tool calls — no `${CLAUDE_PLUGIN_ROOT}` interpolation needed.

## Environment variables available

| Variable | Resolves to | Use for |
|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | Plugin install root (`~/.claude/plugins/cache/<mkt>/<plugin>/<version>/`) | Bundled assets, scripts, templates |
| `CLAUDE_PLUGIN_DATA` | Plugin persistent data dir (`~/.claude/plugins/data/<plugin-id>/`) | Read/write state across plugin updates |
| `CLAUDE_PROJECT_DIR` | Current project working directory | Per-project state |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | Resolved value of a `userConfig` option (one env var per key) | Read user-set config |

These are set by Claude Code before invoking your bin and propagate to subprocesses. Don't `export` them yourself — they're already in the environment.

## Wrapper template

```bash
#!/usr/bin/env bash
# my-plugin's mytool — short description here
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:?must be run by Claude Code}"
DATA="${CLAUDE_PLUGIN_DATA:?must be run by Claude Code}"

SCRIPT="$ROOT/scripts/helper.sh"

if [[ $# -eq 0 ]]; then
  echo "usage: mytool <subcommand> [args]" >&2
  exit 2
fi

exec "$SCRIPT" "$@"
```

The `${CLAUDE_PLUGIN_ROOT:?...}` form fails fast with a useful error if the bin is invoked outside Claude Code (e.g. from a stale `$PATH` after the plugin was uninstalled).

## Multi-runtime fallback

```bash
# Node, with bun preferred
if command -v bun >/dev/null 2>&1; then
  exec bun "$SCRIPT" "$@"
else
  exec node "$SCRIPT" "$@"
fi
```

```bash
# Python, prefer python3
if command -v python3 >/dev/null 2>&1; then
  exec python3 "$SCRIPT" "$@"
else
  exec python "$SCRIPT" "$@"
fi
```

If neither runtime is available, the script fails with a clear error from the runtime — that's the right behaviour. Don't bootstrap installations from inside the wrapper.

## Naming conventions

Every enabled plugin's `bin/` is on `$PATH`. Two plugins shipping the same wrapper name will conflict — whichever loads first wins. Conventions:

| Pattern | Example |
|---|---|
| **Plugin-prefix** | `docs-list`, `docs-show`, `docs-add-comment` (plugin: `documentation-guide`) |
| **Single dispatcher** | one bin `pf` that takes subcommands (`pf build`, `pf validate`) |

Avoid generic names: `build`, `test`, `lint`, `serve`, `ls`, `cd`, `git`, `npm`, `jq`, `yq`, `rg` — these collide with system tooling or other plugins.

## Reading `userConfig`

```bash
api_key="${CLAUDE_PLUGIN_OPTION_APIKEY:-}"
if [[ -z "$api_key" ]]; then
  echo "error: apiKey not set — run /plugin and configure my-plugin" >&2
  exit 3
fi
```

For `multiple: true` options (string/directory/file arrays), values are newline-joined in the env var. Split with `IFS=$'\n'`.

## Lifecycle

| Event | Behavior |
|---|---|
| Plugin enabled | `bin/` folder added to `$PATH` on next session start |
| Session start | All enabled plugins' `bin/` folders prepended to `$PATH` |
| Wrapper edited | Hot-swappable — next invocation reads the new file |
| `/reload-plugins` | Picks up new wrappers added since session start |
| Plugin disabled | `bin/` removed from `$PATH` on next session start |
| Plugin updated | `${CLAUDE_PLUGIN_ROOT}` path changes; wrappers should resolve self via `$(dirname "${BASH_SOURCE[0]}")` |

## Boundaries

A bin can:

- Be invoked by name from any shell session that has the plugin enabled
- Read `userConfig` via env vars
- Read/write `${CLAUDE_PLUGIN_DATA}` for state
- Call other bins from other plugins (they're all on `$PATH`)

A bin **cannot**:

- Receive structured event payloads (that's [hooks](./04_hooks.md))
- Inject content into the model's prompt directly (only via stdout that the model sees on a Bash tool call)
- Block model behaviour (just an exit code + stdout/stderr)

## Trust class

**Unsandboxed.** Bins run as subprocesses at the user's shell privilege. Same trust class as hooks and monitors.

## vs hooks

| Concern | Bin | Hook script |
|---|---|---|
| When invoked | User or process explicitly calls it | Triggered by Claude Code event |
| On `$PATH`? | Yes (while plugin enabled) | No (referenced by absolute path) |
| Receives JSON on stdin? | Optional | Yes |
| Can return JSON to control behaviour? | No (just exit + std streams) | Yes (per hook contract) |
| Naming | Plugin-prefixed | Free-form |

A common pattern: a hook script in `scripts/` calls a bin in `bin/` for the actual work — keeps the hook config thin and the implementation reusable.

## vs `scripts/`

`scripts/` is for files **not** on `$PATH`. They're called via absolute path (`${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`) by hooks, agents, or other bins. Ship private helpers there to avoid `$PATH` clutter.

## Why bins beat `${CLAUDE_PLUGIN_ROOT}` in skill bodies

`${CLAUDE_PLUGIN_ROOT}` does **not** expand inside skill markdown bodies. The env var is empty in normal tool-call shells. Writing `bun ${CLAUDE_PLUGIN_ROOT}/scripts/foo.mjs` in a SKILL.md fails because the variable substitutes to empty string.

| Where `${CLAUDE_PLUGIN_ROOT}` works | Where it doesn't |
|---|---|
| `commands/<name>.md` body | `SKILL.md` body |
| `commands/<name>.md` `allowed-tools` frontmatter | Bash tool calls written by the model |
| `hooks/hooks.json` command strings | Shell scripts in `scripts/` invoked from a skill |

`bin/` wrappers are the strategy for any model-driven shell tooling. The wrapper finds itself via `$(dirname "${BASH_SOURCE[0]}")` and resolves bundled assets relative to that.

## OS portability

| OS | Pattern |
|---|---|
| Linux / macOS | `bin/<name>` with `#!/usr/bin/env bash` shebang |
| WSL | Same as Linux |
| Native Windows | Ship `bin/<name>.cmd` or `bin/<name>.ps1` alongside |

Avoid bash-isms (`[[ ]]`, process substitution) in any portable script.

## Verifying after install

```bash
# Should resolve to your plugin's cache bin folder
which mytool

# Should run and return output
mytool --help
```

If the wrapper isn't on `$PATH` after `/reload-plugins`:

- Check `chmod +x bin/*`
- Check the file starts with a valid shebang
- Check `/reload-plugins` output for plugin load errors
- Check `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/bin/` exists with your wrappers

## See also

- Authoring guide: `plugins/ai-toolkit-dev/skills/plugin-dev/references/topics/bin-development/`
- Official: [File locations — Executables](https://code.claude.com/docs/en/plugins-reference#file-locations-reference) — `bin/` and the Bash tool's `$PATH`
- [Hooks](./04_hooks.md) — for event-driven equivalents
- [Slash commands](./02_slash-commands.md) — for templated prompts (not shell tooling)
- [Capabilities index](./00_index.md)
