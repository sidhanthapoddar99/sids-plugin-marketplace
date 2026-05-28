# `ctl` — the global control dispatcher

One executable at repo root. Single entrypoint for the whole stack — local dev processes **and** containers. The user-facing API for the project.

> **Name.** This doc uses `ctl`. The name is a single token you can swap project-wide (`stack`, `app`, `ctl`, or the project name) — pick one and keep it. With mise's project-scoped PATH (`[env]._.path = ["{{config_root}}"]`, see `references/repo-setup/mise.md`) you call it bare — `ctl up` — instead of `./ctl`.

## The model — one host launcher, one docker launcher

Two kinds of thing have two different lifecycles, so they get two different grammars:

| Kind | Lifecycle | Commands |
|---|---|---|
| **The local dev loop** (apps on host, hot reload) | interactive, foreground — you watch it, Ctrl-C to stop | `ctl dev` |
| **The containerised stack** | detached, long-lived background | `ctl up [profile…] [--config=…]` / `ctl down` / `ctl ps` / `ctl logs` |

`ctl dev` runs apps **on the host**; it is genuinely *not* a compose variant, so it's its own verb. Everything that runs **in docker** goes through `ctl up`, parameterised by **profiles** (which services) and optional **`--config` overlays** (how they run). There is **no `ctl prod` verb**: production is `ctl up app edge --config=prod`. See `references/repo-setup/docker/docker-compose-structure.md` for the profile/overlay convention this implements.

## `ctl up` — profiles + optional configs

```
ctl up                          core only (no-profile services: data layer)
ctl up <profile…>               docker compose --profile <p> …   profiles ∈ app|edge|obs|…
ctl up <profile…> --config=<n>… also layer compose.<n>.yaml      configs ∈ prod|expose|traefik|…
ctl up --help                   list discovered profiles + configs
```

- **Profiles are the everyday axis** (which subset runs); they combine freely (`ctl up app edge`). **Configs are the escape hatch** (overlay a different definition) and stack (`--config=prod --config=traefik`).
- **Auto-discovered** — profiles by grepping `profiles:` in `compose.yaml`, configs by globbing `docker/compose.*.yaml`. No hard-coded lists; drop a `compose.<x>.yaml` and it shows up in `--help`.
- **`--config=prod` switches `--env-file` to `.env.production`** when present.
- **Always echoes the composed command** before running, so the active `-f`/`--profile` set is never hidden.

```
ctl up app edge --config=prod --config=traefik
▸ docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml --profile app --profile edge --env-file .env.production up -d
```

## Command surface

```
ctl dev [target]      run the stack LOCALLY on the host (hot reload). target ∈ all|backend|frontend|<svc>
                      auto-ensures the data core (with ports) is up first. foreground; Ctrl-C/q stops.

ctl up [profile…] [--config=n…]   start container stack, detached
ctl up --help                     list discovered profiles + configs
ctl down [service]    stop the project (or named service)
ctl restart [service]
ctl ps                unified view: running containers + running local dev procs
ctl logs [service] [-f]

ctl status [service]  config doctor — project-custom body (see setup-command.md)
ctl setup             interactive .env / config.local.yaml wizard — project-custom body
ctl migrate {up|down|new|status}   alembic (lives here, not under dev)
ctl test [target]
ctl build             production image build
ctl clean             tear down + clear caches (asks first)
ctl help              print the contract
```

`ctl dev backend` (backend on the **host**, reloading) and `ctl up app` (backend **container**) differ by *where it runs* — `dev` = host, `up` = docker. `ctl help` and `ctl status` must spell the distinction out.

## Delegate — don't hand-roll a process manager

The dispatcher is **thin routing**. It must not grow into a 500-line supervisor (that fights the modularity caps in `references/architecture/modularity/`). It delegates:

- **Containers → `docker compose`.** `up`/`down`/`ps`/`logs`/`restart` are thin wrappers. `ctl up`'s only real logic is turning profiles + configs into a `--profile`/`-f`/`--env-file` argument list.
- **Local multi-process dev → a real runner, not bash PID juggling.** Default **`process-compose`** (declarative `process-compose.yaml`: per-process commands, `depends_on`, readiness probes, a TUI with per-service panes, `--detached` mode). Lighter alternative: **`mprocs`**. Zero-dep fallback: a bash `trap` killing backgrounded jobs — fine for 1–2 processes, replace with process-compose past that.
- **`status` / `setup` → project-custom subscripts** (`scripts/status.sh`, `scripts/setup.sh`). The *command surface* is uniform across every project; these two bodies are necessarily case-by-case (which env keys, which services). The dispatcher routes; the bodies vary.

## Skeleton

```bash
#!/usr/bin/env bash
# ctl — <PROJECT> control plane. Local dev + containers, one entrypoint.
set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; cd "$REPO_ROOT"
DOCKER_DIR="docker"; BASE="$DOCKER_DIR/compose.yaml"
DATA_SVCS=(postgres redis)               # the no-profile core ctl dev depends on

c_info(){ printf '\033[36m▸\033[0m %s\n' "$*"; }
c_warn(){ printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die(){    printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
  [[ -f .env ]] || { c_warn ".env missing — run \`ctl setup\` (or cp .env.example .env)."; exit 1; }
  set -a; source .env; set +a
}
require_tools() { for t in mise docker; do command -v "$t" >/dev/null || die "missing: $t"; done; }

# --- discovery: no hard-coded profile/config lists -------------------------
list_profiles() { grep -hoE 'profiles:[[:space:]]*\[[^]]+\]' "$BASE" \
                    | grep -oE '[A-Za-z0-9_-]+' | grep -vx profiles | sort -u; }
list_configs()  { for f in "$DOCKER_DIR"/compose.*.yaml; do b=${f##*/}; b=${b#compose.}; echo "${b%.yaml}"; done; }

# --- ctl up: profiles + --config overlays ----------------------------------
cmd_up() {
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { up_help; return; }
  require_env
  local profiles=() configs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config=*) configs+=("${1#--config=}"); shift ;;
      --config)   configs+=("$2"); shift 2 ;;
      -*)         die "unknown flag: $1 (try ctl up --help)" ;;
      *)          profiles+=("$1"); shift ;;
    esac
  done
  local files=("$BASE") prof_args=() env_args=()
  for c in "${configs[@]}"; do
    local cf="$DOCKER_DIR/compose.$c.yaml"
    [[ -f $cf ]] || die "no such config '$c'. configs: $(list_configs | tr '\n' ' ')"
    files+=("$cf")
    [[ $c == prod && -f .env.production ]] && env_args=(--env-file .env.production)
  done
  for p in "${profiles[@]}"; do
    list_profiles | grep -qx "$p" || die "no such profile '$p'. profiles: $(list_profiles | tr '\n' ' ')"
    prof_args+=(--profile "$p")
  done
  local cmd=(docker compose); for f in "${files[@]}"; do cmd+=(-f "$f"); done
  cmd+=("${prof_args[@]}" "${env_args[@]}" up -d)
  c_info "${cmd[*]}"; "${cmd[@]}"
}
up_help() {
  echo "ctl up [profile…] [--config=name…]"
  echo "  profiles (which services; combine freely):"; for p in $(list_profiles); do echo "    $p"; done
  echo "  configs (overlay how they run; stackable):"; for c in $(list_configs); do echo "    $c"; done
}

# --- other container wrappers ----------------------------------------------
cmd_down()  { docker compose -f "$BASE" down "$@"; }
cmd_ps()    { docker compose -f "$BASE" ps; process-compose process list 2>/dev/null || true; }
cmd_logs()  { docker compose -f "$BASE" logs "$@"; }

# --- the host dev launcher --------------------------------------------------
cmd_dev() {                       # local, host, hot reload
  require_env; require_tools
  c_info "ensuring data core (with ports)…"
  docker compose -f "$BASE" -f "$DOCKER_DIR/compose.expose.yaml" up -d "${DATA_SVCS[@]}"
  bash scripts/wait-for-health.sh "${DATA_SVCS[@]}" 60
  if command -v process-compose >/dev/null; then
    exec process-compose up "${@:+--names $*}"        # reads process-compose.yaml
  else
    bash scripts/dev-host.sh "$@"                      # bash trap fallback (1–2 procs)
  fi
}

# --- custom-body subcommands route to scripts -------------------------------
cmd_status()  { bash scripts/status.sh "$@"; }     # project-custom config doctor
cmd_setup()   { bash scripts/setup.sh "$@"; }      # project-custom .env wizard
cmd_migrate() { bash scripts/migrate.sh "$@"; }

cmd_help() { cat <<EOF
ctl — <PROJECT> control plane
  ctl dev [target]            run locally on the host (hot reload); data core auto-started
  ctl up [profile…] [--config=n…]  run container stack; ctl up --help for profiles+configs
  ctl down [svc]              stop container services
  ctl ps / logs [svc]         inspect containers + local procs
  ctl status [svc]            check config (.env, config.local.yaml, deps reachable)
  ctl setup                   interactive .env wizard
  ctl migrate {up|down|new|status}
  ctl test / build / clean / help
EOF
}

main() {
  case "${1:-help}" in
    dev)      shift; cmd_dev "$@" ;;
    up)       shift; cmd_up "$@" ;;
    down)     shift; cmd_down "$@" ;;
    restart)  shift; docker compose -f "$BASE" restart "$@" ;;
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

The skill drops this from `assets/snippets/scripts/dev-wrapper.sh` and adapts it. Profile/config discovery is a one-line `grep`/glob — convention over a YAML parser, deliberately. (The grep assumes the inline `profiles: [app]` form the snippet uses.)

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

`ctl dev backend` runs just that process; `ctl dev` runs all. `depends_on` plus the data-core auto-up in `cmd_dev` is exactly the "error if a required dep isn't there" behaviour — declare deps, let the runner enforce them.

## Dependency auto-up

`ctl dev` brings up the data core (with ports, so host apps can reach it) before starting host processes, and `process-compose`'s `depends_on` orders the host processes among themselves. So the everyday loop is one command — `ctl dev` — not "`ctl up` then start things by hand." If a declared dep can't be started, fail loudly with the fix, never start half a stack silently.

## Design rules

- **`ctl dev` is the most common path.** Optimise for "fresh clone → `ctl setup` → `ctl dev` → it works."
- **`ctl up` assembles, compose executes.** The only logic in `up` is turning profiles + configs into `--profile`/`-f`/`--env-file`, then echoing and running it. No reimplementing compose.
- **No silent failures.** Missing tool, unset var, healthcheck timeout, unknown profile/config → die with the fix.
- **No hard-coded profile/config lists.** Discover them so `--help` and reality never drift.
- **`status` and `setup` are the two custom bodies** — stable command name, project-specific logic. Everything else is largely uniform.
- **Self-documenting** — `ctl help` is the contract; `ctl up --help` is the discovered profile/config list.

## One dispatcher per repo

A single repo has **one** `ctl`. New need → a profile, a `compose.<config>.yaml`, or a subcommand — not a second wrapper. The one place two contracts exist is Layout 03 (polyrepo + aggregator): each child repo has its own `ctl`, and the aggregator repo has its own `ctl` whose `ctl up app edge --config=prod` deploys the merged stack. When `ctl` itself outgrows shell (structured state across runs, multi-node promotion), escalate it to a binary — see `references/repo-setup/complex-setups/orchestrator-escalation.md`.

## Anti-patterns

- A 500-line bash wrapper that reimplements a process manager — delegate to `process-compose`/`docker compose`.
- A `ctl prod` verb separate from `ctl up` — production is just profiles + `--config=prod`; two verbs for one lifecycle drift apart.
- Per-mode option files (`compose.dev.yaml`, `compose.db.yaml`) when a profile expresses it — `db`→`ctl up` (core), `app`→`--profile app`.
- Hand-managing local PIDs, pidfiles, and tmux sessions when `process-compose`/`mprocs` do it declaratively.
- Folding migrations into `ctl dev` — `dev` is the host loop only; migrations are `ctl migrate`.
- A hard-coded `case` of profile/config names instead of discovery — `--help` lies the moment someone adds a file.
- Subcommands that just alias `docker compose` syntax verbatim — `ctl up` exists to hide the flag soup, not mirror it.
- Silent fallbacks ("if docker isn't installed, try podman") — be explicit; ask the user to install the canonical tool.

## See also

- `references/repo-setup/docker/docker-compose-structure.md` — the profile/`--config` convention `ctl up` implements
- `references/repo-setup/scripts/dev-without-docker.md` — what `ctl dev` runs on the host and why
- `references/repo-setup/scripts/setup-command.md` — `ctl setup` / `ctl status` as project-custom subscripts
- `references/repo-setup/scripts/subscripts.md` — the `scripts/*.sh` the dispatcher calls
- `references/repo-setup/scripts/three-startup-paths.md` — `ctl` / raw compose / no-docker, documented in the README
- `references/repo-setup/complex-setups/orchestrator-escalation.md` — escalate `ctl` → a binary orchestrator
- `references/repo-setup/mise.md` — project-scoped PATH so `ctl` is callable bare
