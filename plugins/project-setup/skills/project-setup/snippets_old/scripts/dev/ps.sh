#!/usr/bin/env bash
# dev/ps.sh — `ctl ps`. Everything this project is running, port-first, across all
# three planes — and the sanctioned way to free those ports:
#
#   dev      host processes on the dev ports (PYTHON_PORT / FRONTEND_PORT)
#   build    frozen test builds serving on the PORT_PRESETS list (test/build.sh)
#   docker   compose containers with published host ports
#
#   ctl ps                      interactive browser over everything running: hover a
#                               process — Enter = action menu · a = attach · k = kill ·
#                               q = quit  (arrow keys to move; j/k vim-nav is off here
#                               because k kills)
#   ctl ps --list               the formatted map only (also the no-TTY behaviour)
#   ctl ps kill [port…] [-y]    free ports — no ports = interactive multi-select of the
#                               occupied ones; -y skips the confirm
#
# Freeing is PLANE-AWARE: a host process gets TERM (then KILL after a grace period), but a
# docker-published port is owned by docker-proxy — killing that PID strands the container,
# so the docker plane routes to `docker compose stop <service>` instead.
# Attaching is plane-aware too: docker → `docker compose logs -f <svc>`; a process started
# by `ctl dev --detach` → tail -f its data/logs/ file; anything else has no log to follow.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

BUILDS_DIR="$CTL_ROOT/test_build"

usage() { print_help "ps" "Everything the project runs (dev · build · docker): browse, attach, free." \
  'ps [--list] [kill [port…]] [-y] [-h]' \
"Subcommands
  (none)         interactive browser over every port the project has listening (dev
                 ports, frozen-build presets ${PORT_PRESETS[*]}, docker published).
                 Hover a process:  Enter action menu · a attach · k kill · q quit
                 (arrows move; j/k vim-nav is disabled on this screen since k = kill)
  --list         print the containers table + the port map, then exit (no prompts;
                 also what a no-TTY run does)
  kill [port…]   free the given ports; with none, pick interactively from the occupied
                 ones. Host processes get TERM→KILL; docker ports are freed via
                 'docker compose stop <service>' (killing docker-proxy strands the
                 container).

Attach follows the process's output (Ctrl-C detaches, the process keeps running):
docker → 'docker compose logs -f <svc>'; a 'ctl dev --detach' process → tail -f of its
data/logs/ file. A process with no log (foreground-started elsewhere) can't be attached.

Options
  -y, --yes      skip the confirmation before freeing
  -h, --help     show this help" \
"Every interactive free prints the exact 'ctl ps kill <ports> -y' that reproduces it."; }

# ── gather: ENTRIES of "plane|port|kind|id|desc"  (kind pid → kill; kind svc → dc stop) ──
pid_desc() { ps -o args= -p "$1" 2>/dev/null | head -1 | cut -c1-56; }
pid_cwd()  { readlink "/proc/$1/cwd" 2>/dev/null \
             || { command -v lsof >/dev/null 2>&1 && lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; } || true; }

gather() {
  ENTRIES=(); local seen=" " p pid cwd desc spec name id svc line hostport ctrport
  # dev plane — the host dev ports
  for spec in "backend:${PYTHON_PORT:-8000}" "frontend:${FRONTEND_PORT:-3000}"; do
    name="${spec%%:*}"; p="${spec#*:}"
    pid="$(port_pid "$p")"; [[ -n $pid && $seen != *" $p "* ]] || continue
    seen+="$p "; ENTRIES+=("dev|$p|pid|$pid|$name — $(pid_desc "$pid")")
  done
  # build plane — frozen builds serving on the preset ports (cwd inside test_build/ = a snapshot)
  for p in "${PORT_PRESETS[@]}"; do
    pid="$(port_pid "$p")"; [[ -n $pid && $seen != *" $p "* ]] || continue
    seen+="$p "; cwd="$(pid_cwd "$pid")"
    if [[ $cwd == "$BUILDS_DIR"/* ]]; then desc="frozen build ${cwd##*/}"
    else desc="${C_DIM}(not a build)${C_RESET} $(pid_desc "$pid")"; fi
    ENTRIES+=("build|$p|pid|$pid|$desc")
  done
  # docker plane — published host ports of this project's containers
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    for id in $(dc ps -q 2>/dev/null); do
      svc="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$id" 2>/dev/null)"
      while IFS= read -r line; do   # "80/tcp -> 0.0.0.0:8080"
        hostport="${line##*:}"; ctrport="${line%%/*}"
        [[ $hostport =~ ^[0-9]+$ ]] || continue
        ENTRIES+=("docker|$hostport|svc|$svc|$svc → :$ctrport  (container ${id:0:12})")
      done < <(docker port "$id" 2>/dev/null)
    done
  fi
}

entry_label() {  # picker/table line for one entry
  local plane port kind id desc; IFS='|' read -r plane port kind id desc <<<"$1"
  printf '%-7s :%-6s %s' "$plane" "$port" "$desc"
}

render_map() {
  section "ports — everything this project has listening"
  if (( ${#ENTRIES[@]} )); then
    printf '  %s%-7s %-7s %s%s\n' "$C_DIM" "plane" "port" "owner" "$C_RESET"
    local e; for e in "${ENTRIES[@]}"; do printf '  %s✓%s %s\n' "$C_GRN" "$C_RESET" "$(entry_label "$e")"; done
  else
    say "${C_DIM}nothing listening (dev ports, build presets ${PORT_PRESETS[*]}, docker published)${C_RESET}"
  fi
}

free_entry() {  # plane-aware: host pid → TERM then KILL; docker → compose stop
  local plane port kind id desc i; IFS='|' read -r plane port kind id desc <<<"$1"
  if [[ $kind == svc ]]; then
    step "docker compose stop $id   (frees :$port)"
    dc stop "$id" && ok "stopped $id" || err "could not stop $id"
  else
    step "kill $id   (frees :$port)"
    kill "$id" 2>/dev/null || { err "no such pid $id (already gone?)"; return 0; }
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$id" 2>/dev/null || { ok "freed :$port"; return 0; }; sleep 0.3; done
    kill -9 "$id" 2>/dev/null || true
    ok "freed :$port (needed KILL)"
  fi
}

# pid_is_under <ancestor> <pid> — true if <pid> equals <ancestor> or descends from it.
# Needed because the pidfile records the wrapper (`bash -c`, `uv run`, `bun run`) while
# the port listener is its child (uvicorn, vite, …).
pid_is_under() {
  local anc="$1" p="$2" i=0
  while [[ -n $p && $p != 0 && $p != 1 && $i -lt 15 ]]; do
    [[ $p == "$anc" ]] && return 0
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; i=$((i+1))
  done
  return 1
}

attach_entry() {  # plane-aware follow (execs — Ctrl-C detaches, the process keeps running)
  local plane port kind id desc f pid log=""; IFS='|' read -r plane port kind id desc <<<"$1"
  if [[ $kind == svc ]]; then
    step "docker compose logs -f $id   (Ctrl-C detaches)"
    exec docker compose -f "$BASE" logs -f "$id"
  fi
  for f in data/run/*.pid; do   # a `ctl dev --detach` process? its pidfile pid = the listener or an ancestor of it
    [[ -f $f ]] || continue
    pid="$(cat "$f" 2>/dev/null)"; [[ -n $pid ]] && pid_is_under "$pid" "$id" || continue
    log="data/logs/$(basename "$f" .pid).log"; break
  done
  [[ -n $log && -f $log ]] || { err "no log for pid $id — not started by 'ctl dev --detach', nothing to attach to"; return 1; }
  step "tail -f $log   (Ctrl-C detaches, pid $id keeps running)"
  exec tail -n 40 -f "$log"
}

do_kill() {  # $@ = requested ports (may be empty → interactive pick)
  local yes="$1"; shift; local want=("$@") targets=() e port matched labels=() choice=() i freed=() action=()
  local cli=0; (( ${#want[@]} )) && cli=1
  gather
  (( ${#ENTRIES[@]} )) || die "nothing is listening — no ports to free"

  # ── selection → plan → confirm (same contract as ctl up; Back re-opens the picker) ──
  while true; do
    targets=(); freed=()
    if (( cli )); then
      for port in "${want[@]}"; do
        matched=0
        for e in "${ENTRIES[@]}"; do [[ "$(cut -d'|' -f2 <<<"$e")" == "$port" ]] && { targets+=("$e"); matched=1; }; done
        (( matched )) || die "nothing of this project listens on :$port (ctl ps to see the map)"
      done
    else
      [[ -t 1 && -r /dev/tty ]] || die "no ports given and no TTY — usage: ctl ps kill <port…> [-y]"
      labels=(); for e in "${ENTRIES[@]}"; do labels+=("$(entry_label "$e")"); done
      choice=()
      tui_select --into choice --multi --header "Free which ports? (Space toggles, Enter confirms — none = cancel)" \
        -- "${labels[@]}" || { say "cancelled."; exit 0; }
      (( ${#choice[@]} )) || { say "nothing selected."; exit 0; }
      for i in "${!labels[@]}"; do
        for e in "${choice[@]}"; do [[ "${labels[$i]}" == "$e" ]] && targets+=("${ENTRIES[$i]}"); done
      done
      printf '\n'
    fi

    say "freeing:"
    for e in "${targets[@]}"; do say "  ${C_DIM}✗${C_RESET} $(entry_label "$e")"; freed+=("$(cut -d'|' -f2 <<<"$e")"); done
    (( yes )) && break
    [[ -t 1 && -r /dev/tty ]] || die "not a TTY and no -y — re-run with -y"

    printf '\n'
    action=()
    if (( cli )); then   # ports came from the CLI — nothing to go Back to
      tui_select --into action --horizontal --header "Free these ports?" -- Free Cancel \
        || { say "cancelled."; exit 0; }
    else
      tui_select --into action --horizontal --header "Free these ports?" -- Free Back Cancel \
        || { say "cancelled."; exit 0; }
    fi
    case "${action[0]:-Cancel}" in
      Free) break ;;
      Back) printf '\n%s↻ starting over — re-pick ports%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
      *)    say "cancelled."; exit 0 ;;
    esac
  done

  for e in "${targets[@]}"; do free_entry "$e"; done
  say "reproduce:  ${C_DIM}ctl ps kill ${freed[*]} -y${C_RESET}"
}

browse() {  # interactive: hover a process — Enter menu · a attach · k kill · q quit
  local labels=() sel=() action=() e i cur
  while true; do
    gather
    (( ${#ENTRIES[@]} )) || { say "${C_DIM}nothing listening — all quiet${C_RESET}"; return 0; }
    labels=(); for e in "${ENTRIES[@]}"; do labels+=("$(entry_label "$e")"); done
    sel=()
    tui_select --into sel --keys "a k" \
      --header "Processes — everything this project is running" \
      --hint "↑/↓ move · Enter options · a attach · k kill · q quit" \
      -- "${labels[@]}" || return 0
    cur=""; for i in "${!labels[@]}"; do [[ "${labels[$i]}" == "${sel[0]:-}" ]] && cur="${ENTRIES[$i]}"; done
    [[ -n $cur ]] || return 0
    case "${TUI_SELECT_KEY:-}" in
      a) attach_entry "$cur" || true ;;                        # attach execs on success
      k) printf '\n'; free_entry "$cur"
         say "reproduce:  ${C_DIM}ctl ps kill $(cut -d'|' -f2 <<<"$cur") -y${C_RESET}"; printf '\n' ;;
      *) printf '\n'                                            # Enter → action menu
         action=()
         tui_select --into action --horizontal --header "$(entry_label "$cur")" \
           -- Attach "Free port" Back || return 0
         case "${action[0]:-Back}" in
           Attach)      attach_entry "$cur" || true ;;
           "Free port") printf '\n'; free_entry "$cur"
                        say "reproduce:  ${C_DIM}ctl ps kill $(cut -d'|' -f2 <<<"$cur") -y${C_RESET}"; printf '\n' ;;
         esac ;;
    esac
  done   # loop → re-gather (freed entries vanish, new ones appear)
}

# ── parse ──
sub="" yes=0 list=0 ports=()
while (( $# )); do case "$1" in
  kill)      sub=kill; shift ;;
  --list|-l) list=1; shift ;;
  -y|--yes)  yes=1; shift ;;
  -h|--help) usage; exit 0 ;;
  *)         [[ $sub == kill && $1 =~ ^[0-9]+$ ]] && { ports+=("$1"); shift; } \
               || die "unknown arg: $1 (try ctl ps --help)" ;;
esac; done

load_env_file .env     # soft, non-clobbering load — ps must never die

if [[ $sub == kill ]]; then do_kill "$yes" ${ports[@]+"${ports[@]}"}; exit 0; fi

section "containers"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then dc ps
else say "${C_DIM}docker not reachable${C_RESET}"; fi
printf '\n'

gather
render_map

# --list (or no TTY): the formatted map is the whole output
if (( list )) || [[ ! -t 1 || ! -r /dev/tty ]]; then exit 0; fi

printf '\n'
browse
