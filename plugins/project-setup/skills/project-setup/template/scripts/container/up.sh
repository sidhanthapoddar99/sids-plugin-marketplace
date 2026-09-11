#!/usr/bin/env bash
# container/up.sh — `ctl up`. One config + stackable modifiers + an optional service subset:
#   config     docker/compose.<name>.yaml — one stack shape. `base` (the whole stack) is the default.
#   modifiers  docker/compose.m.<name>.yaml — overlays, given as `+name` tokens. Only the ones that
#              fit the chosen config are offered: `docker compose config` on the pair must pass.
#   services   a subset of the assembled stack; default = every service the files define. Only the
#              named services and their depends_on chain are built and started.
#   presets    docker/presets.yaml — a name for one argument line. `preset` runs one, `set-preset` writes one.
#
# Grammar:  ctl up [--config <name>] [+mod…] [--modifier a,b] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list]
#           ctl up preset [<name>] [-a] [-y] [--nqa] [--dry-run]     ·  ctl up preset --list
#           ctl up set-preset [<name>] [--config <name>] [+mod…] [--services a,b] [-y]
#
# Bare `ctl up` in a terminal is interactive (dependency-free TUI from _select.sh):
#   pick a config (single; skipped when only one exists) → pick modifiers (multi, the fitting ones,
#   defaults preselected) → pick services (multi, all preselected) → see a plan → confirm (Run/Back/Cancel).
# Anything given on the CLI is used as-is and skips its prompt. None given + no TTY (or --nqa) = the
# default (base, +${DEFAULT_MODIFIERS[*]} where it fits, every service). A modifier whose env keys are
# blank is refused (MODIFIER_REQUIRES).
#   --nqa  no prompts   ·   -y  skip the confirm   ·   --dry-run  plan only   ·   -a  foreground
#
# `preset <name>` is `ctl up <stored line>` with every prompt skipped: it goes straight to the plan.
# `set-preset` walks the same pickers and ends on Save / Save and run / Back / Cancel. An existing
# preset's values are preselected, so editing one is re-walking it.
#
# The plan is the real `docker compose config` merge — it validates the combination before
# anything starts, and prints the exact --nqa command that reproduces the run. Start order
# (engines → schema one-shots → apps) is compose's own, from depends_on in the config file.
#
# The docker guard runs FIRST. Compose reports a dead daemon as a config error, and this file
# once printed "invalid combination" for "docker is not running". require_docker names the
# real fault: not installed · not running · compose plugin missing.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "up" "Assemble + start the container stack (interactive, flag-driven, or from a preset)." \
  'up [--config <name>] [+modifier…] [--services a,b] [-a] [--nqa] [-y] [--dry-run] [--list] [-h]
  ctl up preset [<name>] [-a] [-y] [--nqa] [--dry-run] [--list]
  ctl up set-preset [<name>] [--config <name>] [+modifier…] [--services a,b] [-y]' \
"Arguments
  --config <name>     the stack shape: docker/compose.<name>.yaml — any of: $(list_configs | join_sp | or_none)
                      (none given: interactive pick in a terminal when more than one exists, else $DEFAULT_CONFIG)
  +<name>             a modifier to overlay on the config — any of: $(list_modifiers | sed 's/^/+/' | join_sp | or_none)
                      (none given: interactive pick of the ones that fit, else +${DEFAULT_MODIFIERS[*]} where it fits)
  --modifier <csv>    the same, as a comma-list (alias)
  --services <csv>    start only these services (comma-list). A service's depends_on chain comes with it.
                      (none given: interactive pick in a terminal, else every service)
  -a, --attach        run in the FOREGROUND (stream logs, Ctrl-C stops); default is detached (-d)
  --nqa               no questions — don't prompt; use flags/defaults
  -y, --yes           skip the final confirmation
  --dry-run, -n       show the plan and exit without running
  --list              list the configs, modifiers, presets and the services the config defines, then exit
  -h, --help          show this help

Presets ($PRESETS_FILE — one \`<name>: \"<arguments>\"\` line each)
  preset <name>       run the stored line: no prompts, straight to the plan and the confirm (-y to skip it)
  preset              pick one in a terminal, then the same
  preset --list       the stored presets and their lines
  set-preset [<name>] walk the pickers (an existing preset's values preselected), then Save / Save and run.
                      Flags given here skip their prompt, so \`set-preset x --config db +expose_db -y\` needs no TTY.
                      A preset stores the stack shape only: --config, +modifier, --services. Run flags
                      (-a, -y, --nqa) are given at run time and refused inside the file.

A config publishes no port; modifiers add exposure. The schema one-shots (migrate, neo4j-init) run
before any app because the apps wait on them — never on app boot." \
"Example:  ctl up                                # interactive
          ctl up -y                             # local docker: base +expose_web, no prompts
          ctl up --config db +expose_db -y      # the engines alone, bound to loopback (what ctl dev runs)
          ctl up +public -y                     # public deployment: 80/443 + PUBLIC_URL, uncommented in .env.proxy
          ctl up --services=api,postgres -y     # one backend and its chain only
          ctl up preset dev -y               # a stored line, no prompts
          ctl up set-preset staging             # save a new preset from the pickers"; }

preset_usage() { print_help "up preset" "Run a stored \`ctl up\` line from $PRESETS_FILE." \
  'up preset [<name>] [-a] [-y] [--nqa] [--dry-run] [--list] [-h]' \
"Arguments
  <name>          the preset to run (none given: pick in a terminal)
  -a, --attach    foreground   ·   -y  skip the confirm   ·   --dry-run  plan only
  --list          the stored presets and their lines
  -h, --help      show this help

Stored presets: $(list_presets | join_sp | or_none)" \
"A preset is the reproduce line the plan prints. \`ctl up set-preset\` writes one; so does a text editor."; }

# ── parse ── one parser for the three modes; preset lines are fed back through it
mode=up
case "${1:-}" in preset|set-preset) mode="$1"; shift ;; esac
cfg_cli="" cfg_set=0 mods_cli=() mod_set=0 svcs_cli=() svc_set=0 nqa=0 yes=0 dry=0 attach=0 list=0 name=""
parse_args() { while (( $# )); do case "$1" in
  --nqa|--no-questions-asked) nqa=1; shift ;;
  -y|--yes)      yes=1; shift ;;
  -a|--attach|--no-detach) attach=1; shift ;;
  --list)        list=1; shift ;;
  --dry-run|-n)  dry=1; shift ;;
  --config=*)    cfg_cli="${1#*=}"; cfg_set=1; shift ;;
  --config)      cfg_cli="${2:-}";  cfg_set=1; shift; shift || true ;;
  --modifier=*)  split_csv "${1#*=}"; mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift ;;
  --modifier)    split_csv "${2:-}";  mods_cli+=("${__SPLIT[@]}"); mod_set=1; shift; shift || true ;;
  --modifier=|--modifier='') mod_set=1; shift ;;
  --services=*)  split_csv "${1#*=}"; svcs_cli+=("${__SPLIT[@]}"); svc_set=1; shift ;;
  --services)    split_csv "${2:-}";  svcs_cli+=("${__SPLIT[@]}"); svc_set=1; shift; shift || true ;;
  +?*)           mods_cli+=("${1#+}"); mod_set=1; shift ;;
  -h|--help)     [[ $mode == preset ]] && preset_usage || usage; exit 0 ;;
  -*)            die "unknown argument: $1 (try ctl up --help)" ;;
  *)             [[ $mode != up ]] || die "unknown argument: $1 — modifiers are +name, services are --services a,b (try ctl up --help)"
                 [[ -z $name ]] || die "one preset name only (got '$name' and '$1')"
                 [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || die "preset name '$1' — use letters, digits, - and _"
                 name="$1"; shift ;;
esac; done; }
# parse_shape <name> <token…> — a stored preset line through the same parser, after proving it holds
# only the stack shape. A run flag in the file (-y, --list, -h) would act on the reader, so it is refused.
parse_shape() { local n="$1" t value_next=0; shift
  for t in "$@"; do
    if (( value_next )); then value_next=0; continue; fi      # the word after a bare --config/--modifier/--services
    case "$t" in
      --config|--modifier|--services) value_next=1 ;;
      --config=*|--modifier=*|--services=*|+?*) ;;
      *) die "preset '$n' holds '$t' — a preset stores only --config, +modifier and --services; run flags (-y, -a, --nqa) are given at run time" ;;
    esac
  done
  parse_args "$@"; }
# check_shape [where] — a flag given without a value is an error, never "all" or "the default"
check_shape() { local w="${1:-}"
  (( svc_set && ${#svcs_cli[@]} == 0 )) && die "${w}--services given but empty — name at least one service, or drop the flag for all"
  (( mod_set && ${#mods_cli[@]} == 0 )) && die "${w}--modifier given but empty — name at least one modifier, or drop the flag for none"
  if (( cfg_set )) && [[ -z $cfg_cli ]]; then die "${w}--config given but empty — one of: $(list_configs | join_sp)"; fi
  return 0; }
parse_args "$@"
check_shape

interactive=0; [[ -t 1 && -r /dev/tty && $nqa -eq 0 ]] && interactive=1

# ── preset: resolve the name to its stored line, feed it through the parser, skip every prompt ──
if [[ $mode == preset ]]; then
  if (( list )); then
    printf '%spresets%s  %s(%s)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$PRESETS_FILE" "$C_RESET"
    any=0; while IFS= read -r p; do [[ -z $p ]] && continue; printf '  %-14s ctl up %s\n' "$p" "$(preset_args "$p")"; any=1; done < <(list_presets)
    (( any )) || printf '  %s(none — ctl up set-preset writes one)%s\n' "$C_DIM" "$C_RESET"
    exit 0
  fi
  mapfile -t PRESETS < <(list_presets)
  (( ${#PRESETS[@]} )) || die "no presets in $PRESETS_FILE — \`ctl up set-preset\` writes one"
  if [[ -z $name ]]; then
    (( interactive )) || die "preset name required without a TTY — one of: ${PRESETS[*]}"
    tui_select --into pick --header "Preset — which stored line to run" -- "${PRESETS[@]}" || { say "cancelled."; exit 0; }
    name="${pick[0]}"; printf '\n'
  fi
  # a preset is the whole shape: a shape flag beside it would silently change what the name means
  (( cfg_set || mod_set || svc_set )) && die "'preset $name' takes no --config, +modifier or --services — edit it with: ctl up set-preset $name, or run the line directly: ctl up $(preset_args "$name" 2>/dev/null)"
  stored=$(preset_args "$name") || die "no preset '$name' in $PRESETS_FILE — one of: ${PRESETS[*]}"
  [[ -n ${stored//[[:space:]]/} ]] || die "preset '$name' is empty in $PRESETS_FILE — one line, one value: $name: \"--config base +expose_web\""
  read -r -a stored_argv <<< "$stored"
  parse_shape "$name" "${stored_argv[@]}"
  check_shape "preset '$name': "
  [[ -n $cfg_cli ]] || cfg_cli="$DEFAULT_CONFIG"
  cfg_set=1 mod_set=1 svc_set=1          # a preset is a complete spec: nothing left to ask
  interactive_confirm=$interactive; interactive=0
fi

require_env
require_docker

if (( list )); then
  printf '%sconfigs%s     %s(docker/compose.<name>.yaml — one stack shape; --config picks one)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
  while IFS= read -r c; do [[ -z $c ]] && continue
    printf '  %s' "$c"; [[ $c == "$DEFAULT_CONFIG" ]] && printf '   %s(default)%s' "$C_DIM" "$C_RESET"; printf '\n'
  done < <(list_configs)
  printf '\n%smodifiers%s   %s(overlay on a config; stackable; only the ones compose accepts are offered)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
  any=0; while IFS= read -r m; do [[ -z $m ]] && continue
    printf '  %s+%s%s' "$C_DIM" "$C_RESET" "$m"; [[ -n "${MODIFIER_REQUIRES[$m]:-}" ]] && printf '   %sneeds %s%s' "$C_DIM" "${MODIFIER_REQUIRES[$m]}" "$C_RESET"; printf '\n'; any=1
  done < <(list_modifiers)
  (( any )) || printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"
  printf '\n%spresets%s     %s(%s; ctl up preset <name>)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$PRESETS_FILE" "$C_RESET"
  any=0; while IFS= read -r p; do [[ -z $p ]] && continue; printf '  %-14s %s\n' "$p" "$(preset_args "$p")"; any=1; done < <(list_presets)
  (( any )) || printf '  %s(none)%s\n' "$C_DIM" "$C_RESET"
  c="${cfg_cli:-$DEFAULT_CONFIG}"
  printf '\n%sservices%s    %s(what config %s defines; --services picks a subset)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$c" "$C_RESET"
  compose_cmd -f "$(config_file "$c")" config --services 2>/dev/null | sort | sed 's/^/  /' || printf '  %s(compose could not read %s)%s\n' "$C_DIM" "$(config_file "$c")" "$C_RESET"
  exit 0
fi

mapfile -t CONFIGS < <(list_configs)
(( ${#CONFIGS[@]} )) || die "no config in $DOCKER_DIR/ — ship docker/compose.<name>.yaml"
mapfile -t MODIFIERS < <(list_modifiers)

# ── set-preset: which name, and what to preselect ──
# pre_* hold the values the pickers open with: the existing preset's line (pre_have=1, even when it
# names no modifier), else the defaults. Back sets them from the current pick the same way.
pre_cfg="" pre_mods=() pre_svcs=() pre_have=0
if [[ $mode == set-preset ]]; then
  mapfile -t PRESETS < <(list_presets)
  if [[ -z $name ]]; then
    (( interactive )) || die "set-preset needs a name without a TTY: ctl up set-preset <name> --config … +mod… -y"
    tui_select --into pick --header "Preset — edit one, or (new)" -- "(new)" "${PRESETS[@]}" || { say "cancelled."; exit 0; }
    if [[ ${pick[0]} == "(new)" ]]; then
      while :; do printf '  name: ' > /dev/tty; IFS= read -r name < /dev/tty || { say "cancelled."; exit 0; }
        [[ $name =~ ^[A-Za-z0-9_-]+$ ]] && break; printf '  %sletters, digits, - and _ only%s\n' "$C_YEL" "$C_RESET" > /dev/tty; done
    else name="${pick[0]}"; fi
    printf '\n'
  fi
  if stored=$(preset_args "$name"); then
    # walk the stored line with a throwaway copy of the parser state, so it preselects and does not decide
    saved=("$cfg_cli" "$cfg_set" "$mod_set" "$svc_set"); saved_mods=("${mods_cli[@]}"); saved_svcs=("${svcs_cli[@]}")
    cfg_cli="" cfg_set=0 mods_cli=() mod_set=0 svcs_cli=() svc_set=0
    read -r -a stored_argv <<< "$stored"; parse_shape "$name" "${stored_argv[@]}"; check_shape "preset '$name': "
    pre_cfg="$cfg_cli"; pre_mods=("${mods_cli[@]}"); pre_svcs=("${svcs_cli[@]}"); pre_have=1
    cfg_cli="${saved[0]}" cfg_set="${saved[1]}" mod_set="${saved[2]}" svc_set="${saved[3]}"; mods_cli=("${saved_mods[@]}"); svcs_cli=("${saved_svcs[@]}")
    say "${C_DIM}editing '$name' — stored: ctl up $stored${C_RESET}"
  else say "${C_DIM}new preset '$name'${C_RESET}"; fi
fi

# assembled_services — every service the chosen files define, sorted. Dies when compose rejects
# the file set, so the service picker never opens on an invalid combination.
assembled_services() { "${compose_base[@]}" config --services 2>/dev/null | sort; }

render_plan() {
  hr
  printf '%sPlan%s   config=%s   modifiers=[%s]   services=[%s]\n' "$C_B" "$C_RESET" "$config" \
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
    printf '%s  %-11s %-18s %-10s %s%s\n' "$C_DIM" "service" "ports host:ctr" "network" "volumes src:dst" "$C_RESET"
    local svc ports nets vols mark
    while IFS= read -r svc; do [[ -z $svc ]] && continue
      # host_ip is printed when set: 127.0.0.1:5432:5432 (loopback) reads differently from 5432:5432 (every interface)
      ports=$(jq -r --arg s "$svc" '.services[$s].ports // [] | map(select(.published)|(if .host_ip then .host_ip+":" else "" end)+(.published|tostring)+":"+(.target|tostring)) | join(",")' <<<"$json" 2>/dev/null); [[ -n $ports ]] || ports="-"
      nets=$(jq -r --arg s "$svc" '.services[$s].networks // {} | keys | join(",")' <<<"$json" 2>/dev/null); [[ -n $nets ]] || nets="-"
      vols=$(jq -r --arg s "$svc" '.services[$s].volumes // [] | map((.source // .type)+":"+.target) | join(",")' <<<"$json" 2>/dev/null); [[ -n $vols ]] || vols="-"
      vols="${vols//$CTL_ROOT\//}"
      # a service outside the subset is listed dim, so the plan still shows the whole file set
      if service_selected "$svc"; then mark="${C_GRN}✓${C_RESET}"; else mark="${C_DIM}·${C_RESET}"; fi
      printf '  %s %-11s %-18s %-10s %s\n' "$mark" "$svc" "$ports" "$nets" "$vols"
    done < <(jq -r "$svc_filter" <<<"$json" 2>/dev/null | sort)
  else
    warn "jq not installed — service list only"
    while IFS= read -r svc; do [[ -z $svc ]] && continue
      if service_selected "$svc"; then printf '  %s✓%s %s\n' "$C_GRN" "$C_RESET" "$svc"; else printf '  %s· %s%s\n' "$C_DIM" "$svc" "$C_RESET"; fi
    done < <(assembled_services)
  fi
  hr
  printf '%sreproduce%s  (no prompts)\n' "$C_B" "$C_RESET"
  printf '  %sctl up %s --nqa%s\n'      "$C_DIM" "$repro" "$C_RESET"
  printf '  %sctl up %s --nqa -y%s\n'   "$C_DIM" "$repro" "$C_RESET"
  printf '  %sdocker:%s %s\n'    "$C_DIM" "$C_RESET" "${docker_cmd[*]}"
  hr
}
# service_selected <svc> — 0 when the subset is empty (= all) or names it
service_selected() { (( ${#services[@]} == 0 )) && return 0; printf '%s\n' "${services[@]}" | grep -qx "$1"; }
in_list() { local x="$1"; shift; printf '%s\n' "$@" | grep -qx "$x"; }   # in_list <needle> <hay…>

# preset_write <name> <line> — replace the preset's line, or append it; create the file with its header.
preset_write() {
  local n="$1" v="$2" tmp
  [[ -f $PRESETS_FILE ]] || printf '# docker/presets.yaml — named `ctl up` runs. One line per preset:  <name>: "<what follows ctl up>"\n# `ctl up preset <name>` runs one; `ctl up set-preset` writes one. The value is the reproduce line the plan prints.\n' > "$PRESETS_FILE"
  [[ -w $PRESETS_FILE ]] || die "$PRESETS_FILE is not writable — nothing saved"
  tmp=$(mktemp); local l replaced=0
  while IFS= read -r l || [[ -n $l ]]; do l="${l%$'\r'}"
    if [[ $l =~ $PRESET_LINE && ${BASH_REMATCH[1]} == "$n" ]]; then
      (( replaced )) && continue            # a duplicated name collapses to one line
      printf '%s: "%s"\n' "$n" "$v" >> "$tmp"; replaced=1
    else printf '%s\n' "$l" >> "$tmp"; fi
  done < "$PRESETS_FILE"
  (( replaced )) || printf '%s: "%s"\n' "$n" "$v" >> "$tmp"
  # copy over the file, never mv: the file keeps its mode and owner, and a failure names itself
  cat "$tmp" > "$PRESETS_FILE" || { rm -f "$tmp"; die "could not write $PRESETS_FILE — nothing saved"; }
  rm -f "$tmp"
}

# selection → plan → confirm (Back re-opens the selectors)
while true; do
  # ── config ──
  if (( cfg_set )); then config="$cfg_cli"
  elif (( interactive )) && (( ${#CONFIGS[@]} > 1 )); then
    pick=(); tui_select --into pick --preselect "${pre_cfg:-$DEFAULT_CONFIG}" \
      --header "Config — the stack shape (docker/compose.<name>.yaml)" -- "${CONFIGS[@]}" || { say "cancelled."; exit 0; }
    config="${pick[0]}"; printf '\n'
  else config="${pre_cfg:-$DEFAULT_CONFIG}"; fi
  in_list "$config" "${CONFIGS[@]}" || die "no such config '$config' ($(config_file "$config") missing). configs: ${CONFIGS[*]}"

  # ── modifiers ── only the ones compose accepts on this config are offered. The defaults belong to
  # DEFAULT_CONFIG alone; there, a default compose rejects is an error, never a silent drop, because
  # a stack that came up without its expected port would look right.
  modifiers=()
  if (( mod_set )); then modifiers=("${mods_cli[@]}")
  else
    mapfile -t FITTING < <(fitting_modifiers "$config")
    wanted=()
    if (( pre_have )); then
      wanted=("${pre_mods[@]}")
      # a stored modifier that no longer fits is named, never dropped in silence; with no terminal
      # to show the picker, it is an error
      for m in "${wanted[@]}"; do in_list "$m" "${FITTING[@]}" && continue
        (( interactive )) && warn "stored modifier '+$m' no longer fits '$config' — unticked" || die "stored modifier '+$m' no longer fits '$config' — re-pick in a terminal, or give the modifiers explicitly"
      done
    elif [[ $config == "$DEFAULT_CONFIG" ]]; then
      wanted=("${DEFAULT_MODIFIERS[@]}")
      for m in "${wanted[@]}"; do in_list "$m" "${FITTING[@]}" || die "default modifier '+$m' is rejected on '$config' — $(compose_cmd -f "$(config_file "$config")" -f "$(modifier_file "$m")" config -q 2>&1 | head -1)"; done
    fi
    preselect=(); for m in "${wanted[@]}"; do in_list "$m" "${FITTING[@]}" && preselect+=("$m"); done
    if (( interactive )) && (( ${#FITTING[@]} )); then
      hint=""; for m in "${FITTING[@]}"; do blank=$(modifier_blank_keys "$m" | join_sp); [[ -n $blank ]] && hint+="+$m needs $blank · "; done
      hint+="↑/↓ move · Space toggle · Enter confirm · Esc cancel"
      tui_select --into modifiers --multi --preselect "$(IFS=,; echo "${preselect[*]:-}")" --hint "$hint" \
        --header "Modifiers — overlays that fit '$config' (Space toggles, Enter confirms)" -- "${FITTING[@]}" \
        || { say "cancelled."; exit 0; }
      printf '\n'
    else modifiers=("${preselect[@]}"); fi
  fi
  for m in "${modifiers[@]}"; do
    in_list "$m" "${MODIFIERS[@]}" || die "no such modifier '+$m'. modifiers: $(list_modifiers | sed 's/^/+/' | join_sp)"
    check_modifier_env "$m"
  done

  mapfile -t files < <(compose_files "$config" "${modifiers[@]}")
  file_args=(); for f in "${files[@]}"; do file_args+=(-f "$f"); done
  # the same line compose_cmd runs, kept as an array: the plan prints it, --attach execs it
  mapfile -t compose_base < <(compose_argv "${file_args[@]}")

  # ── services ── the picker needs the assembled file set, so it comes after the modifiers
  services=()
  if (( svc_set )); then services=("${svcs_cli[@]}")
  elif (( interactive )); then
    mapfile -t ALL_SVCS < <(assembled_services)
    if (( ${#ALL_SVCS[@]} )); then
      preselect=(); if (( ${#pre_svcs[@]} )); then preselect=("${pre_svcs[@]}"); else preselect=("${ALL_SVCS[@]}"); fi
      tui_select --into services --multi --preselect "$(IFS=,; echo "${preselect[*]}")" \
        --header "Services — untick what should stay down (Enter = every ticked one)" -- "${ALL_SVCS[@]}" \
        || { say "cancelled."; exit 0; }
      printf '\n'
      (( ${#services[@]} )) || die "no service selected — nothing to start"
      (( ${#services[@]} == ${#ALL_SVCS[@]} )) && services=()   # everything ticked = all, keeps the repro line short
    fi
  elif (( ${#pre_svcs[@]} )); then services=("${pre_svcs[@]}"); fi
  if (( ${#services[@]} )); then
    mapfile -t ALL_SVCS < <(assembled_services)
    (( ${#ALL_SVCS[@]} )) || die "this combination is invalid — $("${compose_base[@]}" config -q 2>&1 | head -1)"
    for s in "${services[@]}"; do
      in_list "$s" "${ALL_SVCS[@]}" || die "no such service '$s' in this file set. services: $(printf '%s ' "${ALL_SVCS[@]}")"
    done
  fi

  detach=(-d); (( attach )) && detach=()
  docker_cmd=("${compose_base[@]}" up "${detach[@]}" --build "${services[@]}")

  # the stack shape as one line: what a preset stores, and what the plan prints after `ctl up`
  shape="--config $config"; for m in "${modifiers[@]}"; do shape+=" +$m"; done
  (( ${#services[@]} )) && shape+=" --services=$(IFS=,; echo "${services[*]}")"
  repro="$shape"; (( attach )) && repro+=" --attach"

  plan_ok=1; render_plan || plan_ok=0

  (( dry )) && { (( plan_ok )) && say "(dry-run — nothing started)" || say "(dry-run — invalid, nothing started)"; exit $(( plan_ok ? 0 : 1 )); }

  # ── confirm ──
  if [[ $mode == set-preset ]]; then
    if (( plan_ok && yes )); then preset_write "$name" "$shape"; ok "saved '$name' → $PRESETS_FILE  (ctl up preset $name)"; exit 0; fi
    (( interactive )) || { (( plan_ok )) || die "invalid combination (see above)"; die "not a TTY and no -y — re-run with -y to save"; }
    printf '\n'; action=()
    if (( plan_ok )); then
      tui_select --into action --horizontal --header "Save '$name'?" -- Save "Save and run" Back Cancel || { say "cancelled."; exit 0; }
    else
      tui_select --into action --horizontal --header "Invalid combination — go back and re-pick?" -- Back Cancel || { say "cancelled."; exit 0; }
    fi
    case "${action[0]:-Cancel}" in
      Save)         preset_write "$name" "$shape"; ok "saved '$name' → $PRESETS_FILE  (ctl up preset $name)"; exit 0 ;;
      "Save and run") preset_write "$name" "$shape"; ok "saved '$name' → $PRESETS_FILE"; break ;;
      Back) cfg_set=0 mod_set=0 svc_set=0; pre_cfg="$config"; pre_mods=("${modifiers[@]}"); pre_svcs=("${services[@]}"); pre_have=1
            printf '\n%s↻ starting over — re-pick config, modifiers and services%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
      *)    say "cancelled."; exit 0 ;;
    esac
  fi

  if (( plan_ok && yes )); then break; fi
  [[ $mode == preset ]] && interactive=$interactive_confirm     # a preset skips the pickers, not the confirm
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
    Back) [[ $mode == preset ]] && { say "a preset is fixed — edit it with: ctl up set-preset $name"; exit 0; }
          cfg_set=0 mod_set=0 svc_set=0; pre_cfg="$config"; pre_mods=("${modifiers[@]}"); pre_svcs=("${services[@]}"); pre_have=1
          printf '\n%s↻ starting over — re-pick config, modifiers and services%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
    *)    say "cancelled."; exit 0 ;;
  esac
done

# ── start ── compose orders the chain itself: engines healthy → schema one-shots done → apps.
# With a subset, only the named services and their depends_on chain come up: an app brings the
# engines and the schema step with it, an engine alone brings nothing.
step "${docker_cmd[*]}"
if (( attach )); then
  say "${C_DIM}foreground — streaming logs; Ctrl-C stops the stack${C_RESET}"
  exec "${docker_cmd[@]}"
fi
"${docker_cmd[@]}"
ok "stack up  (detached — 'ctl logs -f' to follow, 'ctl down' to stop)"
