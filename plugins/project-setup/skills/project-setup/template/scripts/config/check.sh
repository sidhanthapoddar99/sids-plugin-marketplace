#!/usr/bin/env bash
# config/check.sh — `ctl check`. Conformance floor: the rules the layout and env contract impose.
# Read-only. Prints every failure, exits non-zero if any. Runs as a gate rung too (gate/check.sh).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../worktree/_git.sh"

usage() { print_help "check" "Conformance floor — layout, env contract, compose validity." \
  'check [-h]' \
"Options
  -h, --help      show this help

Rules
  versions  no '<version>' placeholder left in .mise.toml or any app manifest (pyproject.toml,
            package.json, Cargo.toml, rust-toolchain.toml, go.mod) — a placeholder breaks every
            toolchain install, so it is resolved with the user before anything runs
  env       every \${VAR} in apps/*/config.yaml is a key in .env.template ·
            .env.template has unique keys and blank secret values ·
            no root .env or .env.* tracked by git except .env.template ·
            no secret literal in config.yaml (every key/password/secret value is \${VAR}) ·
            no config.local.yaml tracked by git
  storage   .env.template derives DATA_DIR and LOGS_DIR from \${BASE_DIR}, and BACKUP_DIR from
            \${LOGS_DIR} or \${BASE_DIR}, each below the line it reads ·
            in .env, no relative storage path resolves outside BASE_DIR (an absolute one is deliberate)
  layout    no package.json / bun.lock / pnpm-workspace.yaml at the root or directly in apps/ ·
            no folder under apps/ that holds a manifest and child folders with manifests (a group
            folder such as a static-frontend group or packages/ is not a workspace) ·
            the root rule is skipped when AGENTS.md records 'root-manifest' under
            '## Exceptions to the standard layout' (an open-source package repo)
  brief     AGENTS.md exists at the repo root · every AGENTS.md has a CLAUDE.md beside it that is
            exactly '@AGENTS.md', and every CLAUDE.md has an AGENTS.md · each AGENTS.md is at most
            200 lines, all of them together at most 32 KiB, and none holds a date (YYYY-MM-DD)
  template  every shared helper in scripts/common/ matches scripts/common/template-core.sha256 outside
            its [ADAPT] blocks, unless AGENTS.md records 'template-core <path>' as an exception
  ladder    the 'Gate ladder' row in AGENTS.md lists the same rungs, in the same order, as RUNGS in
            scripts/gate/all.sh — the audit reads the row and the gate runs the list, so they must agree
  lint      every app ships its lint config with the complexity floor: [tool.ruff] in pyproject.toml,
            .oxlintrc.json beside package.json, clippy.toml beside Cargo.toml, .golangci.yml beside go.mod —
            a linter run without its config reports only its defaults, and ruff's default has no complexity rule
  size      a warning, never a failure: each source file in ctl, apps/ or scripts/ over 500 lines
            (generated files and SQL left out), unless AGENTS.md records 'size-cap <path>'
  pointers  no code, script or compose file names a skill page (references/NN_*.md) or a tracker issue
            (data/tasks/<date>-…), unless AGENTS.md records 'doc-pointer <path>' as an exception
  migrations no file in apps/database/postgres/migrations that is on the default branch is changed or
            deleted, in commits or in the working tree
  compose   no ports: in any config (docker/compose.<name>.yaml) — only a modifier publishes ·
            no ../ in any docker/compose.*.yaml ·
            every \${NAME} inside the root .env file names a set key, no cycle (the values ctl hands
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
# exception_recorded <text> — 0 when a line under "## Exceptions to the standard layout" in AGENTS.md
# holds <text>, because a recorded exception is a decision, not drift.
exception_recorded() {
  [[ -f AGENTS.md ]] && awk '/^## Exceptions to the standard layout/{f=1;next} /^## /{f=0} f' AGENTS.md | grep -qF -- "$1"
}
# repo_files <dir>… — every file git sees below the dirs, untracked ones included; outside git, every
# file below them, build output left out.
repo_files() {
  if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
    git ls-files -co --exclude-standard -- "$@" | sort -u
  else
    find "$@" \( -name node_modules -o -name .git -o -name .worktrees -o -name target -o -name .venv \) -prune -o -type f -print 2>/dev/null \
      | sed 's|^\./||' | sort
  fi
}
pass() { (( sf )) || ok "$*"; }
step() { sf=0; printf '%s▸%s %s\n' "$C_CYN" "$C_RESET" "$*"; }
LOG_INDENT="  "

step "versions"
# Every file here holds a '<version>' placeholder in the shipped template. A placeholder in
# .mise.toml or a manifest makes mise, uv, cargo and go fail, so ctl setup refuses to run until
# each is resolved (with the user, never from memory).
manifest_list=$(mktemp) || die "cannot create source manifest list"
trap 'rm -f "$manifest_list"' EXIT
discover_source_manifests > "$manifest_list" || fail "source package discovery failed"
mapfile -d '' -t source_manifests < "$manifest_list"
for manifest in "$CTL_ROOT/.mise.toml" "$CTL_ROOT/mise.toml" "${source_manifests[@]}"; do
  [[ -f $manifest ]] || continue
  grep -qF '<version>' "$manifest" && fail "${manifest#"$CTL_ROOT/"} still holds '<version>' — resolve it before setup"
done
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
while IFS= read -r f; do [[ $f == .env.template ]] || fail "$f is tracked by git — only .env.template may be committed"
done < <(git ls-files '.env' '.env.*' 2>/dev/null)
# template contract
known=()
for f in "${ENV_FILES[@]}"; do
  [[ -f $f.template ]] || { fail "$f.template missing"; continue; }
  mapfile -t -O "${#known[@]}" known < <(env_keys "$f.template")
done
while IFS= read -r key; do fail ".env.template: duplicate key $key"; done < <(printf '%s\n' "${known[@]}" | sort | uniq -d)
declare -A declared_secrets=()
for declarations in scripts/config/generated-credentials.conf scripts/config/required-credentials.conf; do
  [[ -f $declarations ]] || continue
  while read -r key remainder || [[ -n $key ]]; do
    [[ -z $key || $key == \#* ]] && continue
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { fail "$declarations: invalid credential name"; continue; }
    declared_secrets["$key"]=1
  done < "$declarations"
done
if [[ -f .env.template ]]; then
  while IFS='=' read -r key value || [[ -n $key ]]; do
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ $key =~ _(PASSWORD|KEY|SECRET)(_|$) || -v declared_secrets["$key"] ]] || continue
    value="${value%$'\r'}"; value="${value%%[[:space:]]#*}"; value="${value%"${value##*[![:space:]]}"}"
    [[ -z $value ]] || fail ".env.template: $key must be blank"
  done < .env.template
fi
for cfg in apps/*/config.yaml; do
  [[ -f $cfg ]] || continue
  while IFS= read -r v; do
    printf '%s\n' "${known[@]}" | grep -qx "$v" || fail "$cfg reads \${$v} — not in .env.template"
  done < <(sed 's/#.*//' "$cfg" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' | tr -d '${}' | sort -u)
done
pass "config.yaml \${VAR} keys ⊆ .env.template · unique keys and blank secrets"

step "layout"
# The root-manifest exception: an open-source package repo whose root IS the published artifact
# records `root-manifest` under "## Exceptions to the standard layout" in AGENTS.md. Only the
# root rule is skipped for it; apps/ and group folders keep the rule.
root_manifest_ok=0
if exception_recorded 'root-manifest'; then
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
# AGENTS.md holds the instructions; the CLAUDE.md beside each one only imports it, because Claude Code
# reads CLAUDE.md and Codex reads AGENTS.md, and one text cannot drift. The limits keep the files short
# enough to be followed: Claude Code's guidance is under 200 lines a file, and Codex stops reading once
# all AGENTS.md files together pass 32 KiB. A date marks history, and the files state current rules.
BRIEF_MAX_LINES=200 BRIEF_MAX_BYTES=32768
# brief_files <name> — every file of that name git sees, or, outside git, every one below the root.
brief_files() {
  if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]; then
    git ls-files -co --exclude-standard -- "$1" "*/$1" | sort -u
  else
    find . \( -name node_modules -o -name .git -o -name .worktrees -o -name target -o -name .venv \) -prune -o -name "$1" -print \
      | sed 's|^\./||' | sort
  fi
}
[[ -f AGENTS.md ]] || fail "AGENTS.md missing"
brief_bytes=0 brief_count=0
while IFS= read -r f; do
  [[ -f $f ]] || continue
  brief_count=$(( brief_count + 1 ))
  dir=$(dirname "$f"); if [[ $dir == . ]]; then claude=CLAUDE.md; else claude="$dir/CLAUDE.md"; fi
  if [[ -L $claude || ! -f $claude ]]; then fail "$claude missing — write it as the one line '@AGENTS.md'"
  elif [[ "$(tr -d '[:space:]' < "$claude")" != "@AGENTS.md" ]]; then fail "$claude must be exactly '@AGENTS.md'"; fi
  lines=$(wc -l < "$f"); (( lines <= BRIEF_MAX_LINES )) || fail "$f has $lines lines; the limit is $BRIEF_MAX_LINES — move detail to a README the file points at"
  brief_bytes=$(( brief_bytes + $(wc -c < "$f") ))
  while IFS= read -r hit; do fail "$f:$hit holds a date — state the current rule, and keep its history in git and the tracker"; done \
    < <(grep -nE '(^|[^0-9])20[0-9]{2}-[0-9]{2}-[0-9]{2}([^0-9]|$)' "$f" | cut -d: -f1)
done < <(brief_files AGENTS.md)
while IFS= read -r f; do
  [[ -e $f ]] || continue
  [[ -f "$(dirname "$f")/AGENTS.md" ]] || fail "$f has no AGENTS.md beside it — a CLAUDE.md only imports one"
done < <(brief_files CLAUDE.md)
(( brief_bytes <= BRIEF_MAX_BYTES )) || fail "the AGENTS.md files hold $brief_bytes bytes together; the limit is $BRIEF_MAX_BYTES — cut them, because Codex reads no further"
pass "$brief_count AGENTS.md file(s), $brief_bytes bytes, each with CLAUDE.md → AGENTS.md"

step "template core"
while IFS= read -r problem; do fail "$problem"; done < <(source scripts/common/_template-core.sh 2>/dev/null \
  || { echo "scripts/common/_template-core.sh is missing — copy scripts/common/ whole from the template"; exit; }; template_core_problems .)
pass "scripts/common/ matches the template outside its [ADAPT] blocks"

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

step "source size"
# A file past 500 lines is hard to read whole and often holds more than one job, so it is named. It
# is a warning, never a failure, because a long file can be the right shape. Generated files (under a
# generated/ folder or named *.gen.*), lock files and SQL migrations are not split by hand, so they do
# not count. A file that stays long on purpose is recorded as 'size-cap <path>' under the exceptions,
# which silences it.
SOURCE_WARN_LINES=500 long=0
while IFS= read -r f; do
  [[ -f $f ]] || continue
  case "$f" in */generated/*|*.gen.*|*.d.ts|*.min.js) continue ;; esac
  lines=$(wc -l < "$f"); (( lines > SOURCE_WARN_LINES )) || continue
  exception_recorded "size-cap $f" && continue
  warn "$f has $lines lines — consider a split, or record 'size-cap $f' in AGENTS.md"; long=$(( long + 1 ))
done < <(repo_files ctl apps scripts | grep -E '(^ctl$|\.(py|ts|tsx|js|jsx|mjs|rs|go|sh|css)$)')
if (( long )); then say "  $long file(s) over $SOURCE_WARN_LINES lines (a warning; the check still passes)"
else pass "no source file over $SOURCE_WARN_LINES lines"; fi

step "doc pointers"
# Documentation points at code, never the reverse: a skill page, a tracker issue or a plan moves and
# renumbers, and no test reads a comment, so code that names one goes stale unnoticed. Markdown is the
# documentation side and is not read here. A file whose code names such a path on purpose is recorded
# as 'doc-pointer <path>' under the exceptions.
DOC_POINTER='references/[0-9]{2}[a-z]?_[a-z0-9-]+\.md|data/(tasks|todo)/[0-9]{4}-'
while IFS= read -r f; do
  [[ -f $f ]] && ! exception_recorded "doc-pointer $f" || continue
  while IFS= read -r line; do fail "$f:$line names a doc page or tracker issue — write the rule into the comment instead"; done \
    < <(grep -nIE -- "$DOC_POINTER" "$f" | cut -d: -f1)
done < <(repo_files ctl apps scripts docker | grep -vE '\.md$')
pass "no code, script or compose file names a doc page or tracker issue"

step "migrations"
# A migration on the default branch has run against some database, and Flyway refuses a database whose
# applied history changed, so such a file is never edited or deleted: a change is a new migration.
MIGRATIONS=apps/database/postgres/migrations
if [[ ! -d $MIGRATIONS ]]; then say "  no $MIGRATIONS — nothing to compare"
elif [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) != true ]]; then say "  not a git checkout — nothing to compare"
else
  default=$(wt_default_branch .)
  if ! base=$(git merge-base HEAD "$default" 2>/dev/null); then say "  no $default branch yet — nothing to compare"
  else
    while IFS=$'\t' read -r status path; do
      if [[ $status == [MD]* ]]; then fail "$path is on $default, so a database may have applied it — restore it and add a new migration"; fi
    done < <(git diff --name-status --no-renames "$base" -- "$MIGRATIONS")
    pass "no migration on $default is changed or deleted"
  fi
fi

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
  step "Rust settings (the RUST section holds values Cargo accepts)"
  if rust_env_apply; then pass "CTL_RUST_DEBUG is ${CTL_RUST_DEBUG:-empty, so Cargo.toml decides}"
  else fail "ctl dev, ctl test and ctl gate would stop on CTL_RUST_DEBUG (named above)"; fi
fi

# check_storage_paths — every storage path hangs off BASE_DIR, so one setting moves them all.
# Template: a declared DATA_DIR or LOGS_DIR starts with ${BASE_DIR}, BACKUP_DIR with ${LOGS_DIR} or
# ${BASE_DIR}, and the referenced key sits on an earlier line, because compose resolves a reference
# inside the --env-file only to an earlier line and leaves a later one blank. Local .env: a relative
# path resolves against the repo root, not against BASE_DIR, so it stays behind when BASE_DIR moves.
# An absolute path there is taken as deliberate (a fast disk, a CI tmpfs). Runs before compose_cmd,
# because compose_cmd makes every storage path absolute.
check_storage_paths() {
  local n=0 line key parent parents derived value base
  local -A at=() raw=()
  step "storage paths (every one hangs off BASE_DIR)"
  if [[ -f .env.template ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      (( ++n ))
      [[ $line =~ ^(BASE_DIR|DATA_DIR|LOGS_DIR|BACKUP_DIR)=(.*)$ ]] || continue
      value="${BASH_REMATCH[2]%$'\r'}"; value="${value%%[[:space:]]#*}"
      at[${BASH_REMATCH[1]}]=$n; raw[${BASH_REMATCH[1]}]="${value%"${value##*[![:space:]]}"}"
    done < .env.template
    for key in DATA_DIR LOGS_DIR BACKUP_DIR; do
      [[ -v at[$key] ]] || continue
      parents=BASE_DIR; [[ $key == BACKUP_DIR ]] && parents="LOGS_DIR BASE_DIR"
      derived=0
      for parent in $parents; do
        [[ ${raw[$key]} == "\${$parent}" || ${raw[$key]} == "\${$parent}/"* ]] || continue
        derived=1
        [[ -v at[$parent] ]] && (( at[$parent] < at[$key] )) \
          || fail ".env.template: $key reads \${$parent}, which is not declared above it — compose resolves only earlier lines"
      done
      (( derived )) || fail ".env.template: $key=${raw[$key]} does not derive from \${BASE_DIR} — moving BASE_DIR would leave it behind"
    done
  fi
  if [[ -f .env ]]; then
    load_env_files; expand_env_refs 2>/dev/null || true
    storage_path base "${BASE_DIR-.}"
    for key in DATA_DIR LOGS_DIR BACKUP_DIR; do
      [[ -v $key && ${!key} != /* && ${!key} != *'${'* ]] || continue
      storage_path value "${!key}"
      [[ $value == "$base" || $value == "$base"/* ]] \
        || fail ".env: $key=${!key} resolves to $value, outside BASE_DIR ($base) — derive it from \${BASE_DIR}, or write an absolute path if it lives elsewhere on purpose"
    done
  fi
  pass "DATA_DIR, LOGS_DIR and BACKUP_DIR derive from BASE_DIR"
}
check_storage_paths

if [[ "$(docker_state)" == ok ]] && (( have_env )); then
  step "compose config (the root .env file supplies \${VAR}, resolved as ctl up hands them on)"
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
    if (( ${#blank[@]} )); then warn "+$m — skipped: needs ${blank[*]} set in .env (ctl up refuses it the same way)"; continue; fi
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
