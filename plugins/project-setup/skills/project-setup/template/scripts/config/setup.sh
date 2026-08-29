#!/usr/bin/env bash
# config/setup.sh — `ctl setup`. First run on a clone: seed .env, sync new keys, generate secrets,
# create data dirs, install deps. Idempotent — never overwrites a filled value.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "setup" "Seed .env, generate secrets, create data dirs, install deps." \
  'setup [-h]' \
"Options
  -h, --help      show this help

Steps
  1. cp .env.example .env if .env is missing; append keys .env.example gained since
  2. fill every blank *_KEY / *_SECRET with openssl rand -hex 32,
     every blank *_PASSWORD with a 24-char base64 string
  3. per frontend: cp .env.example → .env in apps/example-multi-web-app/<name>/ and apps/example-dashboard-nextjs/ if missing
  4. mkdir data/{$(IFS=,; echo "${DATA_SVCS[*]}"),test_build,logs,run}  (data/.gitignore keeps them out of git)
  5. mise install · uv sync per python app · bun install per js app · cargo fetch · go mod download" \
"Re-run any time to top up missing keys and secrets."; }

is_help "${1:-}" && { usage; exit 0; }
[[ -f .env.example ]] || die "no .env.example to template from"
if [[ ! -f .env ]]; then cp .env.example .env; ok "created .env from .env.example"; fi

# sync: append any key present in .env.example but missing from .env. Copies the template
# line verbatim; never touches a value that already exists.
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  key=${line%%=*}; [[ "$key" == "$line" ]] && continue
  grep -q "^${key}=" .env || { printf '%s\n' "$line" >> .env; ok "added missing key $key"; }
done < .env.example

# generate blank secrets. Keys are matched by suffix; the value must be empty.
sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # GNU vs BSD
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"
  [[ -z "$val" ]] || continue
  case "$key" in
    *_PASSWORD)     sed_i "s|^${key}=.*|${key}=$(openssl rand -base64 24 | tr -d '+/=' | head -c 24)|" .env; ok "generated $key" ;;
    *_KEY|*_SECRET) sed_i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" .env; ok "generated $key" ;;
  esac
done < .env

# per-frontend public env — the static group apps/example-multi-web-app/<name>/ plus the SSR app
for fe in apps/example-multi-web-app/*/ apps/example-dashboard-nextjs/; do
  [[ -f "$fe.env.example" && ! -f "$fe.env" ]] || continue
  cp "$fe.env.example" "$fe.env"; ok "created ${fe}.env"
done

# data dirs — created here, owned by the current user, so bind mounts never appear root-owned.
step "ensuring data dirs…"
dirs=(test_build logs run backups); (( ${#DATA_SVCS[@]} )) && dirs+=("${DATA_SVCS[@]}")
for d in "${dirs[@]}"; do mkdir -p "data/$d"; done
ok "data/{$(IFS=,; echo "${dirs[*]}")}"

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

blanks=$(grep -nE '^[A-Z_]+=\s*(#.*)?$' .env || true)
if [[ -n "$blanks" ]]; then warn "fill these blanks in .env:"; say "$blanks"; else ok "no blanks remaining"; fi
say "next: ${C_B}ctl dev${C_RESET}   ${C_DIM}(then ctl migrate once the data core is up)${C_RESET}"
