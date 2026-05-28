#!/usr/bin/env bash
# ctl — <PROJECT> control plane.  Drop at repo root as `ctl` (no extension), chmod +x.
#
#   ctl dev [target]                      run locally on the host (hot reload); data core auto-started
#   ctl up [profile…] [--config=prod] [--<modifier>…]   run container stack (bare = no-profile data core)
#   ctl down [svc] | ps | logs | restart                 container lifecycle
#   ctl setup | status | migrate | test | build | clean | help
#
# THIN WRAPPER: `ctl` owns arg routing + the compose assembly (profiles + one config + .m. modifiers)
# + trivial `docker compose` passthroughs. Every command with a real body lives in scripts/<cmd>.sh,
# self-contained and runnable on its own. Add a worker → add a file; no edits here.
#
# dev = host loop; up = docker. Profiles select services; one --config=<name> swaps the deployment
# config; --<modifier> flags layer compose.m.<modifier>.yaml overlays (stack freely).
# No `ctl prod` verb — production is `ctl up app edge --config=prod`.  Migrations are `ctl migrate`.

set -euo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ── helpers ───────────────────────────────────────────────
c_info()  { printf '\033[36m▸\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[33m!\033[0m %s\n' "$*" >&2; }
die()     { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

DOCKER_DIR="docker"; BASE="$DOCKER_DIR/compose.yaml"
DATA_SVCS=(postgres redis)               # the no-profile data core dev depends on
compose() { docker compose -f "$BASE" "$@"; }

# discovery — no hard-coded lists (assumes inline `profiles: [app]` form). compose.m.* = modifiers,
# the rest (minus the base) = configs.
list_profiles()  { grep -hoE 'profiles:[[:space:]]*\[[^]]+\]' "$BASE" \
                     | grep -oE '[A-Za-z0-9_-]+' | grep -vx profiles | sort -u; }
list_configs()   { for f in "$DOCKER_DIR"/compose.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/}; [[ $b == compose.yaml || $b == compose.m.* ]] && continue
                     b=${b#compose.}; echo "${b%.yaml}"; done; }
list_modifiers() { for f in "$DOCKER_DIR"/compose.m.*.yaml; do [[ -e $f ]] || continue
                     b=${f##*/compose.m.}; echo "${b%.yaml}"; done; }

require_env() {
  [[ -f .env ]] || die ".env missing — run \`ctl setup\` (or cp .env.example .env)."
  set -a; # shellcheck disable=SC1091
  source .env; set +a
}
require_tools() {
  local missing=()
  for t in mise docker; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
  (( ${#missing[@]} )) && die "missing on PATH: ${missing[*]} — install mise then \`mise install\`."
}

# ── ctl up: profiles + one --config + stacked --<modifier> overlays ─────────
cmd_up() {
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { up_help; return; }
  require_env
  local profiles=() config="" modifiers=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config=*) [[ -z $config ]] || die "one --config at a time"; config="${1#--config=}"; shift ;;
      --config)   [[ -z $config ]] || die "one --config at a time"; config="${2:-}"; shift 2 ;;
      --*)        modifiers+=("${1#--}"); shift ;;          # --expose → modifier 'expose'
      -*)         die "unknown flag: $1 (try ctl up --help)" ;;
      *)          profiles+=("$1"); shift ;;
    esac
  done
  local files=("$BASE") prof_args=() env_args=()
  if [[ -n $config ]]; then                                # base + config first
    local cf="$DOCKER_DIR/compose.$config.yaml"
    [[ -f $cf ]] || die "no such config '$config'. configs: $(list_configs | tr '\n' ' ')"
    files+=("$cf")
    [[ $config == prod && -f .env.production ]] && env_args=(--env-file .env.production)
  fi
  local m mf
  for m in "${modifiers[@]}"; do                           # modifiers stack last (they win)
    mf="$DOCKER_DIR/compose.m.$m.yaml"
    [[ -f $mf ]] || die "no such modifier '$m'. modifiers: $(list_modifiers | tr '\n' ' ')"
    files+=("$mf")
  done
  local p
  for p in "${profiles[@]}"; do
    list_profiles | grep -qx "$p" || die "no such profile '$p'. profiles: $(list_profiles | tr '\n' ' ')"
    prof_args+=(--profile "$p")
  done
  local cmd=(docker compose) f; for f in "${files[@]}"; do cmd+=(-f "$f"); done
  cmd+=("${prof_args[@]}" "${env_args[@]}" up -d)
  c_info "${cmd[*]}"; "${cmd[@]}"                           # echo composed cmd, then run
}
up_help() {
  echo "ctl up [profile…] [--config=<name>] [--<modifier>…]"
  echo "  profiles  (which services; combine freely):"; for p in $(list_profiles);  do echo "    $p"; done
  echo "  config    (one alternate deployment config):"; for c in $(list_configs);   do echo "    --config=$c"; done
  echo "  modifiers (cross-cutting; stack freely):";      for m in $(list_modifiers); do echo "    --$m"; done
}

# ── ctl dev: ensure data core, then process-compose (or the bash fallback worker) ─
cmd_dev() {
  require_env; require_tools
  c_info "ensuring data core (with ports)…"
  docker compose -f "$BASE" -f "$DOCKER_DIR/compose.m.expose.yaml" up -d "${DATA_SVCS[@]}"
  bash scripts/wait-for-health.sh "${DATA_SVCS[@]}" 60 || c_warn "health poll skipped/failed."
  if command -v process-compose >/dev/null 2>&1 && [[ -f process-compose.yaml ]]; then
    exec process-compose up "$@"
  fi
  exec bash scripts/dev-host.sh "$@"     # bash fallback (≤2 procs; prefer process-compose past that)
}

cmd_ps() {
  compose ps
  command -v process-compose >/dev/null 2>&1 && process-compose process list 2>/dev/null || true
}

# real-body commands live in scripts/<cmd>.sh — ctl just routes
run_script() { local s="scripts/$1.sh"; shift; [[ -f $s ]] || die "missing $s (ship it in scripts/)."; exec bash "$s" "$@"; }

cmd_help() {
  cat <<'EOF'
ctl — <PROJECT> control plane
  ctl dev [target]                                   host loop (hot reload); data core auto-started
  ctl up [profile…] [--config=prod] [--<modifier>…]  container stack; ctl up --help for the lists
  ctl down [svc] | ps | logs [svc] [-f] | restart    container lifecycle
  ctl setup            interactive .env wizard            (scripts/setup.sh)
  ctl status [svc]     config doctor                      (scripts/status.sh)
  ctl migrate {up|down|new "<msg>"|status}               (scripts/migrate.sh)
  ctl test | build | clean                               (scripts/{test,build,clean}.sh)
EOF
}

# ── dispatch ──────────────────────────────────────────────
main() {
  case "${1:-help}" in
    dev)            shift; cmd_dev "$@" ;;
    up)             shift; cmd_up "$@" ;;
    down)           shift; compose down "$@" ;;
    restart)        shift; compose restart "$@" ;;
    logs)           shift; compose logs "$@" ;;
    ps)             cmd_ps ;;
    setup|status|migrate|test|build|clean) local c="$1"; shift; run_script "$c" "$@" ;;
    help|-h|--help) cmd_help ;;
    *)              die "unknown command: ${1:-}. Try ctl help" ;;
  esac
}
main "$@"
