#!/usr/bin/env bash
# config/setup.sh — `ctl setup`. First run on a clone: create the three env files from their
# templates, sync new keys, generate secrets, create data/logs dirs, install deps.
# Idempotent — never overwrites a filled value.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "setup" "Create .env.secrets / .env.data / .env.proxy from templates, generate secrets, create dirs, install deps." \
  'setup [-h]' \
"Options
  -h, --help      show this help

Steps
  1. for each of .env.secrets .env.data .env.proxy: cp <file>.template <file> if missing;
     append keys the template gained since. Never overwrites a value.
  2. in .env.secrets only: fill every blank key with a _KEY or _SECRET segment with openssl rand -hex 32,
     every blank key with a _PASSWORD segment with a 24-char base64 string
  3. mkdir data/{$(IFS=,; echo "${DATA_SVCS[*]}")} and logs/{dev,run,backups,test_build}  (each folder's .gitignore keeps it out of git)
  4. refuse while any '<version>' placeholder remains in .mise.toml or an app manifest (ctl check names them)
  5. mise install · uv sync per python app · bun install per js app · cargo fetch · go mod download · lefthook install

Exit 0 only when every step succeeded. A failed install is named and the exit code is 1." \
"Re-run any time to top up missing keys and secrets."; }

is_help "${1:-}" && { usage; exit 0; }
rc=0; fail() { err "$*"; rc=1; }
step "env files (template → file)"
for f in "${ENV_FILES[@]}"; do
  [[ -f "$f.template" ]] || die "no $f.template to create $f from"
  if [[ ! -f "$f" ]]; then cp "$f.template" "$f"; ok "created $f from $f.template"; fi
  # sync: append any key present in the template but missing from the file. Copies the template
  # line verbatim; never touches a value that already exists.
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}; [[ "$key" == "$line" ]] && continue
    grep -q "^${key}=" "$f" || { printf '%s\n' "$line" >> "$f"; ok "$f: added missing key $key"; }
  done < "$f.template"
done

# generate blank secrets — in .env.secrets only. A key is a secret when its name holds a _PASSWORD,
# _KEY or _SECRET segment, at the end or followed by more (ENCRYPTION_KEY_PYTHON). The value must be empty.
step "secrets"
sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # GNU vs BSD
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"
  [[ -z "$val" ]] || continue
  case "$key" in
    *_PASSWORD|*_PASSWORD_*)               sed_i "s|^${key}=.*|${key}=$(openssl rand -base64 24 | tr -d '+/=' | head -c 24)|" .env.secrets; ok "generated $key" ;;
    *_KEY|*_KEY_*|*_SECRET|*_SECRET_*)     sed_i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" .env.secrets; ok "generated $key" ;;
  esac
done < .env.secrets

# data dirs — created here, owned by the current user, so bind mounts never appear root-owned.
step "ensuring data dirs…"
# data/ = actual data (engine mounts, datasets). logs/ = everything else that is produced: logs, pids, backups, frozen builds.
for d in "${DATA_SVCS[@]}"; do mkdir -p "data/$d"; done
for d in dev run backups test_build; do mkdir -p "logs/$d"; done
ok "data/{$(IFS=,; echo "${DATA_SVCS[*]}")}  logs/{dev,run,backups,test_build}"

step "versions"
# A '<version>' placeholder makes mise, uv, cargo and go fail, and a failed install that still
# printed "next: ctl dev" is worse than a stop. Resolve each with the user, never from memory.
unresolved=$({ grep -l --fixed-strings '<version>' .mise.toml 2>/dev/null; grep -rl --fixed-strings '<version>' apps --include=pyproject.toml --include=package.json \
               --include=Cargo.toml --include=rust-toolchain.toml --include=go.mod --exclude-dir=node_modules 2>/dev/null; } || true)
if [[ -n $unresolved ]]; then
  err "these files still hold '<version>' — resolve each before setup installs anything:"; say "$unresolved"
  die "setup stopped — env files and dirs are in place, toolchains were not installed"
fi
ok "no <version> placeholder left"

step "installing toolchains + dependencies…"
# A missing tool is a warning: the user may install it later. A tool that is present and fails is a
# failure, because the next step (ctl dev) will not work and must not be announced.
if command -v mise >/dev/null 2>&1; then
  if mise install; then ok "mise install"; else fail "mise install failed"; fi
else warn "mise not found — toolchains skipped"; fi
for d in apps/*/ apps/database/postgres/; do
  [[ -f "$d/pyproject.toml" ]] || continue
  if command -v uv >/dev/null 2>&1; then
    if ( cd "$d" && uv sync ); then ok "$d uv sync"; else fail "$d uv sync failed"; fi
  else warn "uv not found — $d skipped"; break; fi
done
for d in apps/*/ apps/*/*/ apps/packages/*/; do
  [[ -f "$d/package.json" ]] || continue
  if command -v bun >/dev/null 2>&1; then
    if ( cd "$d" && bun install ); then ok "$d bun install"; else fail "$d bun install failed"; fi
  else warn "bun not found — $d skipped"; break; fi
done
for d in apps/*/; do
  [[ -f "$d/Cargo.toml" ]] || continue
  if command -v cargo >/dev/null 2>&1; then
    if ( cd "$d" && cargo fetch ); then ok "$d cargo fetch"; else fail "$d cargo fetch failed"; fi
  else warn "cargo not found — $d skipped"; break; fi
done
for d in apps/*/; do
  [[ -f "$d/go.mod" ]] || continue
  if command -v go >/dev/null 2>&1; then
    if ( cd "$d" && go mod download ); then ok "$d go mod download"; else fail "$d go mod download failed"; fi
  else warn "go not found — $d skipped"; break; fi
done
# git hooks: lefthook.yml is inert until installed, so this is the one place that installs it
if [[ -f lefthook.yml && -d .git ]]; then
  if command -v lefthook >/dev/null 2>&1; then
    if lefthook install >/dev/null; then ok "lefthook install (hooks: pre-commit lint + data guard, pre-push test)"; else fail "lefthook install failed"; fi
  else warn "lefthook not found — hooks not installed (mise install adds it)"; fi
fi

for f in "${ENV_FILES[@]}"; do
  blanks=$(grep -nE '^[A-Z_]+=\s*(#.*)?$' "$f" || true)
  if [[ -n "$blanks" ]]; then warn "fill these blanks in $f:"; say "$blanks"; else ok "$f: no blanks"; fi
done
if (( rc == 0 )); then
  say "next: ${C_B}ctl dev${C_RESET}   ${C_DIM}(then ctl migrate once the data core is up)${C_RESET}"
else
  err "setup incomplete — fix the lines above, then re-run ctl setup"
fi
exit $rc
