#!/usr/bin/env bash
# config/check.sh — `ctl check`. Conformance floor: the rules the layout and env contract impose.
# Read-only. Prints every failure, exits non-zero if any. Runs as a gate rung too (gate/check.sh).
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
  ladder    the 'Gate ladder' row in AGENTS.md lists the same rungs, in the same order, as RUNGS in
            scripts/gate/all.sh — the audit reads the row and the gate runs the list, so they must agree
  lint      every app ships its lint config with the complexity floor: [tool.ruff] in pyproject.toml,
            .oxlintrc.json beside package.json, clippy.toml beside Cargo.toml, .golangci.yml beside go.mod —
            a linter run without its config reports only its defaults, and ruff's default has no complexity rule
  compose   no ports: in any config (docker/compose.<name>.yaml) — only a modifier publishes ·
            no ../ in any docker/compose.*.yaml ·
            every \${NAME} inside the three env files names a set key, no cycle (the values ctl hands
            compose and the apps) ·
            docker compose config validates every config alone, and every modifier fits at least one
            config (the pair validates) — the fit list is printed, because that is what ctl up offers
            (a modifier whose required keys are blank, such as +public before the public origin is
            uncommented, is skipped and named, the way ctl up refuses it)

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

step "ladder"
# The row is `| Gate ladder | \`lint typecheck test check\` |`: the first backtick span is the list.
# RUNGS is the line `RUNGS=(lint typecheck test check)` in all.sh. Word lists, compared in order.
if [[ -f AGENTS.md && -f scripts/gate/all.sh ]]; then
  row=$(grep -E '^\| *Gate ladder *\|' AGENTS.md | head -1 | sed -E 's/^[^`]*`([^`]*)`.*/\1/' | xargs || true)
  rungs=$(grep -E '^RUNGS=\(' scripts/gate/all.sh | head -1 | sed -E 's/^RUNGS=\(([^)]*)\).*/\1/' | xargs || true)
  [[ -n $row ]]   || fail "AGENTS.md has no 'Gate ladder' row with a backticked rung list"
  [[ -n $rungs ]] || fail "scripts/gate/all.sh has no RUNGS=(…) line"
  if [[ -n $row && -n $rungs && $row != "$rungs" ]]; then fail "AGENTS.md Gate ladder row says '$row' but scripts/gate/all.sh RUNGS says '$rungs' — keep the two equal"; fi
  pass "AGENTS.md Gate ladder row = RUNGS ($rungs)"
else fail "AGENTS.md or scripts/gate/all.sh missing — the ladder has no record to compare"; fi

step "lint config"
# One config per ecosystem, beside the manifest, because a linter run without it reports only its
# defaults. Packages and the database folder count when they carry a manifest; node_modules never.
while IFS= read -r m; do
  d=$(dirname "$m")
  case "$(basename "$m")" in
    pyproject.toml) grep -qE '^\[tool\.ruff' "$m" || fail "$m has no [tool.ruff] section — the complexity floor (C901 at 10) is unset" ;;
    package.json)   [[ -d $d/src ]] || continue   # a manifest with no source (packages/tsconfig) has nothing to lint
                    [[ -f $d/.oxlintrc.json ]] || fail "$d has no .oxlintrc.json — oxlint runs with defaults and no size or depth floor" ;;
    Cargo.toml)     [[ -f $d/clippy.toml ]] || fail "$d has no clippy.toml — the cognitive complexity threshold is unset" ;;
    go.mod)         [[ -f $d/.golangci.yml ]] || fail "$d has no .golangci.yml — gocyclo never runs" ;;
  esac
done < <(find apps -maxdepth 3 \( -name pyproject.toml -o -name package.json -o -name Cargo.toml -o -name go.mod \) \
          -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/.venv/*' -not -path '*/crates/*' 2>/dev/null | sort)
pass "every app ships its lint config"

step "compose files"
# a config never publishes a port: lists only union across files, so exposure can only be added, by a modifier
while IFS= read -r c; do [[ -z $c ]] && continue
  # comments stripped first, then a `ports` key in block form or inside a flow map, with any spacing before the colon
  f=$(config_file "$c"); sed 's/#.*//' "$f" 2>/dev/null | grep -qE '(^|[[:space:]{,])ports[[:space:]]*:' && fail "$f publishes ports — a config never does; exposure belongs in a modifier"
done < <(list_configs)
for f in "$DOCKER_DIR"/compose.*.yaml; do
  [[ -e $f ]] || continue
  grep -q '\.\./' "$f" && fail "$f uses ../ — paths are root-relative (--project-directory)"
done
pass "no config publishes a port · no ../ paths"

have_env=1; for f in "${ENV_FILES[@]}"; do [[ -f $f ]] || have_env=0; done
if (( have_env )); then
  # The same load ctl up and ctl dev do: files skip-if-set, then every ${NAME} resolved. A
  # reference that does not resolve is a finding here, because ctl would hand it on as text.
  step "composed values (every \${NAME} in the env files names a set key)"
  load_env_files
  if expand_env_refs; then pass "every \${NAME} in the env files resolves"
  else fail "an env file holds a reference ctl cannot resolve — ctl up and ctl dev would hand it on as text"; fi
fi
if [[ "$(docker_state)" == ok ]] && (( have_env )); then
  step "compose config (the three env files supply \${VAR}, resolved as ctl up hands them on)"
  # every config must stand alone
  mapfile -t cfgs < <(list_configs)
  (( ${#cfgs[@]} )) || fail "no config in $DOCKER_DIR/ (docker/compose.<name>.yaml)"
  for c in "${cfgs[@]}"; do
    if out=$(compose_cmd -f "$(config_file "$c")" config -q 2>&1); then ok "config $c"
    else fail "config $c — $out"; fi
  done
  # every modifier must fit at least one config; the fit list is what ctl up offers for each config.
  # A modifier whose mapped keys are blank is skipped, the way ctl up refuses it: +public needs the
  # optional public-origin keys uncommented, and a blank ${VAR} would validate as an empty string.
  while IFS= read -r m; do [[ -z $m ]] && continue
    mapfile -t blank < <(modifier_blank_keys "$m")
    if (( ${#blank[@]} )); then warn "+$m — skipped: needs ${blank[*]} set in .env.proxy / .env.secrets (ctl up refuses it the same way)"; continue; fi
    fits=(); for c in "${cfgs[@]}"; do modifier_fits "$c" "$m" && fits+=("$c"); done
    if (( ${#fits[@]} )); then ok "+$m fits: ${fits[*]}"
    else fail "+$m fits no config — $(compose_cmd -f "$BASE" -f "$(modifier_file "$m")" config -q 2>&1 | head -1)"; fi
  done < <(list_modifiers)
else
  warn "compose validation skipped — docker: $(docker_state) · env files present: $have_env"
fi

LOG_INDENT=""; hr
(( rc == 0 )) && ok "check green" || err "check red — fix the lines above"
exit $rc
