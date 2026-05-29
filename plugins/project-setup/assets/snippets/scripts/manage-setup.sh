#!/usr/bin/env bash
# manage-setup.sh — `ctl setup`. Interactive .env wizard: create .env, generate secrets, make data dirs.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "setup" "Interactive .env wizard: create .env, generate secrets, make data dirs." \
  'setup [-h]' \
"Options
  -h, --help      show this help" \
"Idempotent — re-run to top up missing secrets; never clobbers filled values."; }

is_help "${1:-}" && { usage; exit 0; }
[[ -f .env.example ]] || die "no .env.example to template from"
if [[ ! -f .env ]]; then cp .env.example .env; ok "created .env from .env.example"; fi

# auto-generate blank secrets (keys ending _PASSWORD / _SECRET / _KEY)
sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # GNU vs BSD
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  if [[ "$key" =~ (_PASSWORD|_SECRET|_KEY)$ && -z "$val" ]]; then
    sed_i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" .env
    ok "generated $key"
  fi
done < .env

# data dirs — only with a data core (skipped cleanly for no-data-core projects)
if (( ${#DATA_SVCS[@]} )); then step "ensuring data dirs…"; mkdir -p data/postgres/pgdata data/redis/data; fi

step "installing dependencies…"      # default tools: uv (python) + bun (node). See script-alternatives.md to swap.
if [[ -d apps/backend ]]; then
  if command -v uv >/dev/null 2>&1; then ( cd apps/backend && uv sync ) && ok "backend deps (uv sync)"
  else warn "uv not found — backend deps skipped (see runtime/script-alternatives.md for venv/poetry/uvenv)"; fi
fi
if [[ -d apps/frontend ]]; then
  if command -v bun >/dev/null 2>&1; then ( cd apps/frontend && bun install ) && ok "frontend deps (bun install)"
  else warn "bun not found — frontend deps skipped (see runtime/script-alternatives.md for pnpm/npm)"; fi
fi

blanks=$(grep -nE '=$' .env || true)
if [[ -n "$blanks" ]]; then warn "fill these blanks in .env:"; say "$blanks"; else ok "no blanks remaining"; fi
say "next: ${C_B}ctl dev${C_RESET}"
