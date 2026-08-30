# Testing — the kinds, the ladder, and what green means

Every check runs through `ctl gate`. The ladder is the only definition of green. A repo without CI runs it by hand; a repo with CI calls the same command.

## The kinds

| Kind | Covers | Tool | In the ladder |
|---|---|---|---|
| Lint and code quality | syntax and style; cyclomatic and logical complexity; dead and unused code; dependency hygiene | ruff, clippy, oxlint, gofmt; knip (dead-code census, two passes: with and without tests); `cargo udeps`, `deptry` | **must** — `lint`, `dead` |
| Static analysis and security | type checking; static security analysis; dependency vulnerability scan; secret scan; AI adversarial code review | tsc, mypy, clippy; bandit, semgrep; `bun audit`, `pip-audit`, `cargo audit`; gitleaks; Codex adversarial review per round | **must** — `typecheck`, `audit`; the review is per round, not a rung |
| Unit | one function, class or module; boundaries; error paths; regressions | pytest, vitest, `cargo test`, `go test` | **must** — `test` |
| Integration | database, HTTP APIs, queues, third-party clients, component-to-component | the same runners against real engines from `compose.db.yaml`; `httpx` / `supertest` against the app | recommended — `test` |
| Conformance | the repo's own rules: layout, env contract, compose validity, structure checks (import zones, file caps, design tokens, scope placement) | `ctl check` for the repo level; structure checks registered in one file and run as ordinary tests. See "Conformance" below | recommended — `check` |
| Build | the images and bundles compile | `ctl build` | recommended — `build` |
| End-to-end | complete user flows, critical business paths, failure and recovery | Playwright against a built stack on a throwaway `DATA_DIR` | recommended — `e2e`, last |
| Property-based and fuzz | unexpected and malformed input, invariants, edge cases nobody listed | hypothesis, fast-check, `cargo fuzz` | by name, `gate fuzz`; in the ladder for a parser or a codec |
| Performance and reliability | load, stress, races, timeout and retry, leaks | k6, `pytest-benchmark`, `cargo bench`; `go test -race` always on | by name, `gate perf`; `-race` inside `test` |
| Exploratory | unusual workflows, UX, adversarial behaviour, "try to break it" | a person, or an agent driving the built app through Playwright | at a stage close-out, on a frozen build |
| Clones | copy-pasted code | jscpd via `bunx`, never a dependency | by name, `gate clones` |

**Must** is the floor every project has from day one, whatever its pace: lint and code quality, static analysis and security, unit tests. Four rungs, all seconds to a minute. **Recommended** joins when the project earns it: integration once there is a database, conformance once there is a second app, build once there is an image, end-to-end once there is a user flow worth protecting. A project moving fast runs the four must rungs and says so in `AGENTS.md`; it does not skip them.

Not done: **mutation testing**. It costs hours and finds little that an adversarial audit and a manual pass do not. The time goes to those.

## The ladder

```
ctl gate            lint → typecheck → dead → audit → test  → check → build → e2e
                    ├── must ─────────────────────────────┤  ├── recommended ────────┤
```

Order is cost. Each rung fails cheaper than the next, so a red at the bottom never waits on a browser. Stop at the first red and **name every rung not reached**: a partial run must never read as a full one.

| Rung | Runs | Time |
|---|---|---|
| `lint` | every linter, every app | seconds |
| `typecheck` | tsc, mypy, `cargo check` | seconds to a minute |
| `dead` | the dead-code census, both passes, zero findings; every kept export listed in `knip.json` with its reason | seconds |
| `audit` | static security, vulnerability scan, secret scan | minutes |
| `test` | unit tests every app; integration too once engines exist | minutes |
| `check` | `ctl check` conformance | seconds |
| `build` | every image and bundle | minutes |
| `e2e` | the whole browser suite against the built stack | minutes |

`ctl gate -q` prints one line with counts per green rung and the full output of a red one. Quiet hides nothing that failed. A rung takes no arguments, so a gate means the whole repo. Two exceptions double as the dev verb: `ctl gate lint [app] [--staged]` and `ctl gate typecheck [app]`; tests narrow through `ctl test [app]`. One heavy run at a time: the ladder takes a lock and runs under a memory lid (`--memory 4G`), because two runs at once can take the box down.

Rungs outside the ladder (`fuzz`, `perf`, `clones`) run by name, at a stage close-out or when a round touched their subject. A gate that reports zero every run is a gate people stop reading.

## The rung contract

Every rung, and every check inside one, keeps four promises:

1. **Exit 0 only when the rule was proved.** A check that cannot find its target dies by name. Green never means "nothing ran".
2. **Name the file and the line** when it fails.
3. **One implementation, two callers.** `ctl test` and `gate test` run the same worker; `ctl test e2e` and `gate e2e` the same. Never a second copy of a suite.
4. **A check is a test when it can be.** A structure or conformance rule that a test runner can express is a test in the suite, registered in one place. A shell file exists only for what no test runner can do (render pixels, drive a browser). Duplicated shell checks cost half a rung's time for nothing.

## Where tests live

| Kind | Where | Runner |
|---|---|---|
| Unit and component | Next to the file: `thing.py` + `test_thing.py`; `Thing.tsx` + `Thing.test.tsx` | pytest, cargo test, vitest, `go test` |
| Integration | `apps/<backend>/tests/` | pytest against the engines from `ctl dev` |
| Structure and conformance | `apps/<app>/conformance/` (TS) or `apps/<app>/tests/conformance/` (Python, Go): one registry, one test that asserts the registry count | the app's own runner |
| End-to-end | `apps/<frontend>/e2e/` (template: `example-single-web-app-vite/e2e/`) | Playwright through `ctl test e2e` |
| Fuzz, perf | `apps/<app>/tests/{fuzz,perf}/` | by name |
| Fixtures | `apps/<app>/tests/fixtures/` | never in `data/` |

No root `tests/` folder. Each app owns its suite and its `test` script (`bun test`, `uv run pytest`, `cargo test`, `go test ./...`).

## Conformance

A conformance check is a unit test whose subject is the file tree, not a function. It proves the rules in `11_conventions.md` and `01_layout.md` mechanically: a service never imports a router, `os.environ` appears only in `config.py`, no hex value in a component, no file over the cap, a thing with two consumers lives in `packages/`. Lint judges syntax, types judge shapes, unit tests judge behaviour. Nothing else judges architecture, and architecture is what drifts across rounds under a green gate.

The full-size layout, when one file is no longer enough: **`structure/` reads the tree, `suites/` run the code, `fixtures/` are what suites borrow.** Inside `structure/`:

| Part | Job |
|---|---|
| `registry.ts` | The one list of checks, in order. Each entry names the rule and what it catches. |
| `structure.test.ts` | Runs every registered check over the real tree. Asserts the registry count, so a check cannot be dropped silently. |
| `detection.test.ts` | Runs every check over a temp fixture tree that breaks the rule on purpose. A check with no red fixture is not proved to bite. |
| `imports/`, `shape/`, `text/` | The checks, grouped by what they read: the import graph, folder and file shape, file text. |
| `ledgers/` | Hand-kept exemptions (`file-size-ledger.ts`). A ledger row for a file that no longer violates is itself red, so exemptions expire. |
| `harness/` | How a check reads the tree: file listing, source parsing, the report shape (file, line, rule id). |

Three properties make it a test and not a scan:

1. **The rule is a hand-written list**, never derived from disk. A zone table that scans the folders agrees with whatever is there.
2. **Every check has a red fixture.** On a clean tree a check that returns nothing looks the same as a check that works.
3. **Exemptions expire.** A stale ledger row fails.

The same shape in every ecosystem; only the parser changes. TypeScript: the `typescript` API for imports. Python: `ast`. Rust: crate edges from `Cargo.toml` plus clippy for the rest. Go: `go list -deps`. Template: `template/apps/example-api-python/tests/conformance/test_structure.py`, one registry and two checks with their red fixtures. Repo-level rules (env keys, compose shape) stay in `ctl check`; they have no runner but the shell.

Earned, not scaffolded: add the first check when the first drift appears or the second app arrives. A rule that has never been broken does not need a test yet.

## Rules

- Green means `ctl gate` passed. Nothing else does. Which rungs the ladder holds is written in `AGENTS.md`; a recommended rung, once added, is never removed.
- A backend suite runs against real engines, not mocks of them. SQLite in tests only when the app ships on SQLite.
- E2E runs against a built stack on a throwaway `DATA_DIR`, never against dev servers, never against `data/`.
- `go test -race` always. Concurrency bugs are cheapest here.
- Lint config lives per ecosystem, in the app (`ruff` in `pyproject.toml`, `.oxlintrc.json`, `rustfmt.toml`). Repo-wide tools (`knip.json`) at the root.
- `lefthook.yml`: `ctl gate lint --staged` on commit, `ctl test` on push. A hook never calls a tool directly.
- CI, when it exists, runs `ctl gate`. Nothing else. PR builds get no secrets.
- Every round of substantive work gets an adversarial review before it is called done. It is part of static analysis and security, done by a second model with its own shell. Reading is the failure mode; the reviewer runs the code.

## Linters

| Language | Tool | Runs |
|---|---|---|
| Python | ruff (lint + format), mypy | `ruff check`, `ruff format --check`, `mypy` |
| Rust | rustfmt, clippy | `cargo fmt --check`, `cargo clippy -- -D warnings` |
| TypeScript | oxlint, tsc, knip | `oxlint src`, `tsc --noEmit`, `knip` |
| Go | gofmt, go vet | |

## Verbs

| Verb | Runs |
|---|---|
| `ctl gate [-q]` | the ladder |
| `ctl gate <rung>` | one rung |
| `ctl gate fuzz \| perf \| clones` | by name |
| `ctl test [app\|e2e]` | the test worker directly |
| `ctl gate lint [app] [--staged]` | the lint worker directly |
| `ctl check` | the conformance worker directly |
| `ctl build save` | a frozen build for a manual or exploratory pass; see `08_ctl.md` |

Template: `template/scripts/gate/` (`all.sh` = the ladder, one file per rung, `_gate.sh` = the rung contract and `--quiet`, `_lock.sh` = one heavy run at a time under a memory lid), `template/scripts/test/`, `template/lefthook.yml`.
