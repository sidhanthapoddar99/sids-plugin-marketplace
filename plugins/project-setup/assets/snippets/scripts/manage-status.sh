#!/usr/bin/env bash
# manage-status.sh — `ctl status`. Config doctor: env schema, toolchain, docker, health, the stack.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "status" "Config doctor: .env schema, toolchain (mise/uv/bun/uvenv), docker, health, stack." \
  'status [-h]' \
"Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
[[ -f .env ]] && { set -a; source .env; set +a; }
rc=0

step "env"
check_env_schema || rc=1

step "runtimes"
if command -v mise >/dev/null 2>&1; then
  ok "mise — $(tool_version mise)"
  mise current 2>/dev/null | sed 's/^/    /' || true        # the toolchain .mise.toml pins
else
  err "mise — missing (install mise, then \`mise install\`)"; rc=1
fi
for t in uv bun uvenv; do                                    # stack-dependent — informational, not required
  if command -v "$t" >/dev/null 2>&1; then ok "$t — $(tool_version "$t")"
  else printf '  %s%s — not installed%s\n' "$C_DIM" "$t" "$C_RESET"; fi
done

step "docker"
if docker info >/dev/null 2>&1; then
  ok "daemon reachable — compose $(docker compose version --short 2>/dev/null || echo '?')"
else
  err "daemon not reachable — is Docker running?"; rc=1
fi
printf '  %s%-9s%s %s\n' "$C_DIM" "project"  "$C_RESET" "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}"
printf '  %s%-9s%s %s\n' "$C_DIM" "data dir" "$C_RESET" "${DATA_DIR:-./data}"

step "deps (run \`ctl setup\` if missing)"
[[ -d apps/backend ]]  && { [[ -d apps/backend/.venv ]]         && ok "backend .venv"        || warn "backend .venv missing"; }
[[ -d apps/frontend ]] && { [[ -d apps/frontend/node_modules ]] && ok "frontend node_modules" || warn "frontend node_modules missing"; }

step "data core"
health_table "${DATA_SVCS[@]}"

step "stack (what \`ctl up\` can assemble)"
printf '  %-11s %s\n' "profiles"  "$(list_profiles  | join_sp)"
printf '  %-11s %s\n' "configs"   "$(list_configs   | sed 's/^/--config=/' | join_sp)"
printf '  %-11s %s\n' "modifiers" "$(list_modifiers | sed 's/^/--/'        | join_sp)"

hr
(( rc == 0 )) && ok "ready" || warn "issues above — fix and re-run"
exit $rc
