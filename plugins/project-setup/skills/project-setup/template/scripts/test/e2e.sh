#!/usr/bin/env bash
# test/e2e.sh — `ctl test e2e`. Bring up the whole stack with every port published, against a
# THROWAWAY data dir, run the browser suite in apps/web/e2e, tear it all down. Never touches data/.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "test e2e" "Browser suite against a throwaway stack (ctl up +expose, temp DATA_DIR)." \
  'test e2e [--keep] [-h]' \
"Options
  --keep          leave the stack running afterwards (debugging a red run)
  -h, --help      show this help

The stack's DATA_DIR is a fresh mktemp folder, so the suite starts from empty engines and
your data/ is never read or written. The suite itself is \`bun run test:e2e\` in apps/web."; }

is_help "${1:-}" && { usage; exit 0; }
keep=0; [[ "${1:-}" == --keep ]] && keep=1
require_env; require_docker; require_tools bun
[[ -d apps/web/e2e ]] || die "no apps/web/e2e — nothing to run"

export DATA_DIR; DATA_DIR="$(mktemp -d -t e2e-data-XXXXXX)"
for s in "${DATA_SVCS[@]}"; do mkdir -p "$DATA_DIR/$s"; done
teardown() { (( keep )) && { warn "--keep: stack left up, data in $DATA_DIR"; return 0; }
             step "tearing down"; dc down --remove-orphans >/dev/null 2>&1 || true; rm -rf "$DATA_DIR"; }
trap teardown EXIT

step "stack up (+expose) with DATA_DIR=$DATA_DIR"
bash "$CTL_ROOT/scripts/container/up.sh" +expose --nqa -y
step "bun run test:e2e (apps/web)"
( cd apps/web && bun run test:e2e ) && ok "e2e green" || { err "e2e red"; exit 1; }
