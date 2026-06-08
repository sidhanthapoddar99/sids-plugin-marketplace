#!/usr/bin/env bash
# scripts/common/_lib.sh — shared foundation for `ctl` and every scripts/*.sh worker.
# SOURCE this, do not execute it. It provides: colored, indent-aware logging, a uniform
# --help renderer, docker-compose helpers + config/modifier discovery, env/tool guards,
# container health, a (none)-aware list filter, and confirm prompts. Keeping it here is
# what lets each worker stay ~25 lines and look identical.
#
# TEMPLATE — adapt per project. Workers live at `scripts/<category>/<name>.sh`, category ∈
# common | dev | container | config (the `ctl` subcommand stays clean — `ctl migrate`, file
# `dev/migrate.sh`). The shared files (this one + `_select.sh`) live in `common/`.
# Add a worker with the preamble below, then wire one `run <category>/<name>` line into `ctl`.
#
# PROFILE-LESS 2-axis model. `ctl up` assembles a single, optional standalone `config`
# (a compose.<name>.yaml that REPLACES base) + stackable `--modifier` overlays
# (compose.m.<name>.yaml). There is intentionally NO list_profiles — profiles are the rare
# advanced escalation (see references/.../complex-setups.md), not the default.
#
# The [ADAPT] knobs, all inline below:
#   • DATA_SVCS               — your data services ("postgres redis"); empty = no data core.
#   • COMPOSE_PROJECT_NAME    — not forced; compose `name:` decides. Set it only to override.
#   • require_env / check_env_schema — STRICT here (data core ⇒ real secrets). Soften them
#                               (warn-don't-die) for a defaulted-env / no-data-core project —
#                               see the soft one-liners marked at each function + no-data-core.md.
#
# Worker preamble (copy verbatim at the top of every scripts/<category>/<name>.sh):
#   #!/usr/bin/env bash
#   set -euo pipefail
#   source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# ── repo root — set by ctl before sourcing; else derived from this file ──
# This file lives at scripts/common/_lib.sh, so the repo root is two levels up.
: "${CTL_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
DOCKER_DIR="docker"
BASE="$DOCKER_DIR/compose.yaml"
# [ADAPT] data services, space-separated. Empty = no data core — every consumer below
# degrades gracefully (ctl dev won't bring up a core, status/health/setup skip it).
# e.g. DATA_SVCS="postgres redis" (default), or DATA_SVCS="" for a DB-less project.
read -r -a DATA_SVCS <<< "${DATA_SVCS:-postgres redis}" || true
# Project name: let docker compose decide it from the compose file's `name:` (or the repo
# directory). We deliberately DON'T force a default here — exporting one (e.g. the dir
# basename) would OVERRIDE a compose `name:` that differs and make every `dc ps` / health
# lookup miss. Set COMPOSE_PROJECT_NAME yourself (env or .env) only to override. svc_health
# resolves the real container via `dc ps -aq` (so it respects the compose `name:`); cname()
# is only a fallback and uses COMPOSE_PROJECT_NAME if set, else the directory.
[[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && export COMPOSE_PROJECT_NAME || true

# ── colors: on only for an interactive TTY without NO_COLOR ──
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'
else
  C_RESET='' C_DIM='' C_B='' C_RED='' C_GRN='' C_YEL='' C_CYN=''
fi

# dependency-free interactive selector (tui_select) — sourced after colors so it reuses them.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_select.sh"

# ── logging (info → stdout, warn/err → stderr) ──
# Result lines (say/ok/warn/err) honor an optional ${LOG_INDENT} prefix so a command can
# nest them UNDER a step() header (e.g. `ctl status` sets LOG_INDENT="  " for its sections).
# Unset by default → byte-identical output everywhere else. step()/hr() are never indented
# (headers + rules stay at column 0).
say()  { printf '%s%s\n' "${LOG_INDENT:-}" "$*"; }
step() { printf '%s▸%s %s\n' "$C_CYN" "$C_RESET" "$*"; }
ok()   { printf '%s%s✓%s %s\n' "${LOG_INDENT:-}" "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s%s!%s %s\n' "${LOG_INDENT:-}" "$C_YEL" "$C_RESET" "$*" >&2; }
err()  { printf '%s%s✗%s %s\n' "${LOG_INDENT:-}" "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }
section() { printf '%s%s%s\n' "$C_B" "$*" "$C_RESET"; hr; }   # bold title + rule line (grouped output, no ▸)
# row <name> <desc> [width] — two-column help row padded by DISPLAY width (char count,
# UTF-8-aware via ${#n}), so multibyte glyphs (…, ·) in the name column don't throw off
# alignment the way `printf %-Ns` does (it pads by bytes). Used by ctl_help + usage blocks.
row()  { local n="$1" d="$2" w="${3:-36}" pad; pad=$(( w - ${#n} )); (( pad < 1 )) && pad=1
         printf '  %s%*s%s\n' "$n" "$pad" '' "$d"; }

# ── help ──
is_help() { [[ "${1:-}" == -h || "${1:-}" == --help ]]; }
# print_help <cmd> <summary> <usage> <body> [dim-note]
# Canonical body anatomy: Arguments/Options → (discovered/availability block) → Example.
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
# (Profile-less by design: a config is a standalone scenario that REPLACES base, not a profile.)
list_configs()   { local f b; for f in "$DOCKER_DIR"/compose.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/}; [[ $b == compose.yaml || $b == compose.m.* ]] && continue
                     b=${b#compose.}; printf '%s\n' "${b%.yaml}"; done; }
list_modifiers() { local f b; for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.m.}; printf '%s\n' "${b%.yaml}"; done; }
join_sp() { paste -sd' ' - 2>/dev/null || tr '\n' ' '; }   # newline list → space-joined
# echo stdin unchanged, or a dim "(none)" when it's empty/whitespace — so discovery
# lists never render as a dangling label. Use as the last stage: `list_x | join_sp | or_none`.
or_none() { local raw; raw=$(cat); raw="${raw%"${raw##*[![:space:]]}"}"
            [[ -n $raw ]] && printf '%s' "$raw" || printf '%s(none)%s' "$C_DIM" "$C_RESET"; }

# ── guards ──
require_env() {
  # STRICT (data core ⇒ real secrets): die if .env is missing.
  # [ADAPT] SOFT (defaulted env, no secrets): replace the two lines below with
  #   [[ -f .env ]] && { set -a; source .env; set +a; } || true; return 0
  [[ -f .env ]] || die ".env missing — run \`ctl setup\` (or cp .env.example .env)."
  set -a; source .env; set +a   # shellcheck disable=SC1091
}
require_tools() {  # require_tools mise docker …
  local t missing=()
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} )) && die "missing on PATH: ${missing[*]} (run: mise install)"
  return 0
}

# ── container health ──
tool_version() { command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | head -1 | tr -d '\n'; }  # best-effort "<tool> --version"
cname()      { printf '%s-%s' "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}" "$1"; }
svc_health() {  # resolve the REAL container, then read its health/status
  # Ask compose for the container id (robust to container_name:, custom name:, project
  # overrides); fall back to the reconstructed name if compose can't answer.
  local id s
  id=$(dc ps -aq "$1" 2>/dev/null | head -1)
  [[ -n $id ]] || id="$(cname "$1")"
  # hardened: docker inspect can exit 0 with empty output for a missing container (e.g. WSL2) — treat empty as down.
  s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null)
  s="${s//[$'\n\r\t ']/}"
  [[ -n $s ]] && printf '%s\n' "$s" || echo down
}
health_table() {  # health_table <svc…>
  local s st col
  for s in "$@"; do
    st=$(svc_health "$s")
    case "$st" in
      healthy|running)            col=$C_GRN ;;
      starting)                   col=$C_YEL ;;
      down|exited|created|absent) col=$C_YEL; st="${st/down/not running}" ;;   # stopped ≠ failed
      *)                          col=$C_RED ;;
    esac
    printf '  %-14s %s%s%s\n' "$s" "$col" "$st" "$C_RESET"
  done
}
wait_healthy() {  # wait_healthy <svc…> [timeout-seconds] — used by ctl dev's data-core bring-up
  local svcs=("$@") timeout=60 last
  last=$(( ${#svcs[@]} - 1 ))
  if [[ "${svcs[last]:-}" =~ ^[0-9]+$ ]]; then timeout="${svcs[last]}"; unset 'svcs[last]'; svcs=("${svcs[@]}"); fi
  (( ${#svcs[@]} )) || return 0          # nothing to wait for (e.g. empty DATA_SVCS)
  local elapsed=0 s all
  while (( elapsed < timeout )); do
    all=1; for s in "${svcs[@]}"; do [[ "$(svc_health "$s")" == healthy ]] || { all=0; break; }; done
    (( all )) && { ok "healthy: ${svcs[*]}"; return 0; }
    sleep 2; elapsed=$(( elapsed + 2 ))
  done
  err "not healthy within ${timeout}s: ${svcs[*]}"; return 1
}

# ── host processes ──
# port_pid <port> — PID listening on TCP <port> (ss, then lsof); empty if none. Used by `ctl ps`.
port_pid() {
  local p="$1" pid=""
  command -v ss >/dev/null 2>&1 && pid=$(ss -tlnp 2>/dev/null | awk -v p=":$p" '$4 ~ p"$"' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
  [[ -z $pid ]] && command -v lsof >/dev/null 2>&1 && pid=$(lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | head -1)
  printf '%s' "$pid"
}

# ── env schema (used by ctl status and config/check-env.sh) ──
check_env_schema() {  # 0 if .env has every key .env.example declares
  # STRICT: missing .env / .env.example is an error.
  # [ADAPT] SOFT (defaulted env): warn-don't-fail — return 0 with a warn when either is absent
  # and when keys are missing (defaults apply). See no-data-core.md.
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

# split a comma-list into the global array __SPLIT (trims surrounding whitespace, drops blanks)
split_csv() { __SPLIT=(); local raw tok s; IFS=',' read -r -a raw <<< "$1"
  for tok in "${raw[@]}"; do s="${tok#"${tok%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; [[ -n $s ]] && __SPLIT+=("$s"); done; }

# Interactive selection lives in _select.sh (tui_select) — sourced above. No fzf/gum dependency.
