#!/usr/bin/env bash
# ctl — <PROJECT> control plane.  Drop at repo root as `ctl` (no extension), chmod +x.
#
#   ctl dev [target]   run locally on the host (hot reload); data deps auto-started
#   ctl prod           run the full stack in docker (prod overlay + traefik)
#   ctl up/down [svc]   start/stop container services (bare = data services)
#   ctl ps | logs | restart | status | setup | migrate | test | build | clean | help
#
# dev = host loop; prod = full docker; up/down = granular containers.  Migrations are `ctl migrate`.
# Local multi-process dev delegates to process-compose if present (else a bash trap fallback).

set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── helpers ───────────────────────────────────────────────
c_info()  { printf '\033[36m▸\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()     { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

DATA_SVCS=(postgres redis)               # container services dev depends on
compose() { docker compose -f docker/compose.yaml "$@"; }

require_env() {
  [[ -f .env ]] || die ".env missing — run \`ctl setup\` (or cp .env.example .env)."
  set -a; # shellcheck disable=SC1091
  source .env; set +a
}
require_tools() {
  local missing=()
  for t in mise docker; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} )) && die "missing on PATH: ${missing[*]} — install mise then \`mise install\`."
}

# ── container lifecycle (thin wrappers over docker compose) ─
cmd_up() {
  require_env
  if [[ $# -eq 0 ]]; then compose up -d "${DATA_SVCS[@]}"; else compose up -d "$@"; fi
}
cmd_down()    { compose down "$@"; }
cmd_restart() { compose restart "$@"; }
cmd_logs()    { compose logs "$@"; }
cmd_ps() {
  compose ps
  command -v process-compose >/dev/null 2>&1 && process-compose process list 2>/dev/null || true
}

# ── the two stack launchers ───────────────────────────────
cmd_dev() {                              # local, host, hot reload
  require_env; require_tools
  c_info "ensuring data services…"
  cmd_up "${DATA_SVCS[@]}"
  bash scripts/wait-for-health.sh "${DATA_SVCS[@]}" 60 2>/dev/null || \
    c_warn "wait-for-health.sh missing — skipping healthcheck poll."
  if command -v process-compose >/dev/null 2>&1 && [[ -f process-compose.yaml ]]; then
    exec process-compose up "$@"
  fi
  # ── bash fallback: fine for 1–2 processes; prefer process-compose past that ──
  c_info "starting services on host. Ctrl-C kills all."
  prefix() { local tag="$1" c="$2"; while IFS= read -r l; do printf '\033[%sm[%s]\033[0m %s\n' "$c" "$tag" "$l"; done; }
  ( cd apps/backend && uv run uvicorn "${BACKEND_MODULE:-app.main}":app --reload \
      --host "${PYTHON_HOST:-0.0.0.0}" --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " 33 ) & be=$!
  ( cd apps/frontend && bun dev 2>&1 | prefix "frontend" 36 ) & fe=$!
  trap 'kill "$be" "$fe" 2>/dev/null || true; wait || true; exit 0' INT TERM
  wait
}

cmd_prod() {                             # full docker, prod overlay
  require_env
  docker compose -f docker/compose.yaml -f docker/compose.prod.yaml -f docker/compose.traefik.yaml \
    --env-file .env.production up -d
}

# ── custom-body subcommands route to scripts/ ─────────────
cmd_status() {
  if [[ -x scripts/status.sh ]]; then bash scripts/status.sh "$@";
  else c_warn "scripts/status.sh not present — add a project config doctor."; fi
}
cmd_setup() {
  if [[ -x scripts/setup.sh ]]; then bash scripts/setup.sh "$@";
  else [[ -f .env ]] || cp .env.example .env; c_warn "Fill REQUIRED blanks in .env, then \`ctl dev\`."; fi
}

cmd_migrate() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    new)    [[ -n "${1:-}" ]] || die "usage: ctl migrate new \"<message>\""
            ( cd apps/backend && uv run alembic revision -m "$1" ) ;;
    up)     ( cd apps/backend && uv run alembic upgrade head ) ;;
    down)   ( cd apps/backend && uv run alembic downgrade -1 ) ;;
    status) ( cd apps/backend && uv run alembic current ) ;;
    *)      die "unknown migrate subcommand: ${sub:-<none>}. Try ctl help" ;;
  esac
}

cmd_test() {
  c_info "backend tests…";  ( cd apps/backend && uv run pytest ) || true
  c_info "frontend tests…"; ( cd apps/frontend && bun test ) || true
}
cmd_build() {
  c_info "building frontend…"; ( cd apps/frontend && bun run build )
  c_info "building backend image…"; docker build -t "${COMPOSE_PROJECT_NAME:-myapp}-backend:dev" apps/backend
}
cmd_clean() {
  cat <<EOF >&2
This will: compose down -v (drops data volumes), rm node_modules/dist/.vite, clear __pycache__.
EOF
  read -r -p "Continue? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || { c_warn "aborted."; exit 0; }
  compose down -v 2>/dev/null || true
  rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
  find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
  c_ok "clean."
}

cmd_help() {
  cat <<EOF
ctl — <PROJECT> control plane
  ctl dev [target]     run locally on the host (hot reload); data deps auto-started
  ctl prod             run the full stack in docker (prod overlay + traefik)
  ctl up/down [svc]    start/stop container services (bare = ${DATA_SVCS[*]})
  ctl ps               containers + local procs
  ctl logs [svc] [-f]  service logs
  ctl status [svc]     check config (.env, config.local.yaml, deps reachable)
  ctl setup            interactive .env wizard
  ctl migrate {up|down|new "<msg>"|status}
  ctl test | build | clean | help
EOF
}

# ── dispatch ──────────────────────────────────────────────
main() {
  case "${1:-help}" in
    dev)            shift; cmd_dev "$@" ;;
    prod)           cmd_prod ;;
    up)             shift; cmd_up "$@" ;;
    down)           shift; cmd_down "$@" ;;
    restart)        shift; cmd_restart "$@" ;;
    ps)             cmd_ps ;;
    logs)           shift; cmd_logs "$@" ;;
    status)         shift; cmd_status "$@" ;;
    setup)          cmd_setup ;;
    migrate)        shift; cmd_migrate "$@" ;;
    test)           cmd_test ;;
    build)          cmd_build ;;
    clean)          cmd_clean ;;
    help|-h|--help) cmd_help ;;
    *)              die "unknown command: $1. Try ctl help" ;;
  esac
}
main "$@"
