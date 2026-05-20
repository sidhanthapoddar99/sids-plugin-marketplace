#!/usr/bin/env bash
# ./dev — <PROJECT> developer entry point.
#
# Bare ./dev runs the first-run / day-to-day flow.
# Subcommands wrap day-to-day operations.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── helpers ───────────────────────────────────────────────

c_dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
c_info()  { printf '\033[36m▸\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
c_err()   { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }
die()     { c_err "$*"; exit 1; }

require_env() {
  if [[ ! -f .env ]]; then
    if [[ -f .env.example ]]; then
      c_warn ".env not found — copying from .env.example."
      c_warn "Fill REQUIRED blanks, then re-run."
      cp .env.example .env
      exit 1
    fi
    die ".env is missing and no .env.example exists."
  fi
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
}

require_tools() {
  local missing=()
  for t in mise docker; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  (( ${#missing[@]} > 0 )) && die "Missing tools on PATH: ${missing[*]}. Install mise (https://mise.jdx.dev), then \`mise install\`."
}

# ── subcommands ───────────────────────────────────────────

cmd_help() {
  cat <<EOF
./dev — <PROJECT> developer entry point.

Usage:
  ./dev                              full first-run / dev flow
  ./dev migrate {up|down|new "<msg>"|status}
  ./dev test                         run all test suites
  ./dev build                        production build
  ./dev clean                        docker compose down -v + clear caches (asks first)
  ./dev help                         print this contract
EOF
}

cmd_migrate() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    new)
      local msg="${1:-}"
      [[ -z "$msg" ]] && die "usage: ./dev migrate new \"<message>\""
      ( cd apps/backend && uv run alembic revision -m "$msg" )
      ;;
    up)     ( cd apps/backend && uv run alembic upgrade head ) ;;
    down)   ( cd apps/backend && uv run alembic downgrade -1 ) ;;
    status) ( cd apps/backend && uv run alembic current ) ;;
    *)      die "unknown migrate subcommand: ${sub:-<none>}. Try ./dev help" ;;
  esac
}

cmd_test() {
  c_info "Running backend tests…"
  ( cd apps/backend && uv run pytest ) || true
  c_info "Running frontend tests…"
  ( cd apps/frontend && bun test ) || true
}

cmd_build() {
  c_info "Building frontend…"
  ( cd apps/frontend && bun run build )
  c_info "Building backend image…"
  docker build -t "${COMPOSE_PROJECT_NAME:-myapp}-backend:dev" apps/backend
}

cmd_clean() {
  cat <<EOF >&2
This will:
  • docker compose down -v   (drops postgres + redis data volumes)
  • rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
  • find . -name __pycache__ -prune -exec rm -rf {} +
EOF
  read -r -p "Continue? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || { c_warn "aborted."; exit 0; }
  docker compose -f docker/compose.yaml down -v 2>/dev/null || true
  rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
  find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
  c_ok "clean."
}

# ── bare flow ─────────────────────────────────────────────

cmd_bare() {
  c_info "<PROJECT> dev — first-run flow"
  require_env
  require_tools

  c_info "Ensuring data dirs exist…"
  mkdir -p data/postgres/pgdata data/redis/data

  c_info "Bringing up postgres + redis…"
  docker compose -f docker/compose.database-only.yaml up -d
  bash scripts/wait-for-health.sh postgres redis 60 2>/dev/null || \
    c_warn "wait-for-health.sh missing — skipping healthcheck poll."

  if [[ ! -d apps/frontend/node_modules ]]; then
    c_info "Installing frontend deps (bun install)…"
    ( cd apps/frontend && bun install )
  fi

  c_info "Syncing python deps (uv sync)…"
  ( cd apps/backend && uv sync )

  c_info "Applying migrations…"
  ( cd apps/backend && uv run alembic upgrade head )

  c_info "Starting backend + frontend on host. Ctrl-C kills all."

  prefix() {
    local tag="$1" color="$2"
    while IFS= read -r line; do
      printf '\033[%sm[%s]\033[0m %s\n' "$color" "$tag" "$line"
    done
  }

  ( cd apps/backend && uv run uvicorn "${BACKEND_MODULE:-app.main}":app --reload \
      --host "${PYTHON_HOST:-0.0.0.0}" --port "${PYTHON_PORT:-8000}" 2>&1 \
      | prefix "backend " "33" ) &
  local be_pid=$!

  ( cd apps/frontend && bun dev 2>&1 | prefix "frontend" "36" ) &
  local fe_pid=$!

  trap 'kill "$be_pid" "$fe_pid" 2>/dev/null || true; wait || true; exit 0' INT TERM
  wait
}

# ── dispatch ──────────────────────────────────────────────

main() {
  local cmd="${1:-}"
  case "$cmd" in
    "")               cmd_bare ;;
    migrate)          shift; cmd_migrate "$@" ;;
    test)             cmd_test ;;
    build)            cmd_build ;;
    clean)            cmd_clean ;;
    help|-h|--help)   cmd_help ;;
    *)                die "unknown command: $cmd. Try ./dev help" ;;
  esac
}

main "$@"
