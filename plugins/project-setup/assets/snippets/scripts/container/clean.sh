#!/usr/bin/env bash
# container/clean.sh — `ctl clean`. Tear down the stack and wipe caches + data volumes.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "clean" "Tear down the stack and wipe caches + data volumes." \
  'clean [-y|--yes] [-h]' \
"Options
  -y, --yes       skip the confirmation prompt
  -h, --help      show this help

Removes: docker volumes (DROPS DATA), apps/frontend/{node_modules,dist,.vite}, __pycache__."; }

is_help "${1:-}" && { usage; exit 0; }
yes=0; [[ "${1:-}" == -y || "${1:-}" == --yes ]] && yes=1
if (( ! yes )); then
  warn "this DROPS data volumes and clears caches."
  confirm "continue" || { say "aborted."; exit 0; }
fi
require_env   # compose interpolates ${VAR} even for `down` — without env, `${X:?}` files fail silently here
dc down -v 2>/dev/null || true
rm -rf apps/frontend/node_modules apps/frontend/dist apps/frontend/.vite
find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
ok "clean"
