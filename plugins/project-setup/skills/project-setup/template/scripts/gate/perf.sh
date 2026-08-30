#!/usr/bin/env bash
# gate/perf.sh — `ctl gate perf`. BY NAME: performance and reliability — benchmarks and load.
# Each app keeps them in tests/perf/ (pytest-benchmark, k6 scripts) or benches/ (cargo bench,
# criterion). `go test -race` is NOT here: it runs inside `ctl test` every time, because a race is
# cheapest to find there. A run with 0 targets dies by name.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { print_help "gate perf" "benchmarks and load tests, by name (never in the ladder)" \
  'gate perf [-h]' \
"Options
  -h, --help      show this help

Targets: apps/*/tests/perf/ (pytest-benchmark · k6 *.js against a running stack) and apps/*/benches/
(cargo bench). Compare against the last saved run in logs/perf/; a regression is a judgment, not an
exit code — this gate prints numbers and fails only when a target cannot run."; }
is_help "${1:-}" && { usage; exit 0; }
(( $# == 0 )) || die "ctl gate perf takes no arguments (got: $*)"

mkdir -p logs/perf; stamp="$(date +%Y%m%d-%H%M%S)"
failed=() ran=0
while IFS= read -r d; do [[ -n $d && -d "$d/tests/perf" ]] || continue
  step "perf $d (pytest-benchmark)"; ran=$((ran+1))
  ( cd "$d" && uv run pytest tests/perf --benchmark-only --benchmark-json="$CTL_ROOT/logs/perf/$stamp-${d##*/}.json" ) || failed+=("$d")
done < <(gate_apps pyproject.toml)
while IFS= read -r d; do [[ -n $d && -d "$d/tests/perf" ]] || continue
  require_tools k6
  while IFS= read -r s; do [[ -n $s ]] || continue
    step "perf $d (k6 ${s##*/})"; ran=$((ran+1))
    k6 run --summary-export="$CTL_ROOT/logs/perf/$stamp-${s##*/}.json" "$s" || failed+=("$s")
  done < <(find "$d/tests/perf" -name '*.js' | sort)
done < <(gate_apps package.json)
while IFS= read -r d; do [[ -n $d && -d "$d/benches" ]] || continue
  step "perf $d (cargo bench)"; ran=$((ran+1))
  ( cd "$d" && cargo bench ) | tee "$CTL_ROOT/logs/perf/$stamp-${d##*/}.txt" || failed+=("$d")
done < <(gate_apps Cargo.toml)

(( ran )) || die "0 perf targets found (apps/*/tests/perf, apps/*/benches) — nothing ran"
hr
(( ${#failed[@]} )) && { err "gate perf RED — could not run: ${failed[*]}"; exit 1; }
ok "gate perf green — $ran targets · results in logs/perf/$stamp-*"
