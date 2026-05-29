#!/usr/bin/env bash
# manage-check-env.sh — diff .env keys against .env.example. Helper; also used by `ctl status`.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"; cd "$CTL_ROOT"

usage() { print_help "check-env" "Diff .env keys against .env.example; fail on missing keys." \
  'check-env [-h]' \
"Options
  -h, --help      show this help" \
"Helper script — \`ctl status\` runs this as part of its env check."; }

is_help "${1:-}" && { usage; exit 0; }
check_env_schema
