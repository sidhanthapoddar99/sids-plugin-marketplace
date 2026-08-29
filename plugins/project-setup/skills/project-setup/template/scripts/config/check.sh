#!/usr/bin/env bash
# config/check.sh — `ctl check`. Conformance floor: the rules the layout and env contract impose.
# Read-only. Prints every failure, exits non-zero if any. Runs as a gate rung (test/gate.sh).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "check" "Conformance floor — layout, env contract, compose validity." \
  'check [-h]' \
"Options
  -h, --help      show this help

Rules
  env       every \${VAR} in apps/*/config.yaml is a key in .env.example
  layout    no package.json / bun.lock / pnpm-workspace.yaml at the root or directly in apps/
  brief     CLAUDE.md is exactly '@AGENTS.md'
  compose   no ports: in compose.base.yaml · no ../ in any docker/compose.*.yaml ·
            docker compose config validates: db alone, base alone, base + each modifier
  TODO      every key in .env.example carries a comment naming its consumer"; }

is_help "${1:-}" && { usage; exit 0; }
rc=0; fail() { err "$*"; rc=1; }
LOG_INDENT="  "

step "env contract"
if [[ -f .env.example ]]; then
  mapfile -t known < <(env_keys .env.example)
  for cfg in apps/*/config.yaml; do
    [[ -f $cfg ]] || continue
    while IFS= read -r v; do
      printf '%s\n' "${known[@]}" | grep -qx "$v" || fail "$cfg reads \${$v} — not in .env.example"
    done < <(sed 's/#.*//' "$cfg" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | tr -d '${}' | sort -u)
  done
  ok "config.yaml \${VAR} keys ⊆ .env.example"
else fail "no .env.example"; fi

step "layout"
for f in package.json bun.lock pnpm-workspace.yaml apps/package.json apps/bun.lock apps/pnpm-workspace.yaml; do
  [[ -e $f ]] && fail "$f exists — no workspace at the root or in apps/; each app owns its manifest"
done
ok "no root manifests"

step "brief"
if [[ -f CLAUDE.md ]]; then
  [[ "$(tr -d '[:space:]' < CLAUDE.md)" == "@AGENTS.md" ]] || fail "CLAUDE.md must be exactly '@AGENTS.md'"
  [[ -f AGENTS.md ]] || fail "AGENTS.md missing"
  ok "CLAUDE.md → AGENTS.md"
else fail "CLAUDE.md missing"; fi

step "compose files"
if grep -qE '^\s+ports:' "$BASE" 2>/dev/null; then fail "$BASE publishes ports — exposure belongs in a modifier"; fi
for f in "$DOCKER_DIR"/compose.*.yaml; do
  [[ -e $f ]] || continue
  grep -q '\.\./' "$f" && fail "$f uses ../ — paths are root-relative (--project-directory)"
done
ok "base has no ports · no ../ paths"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && [[ -f .env ]]; then
  step "compose config (needs .env for \${VAR})"
  load_env_file .env
  combos=("$DB_FILE" "$BASE")
  while IFS= read -r m; do [[ -n $m ]] && combos+=("$BASE $DOCKER_DIR/compose.m.$m.yaml"); done < <(list_modifiers)
  for c in "${combos[@]}"; do
    args=(); for f in $c; do args+=(-f "$f"); done
    if out=$(docker compose --project-directory "$CTL_ROOT" "${args[@]}" config -q 2>&1); then ok "$c"
    else fail "$c — $out"; fi
  done
else
  warn "docker or .env unavailable — compose validation skipped"
fi

LOG_INDENT=""; hr
(( rc == 0 )) && ok "check green" || err "check red — fix the lines above"
exit $rc
