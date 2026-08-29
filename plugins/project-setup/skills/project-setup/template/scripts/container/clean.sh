#!/usr/bin/env bash
# container/clean.sh — `ctl clean`. Tear down the stack and wipe build caches. Data in data/ is
# NEVER touched here — the bind mounts are the database; wiping them is `rm -rf data/<svc>` by hand.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "clean" "Tear down the stack and wipe build caches (data/ is kept)." \
  'clean [-y|--yes] [-h]' \
"Options
  -y, --yes       skip the confirmation prompt
  -h, --help      show this help

Removes: the containers + network, node_modules/ dist/ .next/ per JS app, target/ per Rust app,
__pycache__, apps/example-tui-go/bin/. Keeps: data/, logs/, the .env.* files, every lockfile."; }

is_help "${1:-}" && { usage; exit 0; }
yes=0; [[ "${1:-}" == -y || "${1:-}" == --yes ]] && yes=1
if (( ! yes )); then
  warn "this stops the stack and deletes every build cache (data/ is kept)."
  confirm "continue" || { say "aborted."; exit 0; }
fi
require_env
dc down --remove-orphans 2>/dev/null || true
for d in apps/*/ apps/packages/*/; do
  [[ -f "$d/package.json" ]] && rm -rf "$d/node_modules" "$d/dist" "$d/.next" "$d/.vite"
  [[ -f "$d/Cargo.toml" ]]   && ( cd "$d" && cargo clean ) 2>/dev/null
done
rm -rf apps/example-tui-go/bin
find apps -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
ok "clean"
