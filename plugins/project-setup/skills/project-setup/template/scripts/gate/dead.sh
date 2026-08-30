#!/usr/bin/env bash
# gate/dead.sh — `ctl gate dead`. Rung 3: the dead-code census. Green only at ZERO findings in
# every census. It sits after typecheck because it reads the graph typecheck just proved compiles,
# and before test because a module the census condemns has tests not worth waiting for.
#
# Per ecosystem, from the tool the app pins (never `bunx <tool>`: a version resolved over the
# network on every run answers differently tomorrow):
#   TypeScript  knip, two runs — the FULL census (knip.json: every entry, tests among them) and the
#               PRODUCTION census (knip.production.json: tests out of the graph, so a file kept
#               alive only by its own test is a finding). A kept export is listed in the config
#               with its reason beside it, never a source comment.
#   Python      deptry (unused / missing / transitive deps) + `ruff check --select F401,F841`
#   Rust        cargo udeps (nightly) when the app pins it; clippy's dead_code is on under lint
#   Go          `go vet` covers unused; staticcheck U1000 when the app pins it
# [ADAPT] delete the ecosystems the repo does not use; knip configs live at the root (repo-wide tool).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage dead "find code, files and dependencies nothing reaches" \
"Two knip censuses at the root (knip.json, knip.production.json), deptry per Python app, cargo udeps
per Rust app when pinned. Every census must report zero. A finding is deleted, or kept through an
entry in the tool's config with the reason written beside it." \
"Run one census by hand: bunx --bun knip --config knip.json · uv run deptry . · cargo udeps"; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate dead" "run one census by hand with the tool's own CLI" "$@"

failed=() ran=0
census() {  # census <label> <cmd…> — exit 0 = clean, 1 = findings, other = could not run (dies)
  local what="$1"; shift; local rc=0
  step "gate dead — $what"
  "$@" || rc=$?
  case "$rc" in
    0) ok "$what: nothing" ;;
    1) failed+=("$what") ;;
    *) die "$what could not run (exit $rc) — nothing was censused" ;;
  esac
  ran=$(( ran + 1 ))
}

# TypeScript — the two knip censuses, from the root config, only when the repo has one
if [[ -f knip.json ]]; then
  require_tools bun
  KNIP="scripts/node_modules/.bin/knip"     # pinned in scripts/package.json; `cd scripts && bun install`
  gate_require_file "$KNIP" "the knip binary (cd scripts && bun install)"
  census "the full census (knip.json)" "$CTL_ROOT/$KNIP" --no-progress --config knip.json
  if [[ -f knip.production.json ]]; then
    census "the production census (knip.production.json)" "$CTL_ROOT/$KNIP" --no-progress --config knip.production.json \
      --production --include files,dependencies,unlisted,unresolved
  fi
fi

# Python — deptry + unused imports/variables, per app
while IFS= read -r d; do [[ -n $d ]] || continue
  census "deptry $d" bash -c "cd '$d' && uv run deptry ."
  census "ruff F401/F841 $d" bash -c "cd '$d' && uv run ruff check --select F401,F841 ."
done < <(gate_apps pyproject.toml)

# Rust — cargo udeps only where the app pins a nightly toolchain for it
while IFS= read -r d; do [[ -n $d ]] || continue
  if grep -q 'udeps' "$d/rust-toolchain.toml" 2>/dev/null; then
    census "cargo udeps $d" bash -c "cd '$d' && cargo udeps --workspace --all-targets"
  else say "  ${C_DIM}$d: cargo udeps not pinned — dead_code is judged by clippy under lint${C_RESET}"; fi
done < <(gate_apps Cargo.toml)

(( ran )) || die "0 censuses ran — no knip.json, no pyproject.toml, no Cargo.toml found; this rung has no target"
hr
if (( ${#failed[@]} )); then
  err "gate dead RED — ${#failed[@]} of $ran censuses found something:"
  for f in "${failed[@]}"; do err "  $f"; done
  err "  delete it, or keep it through an entry in the config with the reason beside it"
  exit 1
fi
ok "gate dead green — $ran censuses at zero findings"
