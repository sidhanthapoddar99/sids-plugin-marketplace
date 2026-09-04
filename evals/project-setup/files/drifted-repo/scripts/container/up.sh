#!/usr/bin/env bash
# container/up.sh — `ctl up`. One base + stackable modifiers + an optional service subset:
#   base       docker/compose.base.yaml — the whole stack (it includes compose.db.yaml). No ports.
#   modifiers  docker/compose.m.<name>.yaml — cross-cutting overlays, given as `+name` tokens.
#   services   a subset of the assembled stack; default = every service the files define.
#
# Grammar:  ctl up [+mod…] [--modifier a,b] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list]
#
# Bare `ctl up` in a terminal is interactive (dependency-free TUI from _select.sh):
#   pick modifiers (multi, default preselected) → pick services (multi, all preselected)
#   → see a plan → confirm (Run/Back/Cancel).
# Modifiers or services given on the CLI are used as-is and skip their prompt. None given + no
# TTY (or --nqa) = the default (+${DEFAULT_MODIFIERS[*]}, every service). A modifier whose env
# keys are blank is refused (MODIFIER_REQUIRES).
#   --nqa  no prompts   ·   -y  skip the confirm   ·   --dry-run  plan only   ·   -a  foreground
#
# The plan is the real `docker compose config` merge — it validates the combination before
# anything starts, and prints the exact --nqa command that reproduces the run.
#
# The docker guard runs FIRST. Compose reports a dead daemon as a config error, and this file
# once printed "invalid combination" for "docker is not running". require_docker names the
# real fault: not installed · not running · compose plugin missing.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "up" "Assemble + start the container stack (interactive, or flag-driven)." \
  'up [+modifier…] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list] [-h]' \
"Arguments
  +<name>             a modifier to overlay on base — any of: $(list_modifiers | sed 's/^/+/' | join_sp | or_none)
                      (none given: interactive pick in a terminal, else +${DEFAULT_MODIFIERS[*]})
  --modifier <csv>    the same, as a comma-list (alias)
  --services <csv>    start only these services (comma-list). A service's depends_on come with it.
                      (none given: interactive pick in a terminal, else every service)
  -a, --attach        run in the FOREGROUND (stream logs, Ctrl-C stops); default is detached (-d)
  --nqa               no questions — don't prompt; use flags/defaults
  -y, --yes           skip the final confirmation
  --dry-run, -n       show the plan and exit without running
  --list              list the discovered modifiers and the services base defines, then exit
  -h, --help          show this help

Base is docker/compose.base.yaml (the whole stack, includes the data engines). Modifiers add
exposure or re-point services; base itself publishes no ports. Migrations run once, before any
app service starts — never on app boot." \
"Example:  ctl up                                # interactive
          ctl up +expose_web -y                 # prod default, no prompts
          ctl up +expose +env_override          # debug ports, services re-pointed from .env.proxy / .env.secrets
          ctl up --services=api,postgres -y     # one backend and its engine only
          ctl up --attach                       # foreground; watch logs, Ctrl-C to stop"; }

is_help "${1:-}" && { usage; exit 0; }
require_env
require_docker

# ── parse ──
mods_cli=() mod_set=0 svcs_cli=() svc_set=0 nqa=0 yes=0 dry=0 attach=0 list=0
while (( $# )); do case "$1" in
  --nqa|--no-questions-asked) nqa=1; shift ;;
  -y|--yes)      yes=1; shift ;;
  -a|--attach|--no-detach) attach=1; shift ;;
  --list)        list=1; shift ;;
  --dry-run|-n)  dry=1; shift ;;
  --modifier=*)  split_csv "${1#*=}"; mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift ;;
  --modifier)    split_csv "${2:-}";  mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift 2 ;;
  --services=*)  split_csv "${1#*=}"; svcs_cli+=("${__SPLIT[@]}"); svc_set=1; shift ;;
  --services)    split_csv "${2:-}";  svcs_cli+=("${__SPLIT[@]}"); svc_set=1; shift 2 ;;
  +?*)           mods_cli+=("${1#+}"); mod_set=1; shift ;;
  -h|--help)     usage; exit 0 ;;
  *)             die "unknown argument: $1 — modifiers are +name, services are --services a,b (try ctl up --help)" ;;
esac; done
(( svc_set && ${#svcs_cli[@]} == 0 )) && die "--services given but empty — name at least one service, or drop the flag for all"

if (( list )); then
  printf '%smodifiers%s   %s(overlay on base; stackable)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
  any=0; while IFS= read -r m; do [[ -z $m ]] && continue
    printf '  %s+%s%s' "$C_DIM" "$C_RESET" "$m"; [[ -n "${MODIFIER_REQUIRES[$m]:-}" ]] && printf '   %sneeds %s%s' "$C_DIM" "${MODIFIER_REQUIRES[$m]}" "$C_RESET"; printf '\n'; any=1
  done < <(list_modifiers)
  (( any )) || printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"
  printf '\n%sservices%s    %s(what base defines; --services picks a subset)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
  dc config --services 2>/dev/null | sort | sed 's/^/  /' || printf '  %s(compose could not read base)%s\n' "$C_DIM" "$C_RESET"
  exit 0
fi

interactive=0; [[ -t 1 && -r /dev/tty && $nqa -eq 0 ]] && interactive=1
mapfile -t MODIFIERS < <(list_modifiers)

# assembled_services — every service the chosen files define, sorted. Dies when compose rejects
# the file set, so the service picker never opens on an invalid combination.
assembled_services() { "${compose_base[@]}" config --services 2>/dev/null | sort; }

render_plan() {
  hr
  printf '%sPlan%s   modifiers=[%s]   services=[%s]\n' "$C_B" "$C_RESET" \
    "$(IFS=,; echo "${modifiers[*]:-}")" "$( (( ${#services[@]} )) && { IFS=,; echo "${services[*]}"; } || echo all)"
  printf '%scompose%s %s\n\n' "$C_DIM" "$C_RESET" "${files[*]}"
  local json cfg_err
  cfg_err=$("${compose_base[@]}" config -q 2>&1 >/dev/null) || {
    err "this combination is invalid — docker compose rejected it:"
    printf '  %s%s%s\n' "$C_RED" "$cfg_err" "$C_RESET"
    hr; return 1
  }
  local svc_filter='.services|keys[]'
  if command -v jq >/dev/null 2>&1 && json=$("${compose_base[@]}" config --format json 2>/dev/null); then
    printf '%s  %-9s %-18s %-10s %s%s\n' "$C_DIM" "service" "ports host:ctr" "network" "volumes src:dst" "$C_RESET"
    local svc ports nets vols mark
    while IFS= read -r svc; do [[ -z $svc ]] && continue
      ports=$(jq -r --arg s "$svc" '.services[$s].ports // [] | map(select(.published)|(.published|tostring)+":"+(.target|tostring)) | join(",")' <<<"$json" 2>/dev/null); [[ -n $ports ]] || ports="-"
      nets=$(jq -r --arg s "$svc" '.services[$s].networks // {} | keys | join(",")' <<<"$json" 2>/dev/null); [[ -n $nets ]] || nets="-"
      vols=$(jq -r --arg s "$svc" '.services[$s].volumes // [] | map((.source // .type)+":"+.target) | join(",")' <<<"$json" 2>/dev/null); [[ -n $vols ]] || vols="-"
      vols="${vols//$CTL_ROOT\//}"
      # a service outside the subset is listed dim, so the plan still shows the whole file set
      if service_selected "$svc"; then mark="${C_GRN}✓${C_RESET}"; else mark="${C_DIM}·${C_RESET}"; fi
      printf '  %s %-9s %-18s %-10s %s\n' "$mark" "$svc" "$ports" "$nets" "$vols"
    done < <(jq -r "$svc_filter" <<<"$json" 2>/dev/null | sort)
  else
    warn "jq not installed — service list only"
    while IFS= read -r svc; do [[ -z $svc ]] && continue
      if service_selected "$svc"; then printf '  %s✓%s %s\n' "$C_GRN" "$C_RESET" "$svc"; else printf '  %s· %s%s\n' "$C_DIM" "$svc" "$C_RESET"; fi
    done < <(assembled_services)
  fi
  hr
  printf '%sreproduce%s  (no prompts)\n' "$C_B" "$C_RESET"
  printf '  %s%s --nqa%s\n'      "$C_DIM" "$repro" "$C_RESET"
  printf '  %s%s --nqa -y%s\n'   "$C_DIM" "$repro" "$C_RESET"
  printf '  %sdocker:%s %s\n'    "$C_DIM" "$C_RESET" "${docker_cmd[*]}"
  hr
}
# service_selected <svc> — 0 when the subset is empty (= all) or names it
service_selected() { (( ${#services[@]} == 0 )) && return 0; printf '%s\n' "${services[@]}" | grep -qx "$1"; }

# selection → plan → confirm (Back re-opens the selectors)
while true; do
  # ── modifiers ──
  modifiers=()
  if (( mod_set )); then modifiers=("${mods_cli[@]}")
  elif (( interactive )) && (( ${#MODIFIERS[@]} )); then
    tui_select --into modifiers --multi --preselect "$(IFS=,; echo "${DEFAULT_MODIFIERS[*]}")" \
      --header "Modifiers — overlays on base (Space toggles, Enter confirms)" -- "${MODIFIERS[@]}" \
      || { say "cancelled."; exit 0; }
    printf '\n'
  else modifiers=("${DEFAULT_MODIFIERS[@]}"); fi
  for m in "${modifiers[@]}"; do
    printf '%s\n' "${MODIFIERS[@]}" | grep -qx "$m" || die "no such modifier '+$m'. modifiers: $(list_modifiers | sed 's/^/+/' | join_sp)"
    check_modifier_env "$m"
  done

  mapfile -t files < <(compose_files "${modifiers[@]}")
  compose_base=(docker compose --project-directory "$CTL_ROOT"); mapfile -t -O "${#compose_base[@]}" compose_base < <(env_file_args)
  for f in "${files[@]}"; do compose_base+=(-f "$f"); done

  # ── services ── the picker needs the assembled file set, so it comes after the modifiers
  services=()
  if (( svc_set )); then services=("${svcs_cli[@]}")
  elif (( interactive )); then
    mapfile -t ALL_SVCS < <(assembled_services)
    if (( ${#ALL_SVCS[@]} )); then
      tui_select --into services --multi --preselect "$(IFS=,; echo "${ALL_SVCS[*]}")" \
        --header "Services — untick what should stay down (Enter = every ticked one)" -- "${ALL_SVCS[@]}" \
        || { say "cancelled."; exit 0; }
      printf '\n'
      (( ${#services[@]} )) || die "no service selected — nothing to start"
      (( ${#services[@]} == ${#ALL_SVCS[@]} )) && services=()   # everything ticked = all, keeps the repro line short
    fi
  fi
  if (( ${#services[@]} )); then
    mapfile -t ALL_SVCS < <(assembled_services)
    for s in "${services[@]}"; do
      printf '%s\n' "${ALL_SVCS[@]}" | grep -qx "$s" || die "no such service '$s' in this file set. services: $(printf '%s ' "${ALL_SVCS[@]}")"
    done
  fi

  detach=(-d); (( attach )) && detach=()
  docker_cmd=("${compose_base[@]}" up "${detach[@]}" --build "${services[@]}")

  repro="ctl up"; for m in "${modifiers[@]}"; do repro+=" +$m"; done
  (( ${#services[@]} )) && repro+=" --services=$(IFS=,; echo "${services[*]}")"
  (( attach )) && repro+=" --attach"

  plan_ok=1; render_plan || plan_ok=0

  (( dry )) && { (( plan_ok )) && say "(dry-run — nothing started)" || say "(dry-run — invalid, nothing started)"; exit $(( plan_ok ? 0 : 1 )); }
  if (( plan_ok && yes )); then break; fi
  if (( ! interactive )); then
    (( plan_ok )) || die "invalid combination (see above)"
    die "not a TTY and no -y — re-run with -y to execute, or --dry-run to preview"
  fi

  printf '\n'
  action=()
  if (( plan_ok )); then
    tui_select --into action --horizontal --header "Start this stack?" -- Run Back Cancel || { say "cancelled."; exit 0; }
  else
    tui_select --into action --horizontal --header "Invalid combination — go back and re-pick?" -- Back Cancel || { say "cancelled."; exit 0; }
  fi
  case "${action[0]:-Cancel}" in
    Run)  break ;;
    Back) mod_set=0; mods_cli=(); svc_set=0; svcs_cli=(); printf '\n%s↻ starting over — re-pick modifiers and services%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
    *)    say "cancelled."; exit 0 ;;
  esac
done

# ── data core, then migrations, then the apps ──
# Migrations run once, as an explicit step, before any app takes traffic — never on app boot.
# With a subset: the engines come up only when the subset needs them (a selected app, or a
# selected engine); migrations run only when an app is about to start.
core_wanted=() app_wanted=0
if (( ${#DATA_SVCS[@]} )); then
  for s in "${DATA_SVCS[@]}"; do service_selected "$s" && core_wanted+=("$s"); done
  if (( ${#services[@]} == 0 )); then app_wanted=1
  else for s in "${services[@]}"; do printf '%s\n' "${DATA_SVCS[@]}" | grep -qx "$s" || app_wanted=1; done; fi
  (( app_wanted )) && core_wanted=("${DATA_SVCS[@]}")   # an app needs the whole core, whatever was ticked
fi
if (( ${#core_wanted[@]} )); then
  step "data core first: ${core_wanted[*]}"
  "${compose_base[@]}" up -d "${core_wanted[@]}"
  wait_healthy "${core_wanted[@]}" 60 || die "data core not healthy — not starting the apps"
  if (( app_wanted )); then
    step "migrations"
    bash "$CTL_ROOT/scripts/db/migrate.sh" up || die "migrations failed — not starting the apps"
  fi
fi

step "${docker_cmd[*]}"
if (( attach )); then
  say "${C_DIM}foreground — streaming logs; Ctrl-C stops the stack${C_RESET}"
  exec "${docker_cmd[@]}"
fi
"${docker_cmd[@]}"
ok "stack up  (detached — 'ctl logs -f' to follow, 'ctl down' to stop)"
