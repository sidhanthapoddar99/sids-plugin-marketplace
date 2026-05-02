# Verification and troubleshooting

Two purposes: the **clean-install loop** for proactively verifying a plugin actually installs end-to-end, and **failure-mode walkthroughs** for diagnosing problems in the wild. Hot-swap and GC mechanics live in [`lifecycle-and-storage.md`](lifecycle-and-storage.md); this document focuses on verification and diagnosis.

---

## Part 1: The clean-install loop

Verify a plugin installs correctly from a clean cache, end-to-end. This is the test `--plugin-dir` (see [`testing.md`](testing.md)) can't do.

### Why

`--plugin-dir` skips marketplace resolution, version-tag resolution, dependency resolution, and schema validation at install time. A plugin that works under `--plugin-dir` can still fail when installed normally if any of those layers has a bug.

The clean-install loop catches:
- Missing files that you forgot to commit
- Bad `marketplace.json` source declarations
- Version tags that don't exist
- Dependency entries that fail to resolve
- Schema validation issues only triggered at install time

### The loop

```bash
#!/usr/bin/env bash
# clean-install-test.sh

set -euo pipefail

MARKETPLACE_REF=$1   # e.g. owner/repo
PLUGIN_NAME=$2

# 1. Wipe the plugin's cache + data
echo "::: cleaning cache"
rm -rf ~/.claude/plugins/cache/*/$PLUGIN_NAME 2>/dev/null || true
rm -rf ~/.claude/plugins/data/$PLUGIN_NAME 2>/dev/null || true

# 2. Force-refresh the marketplace
echo "::: refreshing marketplace"
claude plugin marketplace remove sids-plugin-marketplace 2>/dev/null || true
claude plugin marketplace add "$MARKETPLACE_REF"

# 3. Install
echo "::: installing"
claude plugin install "$PLUGIN_NAME"

# 4. Verify enabled
echo "::: verifying activation"
claude plugin list --json | jq -e ".enabledPlugins.\"$PLUGIN_NAME\" == true"

# 5. Smoke test
echo "::: smoke test"
claude -p "<a representative prompt>" --json | jq -e '.response | length > 0'

echo "::: ✓ clean install passed"
```

Run before every release. 10–60 seconds depending on plugin size and dependency count.

### What to clean

The script clears the plugin's cache and data dir. For a *fully* fresh install (testing what a brand-new user sees):

```bash
# Removes ALL plugin state for ALL plugins — back up first
rm -rf ~/.claude/plugins/cache/
rm -rf ~/.claude/plugins/data/
jq 'del(.enabledPlugins)' ~/.claude/settings.json | sponge ~/.claude/settings.json
```

For routine release testing, the per-plugin clean is sufficient.

### Sandbox testing

For paranoid testing (e.g. before a public release), run the loop in a container or fresh user account:

```bash
docker run --rm -it -v "$HOME/.claude:/root/.claude" -e HOME=/root anthropic/claude-code:latest \
  bash -c "claude plugin marketplace add owner/repo && claude plugin install my-plugin && claude -p 'test'"
```

### What the loop does NOT validate

- **Multi-plugin composition.** If your plugin will be installed alongside others, run the loop with those other plugins also installed.
- **Cross-platform.** A clean-install loop on macOS doesn't catch Linux-only path issues. Run on every supported OS at least once per major release.
- **Long-running behavior.** GC, hot-swap, version-bump migrations — see Part 2 below and `release.md`.
- **Real dependency resolution at scale.** If your plugin has many deps with overlapping version ranges, the resolver may behave differently when installed alongside other plugins that pin different versions of the same deps.

### Most common failure: "resource not found"

Usually one of:
- A file referenced via `${CLAUDE_PLUGIN_ROOT}/path/to/thing` that you didn't actually commit. Check `git ls-files` for what's tracked.
- A dependency tag that doesn't exist upstream (e.g. `claude plugin tag` was never run for that version).
- A `source` field pointing at a path/repo that no longer exists.

Re-run under `claude --debug` to see plugin-loading details:

```bash
claude --debug 2>&1 | tee install.log
# inside the session: /plugin install my-plugin
```

The debug output names the failing step. For non-interactive failure surfaces, `claude plugin list --json | jq '.errors'` exposes per-plugin error objects, and `/doctor` surfaces dep-resolution / range-conflict / missing-tag issues.

---

## Part 2: Failure-mode walkthroughs

For diagnosing problems with a plugin already in use.

### "Plugin doesn't load / not active"

#### Check enablement

```bash
claude plugin list --json | jq '.enabledPlugins'
```

Look for your plugin's name. If absent, the plugin isn't installed or enabled. If present but `false`, it's installed but disabled — `claude plugin enable <plugin>`.

#### Check scope

There's no dedicated `scope` subcommand — read the per-scope `enabledPlugins` directly:

```bash
grep -H enabledPlugins ~/.claude/settings.json <repo>/.claude/settings.json <repo>/.claude/settings.local.json 2>/dev/null
```

If a higher-priority scope has it set to `false` (precedence is Managed > Local > Project > User for explicit-`false` overrides), that scope wins. See `lifecycle-and-storage.md` for the union semantics.

#### Check for schema validation failures

Schema failures land in the `/plugin` Errors tab and in the structured `errors` field of `claude plugin list --json`:

```bash
claude plugin list --json | jq '.errors'
```

For richer logs at session-start, run `claude --debug` and look for "loading plugin" / "validation error" lines.

### "Components don't appear (skill / command / agent missing)"

#### Skill not triggering

Two causes:

1. **Description doesn't match** — Claude Code's skill matcher reads the `description` frontmatter. If your description doesn't mention the user's intent words, it won't fire. Tune the description (see the `skill-creator` skill).

2. **Skill not auto-discovered** — auto-discovery looks for `skills/*/SKILL.md`. If your skill is at `skills/<name>/skill.md` (lowercase) or nested deeper, it won't be picked up. Filename must be `SKILL.md` exactly.

#### Command not appearing in `/`

- File must be at `commands/<name>.md`
- Filename (sans `.md`) becomes the command name; check for typos
- Hot-swap is immediate — no restart needed once the file is correctly named

#### Agent not invokable

- File at `agents/<name>.md` with `name: <name>` matching in frontmatter
- `description` field must trigger on the user's intent (similar matcher rules to skills)
- For *proactive* agents (auto-invoked), description should explicitly suggest when to fire

### "Cache / stale state issues"

#### Symptom: edits to plugin don't show up

| Component | Hot-swap via `/reload-plugins`? | Fix |
|---|---|---|
| Skill | Yes | Run `/reload-plugins`, then prompt |
| Command | Yes | Run `/reload-plugins` |
| Subagent | Yes | Run `/reload-plugins` |
| MCP server | Yes (subprocess restarted on reload) | Run `/reload-plugins` |
| LSP server | Yes (subprocess restarted on reload) | Run `/reload-plugins` |
| Theme / output style / bin wrapper | Yes | Run `/reload-plugins` |
| Hook (any change — script, matcher, event) | **No — session-lifetime** | Restart `claude` |
| Background monitor (any change) | **No — session-lifetime; not restarted by `/reload-plugins`** | Restart `claude` |
| `userConfig` schema (new field) | Yes | Reload; user re-prompted on enable for new field |

If a hot-swappable component still shows stale, clear cache and reinstall:

```bash
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
claude plugin install <plugin>
```

For `--plugin-dir` mode, just restart `claude` — there's no cache to clear.

#### Symptom: old version persists after update

Inspect the resolved version:

```bash
claude plugin list --json | jq '.plugins[] | select(.name == "<plugin>")'
```

Force a marketplace refresh and re-install:

```bash
claude plugin marketplace update <marketplace>
claude plugin update <plugin>
```

Or wipe cache + data and reinstall:

```bash
claude plugin uninstall <plugin>            # default: removes the plugin AND its data dir
rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/   # optional — wipes all cached versions
claude plugin install <plugin>
```

`uninstall`'s default behavior IS to delete `${CLAUDE_PLUGIN_DATA}` when uninstalling from the last scope. Pass `--keep-data` if you want the data dir preserved (e.g. when reinstalling after testing a new version).

### "Dependencies fail to resolve"

#### Symptom: install errors with "could not resolve dep"

Common causes:

1. **Tag missing.** The dep's `version` doesn't exist as `<dep-name>--v<X.Y.Z>` in the dep's marketplace. Check upstream tags.
2. **Cross-marketplace not allowed.** The dep is in another marketplace, but the dependent plugin's marketplace doesn't list it in `allowCrossMarketplaceDependenciesOn`.
3. **Marketplace not installed.** The dep references a marketplace the user hasn't added.

Run under `claude --debug` to see which resolution step fails. `/doctor` also surfaces dep resolution errors, range conflicts, and missing tags with the constraining plugin named.

### "MCP server name conflict"

```
Error: MCP server name conflict: 'fs' declared by plugin-a and plugin-b
```

Both plugins claim the same name in their `.mcp.json`. Fix:

- Disable one plugin temporarily, OR
- Open an issue against one of the plugins to rename their server (plugin-prefix is the convention; see `config/naming.md`)

There's no per-user override for this — the conflict is at load time.

### "userConfig won't accept my value"

The runtime rejected it. Check the `/plugin` UI's option-editing dialog for inline error messages. Common causes:

- Missing `required: true` field — the dialog won't let you save until it's filled.
- Type mismatch — e.g. you typed a string for a `type: number` field, or a non-existent path for `type: directory`/`file`.
- Value outside `min`/`max` bounds (numbers only).
- For sensitive values: the OS keychain rejected the write (rare; usually a 2 KB total-cap issue if you're stuffing many large secrets).

Note that `userConfig` is **NOT** JSON Schema — there's no `enum`, `pattern`, `oneOf`, etc. Real types are `string | number | boolean | directory | file`. See [`../config/user-config.md`](../config/user-config.md).

### "Plugin works locally but breaks in CI / on another machine"

Likely culprits:

1. **Path assumptions.** Hardcoded `~/.claude/plugins/...` instead of `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`.
2. **Unstaged files.** A file referenced from the plugin but not committed. Run `git ls-files` and check.
3. **OS-specific scripts.** `bin/` scripts using bashisms but invoked on a system where `/bin/sh` is `dash`. Use `#!/usr/bin/env bash` shebang.
4. **Missing dependencies on PATH.** A bin script invoking `jq` or `gh` but those aren't installed on the target machine. Either bundle them or check + error gracefully.

### "Plugin is slow / heavy"

If a plugin makes every session feel sluggish:

- Profile token cost — see `testing.md` (Cost-aware benchmarking)
- Check if a SKILL.md description is firing on every prompt (matcher does), and the skill body is large
- A SessionStart hook taking >100ms is noticeable; >1s is painful. Move expensive work to lazy initialization
- An MCP server with a large startup time blocks session readiness — same advice

---

## Diagnostic command cheat sheet

```bash
# What's installed and enabled (full structured output, including .errors)
claude plugin list --json

# Pull a plugin out of the list output
claude plugin list --json | jq '.plugins[] | select(.name == "<plugin>")'

# Per-scope enable flags
grep -H enabledPlugins ~/.claude/settings.json <repo>/.claude/settings.json <repo>/.claude/settings.local.json 2>/dev/null

# Filesystem locations (by convention — derive from name + marketplace)
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/         # all cached versions
ls ~/.claude/plugins/data/<plugin>-<marketplace>/          # persistent data dir (slugified id)

# In-session diagnostics
# /plugin                Errors tab surfaces validation + load failures
# /doctor                surfaces dep / range / tag / auto-update issues
# /hooks                 lists hooks loaded for the session
# /mcp                   lists MCP servers (and their tools)
# /reload-plugins        re-reads plugins from cache (skill/cmd/agent/MCP/LSP/theme; NOT hooks/monitors)

# Verbose plugin loading at session start
claude --debug
```

## Escalation

If none of the above helps:

1. Capture `claude --debug` output for the failing session
2. Capture `claude plugin list --json` (especially `.errors`)
3. Capture `/doctor` output if it's a dep/version issue
4. File an issue on the plugin's repo (or Claude Code's, if the failure is in plugin loading itself rather than plugin code)
