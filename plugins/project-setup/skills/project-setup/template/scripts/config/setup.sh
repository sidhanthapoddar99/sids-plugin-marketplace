#!/usr/bin/env bash
# config/setup.sh — `ctl setup` and `ctl setup env`. Both run setup_env, the one env step, so the
# two cannot drift. `ctl setup env` stops there and installs nothing; `ctl setup` then installs the
# toolchains and dependencies.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
setup_scripts=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$setup_scripts/_discovery.sh"
source "$setup_scripts/_credentials.sh"

ENV_STEPS="  1. copy .env.template to .env when .env is missing; append each key the template gained,
     with its template value; keep every existing line and value
  2. generate the blank local credentials listed in scripts/config/generated-credentials.conf,
     then require every active credential and those in scripts/config/required-credentials.conf
  3. resolve BASE_DIR, DATA_DIR, LOGS_DIR and BACKUP_DIR; create the data, logs and backup dirs"

usage() { print_help "setup" "Create .env and credentials, create the storage dirs, install toolchains and deps." \
  'setup [env] [-h]' \
"Subcommands
  env             the environment only: steps 1-3. Installs no toolchain and no dependency

Options
  -h, --help      show this help

Steps
$ENV_STEPS
  4. refuse unresolved '<version>' placeholders before installing toolchains
  5. install and activate declared mise tools; install dependencies under apps
     (at most 12 levels, excluding dependency, cache and build directories)
  6. install hooks when lefthook.yml is present

Requires Bash, standard Unix shell utilities, and openssl for generated credentials.
Exit 0 only when every required tool and dependency step succeeds."; }

usage_env() { print_help "setup env" "Set up the environment only: .env, generated credentials, storage dirs." \
  'setup env [-h]' \
"Options
  -h, --help      show this help

Steps
$ENV_STEPS

Installs no toolchain and no dependency, so it runs before the versions are resolved, and on a
host that only runs images. \`ctl setup\` runs these same steps first. A rerun keeps every value
and never rotates a credential.
Requires Bash, standard Unix shell utilities, and openssl for generated credentials."; }

# setup_env — the env step: .env, its credentials and the storage dirs it names. The storage dirs
# belong here because they are what .env configures, creating them installs nothing, and Docker
# creates a missing bind-mount source as root.
setup_env() {
  local service
  step "env files (template → file)"
  sync_env_template || die "setup could not sync env templates"
  step "local credentials"
  generate_local_credentials "$setup_scripts/generated-credentials.conf" || die "setup could not generate local credentials"
  require_env
  validate_setup_credentials "$setup_scripts/generated-credentials.conf" "$setup_scripts/required-credentials.conf" || die "setup credentials are incomplete"
  step "storage dirs"
  resolve_storage_dirs || die "setup could not resolve the storage paths in .env"
  for service in "${DATA_SVCS[@]}"; do mkdir -p -- "$DATA_DIR/$service" || die "setup could not create $DATA_DIR/$service"; done
  mkdir -p -- "$LOGS_DIR/dev" "$LOGS_DIR/run" "$LOGS_DIR/test_build" "$BACKUP_DIR" || die "setup could not create the dirs under $LOGS_DIR"
  ok "data $DATA_DIR · logs $LOGS_DIR · backups $BACKUP_DIR"
}

if [[ ${1:-} == env ]]; then
  shift
  is_help "${1:-}" && { usage_env; exit 0; }
  (( $# == 0 )) || die "usage: ctl setup env [-h]"
  setup_env
  say "next: ctl setup installs the toolchains and dependencies"
  exit 0
fi
is_help "${1:-}" && { usage; exit 0; }
(( $# == 0 )) || die "usage: ctl setup [env] [-h]"
setup_env

step "installing toolchains + dependencies"
sync_source_dependencies || die "setup dependency installation failed"
if [[ -f lefthook.yml && -e .git ]]; then
  require_tools lefthook || die "setup requires lefthook"
  lefthook install || die "lefthook install failed"
fi
say "next: ctl dev"
