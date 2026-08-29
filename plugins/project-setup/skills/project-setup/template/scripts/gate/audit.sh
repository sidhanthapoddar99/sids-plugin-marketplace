#!/usr/bin/env bash
# gate/audit.sh — `ctl gate audit`. Rung 4: static security analysis, dependency vulnerability
# scan, secret scan. The AI adversarial review is the fourth part of this class and is NOT a rung:
# it is done per round by a second model with its own shell (~/.claude/references/codex-companion.md).
#
# Per ecosystem, from the tool the app pins:
#   Python      bandit -r app · pip-audit (uv export → pip-audit -r)
#   TypeScript  bun audit (bun ≥ 1.2) per app
#   Rust        cargo audit (cargo-audit pinned in .mise.toml)
#   Go          govulncheck ./...
#   Repo        gitleaks detect --no-banner (pinned in .mise.toml); semgrep --config auto when pinned
# [ADAPT] delete the ecosystems the repo does not use. A tool named here and absent from PATH dies by
# name: a scan that silently did not run is the one failure mode this rung must never have.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/gate/_gate.sh"

usage() { gate_usage audit "static security analysis · dependency vulnerabilities · secret scan" \
"Repo-wide: gitleaks. Per app: bandit + pip-audit (Python), bun audit (TypeScript), cargo audit (Rust),
govulncheck (Go). Every scanner must run; a finding at or above its tool's default threshold is red.
Accepted findings are suppressed in the tool's own config with the reason beside them
(pyproject [tool.bandit], .gitleaksignore, audit.toml, package.json overrides) — never inline." \
"The adversarial review is the fourth part of this rung's class and runs per round, not here."; }
gate_quiet_reexec "$@"
is_help "${1:-}" && { usage; exit 0; }
gate_reject_args "gate audit" "run one scanner by hand with its own CLI" "$@"

failed=() ran=0
scan() {  # scan <label> <tool-on-PATH> <cmd…>
  local what="$1" tool="$2"; shift 2; local rc=0
  require_tools "$tool"
  step "gate audit — $what"
  "$@" || rc=$?
  (( rc == 0 )) && ok "$what: clean" || failed+=("$what (exit $rc)")
  ran=$(( ran + 1 ))
}

scan "gitleaks (secrets in the tree and history)" gitleaks gitleaks detect --no-banner --redact --source "$CTL_ROOT"

while IFS= read -r d; do [[ -n $d ]] || continue
  scan "bandit $d" uv bash -c "cd '$d' && uv run bandit -q -r app"
  scan "pip-audit $d" uv bash -c "cd '$d' && uv export --no-hashes --quiet | uv run pip-audit --strict -r /dev/stdin"
done < <(gate_apps pyproject.toml)

while IFS= read -r d; do [[ -n $d ]] || continue
  [[ -f "$d/bun.lock" ]] || { say "  ${C_DIM}$d: no bun.lock — nothing to audit${C_RESET}"; continue; }
  scan "bun audit $d" bun bash -c "cd '$d' && bun audit --audit-level=high"
done < <(gate_apps package.json)

while IFS= read -r d; do [[ -n $d ]] || continue
  scan "cargo audit $d" cargo bash -c "cd '$d' && cargo audit"
done < <(gate_apps Cargo.toml)

while IFS= read -r d; do [[ -n $d ]] || continue
  scan "govulncheck $d" govulncheck bash -c "cd '$d' && govulncheck ./..."
done < <(gate_apps go.mod)

(( ran )) || die "0 scanners ran — this rung has no target"
hr
if (( ${#failed[@]} )); then
  err "gate audit RED — ${#failed[@]} of $ran scanners found something:"
  for f in "${failed[@]}"; do err "  $f"; done
  exit 1
fi
ok "gate audit green — $ran scanners clean"
