# `./dev` — the global wrapper dispatcher

One executable at repo root. Single entrypoint. Dispatches to subcommands and to subscripts. Setup folds in. The user-facing API for the project.

## Contract

- Always executable, always at `./dev` (no `.sh` extension)
- `./dev` (bare) — first-run / day-to-day default flow
- `./dev <subcommand> [args]` — specific operation
- `./dev help` — print the contract
- Always sourced from `set -euo pipefail` for safety
- Sources `.env` after verifying it exists (and copies from `.env.example` if missing, then exits with instructions)

## Skeleton

```bash
#!/usr/bin/env bash
# ./dev — <PROJECT> developer entry point.
#
# Bare ./dev runs the full first-run / dev flow.
# Subcommands wrap day-to-day flows.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ---------- helpers --------------------------------------------------------

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
      c_warn "Edit .env to fill in REQUIRED blanks, then re-run."
      cp .env.example .env
      exit 1
    fi
    die ".env is missing and no .env.example exists."
  fi
  set -a
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

# ---------- subcommands ----------------------------------------------------

cmd_help() {
  cat <<EOF
./dev — <PROJECT> developer entry point.

Usage:
  ./dev                           full first-run flow (compose up DBs, install deps, migrate, start services)
  ./dev migrate {up|down|new}     alembic operations
  ./dev test                      run all test suites
  ./dev build                     production build (frontend + backend)
  ./dev clean                     docker compose down -v + clear caches (asks first)
  ./dev help                      print this contract

EOF
}

cmd_migrate() { bash scripts/migrate.sh "$@"; }
cmd_test()    { bash scripts/test.sh "$@"; }
cmd_build()   { bash scripts/build.sh "$@"; }

cmd_clean() {
  cat <<EOF >&2
This will:
  • docker compose down -v   (drops postgres + redis data volumes)
  • rm -rf node_modules dist .vite
  • find . -name __pycache__ -prune -exec rm -rf {} +

EOF
  read -r -p "Continue? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || { c_warn "aborted."; exit 0; }
  docker compose -f docker/compose.yaml down -v || true
  rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
  find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
  c_ok "clean."
}

# ---------- bare flow ------------------------------------------------------

cmd_bare() {
  c_info "<PROJECT> dev — first-run flow"
  require_env
  require_tools

  c_info "Ensuring data dirs exist…"
  mkdir -p data/postgres/pgdata data/redis/data

  c_info "Bringing up postgres + redis…"
  docker compose -f docker/compose.database-only.yaml up -d
  bash scripts/wait-for-health.sh postgres redis

  c_info "Installing/syncing deps…"
  ( cd apps/backend && uv sync )
  ( cd apps/frontend && bun install )

  c_info "Applying migrations…"
  ( cd apps/backend && uv run alembic upgrade head )

  c_info "Starting backend + frontend on host. Ctrl-C kills all."
  prefix() { local tag="$1" color="$2"; while IFS= read -r line; do printf '\033[%sm[%s]\033[0m %s\n' "$color" "$tag" "$line"; done; }

  ( cd apps/backend && uv run uvicorn ${BACKEND_MODULE:-app.main}:app --reload \
      --host "${PYTHON_HOST:-0.0.0.0}" --port "${PYTHON_PORT:-8000}" 2>&1 | prefix "backend " "33" ) &
  local be_pid=$!

  ( cd apps/frontend && bun dev 2>&1 | prefix "frontend" "36" ) &
  local fe_pid=$!

  trap 'kill "$be_pid" "$fe_pid" 2>/dev/null || true; wait || true; exit 0' INT TERM
  wait
}

# ---------- dispatch -------------------------------------------------------

main() {
  local cmd="${1:-}"
  case "$cmd" in
    "")              cmd_bare ;;
    migrate)         shift; cmd_migrate "$@" ;;
    test)            shift; cmd_test "$@" ;;
    build)           shift; cmd_build "$@" ;;
    clean)           cmd_clean ;;
    help|-h|--help)  cmd_help ;;
    *)               die "unknown command: $cmd. Try ./dev help" ;;
  esac
}

main "$@"
```

The skill drops this skeleton from `assets/snippets/dev-wrapper.sh` and adapts it to the topology.

## Design rules

- **Bare invocation is the most common path**. Optimise for "fresh clone, ./dev, things work."
- **No silent failures.** If a tool is missing, an env var is unset, or a healthcheck times out — die loudly with the fix.
- **Coloured output** but minimal. Don't make the wrapper a spectacle.
- **Subcommands are thin** — they delegate to `scripts/<name>.sh` for anything non-trivial. The wrapper is dispatch, the scripts are logic.
- **Self-documenting** — `./dev help` is the contract.

## When to split into multiple wrappers

A single repo should have **one** wrapper. If your repo grows two distinct user populations (e.g. developers and operators), prefer subcommands over a second wrapper. Two wrappers means two contracts to remember.

The single exception is Topology 06 (polyrepo + aggregator) where the aggregator gets its own `./deploy` distinct from each child repo's `./dev`. Different repos, different contracts.

## Anti-patterns

- 500-line monolithic wrappers — split logic into `scripts/<name>.sh`
- Subcommands that duplicate `docker compose` syntax — the wrapper exists to hide that
- Adding new subcommands proactively for hypothetical needs — wait for the pain
- Silent fallbacks ("if docker isn't installed, try podman") — be explicit; ask the user to install the canonical tool
