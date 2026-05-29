# `ctl` + `scripts/` — usage reference

The command surface, the dispatcher skeleton, the `scripts/*.sh` map, the host dev loop, and the three startup-path commands. For the model (why `dev` vs `up`, the thin-wrapper principle, the two custom bodies, why-host) start at `script-overview.md`.

## `ctl up` — profiles, one config, stacked modifiers

```
ctl up                              core only (no-profile services: data layer)
ctl up <profile…>                   --profile <p> …                profiles  ∈ app|edge|obs|…
ctl up <profile…> --config=<name>   + compose.<name>.yaml          config    ∈ prod|… (at most one)
ctl up <profile…> --<modifier>…     + compose.m.<modifier>.yaml    modifiers ∈ expose|traefik|no-ports|…
ctl up --help                       list discovered profiles, configs, modifiers
```

- **Auto-discovered**: profiles by grepping `profiles:` in `compose.yaml`; configs are `compose.<name>.yaml`; modifiers are `compose.m.<name>.yaml`. No hard-coded lists — drop a file and it appears in `--help`.
- **`--config=prod` switches `--env-file` to `.env.production`** when present.
- **Always echoes the composed command** before running, so the active set is never hidden.

```
ctl up app edge --config=prod --traefik
▸ docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml --profile app --profile edge --env-file .env.production up -d
```

The compose-file convention these assemble (profiles vs config vs `.m.` modifier, path discipline) is `docker-overview.md`.

## Command surface

Grouped by category (the prefix on the backing script file; the `ctl` verb stays clean). **Every command takes `-h`/`--help`** — uniform, colored, rendered by one helper in `_lib.sh`.

```
Development (host loop)
  ctl dev [target]                 apps on host, hot reload; auto-ups + waits for the data core   (dev-host.sh)
  ctl migrate {up|down|new|status} alembic — backend owns DDL                                      (dev-migrate.sh)
  ctl test [backend|frontend]      run test suites                                                 (dev-test.sh)
  ctl lint [backend|frontend]      lint backend + frontend (ruff + biome; stack-specific)          (dev-lint.sh)

Containers (docker compose)
  ctl up [profile…] [--config=<name>] [--<modifier>…] [--dry-run]   assemble + start the stack     (docker-up.sh)
  ctl up --help                    list discovered profiles, configs, modifiers
  ctl down [svc] / restart [svc]   stop / restart                                       (inline → docker compose)
  ctl logs [svc] [-f] / ps         tail logs / containers + host procs                  (inline → docker compose)
  ctl exec <svc> [cmd]             run a command in a container (default: shell)        (inline → docker compose)
  ctl shell <svc>                  psql / redis-cli / shell in a container                          (docker-shell.sh)
  ctl build                        frontend assets + backend image                                 (docker-build.sh)
  ctl clean [-y]                   tear down + wipe volumes/caches (asks first)                     (docker-clean.sh)
  ctl health [svc…]                one-shot health table                                            (docker-health.sh)

Configuration
  ctl setup                        interactive .env wizard — project-custom                         (manage-setup.sh)
  ctl status                       doctor: env · runtimes (mise/uv/bun/uvenv) · docker · health · stack  (manage-status.sh)
  ctl help                         print the grouped contract
```

Every command takes `-h`/`--help`; `ctl up --help` and `ctl status` both surface the auto-discovered profiles / configs / modifiers, so "what can I run here" is always one command away.

`ctl dev backend` (backend on the **host**, reloading) and `ctl up app` (backend **container**) differ by *where it runs* — `dev` = host, `up` = docker. The trivial `down`/`restart`/`logs`/`ps`/`exec` forwards live inline in `ctl`; everything with a real body is a `scripts/<category>-<name>.sh` worker.

## Architecture — `ctl` + `_lib.sh` + workers

The runnable toolkit ships in `assets/snippets/scripts/` — copy `ctl` (to repo root) + `scripts/` and it works. Three layers:

**`_lib.sh` (sourced by everything)** — the shared foundation that keeps every worker tiny and identical: a TTY/`NO_COLOR`-aware color palette + `say/step/ok/warn/err/die`, the uniform `print_help` renderer, `dc()` + `list_profiles/list_configs/list_modifiers` discovery, `require_env/require_tools`, `wait_healthy/health_table`, `check_env_schema`, `confirm`. Colors auto-disable when stdout isn't a terminal or `NO_COLOR` is set.

**`ctl` (the router)** — sources `_lib.sh`, dispatches each subcommand, inlines only the trivial passthroughs:

```bash
#!/usr/bin/env bash
set -euo pipefail
CTL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$CTL_ROOT/scripts/_lib.sh"; cd "$CTL_ROOT"

run() { local s="$CTL_ROOT/scripts/$1.sh"; shift; [[ -f $s ]] || die "missing $s"; exec bash "$s" "$@"; }

case "${1:-help}" in
  dev)     shift; run dev-host    "$@" ;;          # real bodies → workers
  migrate) shift; run dev-migrate "$@" ;;
  up)      shift; run docker-up   "$@" ;;
  setup)   shift; run manage-setup "$@" ;;
  # … test/build/clean/health/status route the same way …
  down)    shift; is_help "${1:-}" && { passthrough_help down "stop the stack"; exit 0; }; dc down "$@" ;;
  restart|logs|ps|exec) … ;;                       # trivial docker compose forwards, inline
  help|-h|--help) ctl_help ;;
  *)       die "unknown command: ${1:-} (try ctl --help)" ;;
esac
```

**`scripts/<category>-<name>.sh` (the workers)** — each sources `_lib.sh`, has a `usage()`, intercepts `-h/--help`, then does its one job with colored output. The uniform shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

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

The load-bearing piece is `docker-up.sh`'s assembly (the same profiles + one `--config` + stacked `.m.` modifiers logic shown above) plus the discovery in `_lib.sh` — a one-line `grep`/glob per axis, convention over a YAML parser. Everything else is thin routing. Each worker stays ~25 lines because `_lib.sh` carries the shared weight; `ctl <cmd> --help` and `ctl up --help` (the discovered lists) come for free from `print_help`.

## `ctl setup` + `ctl status` — the two custom bodies

**`scripts/manage-setup.sh`** (the wizard): copy `.env.example` → `.env` if missing (never overwrite); walk the **REQUIRED** keys, generating secrets the user shouldn't invent (`openssl rand -hex 32` for `*_PASSWORD/_SECRET/_KEY`); ensure bind-mount data dirs (`mkdir -p data/postgres/pgdata data/redis/data`); end by pointing at `ctl dev`. Idempotent — re-running tops up, never clobbers.

**`scripts/manage-status.sh`** (the doctor) is read-only; it calls `check_env_schema` (from `_lib.sh`) and layers tool + health checks. Project-specific checks, consistent shape:

| Check | Example |
|---|---|
| `.env` exists, matches `.env.example` schema | no missing keys, no empty REQUIRED |
| `config.local.yaml` present (dev) | warn if absent — defaults won't apply |
| Per-service config | backend `config.yaml` valid; frontend `.env` has `VITE_*`/`NEXT_PUBLIC_*` |
| Dependencies reachable | data containers healthy? `mise` tools installed? |
| Secrets not placeholder | REQUIRED keys aren't still `changeme` |

| Check | Example |
|---|---|
| `.env` exists, matches `.env.example` schema | no missing keys, no empty REQUIRED |
| `config.local.yaml` present (dev) | warn if absent — defaults won't apply |
| Per-service config | backend `config.yaml` valid; frontend `.env` has `VITE_*`/`NEXT_PUBLIC_*` |
| Dependencies reachable | data containers up? ports free? `mise` tools installed? |
| Secrets not placeholder | REQUIRED keys aren't still `changeme` |

```
$ ctl status
✓ .env present, matches .env.example
! config.local.yaml not set — using config.yaml defaults
✓ backend: config.yaml valid, DATABASE_URL set
✗ frontend: VITE_API_BASE_URL empty — set it in apps/web/.env
✓ infra: postgres + redis healthy
```

Report per area (backend / frontend / infra), green/yellow/red, with the fix for each red. `ctl status` calls `check_env_schema` (from `_lib.sh`, also exposed as `manage-check-env.sh`) and layers tool, health, and discovered-stack (profiles/configs/modifiers) checks on top.

## `ctl dev` — the host loop

`ctl dev` (1) brings up its data-container deps (`postgres`, `redis`, with ports) via `docker compose` and waits for healthchecks (`wait_healthy` from `_lib.sh`); (2) starts each app as a host process with hot reload; (3) multiplexes output into per-service panes; (4) stops everything cleanly on Ctrl-C. Steps 2–4 are delegated to a process runner — don't hand-roll PID juggling.

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

`ctl dev` runs all; `ctl dev backend` runs one. `depends_on` orders the host processes; the data-container auto-up orders the containers before them — declare deps, let the runner honour them. If a declared dep can't start, fail loudly with the fix, never start half a stack.

### Fallback: bash `trap` (`scripts/dev-host.sh`, ≤ 2 processes)

```bash
prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }
( cd apps/backend  && uv run uvicorn app.main:app --reload --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
```

**Stays in containers** (via `ctl up`): postgres + any stateful service, redis, Seaweed/Meilisearch/Neo4j, optionally an nginx for routing tests. **Runs on host** (via `ctl dev`): Python/Rust backends with `--reload`/`cargo-watch`, the frontend dev server, test runners.

**Reverse proxy in dev:** default is the **Vite proxy** (`vite.config.ts` proxies `/api/*` to the backend host port — CORS-free, no extra container); or `ctl up edge` for a local nginx if you need prod-like routing. In prod (`ctl up app edge --config=prod`), nginx/traefik routes the same `/api/*` over the compose network — only the proxy changes.

**When host-mode doesn't fit a service:** heavy native deps (exotic glibc, GPU libs) → containerise *that one service* (give it a profile), keep the rest on host. Cross-platform team that can't install the toolchain → offer `ctl up app` as the containerised path, but keep host as the `ctl dev` default.

## Three startup paths — the commands

Every README documents all three (concept in `script-overview.md`). The exact commands:

````markdown
## Get started

```bash
git clone <url> && cd <repo>
mise install        # also puts `ctl` on PATH inside the repo
ctl setup           # interactive: fills .env, generates secrets
ctl dev             # apps on host (hot reload), data core in containers
```

### Other ways to start

```bash
# raw docker compose — what ctl does under the hood
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d                     # data core, ports published
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml --profile app up -d       # + app services
docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.m.traefik.yaml \
    --profile app --profile edge --env-file .env.production up -d                                # production

# no docker — host run (IDE debugger attach, profiling, one service in isolation)
docker compose -f docker/compose.yaml -f docker/compose.m.expose.yaml up -d   # data core only
cd apps/backend && uv sync && uv run alembic upgrade head && uv run uvicorn app.main:app --reload --port 8000
cd apps/frontend && bun install && bun dev                                    # new terminal
```
````

The no-docker path is what `ctl dev` automates; documenting it raw lets a developer attach a debugger to one service. **Prod** is `ctl up app edge --config=prod` — keep development (`ctl dev`) distinct from deployment in the README's Deploy section.

`/ps-setup audit` checks the README shows all three paths. Drift to flag: only `ctl dev` (can't debug compose), only `docker compose` (no fast-iteration story), only raw host run (everyone reinvents the flow).

## Anti-patterns

- Logic inside `ctl` that belongs in a script — split when a subcommand grows past ~30 lines.
- Hardcoding service names that should come from compose project naming.
- Forgetting `set -euo pipefail` in a worker — silent failures bite.
- A `status` that just greps for files — it should check reachability and REQUIRED-value-ness, not mere presence.
- Generating prod secrets via the interactive wizard — prod injects real env vars.
- "Just run `make dev`" with no explanation, or a Getting-Started wiki separate from the README — keep the contract in the repo.
- Different commands in CI vs README — CI uses the same documented commands (or a superset).

## Setting up & modifying the scripts

The shipped `ctl` + `scripts/` are a **starting template** — copy them, then edit per project; the workers are custom scripts, not fixed tools. The recommended stack is **mise** (versions + bare-name PATH), **docker** (containers), **uv** (`uv sync` in-tree venv) and **bun** (node) — and `ctl setup` bootstraps a clone end-to-end with them: create `.env`, generate secrets, make data dirs, **install deps** (`uv sync` + `bun install`); `ctl status` then reports env · runtimes · docker · **deps (`.venv`/`node_modules`)** · health · stack.

To **add** a command, drop `scripts/<category>-<name>.sh` (worker preamble + `usage()` + `is_help` guard, sourcing `_lib.sh`) and wire one `run` line into `ctl`. To **modify** one, edit its body — the command surface and `_lib.sh` stay constant.

**Using mise / docker / uv / bun is highly recommended, but not mandatory.** When a project opts out of any of them, **don't fight the template** — follow `script-alternatives.md`, which gives the exact `.sh` lines to edit and the substitute (e.g. `./ctl` instead of bare `ctl` without mise; native Postgres/Redis without docker; **uvenv** named global venvs or `python -m venv`/poetry instead of `uv sync`; pnpm/npm instead of bun).

## See also

- `script-overview.md` — the model (dev vs up, thin wrapper, the two custom bodies, why-host, three-paths concept)
- `script-alternatives.md` — adapting the scripts off mise / docker / uv / bun (incl. uvenv)
- `docker-overview.md` — profiles / config / `.m.` modifiers; `docker/` layout + path discipline
- `mise.md` — project-scoped PATH; `ctl` callable bare
- `assets/snippets/scripts/ctl` (+ `scripts/*.sh`) — the runnable dispatcher and workers
- `references/architecture/frontend/vite-proxy-nginx-pair.md` — dev proxy → prod nginx
