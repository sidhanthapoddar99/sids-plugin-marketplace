#!/usr/bin/env bash
# gate/clones.sh — `ctl gate clones`. BY NAME, never in the ladder: copy-pasted code, measured
# on demand with jscpd through `bunx` (deliberately not a dependency — a tool nobody needs daily
# is one more thing to upgrade for ever). Run it at a stage close-out, or when a round felt like
# it copied something. A clone is 10+ lines and 70+ tokens repeated; below that the matches are
# shapes the language forces.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "gate clones" "measure copy-pasted code with jscpd (by name, never in the ladder)" \
  'gate clones [--all] [--max <percent>] [--report] [-h]' \
"Options
      --all       include test files — default is production code only
      --max <n>   exit 1 if the duplicated-line percentage is above n
      --report    write an HTML report to .jscpd/ as well as printing
  -h, --help      show this help

Scans every app under apps/ (Python, TypeScript, Rust, Go). Read a hit before believing it: two
declarations of one shape for two subjects is what a domain-slice tree looks like on purpose."; }
is_help "${1:-}" && { usage; exit 0; }

ALL=0 MAX="" REPORT=0
while (( $# )); do case "$1" in
  --all)    ALL=1; shift ;;
  --max)    MAX="${2:-}"; [[ -n $MAX ]] || die "--max needs a percentage"; shift 2 ;;
  --report) REPORT=1; shift ;;
  *)        die "unknown argument: $1 (see \`ctl gate clones -h\`)" ;;
esac; done
require_tools bunx

ignore="**/node_modules/**,**/target/**,**/.venv/**,**/dist/**,**/.next/**"
scope="everything — tests too"
if (( ! ALL )); then ignore+=",**/*.test.*,**/*_test.go,**/test_*.py,**/tests/**,**/e2e/**,**/conformance/**"; scope="production code only"; fi
reporters="console"; (( REPORT )) && reporters="console,html"

step "gate clones — jscpd over apps/ ($scope)"
out="$(bunx jscpd apps --min-lines 10 --min-tokens 70 --reporters "$reporters" --ignore "$ignore" 2>&1)" \
  || die "jscpd could not run — the output was:"$'\n'"$out"
printf '%s\n' "$out"

# the Total row carries `NNN (N.NN%)`; take what is inside the brackets
pct="$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' \
  | awk -F'│' '/Total:/ { if (match($7, /\([0-9.]+%\)/)) print substr($7, RSTART + 1, RLENGTH - 3) }')"
[[ -n $pct ]] || die "jscpd ran but its total row could not be read — the format changed; a number nobody can read is worse than none"
hr; ok "duplicated lines: ${pct}%  ($scope)"
if [[ -n $MAX ]]; then
  awk -v p="$pct" -v m="$MAX" 'BEGIN{exit !(p>m)}' && die "the clone ratio is ${pct}%, above the ${MAX}% this run asked for"
  ok "inside the ${MAX}% this run asked for"
fi
