#!/usr/bin/env bash
# scripts/gate/_gate.sh — shared foundation for the `ctl gate` family. SOURCE this after _lib.sh.
#
# THE RUNG CONTRACT (06_testing.md). Every rung keeps four promises:
#   1. exit 0 only when the rule was proved — a rung that cannot find its target dies by name
#   2. name the file and the line when it fails
#   3. one implementation, two callers — a rung calls the same worker `ctl <verb>` calls
#   4. a check is a test when it can be — shell exists only for what no test runner can do
#
# THE LADDER lives in all.sh. One file per rung: scripts/gate/<rung>.sh. A rung takes no
# arguments (gate_reject_args): a gate that quietly ignores one runs something other than what
# the caller asked for. Narrow a run with the dev verb (`ctl test api`); `gate lint` and `gate typecheck` take a target by name.
# A rung takes no arguments (gate_reject_args) except lint and typecheck, whose dev verb IS the rung.
#
# Ported from neurasutra-editor scripts/gate/_gate.sh, minus that repo's frozen-package guards.

# gate_require_dir <repo-relative path> <what it is>
gate_require_dir()  { [[ -d "$CTL_ROOT/$1" ]] || die "$2 not found: $1 — this gate has no target to run against"; }
# gate_require_file <repo-relative path> <what it is>
gate_require_file() { [[ -f "$CTL_ROOT/$1" ]] || die "$2 not found: $1 — this gate has no target to run against"; }

# gate_reject_args <command> <hint> [args…] — a gate takes no arguments.
gate_reject_args() {
  local cmd="$1" hint="$2"; shift 2
  (( $# == 0 )) || die "ctl $cmd takes no arguments (got: $*) — $hint"
  return 0
}

# gate_apps <manifest> — the app folders under apps/ that hold <manifest> (pyproject.toml,
# package.json, Cargo.toml, go.mod), one per line, repo-relative. Packages and the database
# folder are included when they carry the manifest; node_modules and vendored trees are not.
# A rung that finds nothing for an ecosystem the repo does not use simply has no work there.
gate_apps() {
  find "$CTL_ROOT/apps" -maxdepth 3 -name "$1" -not -path '*/node_modules/*' -not -path '*/target/*' \
    -not -path '*/.venv/*' -printf '%h\n' 2>/dev/null | sed "s|^$CTL_ROOT/||" | sort
}

# ── --quiet, ONE IMPLEMENTATION FOR EVERY RUNG ───────────────────────────────
# A green gate is read far more often than a red one. `--quiet` keeps the counts and drops the
# prose. IT HIDES NOTHING THAT FAILED: the output is captured, never discarded, and a red rung
# prints every line it wrote. It works by RE-EXECUTING the rung with the flag removed, so no rung
# threads a quiet mode through its body.

# the count lines worth keeping when a rung passed: pytest / bun / cargo / go / playwright shapes,
# a RED verdict, and the rung's own closing line
GATE_COUNTS='[0-9]+[[:space:]]+(pass|fail|skip|passed|failed|warning|error)|test result:|^(ok|FAIL)[[:space:]]|— RED|(✓|✗) gate '

# gate_report_capture <log> <rc> — everything when it failed, the counts when it passed
gate_report_capture() {
  local log="$1" rc="$2"
  if (( rc != 0 )); then cat "$log"; else grep -E "$GATE_COUNTS" "$log" | sed 's/^/  /' || true; fi
}

# gate_quiet_reexec "$@" — a rung's FIRST act. With -q/--quiet present it re-runs the rung without
# the flag, captured, and NEVER RETURNS. Without the flag it returns at once and the rung runs loud.
# GATE_QUIET_ACTIVE guards the recursion.
gate_quiet_reexec() {
  local want=0 rest=() arg
  for arg in "$@"; do case "$arg" in -q|--quiet) want=1 ;; *) rest+=("$arg") ;; esac; done
  (( want )) || return 0
  [[ -n "${GATE_QUIET_ACTIVE:-}" ]] && return 0
  local log rc=0 started=$SECONDS name
  name="$(basename "$0" .sh)"
  log="$(mktemp -t gate-XXXXXX)"
  GATE_QUIET_ACTIVE=1 bash "$0" ${rest[@]+"${rest[@]}"} >"$log" 2>&1 || rc=$?
  gate_report_capture "$log" "$rc"
  rm -f "$log"
  (( rc == 0 )) && ok "gate $name green — $(( SECONDS - started ))s"
  exit "$rc"
}

# gate_usage <rung> <summary> <body> [note] — the help every rung prints; the -q line is shared
gate_usage() {
  print_help "gate $1" "$2" "gate $1 [-q] [-h]" \
"Options
  -q, --quiet   print this rung's counts and its duration when it PASSES; a red run still prints in full
  -h, --help    show this help

$3" "${4:-}"
}
