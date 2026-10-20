#!/usr/bin/env bash
# test/e2e.sh — `ctl test e2e`. Bring up the whole stack with every port published, against a
# THROWAWAY data dir and under its own compose project, run the browser suite in the first frontend
# that has e2e/, tear it all down. Never touches data/ or the running dev data core.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "test e2e" "Browser suite against a throwaway stack (ctl up +expose, temp DATA_DIR, project <name>-e2e)." \
  'test e2e [--keep] [-h]' \
"Options
  --keep          leave the stack running afterwards (debugging a red run)
  -h, --help      show this help

The stack's DATA_DIR is a fresh mktemp folder, so the suite starts from empty engines and
your data/ is never read or written. The stack runs as compose project <name>-e2e, so a running
dev data core keeps running; the app ports it publishes must be free, so stop the ctl dev apps
first. The suite itself is \`bun run test:e2e\` in apps/example-multi-web-app/app."; }

is_help "${1:-}" && { usage; exit 0; }
keep=0; [[ "${1:-}" == --keep ]] && keep=1
require_env; require_docker; require_tools bun jq
E2E_DIR=""; for d in apps/example-single-web-app-vite apps/example-multi-web-app/app; do [[ -d $d/e2e ]] && { E2E_DIR=$d; break; }; done
[[ -n $E2E_DIR ]] || die "no e2e/ folder in any frontend — nothing to run"

# The project's own name belongs to the dev data core, which outlives ctl dev on purpose. Under it,
# this stack would recreate the engines on the throwaway data and its teardown would remove them.
# compose decides the base name, so an empty COMPOSE_PROJECT_NAME gets the name compose would use.
export COMPOSE_PROJECT_NAME; COMPOSE_PROJECT_NAME="$(dc config --format json | jq -er .name)-e2e" \
  || die "docker compose could not name this project, so the e2e stack cannot get a name of its own"
# Exported DATA_DIR beats the value in .env: compose precedence is shell env > --env-file > compose file.
export DATA_DIR; DATA_DIR="$(mktemp -d -t e2e-data-XXXXXX)"
for s in "${DATA_SVCS[@]}"; do mkdir -p "$DATA_DIR/$s"; done
teardown() { (( keep )) && { warn "--keep: stack left up as compose project $COMPOSE_PROJECT_NAME, data in $DATA_DIR. Remove it with: COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME ctl down"; return 0; }
             step "tearing down"; dc down --remove-orphans >/dev/null 2>&1 || true; rm -rf "$DATA_DIR"; }
trap teardown EXIT

step "stack up (+expose) as $COMPOSE_PROJECT_NAME with DATA_DIR=$DATA_DIR"
bash "$CTL_ROOT/scripts/container/up.sh" +expose --nqa -y
step "bun run test:e2e ($E2E_DIR)"
( cd "$E2E_DIR" && bun run test:e2e ) && ok "e2e green" || { err "e2e red"; exit 1; }
