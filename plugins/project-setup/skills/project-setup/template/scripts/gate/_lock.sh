#!/usr/bin/env bash
# scripts/gate/_lock.sh — ONE gate run per user at a time, under ONE memory lid. SOURCE this after
# _lib.sh and scripts/common/_test-settings.sh, which sizes the lid.
#
# WHY. Two heavy runs at once on one box (a test worker can hold several GB) can run the kernel out
# of memory and end the login session. The danger is per machine, so the lock is per user: every
# checkout and every project made from this template shares it, worktrees included.
#
# TWO GUARDS.
#   THE LOCK   a kernel flock on GATE_LOCK_FILE, /run/user/<uid>/ctl-gate-<uid>.lock, or under /tmp
#              when the user has no /run/user folder. The holder writes its checkout, pid, verb,
#              start time and current step into the file. A second run prints what is running and
#              WAITS until the holder exits. The kernel drops the lock when the last process holding
#              it ends, so there is never a stale lock. Every run, waiting included, also holds a
#              shared flock on ctl-gate.lock in its checkout's git folder, so ctl worktree can tell
#              that a gate waits or runs in a checkout.
#   THE LID    the whole run — every worker, compiler and browser — inside one memory-capped scope:
#              the memory budget of the TESTING settings (--memory, else TEST_MEMORY, else 80 % of
#              what is available at the start). Reach the lid and the RUN is killed, never the
#              machine. Swap is off inside the lid. It needs `systemd-run --user` (cgroup v2);
#              without it the run goes bare and says so once.
#
# OTHER READERS. scripts/worktree/_busy.sh tests the checkout's ctl-gate.lock with an exclusive flock
# that never waits. For a branch whose scripts predate that file, it tests this lock with a shared
# flock that never waits and never writes, and reads the `checkout=` line to learn which checkout
# holds it. Keep both file names, the path variable GATE_LOCK_FILE, a holder's exclusive flock and
# the `checkout=` line stable, because that reader relies on them.
#
# Exit codes: 137 = killed at the lid.

# The default is one file for every shell of the user. XDG_RUNTIME_DIR is not read, because a shell
# without it would pick another file and let a second run start beside the first.
_gl_dir=/tmp
if [[ -d /run/user/$EUID && -O /run/user/$EUID ]]; then _gl_dir=/run/user/$EUID; fi
GATE_LOCK_FILE="${GATE_LOCK_FILE:-$_gl_dir/ctl-gate-$EUID.lock}"

_gl_say()   { printf '%s\n' "$*" >&2; }
_gl_get()   { local key value; [[ -f $GATE_LOCK_FILE ]] || return 0
              while IFS='=' read -r key value; do [[ $key == "$1" ]] && { printf '%s\n' "$value"; return 0; }; done < "$GATE_LOCK_FILE"; return 0; }
_gl_clock() { date -d "@${1:-0}" +%H:%M 2>/dev/null || echo "?"; }
# _gl_write <text> — rewrite the holder lines in place. Never replace the file (mv, rm, sed -i): a
# waiter blocks on this inode, and a new file would let a second run in beside this one.
_gl_write() { printf '%s\n' "$1" > "$GATE_LOCK_FILE"; }

# gate_lock_open — open the lock file for this process, refusing one another user could have planted:
# a symlink, or a file someone else owns. The file is created on first use.
gate_lock_open() {
  [[ ! -L $GATE_LOCK_FILE ]] || die "the gate lock $GATE_LOCK_FILE is a symlink — remove it, it was not made by ctl"
  exec {GATE_LOCK_FD}>>"$GATE_LOCK_FILE" || die "cannot open the gate lock $GATE_LOCK_FILE"
  [[ -O $GATE_LOCK_FILE ]] || die "the gate lock $GATE_LOCK_FILE belongs to another user — set GATE_LOCK_FILE to a path of your own"
}

# gate_lock_take <verb> [args…] — hold the lock for the rest of this process and its children,
# waiting while another run holds it.
gate_lock_take() {
  local verb="$1" started step line held own
  shift
  [[ -z ${GATE_LID:-} ]] || return 0     # the inner half of a lidded run holds it through its parent
  command -v flock >/dev/null 2>&1 || die "the gate lock needs flock (util-linux)"
  gate_lock_open
  # The checkout's own lock, held from before the wait to the end of the run. It lives in the git
  # folder, where git status never sees it. Outside a git checkout no worktree needs it.
  if own=$(git -C "$CTL_ROOT" rev-parse --absolute-git-dir 2>/dev/null); then
    exec {GATE_CHECKOUT_FD}>>"$own/ctl-gate.lock" || die "cannot open the checkout's gate lock $own/ctl-gate.lock"
    flock -s "$GATE_CHECKOUT_FD" || die "could not take the checkout's gate lock $own/ctl-gate.lock"
  fi
  if ! flock -n "$GATE_LOCK_FD"; then
    started="$(_gl_get started)"; step="$(_gl_get step)"; held="$(_gl_get verb) $(_gl_get args)"
    _gl_say "· another gate run holds the lock: ${held% } in $(_gl_get checkout) (pid $(_gl_get pid))"
    line="  started $(_gl_clock "$started")"; [[ -z $step ]] || line+=" · on $step"
    _gl_say "$line"
    _gl_say "  waiting for it to finish — two heavy runs at once can take the whole box down"
    flock "$GATE_LOCK_FD" || die "could not take the gate lock $GATE_LOCK_FILE"
    _gl_say "· the other gate run finished — starting"
  fi
  _gl_write "$(printf 'checkout=%s\npid=%s\nverb=%s\nargs=%s\nstarted=%s\nstep=' "$CTL_ROOT" "$$" "$verb" "$*" "$(date +%s)")"
}

# gate_lock_step <name> — name the step now running, for a waiting run to print. The lidded inner
# run calls it too; it holds the lock through its parent.
gate_lock_step() {
  local lines=() line out=""
  [[ -f $GATE_LOCK_FILE && ! -L $GATE_LOCK_FILE ]] || return 0
  mapfile -t lines < "$GATE_LOCK_FILE"
  for line in ${lines[@]+"${lines[@]}"}; do [[ $line == step=* ]] && line="step=$1"; out+="$line"$'\n'; done
  _gl_write "${out%$'\n'}"
}

# gate_lid_reexec <script> [args…] — run the script again inside the lid and NEVER RETURN; the
# inner run (GATE_LID set) returns at once and does the work. Call it after gate_lock_take.
gate_lid_reexec() {
  [[ -z ${GATE_LID:-} ]] || return 0
  local lid_mib how rc=0
  lid_mib=$(test_memory_budget_mib) || exit 1
  how="$(test_memory_budget_words)"
  [[ -n ${TEST_MEMORY:-} ]] || how+=" · --memory or TEST_MEMORY overrides"
  if ! command -v systemd-run >/dev/null 2>&1 || ! systemd-run --user --scope --quiet -p MemoryMax=1G -- true >/dev/null 2>&1; then
    _gl_say "! no memory lid: systemd-run --user is not available here — the run goes bare"
    export GATE_LID=bare; return 0
  fi
  _gl_say "· memory lid $(test_human "$lid_mib") ($how) · one gate run per user at a time: $GATE_LOCK_FILE"
  GATE_LID="$lid_mib" systemd-run --user --scope --quiet -p "MemoryMax=${lid_mib}M" -p MemorySwapMax=0 -p OOMPolicy=kill -- bash "$@" &
  { wait $!; } 2>/dev/null || rc=$?
  if (( rc == 137 )); then
    _gl_say ""; _gl_say "✗ OUT OF MEMORY — the run was killed at the $(test_human "$lid_mib") lid."
    _gl_say "  It ran: $(_gl_get verb) $(_gl_get args)"
    _gl_say "  Re-run with a bigger lid (--memory, or TEST_MEMORY in .env), or fewer compiler jobs (--build-jobs, or TEST_BUILD_JOBS)."
  fi
  exit "$rc"
}
