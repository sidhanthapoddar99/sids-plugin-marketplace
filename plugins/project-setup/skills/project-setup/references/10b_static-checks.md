# Static checks — the rungs that read the code and never run it

This page owns the ladder, the rung contract, and every static rung. `10c_dynamic-tests.md` owns the rungs that run the code. `10a_review.md` owns what a person does by hand.

## The floor and the rest

Every repo runs four rungs from day one: `lint`, `typecheck`, `test`, `check`. Each costs seconds, needs no extra tooling, and catches the cheapest class of bug at the moment it is typed. The other rungs join by name when their trigger fires, on the user's word. This skill may recommend a rung and say why; it never adds one on its own. A rung leaves the ladder the same way, on the user's word, when it costs more than it catches.

| Check | Industry name | We call it | Do we do it | ctl |
|---|---|---|---|---|
| Formatting | Code formatting | part of `lint` | Floor | `ctl gate lint [app…] [--staged]` |
| Style and correctness rules | Linting, static analysis | `lint` | Floor | same |
| Complexity threshold | Cyclomatic and cognitive complexity | a `lint` rule | Floor | same |
| Layer and import boundaries | Architecture tests, fitness functions | a `lint` config, see below | From the second app | same |
| Type checking | Static typing | `typecheck` | Floor | `ctl gate typecheck [app…]` |
| Env keys, placeholders, compose shape, the brief | Repo lint, policy as code | `check` | Floor | `ctl check`, `ctl gate check` |
| Dead code, unused exports and dependencies | Dead-code detection, dependency hygiene | `dead` | Later: the first dead-code cleanup | `ctl gate dead` |
| Copy-paste detection | Clone detection | `clones` | By name: a refactor round | `ctl gate clones [--all] [--max N]` |
| Security patterns in source | SAST | part of `audit` | Later: the first external user or deploy | `ctl gate audit` |
| Known-vulnerable dependencies | SCA, vulnerability scanning | part of `audit` | same | same |
| Committed secrets | Secret scanning | part of `audit` | same | same |
| Images and bundles compile | Build verification | `build` | Later: the first image | `ctl gate build` |
| Every static rung installed, in order | | `gate static` | Floor | `ctl gate static` |

## The ladder

```
ctl gate            lint → typecheck → dead → audit → test → check → build → e2e
ctl gate static     lint → typecheck → dead → audit → check → build
ctl gate dynamic    test → e2e
```

Order is cost. Each rung fails cheaper than the next, so a red at the bottom never waits on a browser. A repo runs the subset its `AGENTS.md` lists; `RUNGS` in `scripts/gate/all.sh` is trimmed to match, and `static` and `dynamic` are that subset filtered by kind. Stop at the first red and **name every rung not reached**: a partial run must never read as a full one.

| Rung | Kind | Runs | Time |
|---|---|---|---|
| `lint` | static | every linter, every app | seconds |
| `typecheck` | static | tsc, mypy, `cargo check`, `go vet` | seconds to a minute |
| `dead` | static | the dead-code census, both passes, zero findings; every kept export listed in `knip.json` with its reason | seconds |
| `audit` | static | static security, vulnerability scan, secret scan | minutes |
| `test` | dynamic | unit tests every app; integration too once engines exist | minutes |
| `check` | static | `ctl check`, the repo contract | seconds |
| `build` | static | every image and bundle | minutes |
| `e2e` | dynamic | the whole browser suite against the built stack | minutes |

`ctl gate -q` prints one line with counts per green rung and the full output of a red one. Quiet hides nothing that failed. A rung run by name takes no app, so `ctl gate <rung>` checks the whole repo. Two exceptions double as the dev verb: `ctl gate lint [app…] [--staged]` and `ctl gate typecheck [app…]`. Tests narrow through `ctl test [app…]`.

Plain `ctl gate` runs the ladder on what the uncommitted changes reach. `ctl gate --delta <base>` runs it on the changes since a base, and `ctl gate --all` on everything. `10d_test-speed-and-resources.md` owns the modes, the selection rules, the TESTING settings in `.env`, the one-run lock and the memory lid.

Rungs outside the ladder (`fuzz`, `perf`, `clones`) run by name, at a stage close-out or when a round touched their subject. A gate that reports zero every run is a gate people stop reading.

## The rung contract

Every rung, and every check inside one, keeps four promises:

1. **Exit 0 only when the rule was proved.** A check that cannot find its target dies by name. Green never means "nothing ran".
2. **Name the file and the line** when it fails.
3. **One implementation, two callers.** `ctl test` and `gate test` run the same worker; `ctl test e2e` and `gate e2e` the same. Never a second copy of a suite.
4. **A check is a lint rule when it can be.** A rule a linter can express is a linter config, not a script and not a test. A shell file exists only for what no linter can do: read the env contract, validate compose, drive a build.

## Linters

| Language | Tool | Runs |
|---|---|---|
| Python | ruff (lint + format), mypy | `ruff check`, `ruff format --check`, `mypy` |
| Rust | rustfmt, clippy | `cargo fmt --check`, `cargo clippy -- -D warnings` |
| TypeScript | oxlint, tsc, knip | `oxlint src`, `tsc --noEmit`, `knip` |
| Go | gofmt, golangci-lint (go vet, gocyclo) | `gofmt -l`, `golangci-lint run ./...` |

Lint config lives per ecosystem, in the app, because an app lifted out must still lint: `[tool.ruff]` in `pyproject.toml`, `.oxlintrc.json` beside `package.json`, `clippy.toml` beside `Cargo.toml`, `.golangci.yml` beside `go.mod`. Repo-wide tools (`knip.json`) at the root. The template ships each of the four with the complexity floor set, and `ctl check` fails an app that has none, because a linter run without its config reports only its defaults and ruff's default has no complexity rule.

Complexity is a lint rule with a threshold. The floor is a cyclomatic complexity of 10 per function, the McCabe number, and a cognitive complexity of 15 where the tool measures it: ruff `C901` at 10, clippy `cognitive_complexity` at 15 through `clippy.toml`, gocyclo at 10 through `.golangci.yml`. oxlint has no cyclomatic rule, so TypeScript uses the proxies it does have: `max-depth` 4, `max-lines-per-function` 80 and `max-params` 5. A project that runs eslint instead may use `complexity` at 10. A repo that tightens or loosens a number records it in `AGENTS.md`.

## Layer rules are lint config

The rules in `11_conventions.md` and `01_layout.md` that a check can prove mechanically are lint rules: a service never imports a router, `os.environ` appears only in `config.py`, no hex value in a component, no file over the cap, a thing with two consumers lives in `packages/`. They join the `lint` rung as a config file when the second app arrives, or when a rule is broken a second time. Nothing else judges architecture, and architecture is what drifts across rounds under a green gate.

| Language | Tool | Expresses |
|---|---|---|
| Python | import-linter, or ruff `TID` banned-import rules | layer direction, banned imports with an allowlist |
| TypeScript | dependency-cruiser, or eslint-boundaries | feature and layer boundaries, `max-lines` for the cap |
| Rust | crate edges in `Cargo.toml`, clippy, cargo-deny | one crate per layer; the graph is the rule |
| Go | depguard through golangci-lint | banned imports per package |

No hand-written test harness for these. A bespoke registry with fixtures is a framework the project then owns, and every mainstream rule above fits a config file. The one case a custom test earns its place is a rule no tool can express, and that case is written when it happens, not before.

Repo-level rules, the env contract and the compose shape, stay in `ctl check`. They have no linter but the shell. `08_ctl.md` § `ctl check` is the list of what it proves.

## Rules

- Green means a `ctl gate` run passed that covered the whole change: a plain `ctl gate` while all of the work is uncommitted, and `ctl gate --delta <base>` once any of it is committed, where `<base>` is the commit the work started from. Nothing else is green, because a plain run on committed work checks only what is still uncommitted. Which rungs the ladder holds is written twice, in the `Gate ladder` row of `AGENTS.md` and in `RUNGS` in `scripts/gate/all.sh`, and `ctl check` fails when the two differ. `all.sh` refuses a `RUNGS` without the four floor rungs. A run on a tree that already passed is green without running again (`10d_test-speed-and-resources.md` § One run per tree).
- A `test` rung with no test file passes and says so on its own line, "no test file yet", and the closing line says how many suites ran. The suite is found by the names `10c_dynamic-tests.md` mandates; a suite under other names is skipped with the same warning, so the names are the rule.
- Adding a rung beyond the four is the user's decision. Recommend it with the reason; do not add it unasked, and do not add it during a bootstrap.
- The audit tools (`gitleaks`, `cargo-audit`, `govulncheck`) join `.mise.toml` when the `audit` rung joins, not before.
- `lefthook.yml` is an add-on: `ctl gate lint --staged` is the shape of a pre-commit hook, `ctl test` of a pre-push hook. A hook never calls a tool directly. `additional-template/lefthook.yml`.
- CI, when it exists, runs `WORKTREE_ONLY=0 ctl gate --delta <base>` and nothing else, because a CI checkout has no uncommitted changes for a plain `ctl gate` to check. `WORKTREE_ONLY=0` turns off the main-tree guard, because a CI clone is a main tree with no slots (`13_worktree.md` § The main-tree guard). On a pull request, `<base>` is the target branch as CI fetched it, such as `origin/main`. On a push, `<base>` is the commit the branch held before the push. The checkout needs the history back to `<base>`, because `--delta` stops when it cannot find `<base>` or the merge base. PR builds get no secrets.

## Verbs

The verbs are listed once, in `08_ctl.md` § Verbs. The ones this page uses: `ctl gate [--changed | --delta <base> | --all] [-q]`, `ctl gate static | dynamic`, `ctl gate <rung>`, `ctl gate clones`, `ctl check`.

Template: `template/scripts/gate/` (`all.sh` = the ladder, its two groups and its modes, one file per rung, `_gate.sh` = the rung contract and `--quiet`, `_targets.sh` = the apps lint, typecheck and test check, `_changed.sh` = what a changed-only run selects, `_lock.sh` = one gate run per user under a memory lid).
