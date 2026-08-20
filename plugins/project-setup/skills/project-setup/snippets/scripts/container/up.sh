#!/usr/bin/env bash
# container/up.sh — `ctl up`. Two-axis, profile-less (the general structure):
#   config    — single, optional, STANDALONE: a chosen config REPLACES the base file
#               (`compose.<name>.yaml` alone). Omit = base (compose.base.yaml = the whole stack).
#   modifiers — multi, optional: cross-cutting overlays (compose.m.<name>.yaml), empty = none.
#
# Grammar:  ctl up [config] --modifier "a,b"  (also --modifier=a,b)  [-a] [--nqa] [-y] [--dry-run] [--list]
#
# Bare `ctl up` in a terminal is interactive (dependency-free TUI from _select.sh):
#   pick config (single) → pick modifiers (multi) → see a plan → confirm (Run/Back/Cancel).
# Any axis given on the CLI is used as-is; any omitted axis is prompted (when interactive).
#   --nqa  no prompts   ·   -y  skip the confirm   ·   --dry-run  plan only   ·   -a  foreground
#
# A config named `<x>` auto-uses `.env.<x>` if present (e.g. prod → .env.prod). No project
# specifics live here.
#
# [ADAPT] config semantics — STANDALONE by default (replaces base). To make configs OVERLAYS
# instead (base + config, the prod-as-overlay model), change the one assembly line marked below
# to:  files=("$BASE" "$DOCKER_DIR/compose.$config.yaml")
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "up" "Assemble + start the container stack (interactive, or flag-driven)." \
  'up [config] [--modifier "a,b"] [-a] [--nqa] [-y] [--dry-run] [--list] [-h]' \
"Arguments
  config              optional standalone scenario, replaces base: $(list_configs   | join_sp | or_none)(omit = base)
  --modifier <csv>    cross-cutting overlays (comma-list):          $(list_modifiers | join_sp | or_none)
  -a, --attach        run in the FOREGROUND (stream logs, Ctrl-C stops); default is detached (-d)
  --nqa               no questions — don't prompt; use flags/defaults
  -y, --yes           skip the final confirmation
  --dry-run, -n       show the plan and exit without running
  --list              just list the discovered configs + modifiers, then exit
  -h, --help          show this help

A config REPLACES the base compose file (standalone scenario); modifiers overlay on
whichever you choose. Bare 'ctl up' walks config → modifiers → plan → confirm." \
"Example:  ctl up --modifier=expose
          ctl up data --modifier=expose -y
          ctl up --attach            # foreground; watch logs, Ctrl-C to stop"; }

is_help "${1:-}" && { usage; exit 0; }
require_env

# ── parse ──
config="" config_set=0 mod_csv="" mod_set=0 nqa=0 yes=0 dry=0 attach=0 list=0
while (( $# )); do case "$1" in
  --nqa|--no-questions-asked) nqa=1; shift ;;
  -y|--yes)      yes=1; shift ;;
  -a|--attach|--no-detach) attach=1; shift ;;
  --list)        list=1; shift ;;
  --dry-run|-n)  dry=1; shift ;;
  --modifier=*)  mod_csv="${mod_csv:+$mod_csv,}${1#*=}"; mod_set=1; shift ;;
  --modifier)    mod_csv="${mod_csv:+$mod_csv,}${2:-}"; mod_set=1; shift 2 ;;
  -h|--help)     usage; exit 0 ;;
  --*)           die "unknown flag: $1 (try ctl up --help)" ;;
  *)             (( config_set )) && die "only one config per run (got '$config' and '$1')"; config="$1"; config_set=1; shift ;;
esac; done

# --list — discovery as vertical bulleted lists, then exit (no assembly, no prompts)
if (( list )); then
  bullets() {  # bullets <header> <dim-note>  <- newline-separated items on stdin
    printf '%s%s%s' "$C_B" "$1" "$C_RESET"; [[ -n $2 ]] && printf '   %s%s%s' "$C_DIM" "$2" "$C_RESET"; printf '\n'
    local item any=0
    while IFS= read -r item; do [[ -z $item ]] && continue
      printf '  %s-%s %s\n' "$C_DIM" "$C_RESET" "$item"; any=1; done
    (( any )) || printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"
  }
  list_configs   | bullets "configs"   "(omit = base = whole stack)"
  printf '\n'
  list_modifiers | bullets "modifiers" ""
  exit 0
fi

interactive=0; [[ -t 1 && -r /dev/tty && $nqa -eq 0 ]] && interactive=1
mapfile -t CONFIGS   < <(list_configs)
mapfile -t MODIFIERS < <(list_modifiers)
BASE_LABEL="base (whole stack)"

# render the resolved plan (no profiles → every service in the chosen files runs)
render_plan() {
  hr
  printf '%sPlan%s   config=%s   modifiers=[%s]\n' "$C_B" "$C_RESET" "${config:-base}" "$(IFS=,; echo "${modifiers[*]:-}")"
  printf '%scompose%s %s\n\n' "$C_DIM" "$C_RESET" "${files[*]}"
  local json cfg_err
  cfg_err=$("${compose_base[@]}" config -q 2>&1 >/dev/null) || {
    err "this combination is invalid — docker compose rejected it:"
    printf '  %s%s%s\n' "$C_RED" "$cfg_err" "$C_RESET"
    say "  ${C_DIM}(a modifier likely names a service the chosen config doesn't define —" \
        "a whole-stack modifier on a single-slice config can't resolve)${C_RESET}"
    hr; return 1
  }
  if command -v jq >/dev/null 2>&1 && json=$("${compose_base[@]}" config --format json 2>/dev/null); then
    printf '%s  %-9s %-18s %-10s %s%s\n' "$C_DIM" "service" "ports host:ctr" "network" "volumes src:dst" "$C_RESET"
    local svc ports nets vols
    while IFS= read -r svc; do [[ -z $svc ]] && continue
      ports=$(jq -r --arg s "$svc" '.services[$s].ports // [] | map(select(.published)|(.published|tostring)+":"+(.target|tostring)) | join(",")' <<<"$json" 2>/dev/null); [[ -n $ports ]] || ports="-"
      nets=$(jq -r --arg s "$svc" '.services[$s].networks // {} | keys | join(",")' <<<"$json" 2>/dev/null); [[ -n $nets ]] || nets="-"
      vols=$(jq -r --arg s "$svc" '.services[$s].volumes // [] | map((.source // .type)+":"+.target) | join(",")' <<<"$json" 2>/dev/null); [[ -n $vols ]] || vols="-"
      vols="${vols//$CTL_ROOT\//}"
      printf '  %s✓%s %-9s %-18s %-10s %s\n' "$C_GRN" "$C_RESET" "$svc" "$ports" "$nets" "$vols"
    done < <(jq -r '.services|keys[]' <<<"$json" 2>/dev/null | sort)
  else
    warn "jq not installed — service list only"
    "${compose_base[@]}" config --services 2>/dev/null | sed "s/^/  ${C_GRN}✓${C_RESET} /" || true
  fi
  hr
  printf '%sreproduce%s  (no prompts)\n' "$C_B" "$C_RESET"
  printf '  %s%s --nqa%s\n'      "$C_DIM" "$repro" "$C_RESET"
  printf '  %s%s --nqa -y%s\n'   "$C_DIM" "$repro" "$C_RESET"
  printf '  %sdocker:%s %s\n'    "$C_DIM" "$C_RESET" "${docker_cmd[*]}"
  hr
}

# selection → plan → confirm (Back re-opens the selectors)
while true; do
  # config (single, standalone) — prompt only if unset, interactive, and configs exist
  if (( ! config_set )) && (( interactive )) && (( ${#CONFIGS[@]} )); then
    cfg_choice=()
    tui_select --into cfg_choice --header "Configuration — one per run (replaces base)" \
      -- "$BASE_LABEL" "${CONFIGS[@]}" || { say "cancelled."; exit 0; }
    [[ "${cfg_choice[0]:-}" == "$BASE_LABEL" ]] && config="" || config="${cfg_choice[0]:-}"
    printf '\n'
  fi
  [[ -n $config ]] && { printf '%s\n' "${CONFIGS[@]}" | grep -qx "$config" \
    || die "no such config '$config'. configs: $(list_configs | join_sp)"; }

  # modifiers (multi) — prompt only if unset, interactive, and modifiers exist
  modifiers=()
  if (( mod_set )); then split_csv "$mod_csv"; modifiers=("${__SPLIT[@]}")
  elif (( interactive )) && (( ${#MODIFIERS[@]} )); then
    tui_select --into modifiers --multi --header "Modifiers — optional overlays (none = just press Enter)" \
      -- "${MODIFIERS[@]}" || { say "cancelled."; exit 0; }
    printf '\n'
  fi
  for m in "${modifiers[@]}"; do printf '%s\n' "${MODIFIERS[@]}" | grep -qx "$m" \
    || die "no such modifier '$m'. modifiers: $(list_modifiers | join_sp)"; done

  # assemble — config REPLACES base (standalone); modifiers overlay.
  # [ADAPT] overlay model instead: files=("$BASE" "$DOCKER_DIR/compose.$config.yaml")
  if [[ -n $config ]]; then files=("$DOCKER_DIR/compose.$config.yaml"); else files=("$BASE"); fi
  # any config auto-uses a matching .env.<config> if present (e.g. prod → .env.prod)
  envf=(); [[ -n $config && -f ".env.$config" ]] && envf=(--env-file ".env.$config")
  for m in "${modifiers[@]}"; do files+=("$DOCKER_DIR/compose.m.$m.yaml"); done
  compose_base=(docker compose); for f in "${files[@]}"; do compose_base+=(-f "$f"); done
  detach=(-d); (( attach )) && detach=()        # default detached; --attach drops -d (foreground)
  docker_cmd=("${compose_base[@]}" "${envf[@]}" up "${detach[@]}" --build)

  repro="ctl up"; [[ -n $config ]] && repro+=" $config"
  (( ${#modifiers[@]} )) && repro+=" --modifier=$(IFS=,; echo "${modifiers[*]}")"
  (( attach )) && repro+=" --attach"

  plan_ok=1; render_plan || plan_ok=0

  (( dry )) && { (( plan_ok )) && say "(dry-run — nothing started)" || say "(dry-run — invalid, nothing started)"; exit $(( plan_ok ? 0 : 1 )); }
  if (( plan_ok && yes )); then break; fi
  if (( ! interactive )); then
    (( plan_ok )) || die "invalid combination (see above)"
    die "not a TTY and no -y — re-run with -y to execute, or --dry-run to preview"
  fi

  # invalid combo → don't offer Run; valid → full Run/Back/Cancel
  printf '\n'
  action=()
  if (( plan_ok )); then
    tui_select --into action --horizontal --header "Start this stack?" -- Run Back Cancel \
      || { say "cancelled."; exit 0; }
  else
    tui_select --into action --horizontal --header "Invalid combination — go back and re-pick?" -- Back Cancel \
      || { say "cancelled."; exit 0; }
  fi
  case "${action[0]:-Cancel}" in
    Run)  break ;;
    Back) config_set=0; mod_set=0; config=""; mod_csv=""
          printf '\n%s↻ starting over — re-pick config + modifiers%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
    *)    say "cancelled."; exit 0 ;;
  esac
done

step "${docker_cmd[*]}"
if (( attach )); then
  say "${C_DIM}foreground — streaming logs; Ctrl-C stops the stack${C_RESET}"
  exec "${docker_cmd[@]}"        # hand off the TTY so Ctrl-C reaches compose directly
fi
"${docker_cmd[@]}"
ok "stack up  (detached — 'ctl logs -f' to follow, 'ctl down' to stop)"
