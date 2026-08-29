#!/usr/bin/env bash
# container/up.sh — `ctl up`. One base + stackable modifiers, no profiles:
#   base       docker/compose.base.yaml — the whole stack (it includes compose.db.yaml). No ports.
#   modifiers  docker/compose.m.<name>.yaml — cross-cutting overlays, given as `+name` tokens.
#
# Grammar:  ctl up [+mod…] [--modifier a,b] [-a] [--nqa] [-y] [--dry-run] [--list]
#
# Bare `ctl up` in a terminal is interactive (dependency-free TUI from _select.sh):
#   pick modifiers (multi, default preselected) → see a plan → confirm (Run/Back/Cancel).
# Modifiers given on the CLI are used as-is. None given + no TTY (or --nqa) = the default
# (+${DEFAULT_MODIFIERS[*]}). A modifier whose env keys are blank is refused (MODIFIER_REQUIRES).
#   --nqa  no prompts   ·   -y  skip the confirm   ·   --dry-run  plan only   ·   -a  foreground
#
# The plan is the real `docker compose config` merge — it validates the combination before
# anything starts, and prints the exact --nqa command that reproduces the run.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "up" "Assemble + start the container stack (interactive, or flag-driven)." \
  'up [+modifier…] [-a] [--nqa] [-y] [--dry-run] [--list] [-h]' \
"Arguments
  +<name>             a modifier to overlay on base — any of: $(list_modifiers | sed 's/^/+/' | join_sp | or_none)
                      (none given: interactive pick in a terminal, else +${DEFAULT_MODIFIERS[*]})
  --modifier <csv>    the same, as a comma-list (alias)
  -a, --attach        run in the FOREGROUND (stream logs, Ctrl-C stops); default is detached (-d)
  --nqa               no questions — don't prompt; use flags/defaults
  -y, --yes           skip the final confirmation
  --dry-run, -n       show the plan and exit without running
  --list              just list the discovered modifiers, then exit
  -h, --help          show this help

Base is docker/compose.base.yaml (the whole stack, includes the data engines). Modifiers add
exposure or re-point services; base itself publishes no ports." \
"Example:  ctl up                        # interactive
          ctl up +expose_web -y         # prod default, no prompts
          ctl up +expose +env_override  # debug ports, services re-pointed from .env.proxy / .env.secrets
          ctl up --attach               # foreground; watch logs, Ctrl-C to stop"; }

is_help "${1:-}" && { usage; exit 0; }
require_env

# ── parse ──
mods_cli=() mod_set=0 nqa=0 yes=0 dry=0 attach=0 list=0
while (( $# )); do case "$1" in
  --nqa|--no-questions-asked) nqa=1; shift ;;
  -y|--yes)      yes=1; shift ;;
  -a|--attach|--no-detach) attach=1; shift ;;
  --list)        list=1; shift ;;
  --dry-run|-n)  dry=1; shift ;;
  --modifier=*)  split_csv "${1#*=}"; mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift ;;
  --modifier)    split_csv "${2:-}";  mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift 2 ;;
  +?*)           mods_cli+=("${1#+}"); mod_set=1; shift ;;
  -h|--help)     usage; exit 0 ;;
  *)             die "unknown argument: $1 — modifiers are +name (try ctl up --help)" ;;
esac; done

if (( list )); then
  printf '%smodifiers%s   %s(overlay on base; stackable)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
  any=0; while IFS= read -r m; do [[ -z $m ]] && continue
    printf '  %s+%s%s' "$C_DIM" "$C_RESET" "$m"; [[ -n "${MODIFIER_REQUIRES[$m]:-}" ]] && printf '   %sneeds %s%s' "$C_DIM" "${MODIFIER_REQUIRES[$m]}" "$C_RESET"; printf '\n'; any=1
  done < <(list_modifiers)
  (( any )) || printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"
  exit 0
fi

interactive=0; [[ -t 1 && -r /dev/tty && $nqa -eq 0 ]] && interactive=1
mapfile -t MODIFIERS < <(list_modifiers)

render_plan() {
  hr
  printf '%sPlan%s   modifiers=[%s]\n' "$C_B" "$C_RESET" "$(IFS=,; echo "${modifiers[*]:-}")"
  printf '%scompose%s %s\n\n' "$C_DIM" "$C_RESET" "${files[*]}"
  local json cfg_err
  cfg_err=$("${compose_base[@]}" config -q 2>&1 >/dev/null) || {
    err "this combination is invalid — docker compose rejected it:"
    printf '  %s%s%s\n' "$C_RED" "$cfg_err" "$C_RESET"
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

# selection → plan → confirm (Back re-opens the selector)
while true; do
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
  compose_base=(docker compose --project-directory "$CTL_ROOT"); for f in "${files[@]}"; do compose_base+=(-f "$f"); done
  detach=(-d); (( attach )) && detach=()
  docker_cmd=("${compose_base[@]}" up "${detach[@]}" --build)

  repro="ctl up"; for m in "${modifiers[@]}"; do repro+=" +$m"; done
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
    Back) mod_set=0; mods_cli=(); printf '\n%s↻ starting over — re-pick modifiers%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
    *)    say "cancelled."; exit 0 ;;
  esac
done

# migrations run once, as an explicit step, before the apps take traffic — never on app boot.
if (( ${#DATA_SVCS[@]} )); then
  step "data core first, then migrations"
  "${compose_base[@]}" up -d "${DATA_SVCS[@]}"
  wait_healthy "${DATA_SVCS[@]}" 60 || die "data core not healthy — not starting the apps"
  bash "$CTL_ROOT/scripts/db/migrate.sh" up || die "migrations failed — not starting the apps"
fi

step "${docker_cmd[*]}"
if (( attach )); then
  say "${C_DIM}foreground — streaming logs; Ctrl-C stops the stack${C_RESET}"
  exec "${docker_cmd[@]}"
fi
"${docker_cmd[@]}"
ok "stack up  (detached — 'ctl logs -f' to follow, 'ctl down' to stop)"
