#!/usr/bin/env bash
# config/status.sh — `ctl status`. Config doctor: env schema, toolchain, docker, deps, data-core
# health, and the discovered modifiers. Read-only — never dies on a missing env file (diagnosing
# that is the point); reports issues and exits non-zero.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "status" "Config doctor: env, toolchain, docker, deps, data core, stack." \
  'status [-h]' \
"Options
  -h, --help      show this help" \
"Read-only. Fix installs with \`ctl setup\`; fix rule breaches with \`ctl check\`."; }

is_help "${1:-}" && { usage; exit 0; }
load_env_soft         # soft, non-clobbering load of the three env files — status must never die
rc=0
LOG_INDENT="  "       # nest every section's lines under its ▸ header

step "env files"
for f in "${ENV_FILES[@]}"; do
  if [[ -f $f ]]; then ok "$f present"; else warn "$f missing (ctl setup copies $f.template)"; rc=1; fi
done
check_env_schema || rc=1

step "runtimes"
if command -v mise >/dev/null 2>&1; then
  ok "mise — $(tool_version mise)"
  mise current 2>/dev/null | sed "s/^/    /" || true
else
  err "mise — missing (install mise, then \`mise install\`)"; rc=1
fi
for t in uv bun cargo go uvenv; do                        # stack-dependent — informational
  if command -v "$t" >/dev/null 2>&1; then ok "$t — $(tool_version "$t")"
  else printf '  %s%s — not installed%s\n' "$C_DIM" "$t" "$C_RESET"; fi
done

step "docker"
case "$(docker_state)" in
  ok)         ok "engine running — compose $(docker compose version --short 2>/dev/null || echo '?')" ;;
  missing)    warn "docker not installed (needed for ctl dev/up/build/health)" ;;
  stopped)    warn "docker installed but the engine is not running — start it (systemctl start docker · Docker Desktop)" ;;
  no-compose) warn "docker compose plugin missing (docker-compose-plugin ≥ 2.24)" ;;
esac
printf '  %s%-9s%s %s\n' "$C_DIM" "project"  "$C_RESET" "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}"
printf '  %s%-9s%s %s\n' "$C_DIM" "data dir" "$C_RESET" "${DATA_DIR:-./data}"
printf '  %s%-9s%s %s\n' "$C_DIM" "logs dir" "$C_RESET" "${LOGS_DIR:-./logs}"

step "deps (run \`ctl setup\` if missing)"
for d in apps/*/ apps/packages/*/ apps/database/postgres/; do
  n="${d#apps/}"; n="${n%/}"
  [[ -f "$d/pyproject.toml" ]] && { [[ -d "$d/.venv" ]]         && ok "$n .venv"         || warn "$n .venv missing"; }
  [[ -f "$d/package.json" ]]   && { [[ -d "$d/node_modules" ]]  && ok "$n node_modules"  || warn "$n node_modules missing"; }
  [[ -f "$d/Cargo.toml" ]]     && { [[ -d "$d/target" ]]        && ok "$n target/"       || warn "$n not built yet (cargo build)"; }
done

step "data core"
if (( ${#DATA_SVCS[@]} )); then
  if [[ "$(docker_state)" == ok ]]; then health_table "${DATA_SVCS[@]}"
  else say "${C_DIM}docker not available (see above)${C_RESET}"; fi
else say "${C_DIM}none (DATA_SVCS empty)${C_RESET}"; fi

step "stack (what \`ctl up\` can assemble)"
printf '  %-11s %s\n' "base"      "$BASE  (includes $DB_FILE)"
printf '  %-11s %s\n' "modifiers" "$(list_modifiers | sed 's/^/+/' | join_sp | or_none)"

LOG_INDENT=""; hr
(( rc == 0 )) && ok "ready" || warn "issues above — fix and re-run"
exit $rc
