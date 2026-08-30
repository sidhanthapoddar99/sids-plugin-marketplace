#!/usr/bin/env bash
# admin/manage.sh — `ctl manage`. The break-glass operator console: a thin forward to the backend's
# manager.py, run on the host (or over SSH). It bypasses the web auth flow, so ACCESS TO THIS HOST IS
# THE SECURITY BOUNDARY. Every mutating action is written to the operator audit table. Needs the data
# core up (`ctl dev` or `ctl up --services=postgres,redis`). Model: neura-cloud-vault scripts/admin/manage.sh.
#
# [ADAPT] ADMIN_DIR — the backend that owns operator identity. One per product.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

ADMIN_DIR="apps/example-api-python"

usage() { print_help "manage" "Break-glass operator + platform-settings console (wraps manager.py)." \
  'manage <ops|settings> <action> [args…] [-h]' \
"Operators (ops)
  manage ops list                               every operator: email · role · state
  manage ops create <email> [--super] [--password PW | --auto-password]
                                                add an operator (SuperAdmin with --super). Prompts for a
                                                password unless a flag is given. The ONLY way to seed the first admin.
  manage ops disable <email>                    block auth. Never deletes: the audit history stays
  manage ops enable <email>                     re-enable
  manage ops reset-password <email> [--password PW | --auto-password]
  manage ops lockout <email> [--clear]          show, or clear, a login lockout

Platform settings
  manage settings list                          stored values + catalog defaults
  manage settings get <key>
  manage settings set <key> <value>             value parsed as JSON

Options
  -h, --help                                    show this help

Forwards verbatim to ${C_GRN}cd $ADMIN_DIR && uv run python manager.py …${C_RESET}; \`ctl manage ops --help\`
reaches manager.py's own argparse help. Destructive actions confirm unless -y is given." \
"Operator identity is never reachable through public signup or OAuth. This console is the path."; }

# bare `ctl manage` or `ctl manage -h` → this help; anything else forwards (so `ops --help` reaches argparse)
{ [[ $# -eq 0 ]] || { [[ $# -eq 1 ]] && is_help "$1"; }; } && { usage; exit 0; }

require_env; require_tools uv
[[ -f "$ADMIN_DIR/manager.py" ]] || die "$ADMIN_DIR/manager.py missing — the console lives at the backend root"
cd "$ADMIN_DIR" && exec uv run python manager.py "$@"
