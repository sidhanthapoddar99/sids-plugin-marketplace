#!/usr/bin/env bash
# container/build.sh — `ctl build [app…|cli]`. Build the service images through compose.
# Frontend build args (VITE_*, NEXT_PUBLIC_*) come from apps/<frontend>/.env: compose lists the arg
# names without values, and this script exports each frontend's .env into the process environment
# before `compose build`, so compose picks them up. It is the ONE place ctl touches an app .env,
# and it forwards the file opaquely — it never interprets the keys. `cli` builds the Go binary instead.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "build" "Build the service images (compose build) or the Go CLI binary." \
  'build [app…|cli] [-h]' \
"Arguments
  (none)          every service in compose.base.yaml that has a build: context
  app…            only these services (api engine web dashboard …)
  cli             go build apps/cli → apps/cli/bin/

Options
  -h, --help      show this help" \
"Frozen test builds are a different verb: ctl build save|start|clean (see ctl build save -h)."; }

is_help "${1:-}" && { usage; exit 0; }
if [[ "${1:-}" == cli ]]; then
  require_tools go
  step "go build apps/cli"
  ( cd apps/cli && mkdir -p bin && go build -o bin/ ./cmd/... ) && ok "apps/cli/bin/"
  exit 0
fi
require_env; require_docker
# forward every frontend .env as build args (opaque: names listed in compose.base.yaml build.args).
# Static frontends live in apps/multi-web-app/<name>/; the SSR one is apps/dashboard/.
for fe in apps/multi-web-app/*/ apps/dashboard/; do [[ -f "$fe.env" && -f "${fe}package.json" ]] && load_env_file "$fe.env"; done
step "docker compose build ${*:-(all)}"
dc build "$@"
ok "images built"
