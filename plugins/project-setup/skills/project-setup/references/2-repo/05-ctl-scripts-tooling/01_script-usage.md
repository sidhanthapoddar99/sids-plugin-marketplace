# `ctl` + `scripts/` — usage reference

The command surface, the dispatcher skeleton, the interactive `ctl up` flow, the `scripts/*.sh` map, the host dev loop, and the three startup-path commands. For the model (why `dev` vs `up`, the thin-wrapper principle, the two custom bodies, why-host) start at `00_script-overview.md`.

> **These code blocks are ILLUSTRATIVE.** The source of truth is the runnable snippet under **`assets/snippets/scripts/<file>`** (`assets/` is a sibling of `skills/` at the plugin root). Copy verbatim, then adapt — don't regenerate from this prose.

## `ctl up` — one standalone config, stacked modifiers (profile-less)

```
ctl up                              base = the whole stack (interactive in a TTY)
ctl up <config>                     compose.<config>.yaml REPLACES base   config    ∈ data|prod|…  (≤1)
ctl up [config] --modifier "a,b"    + compose.m.<a>.yaml + compose.m.<b>.yaml      modifiers ∈ expose|expose_data|expose_all|traefik|…
ctl up --list                       terse list of discovered configs + modifiers
ctl up --help                       full help with the discovered lists
```

- **Two axes, no profiles**: a single optional **config** (a `compose.<name>.yaml` that *replaces* base) + stackable **`--modifier`** overlays (comma-list, repeatable). Every service in the chosen file runs.
- **Auto-discovered**: configs are `compose.<name>.yaml` (minus base + modifiers); modifiers are `compose.m.<name>.yaml`. No hard-coded lists — drop a file and it appears.
- **A config `<x>` auto-uses `.env.<x>`** if present (e.g. `prod` → `.env.prod`).
- **Always echoes the composed command** before running, so the active set is never hidden.

```
ctl up prod --modifier traefik
▸ docker compose -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml up -d --build
```

The compose-file convention these assemble (standalone config vs `.m.` modifier, the expose tiers, path discipline) is `references/2-repo/04-docker/00_docker-overview.md`.

### Interactive `ctl up` — pick → plan → confirm

Bare `ctl up` (or any partial invocation) in a terminal is **guided**, built on `scripts/common/_select.sh` (a dependency-free TUI — arrow keys + `[x]` checkboxes, numbered-prompt fallback with no TTY; no `fzf`/`gum`). It prompts only for the axes you *didn't* pass:

1. **config** — single-select (`base (whole stack)` + each discovered config).
2. **modifiers** — multi-select (Tab/Space toggle; empty = none).
3. **plan** — the fully-resolved result from `docker compose config`, then a horizontal **Run / Back / Cancel** (Back resets and re-opens the pickers).

```
────────────────────────────────
Plan   config=base   modifiers=[expose]
compose docker/compose.yaml docker/compose.m.expose.yaml

  service   ports host:ctr     network    volumes src:dst
  ✓ backend   -                  internal   -
  ✓ frontend  -                  internal   -
  ✓ nginx     8080:80            internal   infra/nginx/nginx.conf:/etc/nginx/nginx.conf
  ✓ postgres  -                  internal   data/postgres/pgdata:/var/lib/postgresql/data
  ✓ redis     -                  internal   data/redis/data:/data
────────────────────────────────
reproduce  (no prompts)
  ctl up --modifier=expose --nqa
  ctl up --modifier=expose --nqa -y    (also skips this confirm)
  docker: docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d --build
────────────────────────────────
```

The plan is the **real merged config** (services, published ports, networks, bind volumes), not a re-derivation — so building it also **validates the combo**: if a modifier names a service the chosen config doesn't define (e.g. `expose_all` on the `data` slice), `docker compose config -q` fails, the plan shows the real error, and the prompt offers **Back** only (never a broken `up`). Every interactive run prints the exact **`--nqa` command that reproduces it** — interactivity *teaches* the scriptable form.

| Command | Prompt missing axes? | Plan? | Confirm? |
|---|---|---|---|
| `ctl up` (TTY) | yes | yes | yes |
| `ctl up --nqa` | no | yes | **yes** |
| `ctl up … -y` | yes | yes | no |
| `ctl up --nqa -y` | no | yes | no (fully unattended — for CI) |
| `ctl up …` (no TTY, no `-y`) | no | yes | refuses — prints the plan, exits non-zero with guidance |

`--nqa` = no questions (don't prompt). `-y/--yes` = skip the final confirm. They're orthogonal: **`--nqa` alone still shows the plan and confirms** (a script wanting zero interaction says `--nqa -y`). `--dry-run`/`-n` prints the plan and exits. **`-a`/`--attach`** runs in the foreground (drops `-d`, `exec`s compose so Ctrl-C reaches it directly); default is detached.

## Command surface

Grouped by category (the prefix on the backing script file; the `ctl` verb stays clean). **Every command takes `-h`/`--help`** — uniform, colored, rendered by one helper in `_lib.sh`.

```
Development (host loop)
  ctl dev [target] [--dry-run]     apps on host, hot reload; auto-ups + waits for the data core   (dev/host.sh)
                                   --help shows each target's exact host command; --dry-run prints them
  ctl migrate {up|down|new|status} alembic — backend owns DDL                                      (dev/migrate.sh)
  ctl test [backend|frontend]      run test suites                                                 (dev/test.sh)
  ctl lint [backend|frontend]      lint backend + frontend (ruff + biome; stack-specific)          (dev/lint.sh)

Containers (docker compose)
  ctl up [config] [--modifier "a,b"] [-a] [--nqa] [-y] [--dry-run] [--list]   assemble + start     (container/up.sh)
  ctl down [svc] / restart [svc]   stop / restart                                       (inline → docker compose)
  ctl logs [svc] [-f]              tail container logs                                  (inline → docker compose)
  ctl exec <svc> [cmd]             run a command in a container (default: shell)        (inline → docker compose)
  ctl ps                           containers + host dev processes (by dev port → PID)              (container/ps.sh)
  ctl shell <svc>                  psql / redis-cli / shell in a container                          (container/shell.sh)
  ctl build                        build the service images                                         (container/build.sh)
  ctl clean [-y]                   tear down + wipe volumes/caches (asks first)                     (container/clean.sh)
  ctl health [svc…]                one-shot health table                                            (container/health.sh)

Configuration
  ctl setup                        .env wizard + secrets + data dirs + deps — project-custom        (config/setup.sh)
  ctl status                       doctor: env · runtimes (mise/uv/bun/uvenv) · docker · deps · health · stack  (config/status.sh)
  ctl help                         print the grouped contract
```

`ctl up --list` (terse) and `ctl status` (full doctor) both surface the auto-discovered configs / modifiers, so "what can I run here" is always one command away.

`ctl dev backend` (backend on the **host**, reloading) and `ctl up` (backend in a **container**) differ by *where it runs* — `dev` = host, `up` = docker. The trivial `down`/`restart`/`logs`/`exec` forwards live inline in `ctl`; everything with a real body — including `ps` (containers + host procs) — is a `scripts/<category>/<name>.sh` worker.

## Architecture — `ctl` + `_lib.sh` + `_select.sh` + workers

The runnable toolkit ships in `assets/snippets/scripts/` — copy `ctl` (to repo root) + `scripts/` and it works. The layers:

**`_lib.sh` (sourced by everything)** — the shared foundation that keeps every worker tiny and identical: a TTY/`NO_COLOR`-aware color palette + indent-aware `say/step/ok/warn/err/die` (an opt-in `${LOG_INDENT}` nests result lines under a `step()` header — `ctl status` uses it), the `row()` aligned-help helper (pads by display width, UTF-8-safe), the uniform `print_help`/`passthrough_help` renderer, `dc()` + `list_configs/list_modifiers` discovery + `or_none`, `require_env/require_tools`, `wait_healthy/health_table` (which resolves the real container via `dc ps -aq` and reads its health), `check_env_schema`, `split_csv`, `confirm`. It **sources `_select.sh`** after the colors so the picker reuses them. Colors auto-disable when stdout isn't a terminal or `NO_COLOR` is set.

**`_select.sh` (the picker)** — `tui_select --into VAR [--multi|--horizontal] --header … -- opt…`: a self-contained widget (single/multi/horizontal selection, arrow + `j/k`/`h/l` nav, `[x]` checkboxes, `/dev/tty` I/O so it composes inside `$(…)`, automatic numbered-prompt fallback with no TTY). Zero project knowledge — copy it verbatim. Bash 4.3+ (namerefs); `set -e`-safe (`x=$((x+1))`, never `((x++))`).

**`ctl` (the router)** — sources `_lib.sh`, dispatches each subcommand, inlines only the trivial passthroughs:

```bash
#!/usr/bin/env bash
set -euo pipefail
CTL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$CTL_ROOT/scripts/common/_lib.sh"; cd "$CTL_ROOT"

run() { local s="$CTL_ROOT/scripts/$1.sh"; shift; [[ -f $s ]] || die "missing $s"; exec bash "$s" "$@"; }

case "${1:-help}" in
  dev)     shift; run dev/host    "$@" ;;          # real bodies → workers
  migrate) shift; run dev/migrate "$@" ;;
  up)      shift; run container/up   "$@" ;;
  setup)   shift; run config/setup "$@" ;;
  # … test/build/clean/health/shell/status route the same way …
  down)    shift; is_help "${1:-}" && { passthrough_help down "stop the stack"; exit 0; }; dc down "$@" ;;
  restart|logs|ps|exec) … ;;                       # trivial docker compose forwards, inline
  help|-h|--help) ctl_help ;;
  *)       die "unknown command: ${1:-} (try ctl --help)" ;;
esac
```

`ctl_help` builds its two-column layout with `row()` (one command per line, each with its own description — `row` keeps the columns aligned even with multibyte glyphs).

**`scripts/<category>/<name>.sh` (the workers)** — each sources `common/_lib.sh` (one level up), has a `usage()`, intercepts `-h/--help`, then does its one job with colored output. The uniform shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "migrate" "Run database migrations (Alembic)." \
  'migrate {up|down|new "<msg>"|status} [-h]' \
"Commands
  up / down / status   upgrade / downgrade one / show current
  new \"<msg>\"           create a revision

Options
  -h, --help           show this help"; }

is_help "${1:-}" && { usage; exit 0; }
require_env
# … the body (uses dc/step/ok/die from _lib.sh) …
```

The load-bearing piece is `container/up.sh`'s **parse → resolve-missing-axes → assemble → plan/validate → Run/Back/Cancel** flow plus the discovery in `_lib.sh` — a one-line `grep`/glob per axis, convention over a YAML parser. Everything else is thin routing. Each worker stays ~25 lines because `_lib.sh` carries the shared weight.

### `print_help` body anatomy

`print_help <cmd> <summary> <usage> <body> [dim-note]` leaves `<body>` free-form, but follow one anatomy so every `--help` reads identically: **Arguments / Options → (a discovered/availability block where relevant) → Example**. `container/up.sh` is the canonical example (Arguments with inline discovered lists → Example).

## `ctl setup` + `ctl status` — the two custom bodies

**`scripts/config/setup.sh`** (the wizard): copy `.env.example` → `.env` if missing (never overwrite); generate secrets the user shouldn't invent (`openssl rand -hex 32` for `*_PASSWORD/_SECRET/_KEY`); ensure bind-mount data dirs *if there's a data core* (`mkdir -p data/postgres/pgdata data/redis/data`, guarded on `DATA_SVCS`); **install deps** (`uv sync` + `bun install`); end by pointing at `ctl dev`. Idempotent — re-running tops up, never clobbers.

**`scripts/config/status.sh`** (the doctor) is read-only (never dies on a missing `.env` — diagnosing that is the point); it calls `check_env_schema` and layers tool/deps/health checks, each section's result lines nested under its `▸` header via `LOG_INDENT`. Project-specific checks, consistent shape:

| Check | Example |
|---|---|
| `.env` exists, matches `.env.example` schema | no missing keys, no empty REQUIRED |
| Per-service config | backend `config.yaml` valid; frontend `.env` has `VITE_*`/`NEXT_PUBLIC_*` |
| Runtimes | `mise` + its pins; `uv`/`bun`/`uvenv` present (informational) |
| Deps installed | `apps/backend/.venv`, `apps/frontend/node_modules` |
| Dependencies reachable | data containers healthy? ports free? |
| Discoverable stack | configs + modifiers `ctl up` can assemble |

```
$ ctl status
▸ env
  ✓ .env matches .env.example schema
▸ docker
  ✓ daemon reachable — compose v2.30
▸ data core
  postgres   healthy
  redis      healthy
▸ stack (what `ctl up` can assemble)
  configs     data prod
  modifiers   --modifier expose --modifier expose_data --modifier expose_all --modifier traefik
✓ ready
```

Report per area, green/yellow/red, with the fix for each red. `check_env_schema` is also exposed as `config/check-env.sh`.

## `ctl dev` — the host loop

`ctl dev` (1) brings up its data-container deps (`postgres`, `redis`, **with ports** via the `expose_data` modifier — guarded so a no-data-core project skips it entirely) and waits for healthchecks (`wait_healthy`); (2) starts each app as a host process with hot reload; (3) multiplexes output into per-service panes; (4) stops everything cleanly on Ctrl-C. Steps 2–4 are delegated to a process runner — don't hand-roll PID juggling.

### Preferred: `process-compose.yaml`

```yaml
processes:
  backend:
    command: "uv run uvicorn app.main:app --reload --port ${PYTHON_PORT:-8000}"
    working_dir: "apps/backend"
    readiness_probe: { http_get: { host: localhost, port: 8000, path: /health } }
  frontend:
    command: "bun dev"
    working_dir: "apps/frontend"
    depends_on: { backend: { condition: process_healthy } }
```

`ctl dev` runs all; `ctl dev backend` runs one. `depends_on` orders the host processes; the data-container auto-up orders the containers before them. If a declared dep can't start, fail loudly with the fix, never start half a stack.

### Fallback: bash `trap` (`scripts/dev/host.sh`, ≤ 2 processes)

```bash
prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }
( cd apps/backend  && uv run uvicorn app.main:app --reload --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
```

**Stays in containers** (via `ctl up`): postgres + any stateful service, redis, Seaweed/Meilisearch/Neo4j, optionally an nginx for routing tests. **Runs on host** (via `ctl dev`): Python/Rust backends with `--reload`/`cargo-watch`, the frontend dev server, test runners.

**Reverse proxy in dev:** default is the **Vite proxy** (`vite.config.ts` proxies `/api/*` to the backend host port — CORS-free, no extra container); or `ctl up --modifier expose` for a local nginx if you need prod-like routing. In prod (`ctl up prod`), nginx/traefik routes the same `/api/*` over the compose network — only the proxy changes.

## Three startup paths — the commands

Every README documents all three (concept in `00_script-overview.md`). The exact commands:

````markdown
## Get started

```bash
git clone <url> && cd <repo>
mise install        # also puts `ctl` on PATH inside the repo
ctl setup           # fills .env, generates secrets, installs deps
ctl dev             # apps on host (hot reload), data core in containers
```

### Other ways to start

```bash
# raw docker compose — what ctl does under the hood
docker compose -f docker/compose.yaml up -d --build                                   # the whole stack
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d --build    # + nginx published
docker compose -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml up -d      # production

# no docker — host run (IDE debugger attach, profiling, one service in isolation)
docker compose -f docker/compose.data.yaml -f docker/compose.m.expose_data.yaml up -d  # just the data layer, ports published
cd apps/backend && uv sync && uv run alembic upgrade head && uv run uvicorn app.main:app --reload --port 8000
cd apps/frontend && bun install && bun dev                                             # new terminal
```
````

The no-docker path is what `ctl dev` automates; documenting it raw lets a developer attach a debugger to one service. **Prod** is `ctl up prod` — keep development (`ctl dev`) distinct from deployment in the README's Deploy section.

`/ps-setup audit` checks the README shows all three paths (full checklist: `references/2-repo/02-root-hygiene/01_readme-three-paths.md`). Drift to flag: only `ctl dev` (can't debug compose), only `docker compose` (no fast-iteration story), only raw host run (everyone reinvents the flow).

## Anti-patterns

- Logic inside `ctl` that belongs in a script — split when a subcommand grows past ~30 lines.
- Hardcoding service names that should come from compose project naming.
- Forgetting `set -euo pipefail` in a worker — silent failures bite.
- A `status` that just greps for files — it should check reachability and REQUIRED-value-ness, not mere presence.
- Generating prod secrets via the wizard — prod injects real env vars.
- A hand-rolled raw-terminal TUI when the choice space is tiny — `_select.sh` already handles it; don't reinvent it, and don't pull in `fzf`/`gum` for a control plane whose pitch is "one `ctl` and you're running".
- Different commands in CI vs README — CI uses the same documented commands (`ctl up … --nqa -y`).

## Setting up & modifying the scripts

The shipped `ctl` + `scripts/` are a **starting template** — copy them, then edit per project; the workers are custom scripts, not fixed tools. The recommended stack is **mise** (versions + bare-name PATH), **docker** (containers), **uv** (`uv sync` in-tree venv) and **bun** (node) — and `ctl setup` bootstraps a clone end-to-end with them: create `.env`, generate secrets, make data dirs, **install deps**; `ctl status` then reports env · runtimes · docker · **deps (`.venv`/`node_modules`)** · health · stack.

To **add** a command, drop `scripts/<category>/<name>.sh` (worker preamble + `usage()` + `is_help` guard, sourcing `_lib.sh`) and wire one `run` line into `ctl`. To **modify** one, edit its body — the command surface, `_lib.sh`, and `_select.sh` stay constant.

**Using mise / docker / uv / bun is highly recommended, but not mandatory.** When a project opts out of any of them, **don't fight the template** — follow `02_script-alternatives.md`, which gives the exact `.sh` lines to edit and the substitute (e.g. `./ctl` instead of bare `ctl` without mise; native Postgres/Redis without docker; **uvenv** named global venvs or `python -m venv`/poetry instead of `uv sync`; pnpm/npm instead of bun). For a project with **no data layer at all**, see `references/2-repo/04-docker/02_no-data-core.md` (set `DATA_SVCS=()` — the topology swap, the analogue of the tool swap).

## See also

- `00_script-overview.md` — the model (dev vs up, thin wrapper, the two custom bodies, why-host, three-paths concept)
- `02_script-alternatives.md` — adapting the scripts off mise / docker / uv / bun (incl. uvenv)
- `references/2-repo/04-docker/02_no-data-core.md` — `DATA_SVCS=()` + apps-as-core: the exact lines to change for a DB-less project
- `references/2-repo/04-docker/00_docker-overview.md` — standalone config / `.m.` modifiers / expose tiers; `docker/` layout + path discipline
- `references/2-repo/06-runtime-environment/01_mise.md` — project-scoped PATH; `ctl` callable bare
- `assets/snippets/scripts/ctl` (+ `scripts/*.sh`, `_lib.sh`, `_select.sh`) — the runnable dispatcher, workers, and picker
- `references/2-repo/04-docker/04_proxy-and-exposure.md` — dev proxy → prod nginx
