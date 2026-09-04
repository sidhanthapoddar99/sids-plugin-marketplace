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
  versions  no '<version>' placeholder left in .mise.toml or any app manifest (pyproject.toml,
            package.json, Cargo.toml, rust-toolchain.toml, go.mod) — a placeholder breaks every
            toolchain install, so it is resolved with the user before anything runs
  env       every \${VAR} in apps/*/config.yaml is a key in one of .env.{secrets,data,proxy}.template ·
            a key with a _PASSWORD / _KEY / _SECRET segment appears only in .env.secrets.template ·
            every .env.proxy.template key ends _HOST / _PORT / _PREFIX / _URL (or is PUBLIC_URL,
            HTTP_PORT, HTTPS_PORT, DEV_PROXY_PORT, COMPOSE_PROJECT_NAME) ·
            every .env.data.template key ends _DIR ·
            no .env.* tracked by git except *.template ·
            no secret literal in config.yaml (every key/password/secret value is \${VAR}) ·
            no config.local.yaml tracked by git
  layout    no package.json / bun.lock / pnpm-workspace.yaml at the root or directly in apps/ ·
            no folder under apps/ that holds a manifest and child folders with manifests (a group
            folder such as a static-frontend group or packages/ is not a workspace) ·
            the root rule is skipped when AGENTS.md records 'root-manifest' under
            '## Exceptions to the standard layout' (an open-source package repo)
  brief     CLAUDE.md is exactly '@AGENTS.md'
  compose   no ports: in compose.base.yaml · no ../ in any docker/compose.*.yaml ·
            docker compose config validates: db alone, dev alone, base alone, base + each modifier

Every rule runs; nothing stops at the first failure. Exit 0 only when every rule passed.
"; }

is_help "${1:-}" && { usage; exit 0; }
# rc is the whole run; sf is the current step. fail() marks both. pass() prints the step's ok line
# only when nothing in that step failed, so an ok line is never printed under a failure.
rc=0; sf=0
fail() { err "$*"; rc=1; sf=1; }
pass() { (( sf )) || ok "$*"; }
step() { sf=0; printf '%s▸%s %s\n' "$C_CYN" "$C_RESET" "$*"; }
LOG_INDENT="  "

step "versions"
# Every file here holds a '<version>' placeholder in the shipped template. A placeholder in
# .mise.toml or a manifest makes mise, uv, cargo and go fail, so ctl setup refuses to run until
# each is resolved (with the user, never from memory).
while IFS= read -r f; do fail "$f still holds '<version>' — resolve it before setup"; done \
  < <({ grep -l --fixed-strings '<version>' .mise.toml 2>/dev/null; grep -rl --fixed-strings '<version>' apps --include=pyproject.toml --include=package.json \
        --include=Cargo.toml --include=rust-toolchain.toml --include=go.mod --exclude-dir=node_modules 2>/dev/null; } || true)
pass "no <version> placeholder in .mise.toml or an app manifest"

step "env contract"
# grep exits 1 when a file is clean. Read it through process substitution with `|| true`: a pipe
# into `while` would run fail() in a subshell (rc never set) and pipefail would kill the script
# on the clean case.
for cfg in apps/*/config.yaml; do
  [[ -f $cfg ]] || continue
  while IFS= read -r l; do fail "$cfg: secret literal — $l"; done \
    < <(grep -nE '^\s*[a-z_]*(key|password|secret)[a-z_]*:\s*[^$ #]' "$cfg" || true)
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
  while IFS= read -r k; do [[ $k =~ _(PASSWORD|KEY|SECRET)(_|$) ]] && fail "$f holds $k — secrets live only in .env.secrets.template"; done < <(env_keys "$f")
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
  pass "config.yaml \${VAR} keys ⊆ the env templates · template roles hold"
fi

step "layout"
# The root-manifest exception: an open-source package repo whose root IS the published artifact
# records `root-manifest` under "## Exceptions to the standard layout" in AGENTS.md. Only the
# root rule is skipped for it; apps/ and group folders keep the rule.
root_manifest_ok=0
if [[ -f AGENTS.md ]] && awk '/^## Exceptions to the standard layout/{f=1;next} /^## /{f=0} f' AGENTS.md | grep -q 'root-manifest'; then
  root_manifest_ok=1; say "root-manifest exception recorded in AGENTS.md — root manifest allowed"
fi
manifests=(package.json bun.lock pnpm-workspace.yaml)
if (( ! root_manifest_ok )); then
  for f in "${manifests[@]}"; do [[ -e $f ]] && fail "$f exists at the root — each app owns its manifest; record 'root-manifest' in AGENTS.md if this repo is the package"; done
fi
for f in "${manifests[@]}"; do [[ -e apps/$f ]] && fail "apps/$f exists — apps/ is a folder of apps, not a workspace"; done
# a group folder (a static-frontend group, apps/packages/) holds children that each own a manifest.
# A manifest in the group folder itself is a workspace, which the layout forbids.
for d in apps/*/; do
  d=${d%/}
  for f in "${manifests[@]}"; do
    [[ -e $d/$f ]] || continue
    if compgen -G "$d/*/package.json" >/dev/null; then fail "$d/$f exists next to child manifests — $d is a group folder, not a workspace"; fi
  done
done
pass "no workspace at the root, in apps/, or in a group folder"

step "brief"
if [[ -f CLAUDE.md ]]; then
  [[ "$(tr -d '[:space:]' < CLAUDE.md)" == "@AGENTS.md" ]] || fail "CLAUDE.md must be exactly '@AGENTS.md'"
  [[ -f AGENTS.md ]] || fail "AGENTS.md missing"
  pass "CLAUDE.md → AGENTS.md"
else fail "CLAUDE.md missing"; fi

step "compose files"
if grep -qE '^\s+ports:' "$BASE" 2>/dev/null; then fail "$BASE publishes ports — exposure belongs in a modifier"; fi
for f in "$DOCKER_DIR"/compose.*.yaml; do
  [[ -e $f ]] || continue
  grep -q '\.\./' "$f" && fail "$f uses ../ — paths are root-relative (--project-directory)"
done
pass "base has no ports · no ../ paths"

have_env=1; for f in "${ENV_FILES[@]}"; do [[ -f $f ]] || have_env=0; done
if [[ "$(docker_state)" == ok ]] && (( have_env )); then
  step "compose config (the three env files supply \${VAR})"
  combos=("$DB_FILE" "$DEV_FILE" "$BASE")
  while IFS= read -r m; do [[ -n $m ]] && combos+=("$BASE $DOCKER_DIR/compose.m.$m.yaml"); done < <(list_modifiers)
  for c in "${combos[@]}"; do
    args=(); for f in $c; do args+=(-f "$f"); done
    if out=$(compose_cmd "${args[@]}" config -q 2>&1); then ok "$c"
    else fail "$c — $out"; fi
  done
else
  warn "compose validation skipped — docker: $(docker_state) · env files present: $have_env"
fi

LOG_INDENT=""; hr
(( rc == 0 )) && ok "check green" || err "check red — fix the lines above"
exit $rc
