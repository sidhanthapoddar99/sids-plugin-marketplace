#!/usr/bin/env bash
# scripts/common/_lib.sh — shared foundation for `ctl` and every scripts/*.sh worker.
# SOURCE this, do not execute it. It provides: colored, indent-aware logging, a uniform
# --help renderer, docker compose helpers + modifier discovery, env/tool guards,
# container health, host-process helpers, and prompts. Keeping it here is what lets
# each worker stay short and look identical.
#
# Workers live at `scripts/<group>/<name>.sh`, group ∈ common | config | dev | container | db | admin | test | gate.
# Add a worker with the preamble below, then wire one `run <group>/<name>` line into `ctl`.
#
# COMPOSE MODEL (a config + stackable modifiers + a service subset; no profiles, no override file):
#   docker/compose.<name>.yaml     a CONFIG: one stack shape, discovered by filename → `ctl up --config <name>`
#       base   the whole stack (includes the db file); the default; NO ports — this is prod
#       db     the data engines alone; what `ctl dev` runs with +expose_db
#       dev    the nginx dev proxy on the host network             → `ctl dev --proxy`
#   docker/compose.m.<name>.yaml   a MODIFIER: an overlay on a config      → `ctl up +<name>`
#   docker/presets.yaml            named `ctl up` argument lines           → `ctl up preset <name>`
#   include:                       how one config borrows another file (base includes db)
# A config never publishes a port; only a modifier does (ctl check proves it). Which modifiers fit a
# config is computed, not declared: `docker compose config` on the pair must pass.
# Every compose call passes --project-directory "$CTL_ROOT", so every relative path in the
# root .env and in every compose file resolves from the repo root (compose files say ./apps/…,
# ./data, never ../).
#
# ENV MODEL — one ignored root .env and one committed .env.template, grouped by kind.
# ctl loads skip-if-set, then hands the environment to child processes. A frontend dev server
# inherits it too; browser constants must be selected explicitly. Compose receives --env-file
# for interpolation, while each service declares its runtime keys and public build args.
#
# The [ADAPT] knobs, all inline below:
#   • DATA_SVCS           — the data core; empty = no data core (dev/up/status/setup skip it)
#   • app_names/app_port/app_cmd — the host-run apps `ctl dev` knows, in dev/dev.sh
#   • MODIFIER_REQUIRES   — env keys a modifier needs non-blank before `ctl up` accepts it
#   • PORT_PRESETS        — ports offered by `ctl build start`, scanned by `ctl ps`
#
# Worker preamble (copy verbatim at the top of every scripts/<group>/<name>.sh):
#   #!/usr/bin/env bash
#   set -euo pipefail
#   source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# ── repo root — set by ctl before sourcing; else derived from this file ──
: "${CTL_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
DOCKER_DIR="docker"
DEFAULT_CONFIG=base                       # the config `ctl up` runs when --config is not given
BASE="$DOCKER_DIR/compose.$DEFAULT_CONFIG.yaml"   # the passthroughs (down · logs · exec · health) read this file
DEV_FILE="$DOCKER_DIR/compose.dev.yaml"   # the same-origin dev proxy (nginx on the host network)
PRESETS_FILE="$DOCKER_DIR/presets.yaml"   # named `ctl up` argument lines; `ctl up set-preset` writes it
DEFAULT_MODIFIERS=(expose_web)            # what `ctl up` applies on DEFAULT_CONFIG when no +modifier is given; other configs default to none
DEV_PRESET=dev                            # the reserved preset `ctl dev` starts for its data core; missing = ctl dev refuses
ENV_FILES=(.env)   # the root environment contract; template: .env.template

# [ADAPT] the data core. Empty = no data core — every consumer degrades gracefully.
# Overridable from the shell: `DATA_SVCS= ctl dev` (empty is empty, not the default). ctl sources this
# file and then execs a worker, and bash cannot export an array, so the scalar the shell gave is kept
# in *_STR and re-read by the worker. The default is the *_STR line, not the read line.
export DATA_SVCS_STR="${DATA_SVCS_STR-${DATA_SVCS-postgres redis neo4j}}"
read -r -a DATA_SVCS <<< "$DATA_SVCS_STR" || true
# [ADAPT] the schema one-shots in the db config. `ctl dev` waits on them after the engines, because
# nothing in that config depends on them; under `ctl up` the apps do. Empty = no schema step.
export SCHEMA_SVCS_STR="${SCHEMA_SVCS_STR-${SCHEMA_SVCS-migrate neo4j-init}}"
read -r -a SCHEMA_SVCS <<< "$SCHEMA_SVCS_STR" || true

# [ADAPT] env keys a modifier maps with ${VAR} (from .env). `ctl up` refuses
# the modifier when any is blank, and `ctl check` skips validating it and says so —
# an unset ${VAR} in compose becomes an empty string and the service breaks silently.
# +public lists the optional public-origin keys, which ship commented out in .env.template.
declare -A MODIFIER_REQUIRES=(
  [env_override]="DATABASE_URL REDIS_URL NEO4J_URL API_HOST API_PORT ENGINE_HOST ENGINE_PORT DASHBOARD_HOST DASHBOARD_PORT"
  [public]="PUBLIC_URL HTTP_PORT HTTPS_PORT"
  [expose_db]="POSTGRES_PORT REDIS_PORT NEO4J_BOLT_PORT"   # a blank port would publish a random one
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
# Every call is anchored at the repo root and gets the root .env file (compose reads no .env on
# its own). `dc` = the default config (base, the whole stack), `dc_dev` = the dev proxy.
# env_file_args — one --env-file per ENV_FILES entry that exists; a missing file is simply skipped
# here (require_env is the guard that dies). Compose precedence: shell env > --env-file, so an
# exported var (DATA_DIR=… ctl up) still wins over the file. Compose expands ${NAME} only inside
# an --env-file; a value the shell hands it stays as it is, which is why expand_env_refs runs
# before any compose call.
# compose_argv [args…] — the one compose command line, one word per line: project dir, the env
# files, then the args. compose_cmd runs it. up.sh reads it into an array, so the plan can print
# the exact line and `--attach` can exec it. Two callers, one place that builds the line.
env_file_args() { local f; for f in "${ENV_FILES[@]}"; do [[ -f "$CTL_ROOT/$f" ]] || continue; printf -- '--env-file\n%s\n' "$CTL_ROOT/$f"; done; }
compose_argv()  { printf '%s\n' docker compose --project-directory "$CTL_ROOT"; env_file_args; (( $# == 0 )) || printf '%s\n' "$@"; }
compose_cmd()   { resolve_storage_dirs || return; local -a argv; mapfile -t argv < <(compose_argv "$@"); "${argv[@]}"; }
dc()     { compose_cmd -f "$BASE" "$@"; }
dc_dev() { compose_cmd -f "$DEV_FILE" "$@"; }
# auto-discovery — no hard-coded list.
#   compose.<name>.yaml   = config <name>   (a name holds no dot, so compose.m.* is never a config)
#   compose.m.<name>.yaml = modifier <name>
list_configs()   { local f b; for f in "$DOCKER_DIR"/compose.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.}; b=${b%.yaml}; [[ $b == *.* ]] || printf '%s\n' "$b"; done; }
list_modifiers() { local f b; for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.m.}; printf '%s\n' "${b%.yaml}"; done; }
config_file()    { printf '%s/compose.%s.yaml\n' "$DOCKER_DIR" "$1"; }
modifier_file()  { printf '%s/compose.m.%s.yaml\n' "$DOCKER_DIR" "$1"; }
join_sp() { paste -sd' ' - 2>/dev/null || tr '\n' ' '; }   # newline list → space-joined
# echo stdin unchanged, or a dim "(none)" when it's empty — so lists never render as a dangling label.
or_none() { local raw; raw=$(cat); raw="${raw%"${raw##*[![:space:]]}"}"
            [[ -n $raw ]] && printf '%s' "$raw" || printf '%s(none)%s' "$C_DIM" "$C_RESET"; }
# compose_files <config> <mod…> — print the -f list for `ctl up`: the config first, then one file per modifier.
compose_files() { config_file "$1"; shift; local m; for m in "$@"; do modifier_file "$m"; done; }
# modifier_fits <config> <mod> — 0 when compose accepts the pair. Compatibility is computed, never
# declared: a modifier that patches a service the config lacks fails `config`, so it is hidden.
# Needs docker up; the caller guards. One compose call per pair.
modifier_fits()  { compose_cmd -f "$(config_file "$1")" -f "$(modifier_file "$2")" config -q >/dev/null 2>&1; }
# fitting_modifiers <config> — every modifier that fits <config>. A modifier whose MODIFIER_REQUIRES
# keys are blank cannot be tested (a blank ${VAR} may pass or fail config), so it is listed and left
# to check_modifier_env to refuse by name.
fitting_modifiers() { local m; while IFS= read -r m; do [[ -z $m ]] && continue
                        if [[ -n "$(modifier_blank_keys "$m")" ]] || modifier_fits "$1" "$m"; then printf '%s\n' "$m"; fi
                      done < <(list_modifiers); }
# ── presets: docker/presets.yaml, one `<name>: "<ctl up arguments>"` line per preset ──
# The value is the stack shape that follows `ctl up` on the command line (--config, +modifier,
# --services and nothing else), so `ctl up preset <name>` is `ctl up <value>` and needs no second
# parser. Flat map only; comments and blank lines are skipped; CRLF is tolerated. A duplicated name:
# the first line wins on read, list_presets names it once, and set-preset collapses it to one line.
PRESET_LINE='^([A-Za-z0-9_-]+):[[:space:]]*(.*)$'
list_presets() { [[ -f $PRESETS_FILE ]] || return 0
                 local l; declare -A seen=(); while IFS= read -r l || [[ -n $l ]]; do l="${l%$'\r'}"
                   [[ $l =~ $PRESET_LINE && ! -v seen[${BASH_REMATCH[1]}] ]] || continue
                   seen[${BASH_REMATCH[1]}]=1; printf '%s\n' "${BASH_REMATCH[1]}"; done < "$PRESETS_FILE"; }
# preset_args <name> — the stored argument line, unquoted; 1 when absent. A quoted value ends at
# its closing quote, so a `#` inside it is kept; an unquoted value ends at a trailing ` #comment`.
# An empty value is returned empty: the caller decides whether that is an error (`ctl up preset` does).
preset_args()  { [[ -f $PRESETS_FILE ]] || return 1
                 local l v; while IFS= read -r l || [[ -n $l ]]; do l="${l%$'\r'}"
                   [[ $l =~ $PRESET_LINE && ${BASH_REMATCH[1]} == "$1" ]] || continue
                   v="${BASH_REMATCH[2]}"
                   if   [[ $v == \"*\" ]]; then v="${v#\"}"; v="${v%%\"*}"
                   elif [[ $v == \'*  ]]; then v="${v#\'}"; v="${v%%\'*}"
                   else v="${v%%[[:space:]]#*}"; [[ $v == \#* ]] && v=""; v="${v%"${v##*[![:space:]]}"}"; fi
                   printf '%s\n' "$v"; return 0; done < "$PRESETS_FILE"; return 1; }
# modifier_blank_keys <mod> — print each key MODIFIER_REQUIRES maps for <mod> that is blank or unset
# in the loaded env. `ctl up` dies on one (check_modifier_env); `ctl check` skips the combination.
modifier_blank_keys() { local k; for k in ${MODIFIER_REQUIRES[$1]:-}; do [[ -n "${!k:-}" ]] || printf '%s\n' "$k"; done; }
# check_modifier_env <mod> — die when a key the modifier maps is blank in the loaded env.
check_modifier_env() {
  local m="$1" blank; mapfile -t blank < <(modifier_blank_keys "$m")
  (( ${#blank[@]} )) && die "modifier '+$m' needs these keys set in .env (uncomment them if they are): ${blank[*]}"
  return 0
}

# ── guards ──
# load_env_file [file] — export KEY=value pairs from an env file WITHOUT clobbering variables
# already set in the real environment (skip-if-set). `set -a; source .env` would override
# inline runs (`API_PORT=8085 ctl dev`), CI-injected secrets, and secret-store injection.
# Plain KEY=value lines only — no multi-line values, no command substitution; quotes are kept
# literally, so write values unquoted. A composed value (BACKUP_DIR=${LOGS_DIR}/backups) is
# exported as written; expand_env_refs resolves it once the root .env file is loaded.
load_env_file() {
  local f="$1" k v
  [[ -f $f ]] || return 0
  while IFS='=' read -r k v || [[ -n $k ]]; do      # `|| [[ -n $k ]]`: keep a last line with no newline
    [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue  # skip blanks, comments, malformed keys
    v="${v%$'\r'}"; v="${v%%[[:space:]]#*}"           # tolerate CRLF; strip a trailing " # comment"
    v="${v%"${v##*[![:space:]]}"}"
    [[ -v $k ]] || export "$k=$v"                     # never overwrite a set var
  done < "$f"
}
# expand_env_refs — resolve ${NAME} inside every key the root .env file declares, after it is loaded.
# Compose keeps a value the shell hands it as it is, and an app loader that
# does not override keeps it too, so an unexpanded `${DATA_DIR}/postgres` reaches compose as a
# volume name and `${POSTGRES_USER}` reaches the app inside DATABASE_URL. Text substitution
# only: no eval, no command substitution, and the replacement is spliced as text, so `&` or `\`
# in a value stays literal. Skip-if-set still holds: the override (`DATA_DIR=/srv ctl up`) is
# what gets expanded into the keys that reference it. A reference to an unset name, or a cycle,
# fails naming the key. Returns 1 so a soft caller can go on; require_env exits.
expand_env_refs() {
  local f src key value ref n
  for f in "${ENV_FILES[@]}"; do
    src="$CTL_ROOT/$f"; [[ -f $src ]] || src="$src.template"; [[ -f $src ]] || continue
    while IFS= read -r key; do
      [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -v $key ]] || continue
      value="${!key}"; n=0
      while [[ $value =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        ref="${BASH_REMATCH[1]}"
        [[ -v $ref ]] || { err "$f: $key references \${$ref}, which is not set"; return 1; }
        (( n++ < 32 )) || { err "$f: $key does not resolve — a cycle, or more than 32 references"; return 1; }
        value="${value%%"\${$ref}"*}${!ref}${value#*"\${$ref}"}"
      done
      export "$key=$value"
    done < <(env_keys "$src")
  done
}
require_env() {
  # STRICT (data core ⇒ real secrets): die naming the first missing env file.
  # [ADAPT] SOFT (defaulted env, no secrets): replace the `die` line with `continue`.
  local f
  for f in "${ENV_FILES[@]}"; do
    [[ -f $f ]] || die "$f missing — run \`ctl setup\` (it copies $f.template)."
    load_env_file "$f"
  done
  expand_env_refs || exit 1
}
load_env_files() { local f; for f in "${ENV_FILES[@]}"; do load_env_file "$f"; done; }   # skip-if-set; a missing file is skipped
load_env_soft()  { load_env_files; expand_env_refs || true; }                              # diagnostics: never die
# docker_state — one word on stdout: ok · missing · stopped · no-compose. Never dies; `ctl status`
# reads it too. The three failures are different repairs, so they are never one message.
docker_state() {
  command -v docker >/dev/null 2>&1 || { echo missing; return 0; }
  docker info >/dev/null 2>&1        || { echo stopped; return 0; }
  docker compose version >/dev/null 2>&1 || { echo no-compose; return 0; }
  echo ok
}
# require_docker — die by NAME on the first thing wrong. Call it BEFORE the first compose call:
# compose reports a dead daemon as a config error, and "invalid modifier combination" is the
# wrong message for "the engine is not running".
require_docker() {
  case "$(docker_state)" in
    ok)         return 0 ;;
    missing)    die "docker is not installed — install Docker Engine (or Docker Desktop), then re-run" ;;
    stopped)    die "docker engine is not running — start it (systemctl start docker · open Docker Desktop · on WSL2: check the integration), then re-run" ;;
    no-compose) die "docker compose plugin missing — install docker-compose-plugin ≥ 2.24 (docker compose version)" ;;
  esac
}

# ── container health ──
tool_version() { command -v "$1" >/dev/null 2>&1 || return 1; case "$1" in go) go version;; *) "$1" --version;; esac 2>/dev/null | head -1 | tr -d '\n'; }
cname()      { printf '%s-%s' "${COMPOSE_PROJECT_NAME:-$(basename "$CTL_ROOT")}" "$1"; }
svc_health() {  # resolve the REAL container, then read its health/status
  local id s
  id=$(dc ps -aq "$1" 2>/dev/null | head -1) || { echo down; return 0; }
  [[ -n $id ]] || { echo down; return 0; }
  # docker inspect can exit 0 with empty output for a missing container (WSL2) — treat empty as down.
  s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null) || { echo down; return 0; }
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
# ── env schema (used by ctl status and ctl check) ──
# env_keys <file> — every KEY of a KEY=value line, the same lines load_env_file loads: a key starts
# at column 0. An indented line is a continuation comment, never a key, whatever it holds.
env_keys() { local k; while IFS='=' read -r k _; do [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && printf '%s\n' "$k"; done < "$1"; }
check_env_schema() {  # 0 if .env has every key .env.template declares
  local f rc=0 k
  for f in "${ENV_FILES[@]}"; do
    [[ -f $f.template ]] || { err "$f.template missing"; rc=1; continue; }
    [[ -f $f ]] || { err "$f missing (run ctl setup)"; rc=1; continue; }
    declare -A have=(); local missing=()
    while IFS= read -r k; do have["$k"]=1; done < <(env_keys "$f")
    while IFS= read -r k; do [[ -v have[$k] ]] || missing+=("$k"); done < <(env_keys "$f.template")
    if (( ${#missing[@]} )); then err "$f missing keys: ${missing[*]}"; rc=1; else ok "$f matches its template"; fi
    unset have
  done
  return $rc
}

# ── prompts ──
confirm() { local a; printf '%s?%s %s [y/N] ' "$C_YEL" "$C_RESET" "$*"; read -r a; [[ "${a,,}" == y || "${a,,}" == yes ]]; }
# split a comma-list into the global array __SPLIT (trims whitespace, drops blanks)
split_csv() { __SPLIT=(); local raw tok s; IFS=',' read -r -a raw <<< "$1"
  for tok in "${raw[@]}"; do s="${tok#"${tok%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; [[ -n $s ]] && __SPLIT+=("$s"); done; }

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_tools.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_process.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../config/_discovery.sh"
