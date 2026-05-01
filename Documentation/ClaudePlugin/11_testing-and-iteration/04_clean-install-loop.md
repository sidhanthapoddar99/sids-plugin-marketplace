# Clean-install loop

End-to-end install verification — wipe cache, reinstall from the marketplace, smoke-test as a new consumer would. This is the highest-fidelity test surface, and the one that catches bugs `--plugin-dir` cannot.

## What `--plugin-dir` doesn't catch

`--plugin-dir` is fast because it skips the install pipeline entirely. That makes it lossy for a specific class of bugs that only surface during install:

| Bug class | Caught by `--plugin-dir`? | Caught by clean install? |
|---|---|---|
| Marketplace resolution (catalogue patterns, plugins listed in wrong marketplace) | No | Yes |
| Version-tag resolution (`<plugin>--v<X>` lookup) | No | Yes |
| Dependency resolution (`dependencies[].version` constraints) | No | Yes |
| Schema validation at install time | No | Yes |
| Cross-plugin name collisions (`bin/`, `mcp__<server>__`) | Only for dirs you `--plugin-dir` | Yes |
| `.gitignore`d files missing from the install | No (your local copy has them) | Yes |
| `LICENSE` / `README.md` shape consumers see in `/plugin` UI | No | Yes |
| 7-day garbage-collection participation | No | Yes |
| `userConfig` enable-time prompt flow | No | Yes |

Run the clean install at least once before tagging a release, and again any time you touch:

- `marketplace.json` (a new entry, a different `source`, a `ref` change)
- `plugin.json` `dependencies[]`
- `userConfig` declarations
- `version` or release tags
- File-include / `.gitignore` rules

## The full loop

The flow that mirrors what a new consumer experiences:

```bash
# 1. Uninstall any existing copy from your local Claude Code
/plugin uninstall <plugin>@<marketplace>
/plugin marketplace remove <marketplace>

# 2. Wipe the on-disk cache (in your shell, NOT inside Claude Code)
rm -rf ~/.claude/plugins/cache/<marketplace>/

# 3. Verify settings are clean — no lingering enabledPlugins entries
grep enabledPlugins ~/.claude/settings.json
grep enabledPlugins <repo>/.claude/settings.json   # if installed at project scope

# 4. Re-add the marketplace and install fresh
/plugin marketplace add <source>
/plugin install <plugin>@<marketplace>
/reload-plugins

# 5. Smoke-test
which <your-wrapper>                                     # bin/ on PATH?
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/        # cache populated?
claude -p "<representative prompt>" --json | jq .         # plugin actually fires?
```

Step 2 is the one most people skip. Without it, you're testing against whatever's left over from your last iteration — not what a new consumer downloads.

## Why the cache survives uninstall

Uninstalling a plugin or removing a marketplace **does NOT always wipe the on-disk cache** at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. The folder can stick around even after the plugin is no longer enabled or referenced anywhere. For normal use this is harmless. For clean-install testing, it masks bugs:

- Stale skill bodies that wouldn't ship in the new release
- Old `bin/` wrappers the new manifest doesn't include
- Orphaned scripts the new code path no longer references

Manual `rm -rf` is the only guaranteed wipe.

## Cache-wipe granularities

| Scope | Command |
|---|---|
| One specific version | `rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` |
| All versions of one plugin | `rm -rf ~/.claude/plugins/cache/<marketplace>/<plugin>/` |
| Everything from one marketplace | `rm -rf ~/.claude/plugins/cache/<marketplace>/` |
| Nuclear — start over | `rm -rf ~/.claude/plugins/cache/` |

After any of these, run `/reload-plugins`. Existing `enabledPlugins` booleans pointing at wiped plugins will report missing until you reinstall.

## Sandbox testing in a container

For maximum fidelity — testing in an environment with no prior Claude Code state at all — use a container or an ephemeral home directory:

```bash
# Throwaway home dir
TMPHOME=$(mktemp -d)
HOME=$TMPHOME claude
# Inside: /plugin marketplace add <source>; /plugin install <plugin>@<marketplace>
```

Or in Docker:

```dockerfile
FROM node:20
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV HOME=/test-home
RUN mkdir -p $HOME
ENTRYPOINT ["claude"]
```

The container approach catches bugs that depend on a clean `~/.claude/` (no leftover `settings.json` keys, no managed marketplaces, no other plugins providing the same `bin/` wrapper).

## What to assert on the smoke test

Beyond "did the install succeed", verify the consumer-side surface area:

| Surface | Check |
|---|---|
| Cache populated | `ls ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` non-empty |
| `enabledPlugins` set | `jq .enabledPlugins ~/.claude/settings.json` includes your plugin |
| Skills register | `/help` (interactive) or `claude -p "list available skills" --json` |
| Commands register | Slash commands appear in `/help` |
| `bin/` on PATH | `which <wrapper>` resolves under the cache folder |
| `userConfig` prompted | If declared, the enable flow asked for the values |
| README rendering | `/plugin` UI shows the plugin's README correctly |
| Representative prompt | `claude -p` triggers the plugin and produces expected output |

## Combining with benchmarking

For the most rigorous pre-release check, run the headless benchmark harness from [`03_benchmarking.md`](./03_benchmarking.md) against the **installed** copy (not `--plugin-dir`). That's the closest a script can get to consumer reality:

```bash
# After clean install
PLUGIN_CACHE=~/.claude/plugins/cache/<marketplace>/<plugin>/<version>
./bench.sh "$PLUGIN_CACHE" prompts.txt 10 final-bench.jsonl
```

Differences between `--plugin-dir`-based and installed-copy benchmarks usually mean a missing file (gitignored, deps not bundled, etc.).

## When NOT to do the full loop

- **Iterating on a skill body** — `--plugin-dir` + `/reload-plugins` is the right tool.
- **Tweaking a description** — benchmark with `--plugin-dir`; install only when satisfied.
- **Local-only plugin you'll never publish** — full loop is wasted effort.

Run the full loop when you're about to share with another human, or when you've changed install-pipeline-touching files.

## See also

- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — the cache-survival explanation in more depth
- [`../12_cli-and-ui/01_claude-plugin-cli.md`](../12_cli-and-ui/01_claude-plugin-cli.md) — every `claude plugin` subcommand the loop uses
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — the publishing checklist this loop is the final gate of
