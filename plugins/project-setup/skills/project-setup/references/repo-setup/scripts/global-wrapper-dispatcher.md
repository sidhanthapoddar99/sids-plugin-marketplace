# `ctl` — the global control dispatcher

One executable at repo root. Single entrypoint for the whole stack — local dev processes **and** containers. The user-facing API for the project.

> **Name.** This doc uses `ctl`. The name is a single token you can swap project-wide (`stack`, `app`, `ctl`, or the project name) — pick one and keep it. With mise's project-scoped PATH (`[env]._.path = ["."]` / `["scripts"]`, see `references/repo-setup/mise.md`) you call it bare — `ctl dev` — instead of `./ctl`.

## The model — split by lifecycle, not by one verb

Two kinds of thing have two different lifecycles, so they get two different grammars:

| Kind | Lifecycle | Commands |
|---|---|---|
| **The local dev loop** (apps on host, hot reload) | interactive, foreground — you watch it, Ctrl-C to stop | `ctl dev` |
| **The full containerised stack** (prod overlay + traefik) | a deployment | `ctl prod` |
| **Container services** (db, redis, …) | detached, long-lived background | `ctl up` / `ctl down` / `ctl ps` / `ctl logs` |

`dev` and `prod` are the two "run the whole stack" launchers, split by **where it runs** (host vs docker). `up`/`down` are the granular **container** knobs — in dev these are almost always just the data services, because the apps run on the host.

## Command surface

```
ctl dev [target]      run the stack LOCALLY on the host (hot reload). target ∈ all|backend|frontend|<svc>
                      auto-ensures its data-container deps are up first. foreground; Ctrl-C/q stops.
ctl prod              run the full stack IN DOCKER (prod overlay + traefik). detached.

ctl up   [service]    start container service(s), detached. bare = data services (db, redis). --prod for prod overlay
ctl down [service]    stop container service(s)
ctl restart [service]
ctl ps                unified view: running containers + running local dev procs
ctl logs [service] [-f]

ctl status [service]  config doctor — project-custom body (see below)
ctl setup             interactive .env / config.local.yaml wizard — project-custom body
ctl migrate {up|down|new|status}   alembic (lives here, not under dev)
ctl test [target]
ctl build             production image build
ctl clean             tear down + clear caches (asks first)
ctl help              print the contract
```

Note `ctl dev backend` (backend on the **host**, reloading) and `ctl up backend` (backend **container**) differ — `dev` = host, `up` = container. In dev `up` is usually only `db`/`redis`, so the overlap is rare; `ctl help` and `ctl status` must spell the distinction out.

## Delegate — don't hand-roll a process manager

The dispatcher is **thin routing**. It must not grow into a 500-line supervisor (that fights the modularity caps in `references/architecture/modularity/`). It delegates:

- **Containers → `docker compose`.** `up`/`down`/`ps`/`logs`/`restart` are thin wrappers over compose, which already does health, deps, and log multiplexing.
- **Local multi-process dev → a real runner, not bash PID juggling.** Default **`process-compose`** (declarative `process-compose.yaml`: per-process commands, `depends_on`, readiness probes, a TUI with per-service panes, `--detached` mode). Lighter alternative: **`mprocs`**. Zero-dep fallback: a bash `trap` killing backgrounded jobs (shown below) — fine for 1–2 processes, replace with process-compose past that. This is where the "independent frontend/backend views" you'd reach for tmux come from — for free.
- **`status` / `setup` → project-custom subscripts** (`scripts/status.sh`, `scripts/setup.sh`). The *command surface* is uniform across every project; these two bodies are necessarily case-by-case (which env keys, which services, frontend-vs-backend checks). The dispatcher routes; the bodies vary.

## Skeleton

```bash
#!/usr/bin/env bash
# ctl — <PROJECT> control plane. Local dev + containers, one entrypoint.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; cd "$REPO_ROOT"

c_info(){ printf '\033[36m▸\033[0m %s\n' "$*"; }
c_ok(){   printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn(){ printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die(){    printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
  [[ -f .env ]] || { c_warn ".env missing — run \`ctl setup\` (or cp .env.example .env)."; exit 1; }
  set -a; source .env; set +a
}
require_tools() { for t in mise docker; do command -v "$t" >/dev/null || die "missing: $t"; done; }

# --- container lifecycle: thin wrappers over docker compose -----------------
DATA_SVCS=(postgres redis)
compose() { docker compose -f docker/compose.yaml "$@"; }
cmd_up()      { require_env; if [[ $# -eq 0 ]]; then compose up -d "${DATA_SVCS[@]}"; else compose up -d "$@"; fi; }
cmd_down()    { compose down "$@"; }
cmd_ps()      { compose ps; process-compose process list 2>/dev/null || true; }
cmd_logs()    { compose logs "$@"; }

# --- the two stack launchers ------------------------------------------------
cmd_dev() {                       # local, host, hot reload
  require_env; require_tools
  c_info "ensuring data services…"; cmd_up "${DATA_SVCS[@]}"
  bash scripts/wait-for-health.sh "${DATA_SVCS[@]}" 60
  if command -v process-compose >/dev/null; then
    exec process-compose up "${@:+--names $*}"        # reads process-compose.yaml
  else
    bash scripts/dev-host.sh "$@"                      # bash trap fallback (1–2 procs)
  fi
}
cmd_prod() {                      # full docker, prod overlay
  require_env
  docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml \
    --env-file .env.production up -d
}

# --- custom-body subcommands route to scripts -------------------------------
cmd_status()  { bash scripts/status.sh "$@"; }     # project-custom config doctor
cmd_setup()   { bash scripts/setup.sh "$@"; }      # project-custom .env wizard
cmd_migrate() { bash scripts/migrate.sh "$@"; }

cmd_help() { cat <<EOF
ctl — <PROJECT> control plane
  ctl dev [target]     run locally on the host (hot reload); deps auto-started
  ctl prod             run the full stack in docker
  ctl up/down [svc]    start/stop container services (bare = db,redis)
  ctl ps / logs [svc]  inspect containers + local procs
  ctl status [svc]     check config (.env, config.local.yaml, deps reachable)
  ctl setup            interactive .env wizard
  ctl migrate {up|down|new|status}
  ctl test / build / clean / help
EOF
}

main() {
  case "${1:-help}" in
    dev)      shift; cmd_dev "$@" ;;
    prod)     cmd_prod ;;
    up)       shift; cmd_up "$@" ;;
    down)     shift; cmd_down "$@" ;;
    restart)  shift; compose restart "$@" ;;
    ps)       cmd_ps ;;
    logs)     shift; cmd_logs "$@" ;;
    status)   shift; cmd_status "$@" ;;
    setup)    cmd_setup ;;
    migrate)  shift; cmd_migrate "$@" ;;
    test)     shift; bash scripts/test.sh "$@" ;;
    build)    bash scripts/build.sh ;;
    clean)    bash scripts/clean.sh ;;
    help|-h|--help) cmd_help ;;
    *)        die "unknown command: $1. Try ctl help" ;;
  esac
}
main "$@"
```

The skill drops this from `assets/snippets/scripts/dev-wrapper.sh` and adapts it.

## The dev launcher's process file (`process-compose.yaml`)

```yaml
# host dev processes — `ctl dev` runs these; deps auto-ordered; per-process panes
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

`ctl dev backend` runs just that process; `ctl dev` runs all. `depends_on` plus the data-service auto-up in `cmd_dev` is exactly the "error if a required dep isn't there" behaviour — declare deps, let the runner enforce them.

## Dependency auto-up

`ctl dev` brings up its data-container deps (`db`, `redis`) before starting host processes, and `process-compose`'s `depends_on` orders the host processes among themselves. So the everyday loop is one command — `ctl dev` — not "`ctl up db` then start things by hand." If a declared dep can't be started, fail loudly with the fix, never start half a stack silently.

## Design rules

- **`ctl dev` is the most common path.** Optimise for "fresh clone → `ctl setup` → `ctl dev` → it works."
- **No silent failures.** Missing tool, unset var, healthcheck timeout → die with the fix.
- **Thin dispatch, delegated logic.** Subcommands route to `docker compose`, `process-compose`, or `scripts/<name>.sh`. The wrapper is the contract, not the implementation.
- **`status` and `setup` are the two custom bodies** — stable command name, project-specific logic. Everything else is largely uniform across projects.
- **Self-documenting** — `ctl help` is the contract.

## One dispatcher per repo

A single repo has **one** `ctl`. New need → a subcommand, not a second wrapper. The one place two contracts exist is Topology 06 (polyrepo + aggregator): each child repo has its own `ctl`, and the aggregator repo has its own `ctl` whose `ctl prod` deploys the merged stack. Different repos, different contracts — not two wrappers in one repo.

## Anti-patterns

- A 500-line bash wrapper that reimplements a process manager — delegate to `process-compose`/`docker compose`.
- Hand-managing local PIDs, pidfiles, and tmux sessions when `process-compose`/`mprocs` do it declaratively.
- Folding migrations or prod into `ctl dev` — `dev` is the host loop only; migrations are `ctl migrate`, docker is `ctl prod`/`ctl up`.
- Subcommands that just alias `docker compose` syntax verbatim — the wrapper exists to hide the `-f` flag soup.
- Adding subcommands proactively for hypothetical needs — wait for the pain.
- Silent fallbacks ("if docker isn't installed, try podman") — be explicit; ask the user to install the canonical tool.

## See also

- `references/repo-setup/scripts/dev-without-docker.md` — what `ctl dev` runs on the host and why
- `references/repo-setup/scripts/setup-command.md` — `ctl setup` / `ctl status` as project-custom subscripts
- `references/repo-setup/scripts/subscripts.md` — the `scripts/*.sh` the dispatcher calls
- `references/repo-setup/scripts/three-startup-paths.md` — `ctl` / raw compose / no-docker, documented in the README
- `references/repo-setup/mise.md` — project-scoped PATH so `ctl` is callable bare
