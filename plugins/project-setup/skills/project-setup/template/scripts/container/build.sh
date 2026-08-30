#!/usr/bin/env bash
# container/build.sh — `ctl build [app…|cli]`. Build the service images through compose.
# Frontend build args (WEB_APP_PREFIX, WEB_DOCS_PREFIX, DASHBOARD_PREFIX) are interpolated by
# compose from .env.proxy (the prefixes), passed with --env-file like every other dc call. There is
# no per-frontend .env. `cli` builds the Go binary instead.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "build" "Build the service images (compose build) or the Go CLI binary." \
  'build [app…|cli] [-h]' \
"Arguments
  (none)          every service in compose.base.yaml that has a build: context
  app…            only these services (api engine web dashboard …)
  cli             go build apps/example-tui-go → apps/example-tui-go/bin/

Options
  -h, --help      show this help" \
"Frozen test builds are a different verb: ctl build save|start|clean (see ctl build save -h)."; }

is_help "${1:-}" && { usage; exit 0; }
if [[ "${1:-}" == cli ]]; then
  require_tools go
  step "go build apps/example-tui-go"
  ( cd apps/example-tui-go && mkdir -p bin && go build -o bin/ ./cmd/... ) && ok "apps/example-tui-go/bin/"
  exit 0
fi
require_env; require_docker
step "docker compose build ${*:-(all)}"
dc build "$@"
ok "images built"
