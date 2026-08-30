#!/usr/bin/env bash
# gate/fuzz.sh — `ctl gate fuzz`. BY NAME: property-based and fuzz tests — hypothesis, fast-check,
# cargo fuzz. Each app keeps them in tests/fuzz/ (Python, TS) or fuzz/ (cargo-fuzz). They join the
# ladder only for a parser or a codec (then add them to the app's default suite, not here).
# A run with 0 fuzz targets found dies by name: "green" must never mean "nothing ran".
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { print_help "gate fuzz" "property-based and fuzz tests, by name (never in the ladder)" \
  'gate fuzz [--time <seconds>] [-h]' \
"Options
  --time <s>      seconds per cargo-fuzz target (default 60); hypothesis/fast-check use their profiles
  -h, --help      show this help

Targets: apps/*/tests/fuzz/ (pytest with hypothesis · bun test with fast-check) and apps/*/fuzz/
(cargo fuzz). Run it at a stage close-out, or when a round touched a parser, a codec, or input handling."; }
is_help "${1:-}" && { usage; exit 0; }
TIME=60
while (( $# )); do case "$1" in
  --time) TIME="${2:-}"; [[ $TIME =~ ^[0-9]+$ ]] || die "--time wants seconds"; shift 2 ;;
  *) die "unknown argument: $1 (see \`ctl gate fuzz -h\`)" ;;
esac; done

failed=() ran=0
while IFS= read -r d; do [[ -n $d && -d "$d/tests/fuzz" ]] || continue
  step "fuzz $d (hypothesis)"; ran=$((ran+1))
  ( cd "$d" && uv run pytest tests/fuzz ) || failed+=("$d")
done < <(gate_apps pyproject.toml)
while IFS= read -r d; do [[ -n $d && -d "$d/tests/fuzz" ]] || continue
  step "fuzz $d (fast-check)"; ran=$((ran+1))
  ( cd "$d" && bun test tests/fuzz ) || failed+=("$d")
done < <(gate_apps package.json)
while IFS= read -r d; do [[ -n $d && -d "$d/fuzz" ]] || continue
  require_tools cargo
  while IFS= read -r t; do [[ -n $t ]] || continue
    step "fuzz $d ($t, ${TIME}s)"; ran=$((ran+1))
    ( cd "$d" && cargo fuzz run "$t" -- -max_total_time="$TIME" ) || failed+=("$d/$t")
  done < <(cd "$d" && cargo fuzz list 2>/dev/null)
done < <(gate_apps Cargo.toml)

(( ran )) || die "0 fuzz targets found (apps/*/tests/fuzz, apps/*/fuzz) — nothing ran"
hr
(( ${#failed[@]} )) && { err "gate fuzz RED — ${failed[*]}"; exit 1; }
ok "gate fuzz green — $ran targets"
