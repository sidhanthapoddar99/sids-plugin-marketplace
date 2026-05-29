# `ctl` + `scripts/` — the control-plane model

One executable at repo root — `ctl` — is the single entrypoint for the whole stack: local dev processes **and** containers. It's the project's user-facing API. This doc is the **mental model**; the command surface, the dispatcher skeleton, the `scripts/*.sh` map, and the exact startup commands live in `script-usage.md`.

> **Name.** `ctl` is a single swappable token (`stack`, `app`, or the project name) — pick one, keep it. With mise's project-scoped PATH you call it bare — `ctl up`, not `./ctl`. See `mise.md`.

## One host launcher, one docker launcher

Two kinds of thing have two lifecycles, so they get two grammars:

| Kind | Lifecycle | Commands |
|---|---|---|
| **Local dev loop** (apps on host, hot reload) | interactive, foreground — Ctrl-C stops | `ctl dev` |
| **Containerised stack** | detached, long-lived | `ctl up [profile…] [--config=<name>] [--<modifier>…]` · `down` · `ps` · `logs` |

`ctl dev` runs apps **on the host** — genuinely *not* a compose variant, so it's its own verb. Everything that runs **in docker** goes through `ctl up`. There is **no `ctl prod` verb**: production is `ctl up app edge --config=prod`.

### `ctl up`'s three axes (concept)

- **Profiles** — *which services run* (combine freely; the data core has no profile and is always up).
- **Config** — at most one **`--config=prod`**, a full alternate deployment definition.
- **Modifiers** — stackable cross-cutting overlays (`--expose`, `--traefik`).

The compose-file convention behind these (filenames, discovery) is owned by `docker-overview.md`; the exact `ctl up` grammar and the assembled `docker compose` line are in `script-usage.md`.

## Thin wrapper — delegate, don't hand-roll

`ctl` is **thin routing**, never a 500-line supervisor (that would fight the modularity caps). It delegates:

- **Containers → `docker compose`.** `up`/`down`/`ps`/`logs`/`restart` are thin wrappers; `up`'s only real logic is turning profiles + config + modifiers into a `--profile`/`-f`/`--env-file` list, then echoing and running it.
- **Local multi-process dev → a real runner**, not bash PID juggling. Default **`process-compose`** (declarative `process-compose.yaml`, readiness probes, per-service panes); **`mprocs`** as a lighter option; a bash `trap` only as a 1–2-process fallback (`scripts/dev-host.sh`).
- **Real command bodies → `scripts/<category>-<name>.sh`**, each owning one job (the trivial one-liners `down`/`restart`/`logs`/`ps`/`exec` stay inline in `ctl`). See the structure below.
- **Shared concerns → `scripts/_lib.sh`**, sourced by `ctl` and every worker: the color palette + logging, the uniform `--help` renderer, the `dc()`/discovery/assembly helpers, env/tool guards, health. This is what lets each worker stay ~25 lines and look identical.

## The `scripts/` structure — what you create

`ctl` routes; `scripts/<name>.sh` are the workers, **grouped by a category prefix** so the folder reads as a toolkit. Each sources `_lib.sh`, is self-contained (`set -euo pipefail`, exits non-zero, runnable on its own), and ships a `-h/--help`.

```
scripts/
├── _lib.sh                      # shared: colors, logging, print_help, dc()+discovery, guards, health, confirm
├── dev-host.sh                  # ctl dev      — ensure data core, run apps on host (process-compose|bash)
├── dev-migrate.sh               # ctl migrate  — alembic up/down/new/status
├── dev-test.sh                  # ctl test     — pytest + bun test
├── dev-lint.sh                  # ctl lint     — ruff + biome (check; stack-specific)
├── docker-up.sh                 # ctl up       — assemble profiles + --config + .m. modifiers (+ --dry-run)
├── docker-build.sh              # ctl build    — frontend assets + backend image
├── docker-clean.sh              # ctl clean    — teardown + wipe volumes/caches (asks; -y to skip)
├── docker-health.sh             # ctl health   — one-shot health table
├── docker-shell.sh              # ctl shell    — psql / redis-cli / shell in a container
├── manage-setup.sh              # ctl setup    — interactive .env wizard (project-custom)
├── manage-status.sh             # ctl status   — doctor: env·runtimes·docker·health·stack (project-custom)
└── manage-check-env.sh          # helper       — .env vs .env.example schema diff (used by status)
```

| Prefix | Holds | Backing `ctl` verbs |
|---|---|---|
| `dev-` | host-loop / development workflow | `dev`, `migrate`, `test`, `lint` |
| `docker-` | container & compose lifecycle | `up`, `build`, `clean`, `health`, `shell` |
| `manage-` | config management | `setup`, `status` (+ `check-env` helper) |

Naming syntax is **`<category>-<name>.sh`** (`category ∈ dev | docker | manage`). The prefix is the **file** name only — the `ctl` subcommand stays clean (`ctl migrate`, not `ctl dev-migrate`). Trivial `docker compose` passthroughs (`down`/`restart`/`logs`/`ps`/`exec`) are **not** files — they're one-line forwards inlined in `ctl`, still shown under the Containers group with uniform help.

**Treat the shipped set as a template, not a spec.** It's a sensible default — copy `ctl` + `scripts/`, then add / remove / edit per the project; most repos won't need every command, and `lint`/`shell` are stack-specific (adapt or drop). How many files is **utility-driven**: a command earns a file once it outgrows a one-liner. **To add a command:** drop `scripts/<category>-<name>.sh` (worker preamble + `usage()` + `is_help` guard, sourcing `_lib.sh`) and wire one `run <file>` line into `ctl`'s `case`. The runnable toolkit lives in `assets/snippets/scripts/`; `script-usage.md` has the architecture + worked bodies.

## `setup` + `status` — the two project-custom bodies

Every `ctl` verb is uniform across projects **except two**, whose logic is necessarily case-by-case (which env keys, which services, frontend-vs-backend checks):

- **`ctl setup`** — interactive wizard filling `.env` / `config.local.yaml`: copy `.env.example`, prompt REQUIRED blanks, generate secrets (`openssl rand`), make data dirs. Re-runnable — tops up missing values, never clobbers good ones.
- **`ctl status`** — read-only config doctor answering "is this correctly configured to run?" *before* `ctl dev` hits a confusing runtime error.

First run is `ctl setup` → `ctl dev`. Setup is **explicit**, never folded silently into a bare run: `ctl dev` only *guards* (`.env` missing → "run `ctl setup`"); it never mutates config mid-launch. Prod secrets are injected as real env vars (`.env.production` via compose `env_file`), never via the interactive wizard.

## Why apps on host for dev

`ctl dev` runs apps on the host, only data services in containers:

| Containerised apps in dev | Apps on host (`ctl dev`) |
|---|---|
| Total prod parity | Faster iteration |
| Slow bind-mount file watching (esp. macOS) | Native file events |
| Complex debugger attach (port mapping) | IDE attaches directly to the local process |
| `restart` to pick up changes | native `--reload` / `bun dev` / `cargo-watch` |

Parity is enforced by CI building images and by `ctl up app edge --config=prod` running them — you don't *develop* against the image. Source is never bind-mounted into a dev container. When you do want the containerised stack, that's `ctl up app`, not `ctl dev`.

## Three startup paths (every README documents all three)

1. **`ctl dev`** — the dispatcher; recommended day-to-day path.
2. **Raw `docker compose -f docker/…`** — understand what `ctl` does; debug compose itself; copy for prod.
3. **No-docker host run** — `cd apps/backend && uv run …; cd apps/frontend && bun dev` — IDE debugger attach, profiling, one service in isolation.

If any of the three is broken or missing, the project has invisible debt. The exact commands, README template, and audit rule are in `script-usage.md`.

## One dispatcher per repo

A repo has **one** `ctl`. New need → a profile, a `compose.<config>.yaml`, or a subcommand — not a second wrapper. The one exception is Layout 03 (polyrepo + aggregator): each child repo has its own `ctl`, and the aggregator has its own whose `ctl up app edge --config=prod` deploys the merged stack. When `ctl` itself outgrows shell (structured state across runs, multi-node promotion), escalate it to a binary — see `complex-setups.md`.

## Anti-patterns

- `setup.sh` + `start.sh` + `dev.sh` at root — four contracts; collapse to `ctl` verbs.
- A 500-line bash wrapper reimplementing a process manager — delegate to `process-compose`/`docker compose`.
- A `ctl prod` verb separate from `ctl up` — production is just profiles + `--config=prod`; two verbs for one lifecycle drift apart.
- `ctl dev` silently editing `.env` on launch — guard and instruct; mutation belongs in `ctl setup`.
- README "first run `make install`, then `make dev`" — it's `ctl setup` then `ctl dev`.
- Bind-mounting source into a dev container — slow file events, permission pain; run on host.

## See also

- `script-usage.md` — command surface, dispatcher skeleton, the `scripts/*.sh` map, setup/status detail, host-loop runner, how to add/modify scripts
- `script-alternatives.md` — adapting the workers off the recommended defaults (no mise / docker / uv→uvenv·venv·poetry / bun→pnpm·npm)
- `docker-overview.md` — the profile / config / `.m.` modifier compose convention `ctl up` implements
- `mise.md` — the project-scoped PATH that makes `ctl` callable bare
- `complex-setups.md` — when `ctl` outgrows shell (multi-node, Go-CLI orchestrator)
- `overview.md` — the whole-runtime interaction map (mise → ctl → docker)
