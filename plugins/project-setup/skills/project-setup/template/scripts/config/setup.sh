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
  2. in .env.secrets only: fill every blank *_KEY / *_SECRET with openssl rand -hex 32,
     every blank *_PASSWORD with a 24-char base64 string
  3. mkdir data/{$(IFS=,; echo "${DATA_SVCS[*]}")} and logs/{dev,run,backups,test_build}  (each folder's .gitignore keeps it out of git)
  4. mise install · uv sync per python app · bun install per js app · cargo fetch · go mod download · lefthook install" \
"Re-run any time to top up missing keys and secrets."; }

is_help "${1:-}" && { usage; exit 0; }
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

# generate blank secrets — in .env.secrets only. Keys are matched by suffix; the value must be empty.
step "secrets"
sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # GNU vs BSD
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"
  [[ -z "$val" ]] || continue
  case "$key" in
    *_PASSWORD)     sed_i "s|^${key}=.*|${key}=$(openssl rand -base64 24 | tr -d '+/=' | head -c 24)|" .env.secrets; ok "generated $key" ;;
    *_KEY|*_SECRET) sed_i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" .env.secrets; ok "generated $key" ;;
  esac
done < .env.secrets

# data dirs — created here, owned by the current user, so bind mounts never appear root-owned.
step "ensuring data dirs…"
# data/ = actual data (engine mounts, datasets). logs/ = everything else that is produced: logs, pids, backups, frozen builds.
for d in "${DATA_SVCS[@]}"; do mkdir -p "data/$d"; done
for d in dev run backups test_build; do mkdir -p "logs/$d"; done
ok "data/{$(IFS=,; echo "${DATA_SVCS[*]}")}  logs/{dev,run,backups,test_build}"

step "installing toolchains + dependencies…"
if command -v mise >/dev/null 2>&1; then mise install && ok "mise install"; else warn "mise not found — toolchains skipped"; fi
for d in apps/*/ apps/database/postgres/; do
  [[ -f "$d/pyproject.toml" ]] || continue
  if command -v uv >/dev/null 2>&1; then ( cd "$d" && uv sync ) && ok "$d uv sync"; else warn "uv not found — $d skipped"; break; fi
done
for d in apps/*/ apps/example-multi-web-app/*/ apps/packages/*/; do
  [[ -f "$d/package.json" ]] || continue
  if command -v bun >/dev/null 2>&1; then ( cd "$d" && bun install ) && ok "$d bun install"; else warn "bun not found — $d skipped"; break; fi
done
for d in apps/*/; do
  [[ -f "$d/Cargo.toml" ]] || continue
  if command -v cargo >/dev/null 2>&1; then ( cd "$d" && cargo fetch ) && ok "$d cargo fetch"; else warn "cargo not found — $d skipped"; break; fi
done
for d in apps/*/; do
  [[ -f "$d/go.mod" ]] || continue
  if command -v go >/dev/null 2>&1; then ( cd "$d" && go mod download ) && ok "$d go mod download"; else warn "go not found — $d skipped"; break; fi
done
# git hooks: lefthook.yml is inert until installed, so this is the one place that installs it
if [[ -f lefthook.yml && -d .git ]]; then
  if command -v lefthook >/dev/null 2>&1; then lefthook install >/dev/null && ok "lefthook install (hooks: pre-commit lint + data guard, pre-push test)"
  else warn "lefthook not found — hooks not installed (mise install adds it)"; fi
fi

for f in "${ENV_FILES[@]}"; do
  blanks=$(grep -nE '^[A-Z_]+=\s*(#.*)?$' "$f" || true)
  if [[ -n "$blanks" ]]; then warn "fill these blanks in $f:"; say "$blanks"; else ok "$f: no blanks"; fi
done
say "next: ${C_B}ctl dev${C_RESET}   ${C_DIM}(then ctl migrate once the data core is up)${C_RESET}"
