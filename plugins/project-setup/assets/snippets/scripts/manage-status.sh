#!/usr/bin/env bash
# manage-status.sh — `ctl status`. Config doctor: env schema, toolchain, docker, deps,
# data-core health, and the discovered stack (configs + modifiers). Read-only — never dies
# on a missing .env (diagnosing that is the point); reports issues and exits non-zero.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "status" "Config doctor: env, toolchain (mise/uv/bun/uvenv), docker, deps, stack, health." \
  'status [-h]' \
"Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
[[ -f .env ]] && { set -a; source .env; set +a; }    # soft load — status must never die
rc=0

# Nest every section's result lines (ok/warn/say + check_env_schema's) two spaces under their
# ▸ header for a consistent hierarchy; reset to col 0 for the closing summary.
LOG_INDENT="  "

step "env"
check_env_schema || rc=1

step "runtimes"
if command -v mise >/dev/null 2>&1; then
  ok "mise — $(tool_version mise)"
  mise current 2>/dev/null | sed "s/^/    /" || true        # the toolchain .mise.toml pins
else
  err "mise — missing (install mise, then \`mise install\`)"; rc=1
fi
for t in uv bun uvenv; do                                   # stack-dependent — informational, not required
  if command -v "$t" >/dev/null 2>&1; then ok "$t — $(tool_version "$t")"
  else printf '  %s%s — not installed%s\n' "$C_DIM" "$t" "$C_RESET"; fi
done

step "docker"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "daemon reachable — compose $(docker compose version --short 2>/dev/null || echo '?')"
else
  warn "daemon not reachable (needed for ctl up/build/health)"
fi
printf '  %s%-9s%s %s\n' "$C_DIM" "project"  "$C_RESET" "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}"
printf '  %s%-9s%s %s\n' "$C_DIM" "data dir" "$C_RESET" "${DATA_DIR:-./data}"

step "deps (run \`ctl setup\` if missing)"
[[ -d apps/backend ]]  && { [[ -d apps/backend/.venv ]]         && ok "backend .venv"        || warn "backend .venv missing"; }
[[ -d apps/frontend ]] && { [[ -d apps/frontend/node_modules ]] && ok "frontend node_modules" || warn "frontend node_modules missing"; }

if (( ${#DATA_SVCS[@]} )); then
  step "data core"
  health_table "${DATA_SVCS[@]}"
else
  step "data core"; say "${C_DIM}none (DATA_SVCS empty)${C_RESET}"
fi

step "stack (what \`ctl up\` can assemble)"
printf '  %-11s %s\n' "configs"   "$(list_configs   | join_sp | or_none)"
printf '  %-11s %s\n' "modifiers" "$(list_modifiers | sed 's/^/--modifier /' | join_sp | or_none)"

LOG_INDENT=""    # closing verdict sits at column 0, level with the section headers
hr
(( rc == 0 )) && ok "ready" || warn "issues above — fix and re-run"
exit $rc
