#!/usr/bin/env bash
# container/build.sh — `ctl build`. Build frontend assets + backend image (local/dev tags).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "build" "Build frontend assets and the backend image (local/dev tags)." \
  'build [-h]' \
"Options
  -h, --help      show this help"; }

is_help "${1:-}" && { usage; exit 0; }
require_env
step "building frontend…";      ( cd apps/frontend && bun run build )
step "building backend image…"; docker build -t "${COMPOSE_PROJECT_NAME:-myapp}-backend:dev" apps/backend
ok "build complete"
