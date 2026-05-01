# `--plugin-dir`

The fast-iteration primitive. `claude --plugin-dir <path>` loads a plugin folder directly from disk for that session — no marketplace registration, no cache copy, no install.

## Basic shape

```
claude --plugin-dir ./path/to/my-plugin
```

The plugin's components (skills, commands, agents, hooks, MCP servers, LSP servers, monitors, themes, output styles, channels, `bin/` wrappers) load as if installed at **Local scope** for the duration of the session. Closing the session removes the override.

If a plugin with the same name is already installed via a marketplace, the `--plugin-dir` copy **shadows it for that session**. The normal install is left untouched.

## Multiple flags

`--plugin-dir` is repeatable:

```
claude --plugin-dir ./plugin-a --plugin-dir ./plugin-b
```

Useful when:

- You maintain several plugins and want them all loaded at once
- You're A/B testing two versions of the same plugin (give them distinct `name`s in `plugin.json` so both load)
- Your plugin under development depends on another local plugin and you want to test the pair

## What it does

| Behaviour | Detail |
|---|---|
| Loads components | Skills, commands, agents, hooks, MCP, LSP, monitors, themes, output styles, channels, `bin/` |
| Resolves `${CLAUDE_PLUGIN_ROOT}` | Points at your local directory — same expansion semantics as a normal install |
| Resolves `${CLAUDE_PLUGIN_DATA}` | Resolves to the normal data dir at `~/.claude/plugins/data/<plugin-name>/` |
| Adds `bin/` to `$PATH` | Wrappers in the `bin/` folder become callable in tool subprocesses |
| Treats the plugin as enabled | No `enabledPlugins` boolean is written; enablement is implicit for the session |

## What it doesn't do

| Limitation | Why |
|---|---|
| No marketplace resolution | The plugin is loaded by path; there's no `marketplace.json` lookup, no catalogue cross-reference |
| No version pinning | `version` from `plugin.json` is read but not enforced against any tag |
| No dependency resolution | If `dependencies[]` is declared, deps are **not** auto-installed. You either install them separately or `--plugin-dir` them too |
| No tag-based release lookup | The `<plugin>--v<X>` tag convention isn't consulted; the working tree is loaded as-is |
| No schema validation at install time | Manifest errors only surface at session-load time, not earlier |
| No 7-day garbage-collection participation | Only installed plugins are GC candidates |
| No persistence | The next session won't see the plugin unless `--plugin-dir` is repassed |

## Trade-offs vs. full install

`--plugin-dir` is fast but lossy. Treat it as the inner-loop tool, not a substitute for a clean install before release.

| Concern | `--plugin-dir` | Full install |
|---|---|---|
| Edit-test cycle | Seconds | Minutes (push, fetch, install) |
| Catches `marketplace.json` bugs | No | Yes |
| Catches version-tag-resolution bugs | No | Yes |
| Catches dependency-resolution bugs | No | Yes |
| Catches install-time schema errors early | No | Yes |
| Tests the consumer experience | No — your own filesystem | Yes |
| Catches `bin/` collisions across plugins | Only the dirs you `--plugin-dir` | Yes |
| Tests `${CLAUDE_PLUGIN_DATA}` migration semantics | Partial (data dir is the same) | Yes |

For all of those, run the [clean-install loop](./04_clean-install-loop.md) at least once before any release.

## Picking up edits mid-session

After editing a skill body, command body, script, or wrapper, run:

```
/reload-plugins
```

It re-scans active plugins and reports counts:

```
Reloaded: 5 plugins · 4 skills · 5 agents · 1 hook · 0 plugin MCP servers · 1 plugin LSP server
```

If your skill or command count is missing from the totals, the load failed — check the manifest and try again.

**Hot-swap matrix** (which capability changes need a session restart vs. just `/reload-plugins`):

| Change | `/reload-plugins` enough? |
|---|---|
| Skill / command body, references, scripts | Yes |
| Agent definition | Yes |
| MCP server config | Yes |
| LSP server config | Yes |
| `bin/` wrapper contents | Yes |
| Hook config (event handlers) | **No — restart required** |
| Monitor config | **No — restart required** (monitors are session-lifetime) |

See [`07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/00_index.md) for the deeper hot-swap discussion.

## Verifying the plugin loaded

Three quick checks:

| Check | What to look for |
|---|---|
| Skill registration | Skills appear in the system reminder list as `<plugin>:<skill>` |
| Command registration | `/help` lists commands as `<plugin>:<command>` |
| `bin/` wrapper resolution | `which <wrapper>` resolves under the plugin folder you passed |

If any of those return empty after `/reload-plugins`, the plugin's manifest is the first place to look.

## Common pitfalls

- **`${CLAUDE_PLUGIN_ROOT}` empty in skill bodies.** This env var only template-expands in commands, hooks, and `allowed-tools` frontmatter. In skills, use a `bin/` wrapper that resolves the path itself.
- **Two skill versions visible at once.** Expected — your `--plugin-dir` copy is shadowing a marketplace install of the same plugin name. Both descriptions appear in the system reminder.
- **Dependency resolution silently bypassed.** `--plugin-dir` doesn't enforce `dependencies[]`. If your plugin claims to need `dep-plugin@^1.0`, that's not checked. Use the clean-install loop to catch this.
- **Forgetting `chmod +x` on `bin/` wrappers.** A non-executable wrapper isn't loaded into `$PATH`. `chmod +x bin/*` after creation.

## See also

- [`02_headless.md`](./02_headless.md) — combining `--plugin-dir` with `claude -p` for scripted tests
- [`04_clean-install-loop.md`](./04_clean-install-loop.md) — what `--plugin-dir` doesn't catch
- [`../07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/00_index.md) — the full hot-swap matrix
