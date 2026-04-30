# Testing and benchmarking

Two complementary surfaces: `--plugin-dir` for fast iteration during development, and headless `claude -p` for scripted assertions, A/B comparisons, and benchmarks. For *where* the plugin runs once installed, see [`lifecycle-and-storage.md`](lifecycle-and-storage.md). For end-to-end install verification, see the clean-install loop in [`troubleshooting.md`](troubleshooting.md).

## `--plugin-dir`: fast local iteration

```
claude --plugin-dir ./path/to/my-plugin
```

Injects a local plugin into the active session as if it were installed at Local scope. Useful in three ways:

1. **No commit required.** Edit the plugin in place; restart `claude` to pick up changes.
2. **No marketplace round-trip.** Skip `marketplace.json`, tagging, publishing.
3. **Sandboxed.** The flag is per-session; closing the session removes the override. No risk of leaving a half-baked plugin enabled globally.

Multiple `--plugin-dir` flags are allowed:

```
claude --plugin-dir ./plugin-a --plugin-dir ./plugin-b
```

### What it does and doesn't do

**Does:**
- Loads the plugin's components (skills, commands, agents, hooks, MCP, etc.) for the duration of the session
- Resolves `${CLAUDE_PLUGIN_ROOT}` to your local directory
- Resolves `${CLAUDE_PLUGIN_DATA}` to a normal data dir (`~/.claude/plugins/data/<plugin-name>/`) — same as a full install would

**Doesn't:**
- Resolve dependencies. If your plugin's `plugin.json` declares deps, they need to be installed separately (or you need to `--plugin-dir` them too)
- Pick up `marketplace.json` semantics. There's no version pinning, no `version` field resolution
- Persist enablement. The next session won't have the plugin unless you re-pass the flag

### Rapid iteration loop

```bash
# Terminal 1: edit
$EDITOR my-plugin/skills/foo/SKILL.md

# Terminal 2: test
claude --plugin-dir ./my-plugin
```

For changes that hot-swap (skills, commands, scripts in `bin/`), no restart needed — just send the next prompt. For changes that don't hot-swap (hook config, MCP servers, LSP servers), restart `claude` between iterations. See `lifecycle-and-storage.md` for the full hot-swap matrix.

### Testing dependencies during dev

If your plugin depends on `dep-plugin@some-marketplace`:

```bash
claude --plugin-dir ./my-plugin --plugin-dir ./local-copy-of-dep-plugin
```

Both load at Local scope; the dep's components become available. Note: this bypasses the version-range check; `--plugin-dir` always loads "whatever's at this path" regardless of what `dependencies[].version` says. For real dependency-resolution testing, do a clean install (see `troubleshooting.md`).

### Trade-offs vs full install

`--plugin-dir` is fast but lossy. It does NOT test:
- Marketplace resolution (catalogue patterns, cross-marketplace deps)
- Version pinning (`<plugin>--v<X>` tag lookup)
- Cross-plugin name collisions in `.mcp.json` or `bin/` (only the dirs you `--plugin-dir` are checked)
- Schema validation at install time vs at session-load time
- The 7-day GC behavior

For those, run the clean-install loop in `troubleshooting.md` at least once before any release.

## Headless `claude -p`: scripted tests

`claude -p "<prompt>"` runs a single non-interactive turn and exits. Combined with `--plugin-dir`, it's the simplest way to script tests:

```bash
claude --plugin-dir ./my-plugin -p "review the diff in CHANGES.md"
```

Stdout gets the assistant's response. Add `--json` for a structured envelope:

```bash
claude --plugin-dir ./my-plugin -p "..." --json | jq .
```

The JSON includes:
- `response` — the model's textual reply
- `tool_uses` — list of tools called, with inputs/outputs
- `usage` — token counts and cost estimate
- `model` — the model ID actually used
- `latency_ms`

This is what lets you script assertions:

```bash
result=$(claude --plugin-dir ./my-plugin -p "extract the version" --json)
version=$(echo "$result" | jq -r .response | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[[ "$version" == "1.2.3" ]] || { echo "FAIL: got $version"; exit 1; }
```

### Pre-publish smoke test

```bash
# Validate the manifest
claude plugin validate ./my-plugin

# Headless: confirm components register
claude --plugin-dir ./my-plugin -p "list available skills" --json

# Run a representative prompt
claude --plugin-dir ./my-plugin -p "<the kind of thing your plugin should help with>"
```

If `validate` fails or the headless prompt errors, fix before tagging.

## Benchmarking

For tuning skill descriptions, comparing variants, or estimating production cost.

### Why multiple trials matter

Claude is non-deterministic at default temperature. A single run won't tell you whether a plugin change made things better, worse, or neither. Variance shows up in:
- Whether a skill was triggered at all
- Which tool the model chose
- How concise vs verbose the response was

Take medians (not means) for latency — they're more robust to occasional cold starts. 10 trials per variant gives you enough signal to see meaningful differences in token use, latency, or output quality. For tighter statistics, 30+.

### Subagent A/B test

Running the same prompt against two plugin variants:

```bash
for variant in variant-a variant-b; do
  for trial in {1..10}; do
    claude --plugin-dir "./$variant" -p "$prompt" --json > "results/$variant-$trial.json"
  done
done

# Compare aggregate behavior
jq -s '[.[].usage.input_tokens] | add / length' results/variant-a-*.json
jq -s '[.[].usage.input_tokens] | add / length' results/variant-b-*.json
```

### Harness pattern

```bash
#!/usr/bin/env bash
# bench.sh — run a plugin against a prompt set and aggregate

PLUGIN_DIR=$1
PROMPT_SET=$2
RUNS=${3:-10}
OUT=${4:-bench-results.jsonl}

>"$OUT"
while IFS= read -r prompt; do
  for trial in $(seq 1 $RUNS); do
    result=$(claude --plugin-dir "$PLUGIN_DIR" -p "$prompt" --json)
    echo "$result" | jq -c --arg p "$prompt" --arg t "$trial" \
      '{prompt: $p, trial: $t, latency: .latency_ms, tokens: .usage.input_tokens, used_skill: (.tool_uses | any(.name == "Skill"))}' \
      >> "$OUT"
  done
done < "$PROMPT_SET"

# Summarize
jq -s 'group_by(.prompt) | map({
  prompt: .[0].prompt,
  median_latency: (map(.latency) | sort | .[length / 2]),
  median_tokens: (map(.tokens) | sort | .[length / 2]),
  skill_trigger_rate: (map(select(.used_skill)) | length / length)
})' "$OUT"
```

`PROMPT_SET` is a newline-delimited file of test prompts representative of what the plugin should help with. The output gives you per-prompt aggregates you can diff between plugin versions.

### What to measure

| Metric | Why |
|---|---|
| **Skill/agent trigger rate** | Did the plugin actually fire on prompts where it should have? |
| **Token cost** | Did the plugin's content (descriptions, skill bodies) bloat context? |
| **Outcome quality** | Did the response improve in a way the user cares about? |

The third is hardest — usually you need a human evaluator or a separate Claude session as judge. The `skill-creator` skill's `eval-viewer` is built for this; see that skill for evaluation tooling.

### Cost-aware benchmarking

`--json` exposes `usage.input_tokens`, `usage.output_tokens`, and `usage.cost_usd_estimate`. For a plugin used regularly, run a representative-load benchmark and project monthly cost:

```bash
total_cost=$(jq -s '[.[].usage.cost_usd_estimate] | add' "$OUT")
calls_per_day=...  # estimate
echo "Projected: \$$(echo "$total_cost * $calls_per_day * 30 / $RUNS" | bc) /month"
```

This catches plugins that ship a 10kb SKILL.md by accident — context cost compounds across every session.

### Compare against baseline

The most useful benchmark is **with vs without your plugin**:

```bash
./bench.sh ./my-plugin prompts.txt 10 with-plugin.jsonl
./bench.sh /tmp/empty-plugin prompts.txt 10 without-plugin.jsonl
```

Where `/tmp/empty-plugin` is a minimal plugin with just `plugin.json`. Compare the two runs to see what your plugin actually changes.

### When NOT to benchmark

If you're prototyping a single skill, benchmarking is overkill — eyeball the response, iterate. Benchmarks pay off when:
- You're choosing between two skill descriptions
- You're tuning a hook's prompt
- You're shipping a plugin to others and want to claim "we improved X by Y%"

For a personal one-off plugin, `--plugin-dir` + manual testing is fine.
