#!/usr/bin/env bash
# scripts/gate/_lock.sh — ONE heavy gate run at a time, under ONE memory lid. SOURCE this.
# It depends on nothing else in scripts/, so any worker can use it.
#
# WHY. Two heavy runs at once on one box (a test worker can hold several GB) ran the kernel out
# of memory and killed the login session — twice in one evening on the project this is ported
# from. Nothing in ctl had looked at memory.
#
# TWO GUARDS.
#   THE LOCK   scripts/gate/gate.lock (gitignored). A run writes its pid, verb, start time and the
#              step it is on. A second run reads it: holder alive → refuse and say what is running;
#              holder dead → say so, remove the lock, carry on.
#   THE LID    the whole run — every worker, compiler and browser — inside one memory-capped scope:
#              80 % of what is AVAILABLE at start, or `--memory 4G` / `--memory 512M`. Reach the lid
#              and the RUN is killed, never the machine. Swap is off inside the lid. Needs
#              `systemd-run --user` (cgroup v2); without it the run goes bare and says so once.
#
# A PID ALONE IS NOT PROOF. The holder counts as alive only when /proc/<pid>/cmdline names a gate
# script, or the lock was rewritten in the last 20 minutes (a run inside a sandbox writes a pid that
# means nothing on the host; the mtime is the second liveness proof).
#
# Exit codes: 3 = refused, another run holds the lock. 137 = killed at the lid.

GATE_LOCK_FILE="${GATE_LOCK_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate.lock}"
GATE_LOCK_MINE=0
GATE_MEMORY="${GATE_MEMORY:-}"     # the --memory value the caller parsed; empty = default
GATE_LID_SHARE=80
GATE_LOCK_FRESH_S=1200

_gl_say()   { printf '%s\n' "$*" >&2; }
_gl_get()   { sed -n "s/^$1=//p" "$GATE_LOCK_FILE" 2>/dev/null | head -1; }
_gl_set()   { [[ -f "$GATE_LOCK_FILE" ]] && sed -i "s|^$1=.*|$1=$2|" "$GATE_LOCK_FILE"; return 0; }
_gl_clock() { date -d "@${1:-0}" +%H:%M 2>/dev/null || echo "?"; }
_gl_mib() {   # "4G", "512M", "4GB" or a bare number (GB) → MiB; anything else is a refusal by name
  local s="${1^^}" n; s="${s%B}"
  case "$s" in
    *G) n="${s%G}"; [[ "$n" =~ ^[0-9]+$ ]] && { echo $(( n * 1024 )); return 0; } ;;
    *M) n="${s%M}"; [[ "$n" =~ ^[0-9]+$ ]] && { echo "$n"; return 0; } ;;
    *)  [[ "$s" =~ ^[0-9]+$ ]] && { echo $(( s * 1024 )); return 0; } ;;
  esac
  _gl_say "✗ --memory wants a size like 4G or 512M (got: $1)"; exit 2
}
_gl_human() { if (( $1 >= 1024 )); then echo "$(( $1 / 1024 )) GB"; else echo "$1 MB"; fi; }

gate_lock_holder_live() {
  local pid="$1" now mtime
  if [[ -n "$pid" && -d "/proc/$pid" ]] && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'scripts/gate/'; then return 0; fi
  now=$(date +%s); mtime=$(stat -c %Y "$GATE_LOCK_FILE" 2>/dev/null || echo 0)
  (( now - mtime < GATE_LOCK_FRESH_S ))
}

# gate_lock_take <verb> [args…] — take the lock or refuse by name (exit 3)
gate_lock_take() {
  local verb="$1"; shift
  [[ -n "${GATE_LID:-}" ]] && return 0      # the inner half of a lidded run holds it through its parent
  if [[ -f "$GATE_LOCK_FILE" ]]; then
    local pid started step now elapsed line
    pid="$(_gl_get pid)"
    if gate_lock_holder_live "$pid"; then
      started="$(_gl_get started)"; step="$(_gl_get step)"
      now=$(date +%s); elapsed=$(( now - ${started:-$now} ))
      _gl_say "✗ a gate run is already going: $(_gl_get verb) $(_gl_get args) (pid $pid)"
      line="  started $(_gl_clock "$started") · running $(( elapsed / 60 )) min"; [[ -n "$step" ]] && line+=" · on $step"
      _gl_say "$line"; _gl_say "  Wait for it. Two heavy runs at once can take the whole box down."
      exit 3
    fi
    _gl_say "! stale lock: pid ${pid:-?} is no gate run any more — removed"
    rm -f "$GATE_LOCK_FILE"
  fi
  printf 'pid=%s\nverb=%s\nargs=%s\nstarted=%s\nstep=\n' "$$" "$verb" "$*" "$(date +%s)" >"$GATE_LOCK_FILE"
  GATE_LOCK_MINE=1
  trap gate_lock_release EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
  return 0
}
# gate_lock_step <name> — name the step now running; the write also refreshes the mtime
gate_lock_step()    { _gl_set step "$1"; }
gate_lock_release() { (( GATE_LOCK_MINE )) || return 0; [[ "$(_gl_get pid)" == "$$" ]] && rm -f "$GATE_LOCK_FILE"; GATE_LOCK_MINE=0; return 0; }

# gate_lid_reexec <script> [args…] — run the script again inside the lid and NEVER RETURN; the
# inner run (GATE_LID set) returns at once and does the work. Call it after gate_lock_take.
gate_lid_reexec() {
  [[ -n "${GATE_LID:-}" ]] && return 0
  local avail_mib lid_mib how rc=0
  avail_mib="$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ -n "$GATE_MEMORY" ]]; then
    lid_mib="$(_gl_mib "$GATE_MEMORY")" || exit 2
    how="--memory $GATE_MEMORY · $(_gl_human "$avail_mib") available"
  else
    lid_mib=$(( avail_mib * GATE_LID_SHARE / 100 ))
    how="${GATE_LID_SHARE} % of $(_gl_human "$avail_mib") available · --memory 4G or 512M overrides"
  fi
  (( lid_mib < 64 )) && lid_mib=64
  if ! command -v systemd-run >/dev/null 2>&1 || ! systemd-run --user --scope --quiet -p MemoryMax=1G -- true >/dev/null 2>&1; then
    _gl_say "! no memory lid: systemd-run --user is not available here — the run goes bare"
    export GATE_LID=bare; return 0
  fi
  _gl_say "· memory lid $(_gl_human "$lid_mib") ($how) · one run at a time: $(basename "$GATE_LOCK_FILE")"
  GATE_LID="$lid_mib" systemd-run --user --scope --quiet -p "MemoryMax=${lid_mib}M" -p MemorySwapMax=0 -p OOMPolicy=kill -- bash "$@" &
  { wait $!; } 2>/dev/null || rc=$?
  if (( rc == 137 )); then
    _gl_say ""; _gl_say "✗ OUT OF MEMORY — the run was killed at the $(_gl_human "$lid_mib") lid."
    _gl_say "  It ran: $(_gl_get verb) $(_gl_get args)"
    _gl_say "  Re-run with a bigger lid (--memory 48G), or fewer parallel jobs in the rung that died."
  fi
  exit "$rc"
}
