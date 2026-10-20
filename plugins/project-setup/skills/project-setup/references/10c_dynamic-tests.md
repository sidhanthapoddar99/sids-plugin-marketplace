# Dynamic tests — the rungs that run the code

The ladder, the rung contract and the floor are in `10b_static-checks.md`. This page owns the rungs that execute the program: what kinds exist, where the files live, and what a suite must do.

## The kinds

Unit tests are floor work. Writing a test beside non-trivial logic is ordinary work at any stage, needs no decision, and runs through the app's own runner. What the ladder decides is only which suites run on `ctl gate`.

| Test | Industry name | We call it | Do we do it | ctl |
|---|---|---|---|---|
| One function, class or module; boundaries; error paths; regressions | Unit testing | `test` | Floor | `ctl test [app…]`, `ctl gate test` |
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

No root `tests/` folder. Each app owns its suite and its `test` script (`bun test`, `uv run pytest`, `cargo test`, `go test -race ./...`). `ctl test` runs the suites of the apps listed in `scripts/gate/_targets.sh`. `10d_test-speed-and-resources.md` says when to edit that table.

`ctl test` and the test rung read the TESTING settings in `.env`: the cores, the compiler jobs, and the memory budget the default job count is sized from. `10d_test-speed-and-resources.md` owns those settings and the rules that keep a gate run fast. The rules every suite follows are below.

## Rules

- A backend suite runs against real engines, not mocks of them. SQLite in tests only when the app ships on SQLite.
- E2E runs against a built stack on a throwaway `DATA_DIR`, never against dev servers, never against `data/`. The stack runs as its own compose project, `<name>-e2e`, because under the project's own name it would recreate the running dev data core on the throwaway data and its teardown would remove it.
- `go test -race` always. Concurrency bugs are cheapest here.
- The browser suite is its own rung. A browser bolted onto the fast gate makes agents stop running the gate.
- A test that cannot reach its engine dies by name. It never skips itself green.
- A run owns the disposable resources it makes, such as a schema, a container, a port or a folder. Give each one a unique name, because two runs that share mutable test data fail each other at random. Remove each one when the run ends, pass or fail, because leftovers pile up across runs until a disk or an engine fills.
- Pay a setup once per suite, not once per test, such as one migrated schema per suite, because a per-test setup multiplies by the size of the suite.
- Wait for the exact state a test needs, such as a health check or a row, never for a fixed time. A sleep that passes on an idle machine times out under a gate that shares the machine.
- Put a heavy test that only a by-name run uses behind a switch that is off by default, because every default run would otherwise pay for a test it does not need. In Cargo the switch is a feature, and the default suite then skips the test's build too; `10d_test-speed-and-resources.md` shows the `Cargo.toml` form. In pytest it is a marker, such as `heavy`, that `addopts = "-m 'not heavy'"` under `[tool.pytest.ini_options]` in `pyproject.toml` deselects.
- Write the command that turns the switch on, such as `cargo test --features heavy-tests` or `uv run pytest -m heavy`, into the by-name rung or the `AGENTS.md` verb that runs the test, because a test behind a switch that nothing turns on never runs.
- Adding integration, e2e, fuzz or perf is the user's decision. Recommend it with the trigger above; do not add it unasked.

## Verbs

The verbs are listed once, in `08_ctl.md` § Verbs. The ones this page uses: `ctl test [app…|e2e]`, `ctl gate test | e2e`, `ctl gate dynamic`, `ctl gate fuzz | perf`, `ctl build save`.

Template: `template/scripts/test/` (`test.sh` = every app's suite, `e2e.sh` = the throwaway stack, `build.sh` = frozen builds), and `template/scripts/gate/_targets.sh` = the apps `ctl test` runs. Add-on: `additional-template/apps/example-single-web-app-vite/e2e/`.
