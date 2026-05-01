# Benchmarking

Headless mode (`claude -p --json`) at scale, run across N trials per variant, with metrics aggregated to compare plugin variants statistically.

## Why multiple trials

Claude is non-deterministic at default temperature. A single run won't tell you whether a plugin change made things better, worse, or neither. Variance shows up in:

- Whether a skill triggered at all
- Which tool the model picked
- How concise vs. verbose the response was
- Latency (cold-start sensitive)
- Token spend on the same prompt

| Trial count | What you can claim |
|---|---|
| 1 | Anecdote — "it worked once" |
| ~10 | Direction — "variant A typically uses fewer tokens" |
| 30+ | Tighter statistics — "variant A is X% cheaper, p < 0.05" |

Take **medians** for latency (robust to occasional cold starts) and means for token / cost (Gaussian-ish). 10 trials per variant is the practical sweet spot for skill-description tuning; 30+ is worth it before publishing a "we improved X by Y%" claim.

## What to measure

Three independent axes:

| Metric | Source | Why it matters |
|---|---|---|
| **Trigger rate** | `tool_uses[].name` includes the expected skill / command / tool | Did the plugin actually fire on prompts where it should have? |
| **Token cost** | `usage.input_tokens` + `usage.output_tokens` | Did the plugin's content (description, body, references) bloat context for sessions where it didn't fire? |
| **Outcome quality** | Human grader, or a separate Claude session as judge | Did the response improve in a way the user actually cares about? |

The first two are mechanical — `jq` over the `--json` envelope. The third needs evaluation logic; the `skill-creator` skill ships an eval viewer that pairs human/judge grading with token / latency stats.

## Subagent A/B harness

Two variants (e.g., two versions of the same plugin with different skill descriptions), same prompt, N trials each:

```bash
for variant in variant-a variant-b; do
  for trial in {1..10}; do
    claude --plugin-dir "./$variant" -p "$prompt" --json \
      > "results/$variant-$trial.json"
  done
done

# Mean input tokens per variant
jq -s '[.[].usage.input_tokens] | add / length' results/variant-a-*.json
jq -s '[.[].usage.input_tokens] | add / length' results/variant-b-*.json
```

For prompts that need a fuller agent loop than `-p` gives you, spawn two subagents in an interactive session — one with the plugin loaded, one without — and capture the same metrics from each subagent's completion notification.

## Full harness pattern

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
    echo "$result" | jq -c --arg p "$prompt" --arg t "$trial" '{
      prompt: $p,
      trial: $t,
      latency: .latency_ms,
      tokens_in: .usage.input_tokens,
      tokens_out: .usage.output_tokens,
      cost: .usage.cost_usd_estimate,
      used_skill: (.tool_uses | any(.name == "Skill"))
    }' >> "$OUT"
  done
done < "$PROMPT_SET"

# Per-prompt aggregates
jq -s 'group_by(.prompt) | map({
  prompt: .[0].prompt,
  median_latency: (map(.latency) | sort | .[length / 2]),
  mean_tokens_in: (map(.tokens_in) | add / length),
  mean_cost: (map(.cost) | add / length),
  skill_trigger_rate: (map(select(.used_skill)) | length / length)
})' "$OUT"
```

`PROMPT_SET` is a newline-delimited file of test prompts representative of what the plugin should help with. The output gives per-prompt aggregates you can diff between plugin versions.

## Comparison-against-baseline

The most useful single benchmark is **with vs. without your plugin**. Build a minimal "empty" plugin (just `plugin.json`, no capabilities) to use as the no-op baseline:

```bash
mkdir -p /tmp/empty-plugin/.claude-plugin
cat > /tmp/empty-plugin/.claude-plugin/plugin.json <<EOF
{ "name": "empty-baseline", "version": "0.0.0" }
EOF

./bench.sh ./my-plugin     prompts.txt 10 with-plugin.jsonl
./bench.sh /tmp/empty-plugin prompts.txt 10 without-plugin.jsonl
```

Compare to see what your plugin actually changes — both the upside (trigger rate, outcome quality) and the downside (token cost on prompts where the plugin shouldn't have fired but its description bloated context anyway).

## Cost-aware benchmarking

`--json` exposes `usage.cost_usd_estimate` per turn. Project to monthly cost:

```bash
total_cost=$(jq -s '[.[].cost] | add' "$OUT")
calls_per_day=...   # estimate based on actual usage
echo "Projected: \$$(echo "$total_cost * $calls_per_day * 30 / $RUNS" | bc) /month"
```

This catches plugins that ship a 10kB SKILL.md by accident — context cost compounds across every session where the description matches.

| Bloat source | Why it shows up |
|---|---|
| Long skill `description` | Always loaded — paid on every session, every prompt |
| Heavy SKILL.md body | Paid every time the description matches and the body loads |
| Verbose `references/` files | Paid only when the body cites them |
| Untrimmed `tools` allowlist | Marginal, but counts |

A baseline benchmark of an unrelated prompt against your plugin (where it shouldn't trigger at all) reveals only the always-loaded-description cost. Subtracting that from a triggering-prompt benchmark separates "always-on cost" from "triggered cost."

## Automated eval — `skill-creator`

For more than a handful of prompts with grading and a viewer, install `skill-creator`:

```
/plugin install skill-creator@claude-plugins-official
```

It automates the with-plugin / baseline split end-to-end: parallel subagent runs, grading against per-prompt assertions, browser-based viewer with pass rates, token deltas, and timing per configuration. It's targeted at skills specifically but the pattern transfers to any plugin capability.

## When NOT to benchmark

- **Prototyping a single skill** — eyeball the response, iterate. Benchmarking is overkill.
- **Personal one-off plugin** — `--plugin-dir` plus manual checks is fine.
- **You haven't decided what you're measuring** — pick the metric first; otherwise you'll be tempted to fish for a number that flatters the change.

Benchmarks pay off when:

- Choosing between two skill descriptions (trigger-rate driven)
- Tuning a hook prompt (latency / token / outcome driven)
- Shipping to others and wanting a defensible "we improved X by Y%" claim

## See also

- [`02_headless.md`](./02_headless.md) — the `--json` envelope every harness reads
- [`04_clean-install-loop.md`](./04_clean-install-loop.md) — benchmarking against an installed copy, not just `--plugin-dir`
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — when a benchmark warrants a version bump
