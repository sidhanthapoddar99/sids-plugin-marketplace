#!/usr/bin/env bash
# scripts/_lib.sh — shared foundation for `ctl` and every scripts/*.sh worker.
# SOURCE this, do not execute it. It provides: colored logging, a uniform --help
# renderer, docker-compose helpers + profile/config/modifier discovery, env/tool
# guards, container health, and confirm prompts. Keeping it here is what lets each
# worker stay ~25 lines and look identical.
#
# TEMPLATE — adapt per project. Workers are named `<category>-<name>.sh`, category ∈
# dev | docker | manage (the `ctl` subcommand stays clean — `ctl migrate`, file `dev-migrate.sh`).
# Add a worker with the preamble below, then wire one `run` line into `ctl`.
#
# Worker preamble (copy verbatim at the top of every scripts/<category>-<name>.sh):
#   #!/usr/bin/env bash
#   set -euo pipefail
#   source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

# ── repo root — set by ctl before sourcing; else derived from this file ──
: "${CTL_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
DOCKER_DIR="docker"
BASE="$DOCKER_DIR/compose.yaml"
read -r -a DATA_SVCS <<< "${DATA_SVCS:-postgres redis}" || true   # the no-profile core dev needs

# ── colors: on only for an interactive TTY without NO_COLOR ──
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'
else
  C_RESET='' C_DIM='' C_B='' C_RED='' C_GRN='' C_YEL='' C_CYN=''
fi

# ── logging (info → stdout, warn/err → stderr) ──
say()  { printf '%s\n' "$*"; }
step() { printf '%s▸%s %s\n' "$C_CYN" "$C_RESET" "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }

# ── help ──
is_help() { [[ "${1:-}" == -h || "${1:-}" == --help ]]; }
# print_help <cmd> <summary> <usage> <body> [dim-note]
print_help() {
  printf '%s%s%s — %s\n\n' "$C_B$C_CYN" "ctl $1" "$C_RESET" "$2"
  printf '%sUsage%s\n  ctl %s\n\n' "$C_B" "$C_RESET" "$3"
  printf '%s\n' "$4"
  [[ -n "${5:-}" ]] && printf '\n%s%s%s\n' "$C_DIM" "$5" "$C_RESET"
  return 0
}
# passthrough_help <verb> <summary> — for thin `docker compose` forwards
passthrough_help() {
  print_help "$1" "$2" "$1 [args…] [-h]" \
"Options
  -h, --help   show this help

Any extra args forward straight to \`docker compose $1\`." \
"Tip: run \`docker compose -f $BASE $1 --help\` for all native flags."
}

# ── docker compose ──
dc() { docker compose -f "$BASE" "$@"; }
# auto-discovery — no hard-coded lists. compose.m.* = modifiers; the rest (minus base) = configs.
list_profiles()  { grep -hoE 'profiles:[[:space:]]*\[[^]]+\]' "$BASE" 2>/dev/null \
                     | grep -oE '[A-Za-z0-9_-]+' | grep -vx profiles | sort -u; }
list_configs()   { local f b; for f in "$DOCKER_DIR"/compose.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/}; [[ $b == compose.yaml || $b == compose.m.* ]] && continue
                     b=${b#compose.}; printf '%s\n' "${b%.yaml}"; done; }
list_modifiers() { local f b; for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.m.}; printf '%s\n' "${b%.yaml}"; done; }
join_sp() { paste -sd' ' - 2>/dev/null || tr '\n' ' '; }   # newline list → space-joined

# ── guards ──
require_env() {
  [[ -f .env ]] || die ".env missing — run \`ctl setup\` (or cp .env.example .env)."
  set -a; source .env; set +a   # shellcheck disable=SC1091
}
require_tools() {  # require_tools mise docker …
  local t missing=()
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} )) && die "missing on PATH: ${missing[*]}"
  return 0
}

# ── container health ──
tool_version() { command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | head -1 | tr -d '\n'; }  # best-effort "<tool> --version"
cname()      { printf '%s-%s' "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}" "$1"; }
svc_health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(cname "$1")" 2>/dev/null || echo down; }
health_table() {  # health_table <svc…>
  local s st col
  for s in "$@"; do
    st=$(svc_health "$s")
    case "$st" in healthy|running) col=$C_GRN ;; starting) col=$C_YEL ;; *) col=$C_RED ;; esac
    printf '  %-14s %s%s%s\n' "$s" "$col" "$st" "$C_RESET"
  done
}
wait_healthy() {  # wait_healthy <svc…> [timeout-seconds]
  local svcs=("$@") timeout=60 last
  last=$(( ${#svcs[@]} - 1 ))
  if [[ "${svcs[last]:-}" =~ ^[0-9]+$ ]]; then timeout="${svcs[last]}"; unset 'svcs[last]'; svcs=("${svcs[@]}"); fi
  local elapsed=0 s all
  while (( elapsed < timeout )); do
    all=1; for s in "${svcs[@]}"; do [[ "$(svc_health "$s")" == healthy ]] || { all=0; break; }; done
    (( all )) && { ok "healthy: ${svcs[*]}"; return 0; }
    sleep 2; elapsed=$(( elapsed + 2 ))
  done
  err "not healthy within ${timeout}s: ${svcs[*]}"; return 1
}

# ── env schema (used by ctl status and manage-check-env.sh) ──
check_env_schema() {  # 0 if .env has every key .env.example declares
  [[ -f .env && -f .env.example ]] || { err "need both .env and .env.example (run ctl setup)"; return 1; }
  local k; declare -A have=()
  while IFS='=' read -r k _; do [[ -z "$k" || "$k" == \#* ]] || have["$k"]=1; done < .env
  local missing=()
  while IFS='=' read -r k _; do [[ -z "$k" || "$k" == \#* ]] && continue; [[ -v have[$k] ]] || missing+=("$k"); done < .env.example
  if (( ${#missing[@]} )); then err ".env missing keys: ${missing[*]}"; return 1; fi
  ok ".env matches .env.example schema"; return 0
}

# ── prompts ──
confirm() { local a; printf '%s?%s %s [y/N] ' "$C_YEL" "$C_RESET" "$*"; read -r a; [[ "${a,,}" == y || "${a,,}" == yes ]]; }
