# Testing and Iteration

How plugin authors verify their work — from the fastest local-edit loop (`--plugin-dir`) up through scripted assertions, statistical benchmarks, and full clean-install verification.

## The two surfaces

| Surface | When it pays off | Speed |
|---|---|---|
| `claude --plugin-dir <path>` | Mid-development edits — load a folder from disk into a session | Fastest |
| `claude -p "<prompt>"` (`--json`) | Scripted assertions, A/B comparisons, cost benchmarks | Scriptable |
| Headless A/B harness | Variance-aware comparison across N trials per variant | Statistical |
| Clean-install loop | Pre-release verification — what a new consumer actually downloads | Slowest, highest-fidelity |

Each surface trades fidelity against turnaround. Most authors live in the first two during development and run the last only before publishing or after touching install-time concerns (manifest fields, dependencies, version-tag resolution).

## Pages in this folder

| # | Page | Topic |
|---|---|---|
| 01 | `01_plugin-dir.md` | `--plugin-dir` semantics, multiple flags, what it does and doesn't do |
| 02 | `02_headless.md` | `claude -p` non-interactive turn, `--json` envelope, scripting assertions |
| 03 | `03_benchmarking.md` | Multi-trial A/B testing, trigger-rate / token-cost / quality, baseline comparison |
| 04 | `04_clean-install-loop.md` | End-to-end verification — wipe cache, reinstall, smoke test |

## Related chapters

- [`../07_lifecycle-and-runtime/`](../07_lifecycle-and-runtime/00_index.md) — what install actually does, hot-swap matrix for `/reload-plugins`
- [`../12_cli-and-ui/`](../12_cli-and-ui/00_index.md) — the CLI surface used in scripts (`claude plugin install`, `list --json`)
- [`../13_uninstall-and-cleanup.md`](../13_uninstall-and-cleanup.md) — cache wipe details for the clean-install loop
- [`../09_versioning-and-publishing/`](../09_versioning-and-publishing/00_index.md) — when you should bump version vs. iterate locally
