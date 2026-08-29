# Testing and linting

Tests live with the code they test. `ctl` runs them. The gate is the only definition of green.

## Where tests live

| Kind | Where | Runner |
|---|---|---|
| Unit and component | Next to the file: `thing.py` + `test_thing.py`; `Thing.tsx` + `Thing.test.tsx` | pytest, cargo test, vitest, `go test` |
| Mutation tests | Next to the file: `Thing.mutants.tsx` | the app's own script |
| Integration (DB, HTTP) | `apps/<backend>/tests/` | pytest against the engines from `ctl dev` |
| End-to-end (browser) | `apps/multi-web-app/app/e2e/` | Playwright through `ctl test e2e` |
| Fixtures | `apps/<app>/tests/fixtures/` | never in `data/` |

No root `tests/` folder. Each app owns its suite and its `test` script (`bun test`, `uv run pytest`, `cargo test`, `go test ./...`).

## Verbs

| Verb | Runs |
|---|---|
| `ctl test` | every app's own suite, in its folder |
| `ctl test <app>` | one app |
| `ctl test e2e` | `ctl up +expose` against a throwaway `DATA_DIR`, the browser suite, teardown. Never touches `data/`. |
| `ctl lint [app] [--staged]` | ruff, cargo fmt + clippy, oxlint, gofmt + vet. `--staged` limits to staged files, for the pre-commit hook. |
| `ctl gate [-q]` | lint → check → test → build. Stops at the first red. Names every rung not reached. `-q` prints counts when green, full output when red. |
| `ctl build save` | a frozen build to test by hand. See `05_ctl.md`. |

## Rules

- Green means `ctl gate` passed. A partial run never reads as a full one.
- A backend suite runs against real engines from `compose.db.yaml`, not mocks of them. SQLite in tests only when the app ships on SQLite.
- E2E runs against a built stack, never against dev servers.
- Lint config lives per ecosystem, once: `ruff` in each `pyproject.toml`, `oxlint` config with the frontend, `rustfmt.toml` in the Rust app. No root lint config for a language the root does not contain.
- `lefthook.yml` calls `ctl lint --staged` on commit and `ctl test` on push. Hooks never call a tool directly.
- CI, when it exists, calls `ctl gate`. Nothing else.

## Linters

| Language | Tool | Runs |
|---|---|---|
| Python | ruff (lint + format) | `ruff check`, `ruff format --check` |
| Rust | rustfmt, clippy | `cargo fmt --check`, `cargo clippy -- -D warnings` |
| TypeScript | oxlint; tsc for types | `oxlint src`, `tsc --noEmit` |
| Go | gofmt, go vet | |

Template: `template/scripts/test/`, `template/scripts/dev/lint.sh`, `template/lefthook.yml`.
