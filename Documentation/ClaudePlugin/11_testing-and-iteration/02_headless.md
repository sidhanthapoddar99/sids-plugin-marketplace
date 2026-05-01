# Headless mode (`claude -p`)

`claude -p "<prompt>"` runs a single non-interactive turn and exits. Combined with `--plugin-dir`, it's the simplest way to script tests, assertions, and benchmark harnesses.

## Basic shape

```bash
claude -p "review the diff in CHANGES.md"
```

Stdout receives the assistant's textual response. Exit code reflects success/failure of the turn.

For structured output, add `--json`:

```bash
claude -p "<prompt>" --json
```

## The `--json` envelope

Each `--json` run emits a single JSON object on stdout. Field reference:

| Field | Type | Purpose |
|---|---|---|
| `response` | string | The model's textual reply |
| `tool_uses` | array | Each tool call: `name`, `input`, `output` |
| `usage.input_tokens` | number | Prompt token count |
| `usage.output_tokens` | number | Completion token count |
| `usage.cost_usd_estimate` | number | Approximate USD cost of the turn |
| `model` | string | Model ID actually used |
| `latency_ms` | number | Wall-clock duration of the turn |

Pipe through `jq` for inspection:

```bash
claude --plugin-dir ./my-plugin -p "list available skills" --json | jq .
```

## Combining with `--plugin-dir`

The combination — load a local plugin and fire a single prompt — is the workhorse of plugin testing:

```bash
claude --plugin-dir ./my-plugin -p "<the prompt your plugin should help with>"
```

Multiple plugins:

```bash
claude --plugin-dir ./my-plugin --plugin-dir ./dep-plugin -p "..."
```

Versus a baseline:

```bash
# With plugin
claude --plugin-dir ./my-plugin -p "..." --json > with.json

# Without (no --plugin-dir flag at all)
claude -p "..." --json > without.json
```

Diffing `with.json` and `without.json` answers "does my plugin actually change behaviour?"

## Scripting assertions

The `--json` envelope makes shell-level assertions straightforward. Pattern:

```bash
result=$(claude --plugin-dir ./my-plugin -p "extract the version" --json)
version=$(echo "$result" | jq -r .response | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[[ "$version" == "1.2.3" ]] || { echo "FAIL: got $version"; exit 1; }
```

More structured assertions — did a specific skill or tool fire?

```bash
used_skill=$(echo "$result" | jq '.tool_uses | any(.name == "Skill")')
[[ "$used_skill" == "true" ]] || { echo "FAIL: skill didn't trigger"; exit 1; }
```

Cost ceiling:

```bash
cost=$(echo "$result" | jq -r .usage.cost_usd_estimate)
awk "BEGIN { exit ($cost > 0.05) ? 1 : 0 }" || echo "WARN: turn cost \$$cost"
```

## Pre-publish smoke test

A typical sequence to run before tagging a release:

```bash
# 1. Component registration check
claude --plugin-dir ./my-plugin -p "list available skills" --json \
  | jq '.response' \
  | grep -q "<plugin>:<skill>" || exit 1

# 2. Representative prompt that should trigger the plugin
claude --plugin-dir ./my-plugin \
  -p "<the kind of prompt your plugin should help with>" \
  --json > smoke.json

# 3. Inspect tool_uses, response shape, cost
jq '.tool_uses, .usage' smoke.json
```

If component registration fails or the headless prompt errors, fix before tagging.

## What headless mode is not

| Limitation | Why |
|---|---|
| No multi-turn conversations | `-p` is a single turn. For longer flows, spawn subagents in an interactive session |
| No interactive UI | `/plugin`, `/theme`, etc. don't apply — those are TTY commands |
| No human-in-the-loop confirmations | If the model attempts a tool that requires user permission, the turn fails. Pre-grant via `--allowedTools` or settings |
| Subject to system permission policy | Hooks and MCP servers run under the same trust model as interactive sessions |

## Common pitfalls

- **`--json` and human-readable output mixed.** `--json` puts everything in a single JSON object; you can no longer pipe to `less` or read the response inline. Use `jq -r .response` to extract just the text.
- **Forgetting that `-p` is one turn.** If the plugin's value depends on multi-turn reasoning (skills that triage, then read references, then act), one-shot may not show it. Use a subagent in an interactive session for multi-turn.
- **No `--plugin-dir` in CI.** A pure `claude -p` in CI doesn't load any plugin. Always remember the `--plugin-dir` flag in test scripts.
- **Trusting one trial.** Claude is non-deterministic. A single `-p` run is a sample, not a measurement. See [`03_benchmarking.md`](./03_benchmarking.md) for multi-trial harnesses.

## See also

- [`01_plugin-dir.md`](./01_plugin-dir.md) — the `--plugin-dir` flag headless mode is usually paired with
- [`03_benchmarking.md`](./03_benchmarking.md) — running headless mode at scale for variance-aware comparisons
- [`../12_cli-and-ui/01_claude-plugin-cli.md`](../12_cli-and-ui/01_claude-plugin-cli.md) — `claude plugin list --json` for inspection
