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
  env       every \${VAR} in apps/*/config.yaml is a key in one of .env.{secrets,data,proxy}.template ·
            keys ending _PASSWORD / _KEY / _SECRET appear only in .env.secrets.template ·
            every .env.proxy.template key ends _HOST / _PORT / _PREFIX / _URL (or is PUBLIC_URL,
            HTTP_PORT, HTTPS_PORT, DEV_PROXY_PORT, COMPOSE_PROJECT_NAME) ·
            every .env.data.template key ends _DIR ·
            no .env.* tracked by git except *.template ·
            no secret literal in config.yaml (every *_KEY / *_PASSWORD / *_SECRET value is \${VAR}) ·
            no config.local.yaml tracked by git
  layout    no package.json / bun.lock / pnpm-workspace.yaml at the root, directly in apps/, or
            directly in apps/example-multi-web-app/ (the static group; each frontend is apps/example-multi-web-app/<name>/)
  brief     CLAUDE.md is exactly '@AGENTS.md'
  compose   no ports: in compose.base.yaml · no ../ in any docker/compose.*.yaml ·
            docker compose config validates: db alone, base alone, base + each modifier
  TODO      every key in the templates carries a comment naming its consumer"; }

is_help "${1:-}" && { usage; exit 0; }
rc=0; fail() { err "$*"; rc=1; }
LOG_INDENT="  "

step "env contract"
for cfg in apps/*/config.yaml; do
  [[ -f $cfg ]] || continue
  grep -nE '^\s*[a-z_]*(key|password|secret)[a-z_]*:\s*[^$ #]' "$cfg" | while IFS= read -r l; do fail "$cfg: secret literal — $l"; done
done
git ls-files --error-unmatch '*config.local.yaml' >/dev/null 2>&1 && fail "config.local.yaml is tracked by git"
# tracked env files: only the templates may be in git
while IFS= read -r f; do [[ $f == *.template ]] || fail "$f is tracked by git — only .env.*.template may be committed"
done < <(git ls-files '.env' '.env.*' 2>/dev/null)
# template roles
known=()
for f in "${ENV_FILES[@]}"; do
  [[ -f $f.template ]] || { fail "$f.template missing"; continue; }
  mapfile -t -O "${#known[@]}" known < <(env_keys "$f.template")
done
for f in .env.data.template .env.proxy.template; do
  [[ -f $f ]] || continue
  while IFS= read -r k; do [[ $k =~ _(PASSWORD|KEY|SECRET)$ ]] && fail "$f holds $k — secrets live only in .env.secrets.template"; done < <(env_keys "$f")
done
[[ -f .env.proxy.template ]] && while IFS= read -r k; do
  [[ $k =~ _(HOST|PORT|PREFIX|URL)$ || $k =~ ^(PUBLIC_URL|HTTP_PORT|HTTPS_PORT|DEV_PROXY_PORT|COMPOSE_PROJECT_NAME)$ ]] \
    || fail ".env.proxy.template: $k is not a routing key (_HOST/_PORT/_PREFIX/_URL)"
done < <(env_keys .env.proxy.template)
[[ -f .env.data.template ]] && while IFS= read -r k; do
  [[ $k =~ _DIR$ ]] || fail ".env.data.template: $k is not a path key (_DIR)"
done < <(env_keys .env.data.template)
if (( ${#known[@]} )); then
  for cfg in apps/*/config.yaml; do
    [[ -f $cfg ]] || continue
    while IFS= read -r v; do
      printf '%s\n' "${known[@]}" | grep -qx "$v" || fail "$cfg reads \${$v} — not in any .env.*.template"
    done < <(sed 's/#.*//' "$cfg" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | tr -d '${}' | sort -u)
  done
  ok "config.yaml \${VAR} keys ⊆ the env templates · template roles hold"
fi

step "layout"
for f in package.json bun.lock pnpm-workspace.yaml apps/package.json apps/bun.lock apps/pnpm-workspace.yaml \
         apps/example-multi-web-app/package.json apps/example-multi-web-app/bun.lock apps/example-multi-web-app/pnpm-workspace.yaml; do
  [[ -e $f ]] && fail "$f exists — no workspace at the root, in apps/ or in apps/example-multi-web-app/; each app owns its manifest"
done
ok "no root / apps/ / apps/example-multi-web-app/ manifests"

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

have_env=1; for f in "${ENV_FILES[@]}"; do [[ -f $f ]] || have_env=0; done
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && (( have_env )); then
  step "compose config (the three env files supply \${VAR})"
  combos=("$DB_FILE" "$DEV_FILE" "$BASE")
  while IFS= read -r m; do [[ -n $m ]] && combos+=("$BASE $DOCKER_DIR/compose.m.$m.yaml"); done < <(list_modifiers)
  for c in "${combos[@]}"; do
    args=(); for f in $c; do args+=(-f "$f"); done
    if out=$(compose_cmd "${args[@]}" config -q 2>&1); then ok "$c"
    else fail "$c — $out"; fi
  done
else
  warn "docker or .env.{secrets,data,proxy} unavailable — compose validation skipped"
fi

LOG_INDENT=""; hr
(( rc == 0 )) && ok "check green" || err "check red — fix the lines above"
exit $rc
