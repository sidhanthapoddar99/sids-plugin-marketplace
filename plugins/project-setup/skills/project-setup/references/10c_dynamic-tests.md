# Dynamic tests — the rungs that run the code

The ladder, the rung contract and the floor are in `10b_static-checks.md`. This page owns the rungs that execute the program: what kinds exist, where the files live, and what a suite must do.

## The kinds

Unit tests are floor work. Writing a test beside non-trivial logic is ordinary work at any stage, needs no decision, and runs through the app's own runner. What the ladder decides is only which suites run on `ctl gate`.

| Test | Industry name | We call it | Do we do it | ctl |
|---|---|---|---|---|
| One function, class or module; boundaries; error paths; regressions | Unit testing | `test` | Floor | `ctl test [app]`, `ctl gate test` |
| Real database, HTTP APIs, queues, third-party clients | Integration testing | `test`, more files | Later: the first database-backed feature you would be sorry to break | same |
| Data races | Race detection | `-race` inside `test` | Floor, Go only, always on | same |
| One full user flow through a browser | Smoke test | the first e2e spec | Much later, add-on: `additional-template/apps/example-single-web-app-vite/e2e/` | `ctl test e2e`, `ctl gate e2e` |
| Every critical flow, failure and recovery | End-to-end, system testing | `e2e` | Much later: a flow you would page someone for | same |
| Random and malformed input, invariants | Property-based testing, fuzzing | `fuzz` | By name: a parser or a codec exists | `ctl gate fuzz [--time S]` |
| Load, stress, leaks, benchmarks | Performance and load testing | `perf` | By name: a latency or throughput target exists | `ctl gate perf` |
| Every dynamic rung installed, in order | | `gate dynamic` | Floor | `ctl gate dynamic` |

Runners: pytest, vitest, `cargo test`, `go test`; Playwright for the browser; hypothesis, fast-check and `cargo fuzz` for property tests; k6, `pytest-benchmark` and `cargo bench` for perf. Integration uses the same runners against the real engines from `compose.base.yaml`, with `httpx` or `supertest` against the app.

## Where tests live

| Kind | Where | Runner |
|---|---|---|
| Unit and component | Next to the file: `thing.py` + `test_thing.py`; `Thing.tsx` + `Thing.test.tsx` | pytest, cargo test, vitest, `go test` |
| Integration | `apps/<backend>/tests/` | pytest against the engines from `ctl dev` |
| End-to-end | `apps/<frontend>/e2e/` | Playwright through `ctl test e2e` |
| Fuzz, perf | `apps/<app>/tests/{fuzz,perf}/` | by name |
| Fixtures | `apps/<app>/tests/fixtures/` | never in `data/` |

No root `tests/` folder. Each app owns its suite and its `test` script (`bun test`, `uv run pytest`, `cargo test`, `go test ./...`).

## Rules

- A backend suite runs against real engines, not mocks of them. SQLite in tests only when the app ships on SQLite.
- E2E runs against a built stack on a throwaway `DATA_DIR`, never against dev servers, never against `data/`.
- `go test -race` always. Concurrency bugs are cheapest here.
- The browser suite is its own rung. A browser bolted onto the fast gate makes agents stop running the gate.
- A test that cannot reach its engine dies by name. It never skips itself green.
- Adding integration, e2e, fuzz or perf is the user's decision. Recommend it with the trigger above; do not add it unasked.

## Verbs

The verbs are listed once, in `08_ctl.md` § Verbs. The ones this page uses: `ctl test [app|e2e]`, `ctl gate test | e2e`, `ctl gate dynamic`, `ctl gate fuzz | perf`, `ctl build save`.

Template: `template/scripts/test/` (`test.sh` = every app's suite, `e2e.sh` = the throwaway stack, `build.sh` = frozen builds). Add-on: `additional-template/apps/example-single-web-app-vite/e2e/`.
