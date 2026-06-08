#!/usr/bin/env bash
# dev/host.sh — `ctl dev`. Ensure the data core (if any), then run apps on the host with hot reload.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] the host command per target — the ONE source for --help, --dry-run, and the run.
# Emitted as a string so help/dry-run print EXACTLY what runs (ports resolve from .env once loaded).
backend_cmd()  { printf 'cd apps/backend && uv run uvicorn %s:app --reload --host %s --port %s' \
                   "${BACKEND_MODULE:-app.main}" "${PYTHON_HOST:-0.0.0.0}" "${PYTHON_PORT:-8000}"; }
frontend_cmd() { printf 'cd apps/frontend && bun dev'; }

usage() { print_help "dev" "Run apps on the host with hot reload; auto-starts the data core." \
  'dev [all|backend|frontend] [--dry-run] [-h]' \
"Arguments
  all (default)   backend + frontend together — Ctrl-C stops both
  backend         backend API server only (hot reload)
  frontend        frontend dev server only

Direct  (the host command each runs — what --dry-run prints; copy to run without ctl)
  backend         ${C_GRN}$(backend_cmd)${C_RESET}
  frontend        ${C_GRN}$(frontend_cmd)${C_RESET}

Options
  --dry-run, -n   print the data-core bring-up + the host commands, don't run them
  -h, --help      show this help

With a data core (DATA_SVCS set) it first brings those up in containers (with ports, via the
expose_data modifier) and waits for health, then runs the host processes. If process-compose.yaml
exists it hands off to process-compose instead of the bash fallback."; }

# parse: one positional target + flags
target=all dry=0
while (( $# )); do case "$1" in
  -h|--help)            usage; exit 0 ;;
  --dry-run|-n)         dry=1; shift ;;
  all|backend|frontend) target="$1"; shift ;;
  *)                    die "target ∈ all|backend|frontend (got '$1'); see ctl dev --help" ;;
esac; done

require_env

# --dry-run: print what would run, then exit (nothing started, no tools required)
if (( dry )); then
  step "(dry-run — nothing started)"
  (( ${#DATA_SVCS[@]} )) && say "data core   dc -f $DOCKER_DIR/compose.m.expose_data.yaml up -d ${DATA_SVCS[*]}"
  [[ $target == all || $target == backend  ]] && say "backend     $(backend_cmd)"
  [[ $target == all || $target == frontend ]] && say "frontend    $(frontend_cmd)"
  exit 0
fi

require_tools mise

# data core (skipped cleanly when DATA_SVCS is empty — no-data-core projects)
if (( ${#DATA_SVCS[@]} )); then
  require_tools docker
  step "ensuring data core (with ports)…"
  dc -f "$DOCKER_DIR/compose.m.expose_data.yaml" up -d "${DATA_SVCS[@]}"
  wait_healthy "${DATA_SVCS[@]}" 60 || warn "health poll failed — continuing anyway."
fi

if command -v process-compose >/dev/null 2>&1 && [[ -f process-compose.yaml ]]; then
  [[ $target == all ]] && exec process-compose up || exec process-compose up "$target"
fi

step "starting host processes — Ctrl-C stops all"
prefix() { local t="$1" c="$2"; while IFS= read -r l; do printf '%s[%s]%s %s\n' "$c" "$t" "$C_RESET" "$l"; done; }
pids=()
[[ $target == all || $target == backend  ]] && { ( bash -c "$(backend_cmd)"  2>&1 | prefix "backend " "$C_YEL" ) & pids+=($!); }
[[ $target == all || $target == frontend ]] && { ( bash -c "$(frontend_cmd)" 2>&1 | prefix "frontend" "$C_CYN" ) & pids+=($!); }
trap 'kill "${pids[@]}" 2>/dev/null || true; wait || true; exit 0' INT TERM
wait
