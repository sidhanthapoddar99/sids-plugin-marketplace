#!/usr/bin/env bash
# scripts/common/_lib.sh — shared foundation for `ctl` and every scripts/*.sh worker.
# SOURCE this, do not execute it. It provides: colored, indent-aware logging, a uniform
# --help renderer, docker compose helpers + modifier discovery, env/tool guards,
# container health, host-process helpers, and prompts. Keeping it here is what lets
# each worker stay short and look identical.
#
# Workers live at `scripts/<group>/<name>.sh`, group ∈ common | config | dev | container | db | test.
# Add a worker with the preamble below, then wire one `run <group>/<name>` line into `ctl`.
#
# COMPOSE MODEL (one base + stackable modifiers, no profiles, no standalone configs):
#   docker/compose.db.yaml     the data engines alone (loopback ports)   → `ctl dev`
#   docker/compose.base.yaml   the whole stack; it `include:`s the db file; NO ports
#   docker/compose.m.<name>.yaml   modifiers, discovered by filename       → `ctl up +<name>`
# Every compose call passes --project-directory "$CTL_ROOT", so every relative path in
# .env and in every compose file resolves from the repo root (compose files say ./apps/…,
# ./data, never ../). Compose loads $CTL_ROOT/.env itself for ${VAR} interpolation.
#
# The [ADAPT] knobs, all inline below:
#   • DATA_SVCS           — the data core; empty = no data core (dev/up/status/setup skip it)
#   • app_names/app_port/app_cmd — the host-run apps `ctl dev` knows, in dev/dev.sh
#   • MODIFIER_REQUIRES   — .env keys a modifier needs non-blank before `ctl up` accepts it
#   • PORT_PRESETS        — ports offered by `ctl build start`, scanned by `ctl ps`
#
# Worker preamble (copy verbatim at the top of every scripts/<group>/<name>.sh):
#   #!/usr/bin/env bash
#   set -euo pipefail
#   source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# ── repo root — set by ctl before sourcing; else derived from this file ──
: "${CTL_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
DOCKER_DIR="docker"
BASE="$DOCKER_DIR/compose.base.yaml"
DB_FILE="$DOCKER_DIR/compose.db.yaml"
DEFAULT_MODIFIERS=(expose_nginx)          # what `ctl up` applies when no +modifier is given

# [ADAPT] the data core. Empty = no data core — every consumer degrades gracefully.
read -r -a DATA_SVCS <<< "${DATA_SVCS:-postgres redis neo4j}" || true

# [ADAPT] .env keys a modifier maps with ${VAR}. `ctl up` refuses the modifier when any is blank —
# an unset ${VAR} in compose becomes an empty string and the service breaks silently.
declare -A MODIFIER_REQUIRES=(
  [env_override]="DATABASE_URL REDIS_URL NEO4J_URL API_HOST API_PORT"
  [traefik]="PUBLIC_HOST"
)

# Project name: let docker compose decide it from .env's COMPOSE_PROJECT_NAME (or the repo
# directory). Never force a default here — it would override the compose `name:` and make
# every `dc ps` / health lookup miss.
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
# nest them UNDER a step() header. step()/hr() are never indented.
say()  { printf '%s%s\n' "${LOG_INDENT:-}" "$*"; }
step() { printf '%s▸%s %s\n' "$C_CYN" "$C_RESET" "$*"; }
ok()   { printf '%s%s✓%s %s\n' "${LOG_INDENT:-}" "$C_GRN" "$C_RESET" "$*"; }
warn() { printf '%s%s!%s %s\n' "${LOG_INDENT:-}" "$C_YEL" "$C_RESET" "$*" >&2; }
err()  { printf '%s%s✗%s %s\n' "${LOG_INDENT:-}" "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }
section() { printf '%s%s%s\n' "$C_B" "$*" "$C_RESET"; hr; }   # bold title + rule line
# row <name> <desc> [width] — two-column help row padded by DISPLAY width (char count,
# UTF-8-aware via ${#n}), so multibyte glyphs (…, ·) don't throw off alignment.
row()  { local n="$1" d="$2" w="${3:-36}" pad; pad=$(( w - ${#n} )); (( pad < 1 )) && pad=1
         printf '  %s%*s%s\n' "$n" "$pad" '' "$d"; }

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
"Tip: run \`docker compose $1 --help\` for all native flags."
}

# ── docker compose ──
# Every call is anchored at the repo root. `dc` = the whole stack (base), `dc_db` = engines only.
dc()    { docker compose --project-directory "$CTL_ROOT" -f "$BASE" "$@"; }
dc_db() { docker compose --project-directory "$CTL_ROOT" -f "$DB_FILE" "$@"; }
# auto-discovery — no hard-coded list. compose.m.<name>.yaml = modifier <name>.
list_modifiers() { local f b; for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.m.}; printf '%s\n' "${b%.yaml}"; done; }
join_sp() { paste -sd' ' - 2>/dev/null || tr '\n' ' '; }   # newline list → space-joined
# echo stdin unchanged, or a dim "(none)" when it's empty — so lists never render as a dangling label.
or_none() { local raw; raw=$(cat); raw="${raw%"${raw##*[![:space:]]}"}"
            [[ -n $raw ]] && printf '%s' "$raw" || printf '%s(none)%s' "$C_DIM" "$C_RESET"; }
# compose_files <mod…> — print the -f list for `ctl up`: base first, then one file per modifier.
compose_files() { printf '%s\n' "$BASE"; local m; for m in "$@"; do printf '%s/compose.m.%s.yaml\n' "$DOCKER_DIR" "$m"; done; }
# check_modifier_env <mod> — die when a key the modifier maps is blank in .env (see MODIFIER_REQUIRES).
check_modifier_env() {
  local m="$1" k blank=()
  for k in ${MODIFIER_REQUIRES[$m]:-}; do [[ -n "${!k:-}" ]] || blank+=("$k"); done
  (( ${#blank[@]} )) && die "modifier '+$m' needs these keys set in .env: ${blank[*]}"
  return 0
}

# ── guards ──
# load_env_file [file] — export KEY=value pairs from an env file WITHOUT clobbering variables
# already set in the real environment (skip-if-set). `set -a; source .env` would override
# inline runs (`API_PORT=8085 ctl dev`), CI-injected secrets, and secret-store injection.
# Plain KEY=value lines only — no multi-line values, no command substitution; quotes are kept
# literally, so write values unquoted. Composed values (${A}:${B}) stay literal here; compose
# expands them itself, and the config loaders expand them in the apps.
load_env_file() {
  local f="${1:-.env}" k v
  [[ -f $f ]] || return 0
  while IFS='=' read -r k v || [[ -n $k ]]; do      # `|| [[ -n $k ]]`: keep a last line with no newline
    [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue  # skip blanks, comments, malformed keys
    v="${v%$'\r'}"; v="${v%%[[:space:]]#*}"           # tolerate CRLF; strip a trailing " # comment"
    v="${v%"${v##*[![:space:]]}"}"
    [[ -v $k ]] || export "$k=$v"                     # never overwrite a set var
  done < "$f"
}
require_env() {
  # STRICT (data core ⇒ real secrets): die if .env is missing.
  # [ADAPT] SOFT (defaulted env, no secrets): replace the `die` line with `return 0`.
  [[ -f .env ]] || die ".env missing — run \`ctl setup\` (or cp .env.example .env)."
  load_env_file .env
}
require_tools() {  # require_tools mise docker …
  local t missing=()
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} )) && die "missing on PATH: ${missing[*]} (run: mise install)"
  return 0
}
require_docker() { require_tools docker; docker info >/dev/null 2>&1 || die "docker daemon not reachable"; }

# ── container health ──
tool_version() { command -v "$1" >/dev/null 2>&1 || return 1; case "$1" in go) go version;; *) "$1" --version;; esac 2>/dev/null | head -1 | tr -d '\n'; }
cname()      { printf '%s-%s' "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}" "$1"; }
svc_health() {  # resolve the REAL container, then read its health/status
  local id s
  id=$(dc ps -aq "$1" 2>/dev/null | head -1)
  [[ -n $id ]] || id="$(cname "$1")"
  # docker inspect can exit 0 with empty output for a missing container (WSL2) — treat empty as down.
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
wait_healthy() {  # wait_healthy <svc…> [timeout-seconds] — bounded poll of the container healthchecks
  local svcs=("$@") timeout=60 last
  last=$(( ${#svcs[@]} - 1 ))
  if [[ "${svcs[last]:-}" =~ ^[0-9]+$ ]]; then timeout="${svcs[last]}"; unset 'svcs[last]'; svcs=("${svcs[@]}"); fi
  (( ${#svcs[@]} )) || return 0
  local elapsed=0 s all
  while (( elapsed < timeout )); do
    all=1; for s in "${svcs[@]}"; do [[ "$(svc_health "$s")" =~ ^(healthy|running)$ ]] || { all=0; break; }; done
    (( all )) && { ok "healthy: ${svcs[*]}"; return 0; }
    sleep 2; elapsed=$(( elapsed + 2 ))
  done
  err "not healthy within ${timeout}s: ${svcs[*]}"; return 1
}

# ── host processes ──
# [ADAPT] ports offered by `ctl build start`'s picker and scanned by `ctl ps` as the build plane.
read -r -a PORT_PRESETS <<< "${PORT_PRESETS:-5380 5381 5382 4173}" || true
# port_pid <port> — PID listening on TCP <port> (ss, then lsof); empty if none.
port_pid() {
  local p="$1" pid=""
  command -v ss >/dev/null 2>&1 && pid=$(ss -tlnp 2>/dev/null | awk -v p=":$p" '$4 ~ p"$"' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
  [[ -z $pid ]] && command -v lsof >/dev/null 2>&1 && pid=$(lsof -tiTCP:"$p" -sTCP:LISTEN 2>/dev/null | head -1)
  printf '%s' "$pid"
}
# detach_run <name> <dir> <cmd…> — background a host process: output → data/logs/<name>.log,
# PID → data/run/<name>.pid. The pidfile is what lets `ctl ps` re-attach (a) and stop (k) it.
#   • `&` binds to the nohup command ALONE — backgrounding a compound forks a wrapper that keeps
#     the caller's stdout open, so any pipe around ctl never sees EOF.
#   • </dev/null — without it the daemon inherits the caller's stdin.
detach_run() {
  local name="$1" dir="$2"; shift 2
  mkdir -p "$CTL_ROOT/data/logs" "$CTL_ROOT/data/run"
  (
    cd "$dir" || exit 1
    nohup "$@" < /dev/null >> "$CTL_ROOT/data/logs/$name.log" 2>&1 &
    echo $! > "$CTL_ROOT/data/run/$name.pid"
  )
  ok "$name detached (pid $(cat "$CTL_ROOT/data/run/$name.pid")) — log: data/logs/$name.log"
}

# ── env schema (used by ctl status and ctl check) ──
env_keys() { local k; while IFS='=' read -r k _; do [[ -z "$k" || "$k" == \#* ]] || printf '%s\n' "$k"; done < "$1"; }
check_env_schema() {  # 0 if .env has every key .env.example declares
  [[ -f .env && -f .env.example ]] || { err "need both .env and .env.example (run ctl setup)"; return 1; }
  local k; declare -A have=()
  while IFS= read -r k; do have["$k"]=1; done < <(env_keys .env)
  local missing=()
  while IFS= read -r k; do [[ -v have[$k] ]] || missing+=("$k"); done < <(env_keys .env.example)
  if (( ${#missing[@]} )); then err ".env missing keys: ${missing[*]}"; return 1; fi
  ok ".env matches .env.example schema"; return 0
}

# ── prompts ──
confirm() { local a; printf '%s?%s %s [y/N] ' "$C_YEL" "$C_RESET" "$*"; read -r a; [[ "${a,,}" == y || "${a,,}" == yes ]]; }
# split a comma-list into the global array __SPLIT (trims whitespace, drops blanks)
split_csv() { __SPLIT=(); local raw tok s; IFS=',' read -r -a raw <<< "$1"
  for tok in "${raw[@]}"; do s="${tok#"${tok%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; [[ -n $s ]] && __SPLIT+=("$s"); done; }
