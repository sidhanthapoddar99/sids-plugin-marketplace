#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
setup_scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$setup_scripts/_discovery.sh"
source "$setup_scripts/_credentials.sh"

usage() { print_help "setup" "Create .env, generate declared local credentials, create dirs, install deps." \
  'setup [-h]' \
"Options
  -h, --help      show this help

Steps
  1. copy .env.template if missing; append missing keys, preserve supplied values
  2. generate blank local credentials listed in scripts/config/generated-credentials.conf
  3. load the environment and create configured data, logs and backup directories
  4. refuse unresolved '<version>' placeholders before installing toolchains
  5. install and activate declared mise tools; install dependencies under apps
     (at most 12 levels, excluding dependency, cache and build directories)
  6. install hooks when lefthook.yml is present

Requires Bash, standard Unix shell utilities, and openssl for generated credentials.
Exit 0 only when every required tool and dependency step succeeds."; }

is_help "${1:-}" && { usage; exit 0; }
(( $# == 0 )) || die "usage: ctl setup [-h]"
step "env files (template → file)"
sync_env_template || die "setup could not sync env templates"
step "local credentials"
generate_local_credentials "$setup_scripts/generated-credentials.conf" || die "setup could not generate local credentials"
require_env
validate_setup_credentials "$setup_scripts/generated-credentials.conf" "$setup_scripts/required-credentials.conf" || die "setup credentials are incomplete"
resolve_storage_dirs
step "ensuring configured storage dirs"
for service in "${DATA_SVCS[@]}"; do mkdir -p "$DATA_DIR/$service"; done
mkdir -p "$LOGS_DIR/dev" "$LOGS_DIR/run" "$LOGS_DIR/test_build" "$BACKUP_DIR"

step "installing toolchains + dependencies"
sync_source_dependencies || die "setup dependency installation failed"
if [[ -f lefthook.yml && -e .git ]]; then
  require_tools lefthook || die "setup requires lefthook"
  lefthook install || die "lefthook install failed"
fi
say "next: ctl dev"
