#!/usr/bin/env bash
# admin/manage.sh — `ctl manage`. The break-glass operator console: a thin forward to the backend's
# manager.py. It bypasses the web auth flow, so ACCESS TO THIS HOST IS THE SECURITY BOUNDARY. Every
# mutating action is written to the operator audit table. Needs the data core up.
#
# One program, launched where the engines are reachable: inside the running api container under
# `ctl up` (manager.py ships in the image, at the backend root), else on the host under `ctl dev`,
# where +expose_db binds the engines to loopback. No engine port is published for the container path.
#
# [ADAPT] ADMIN_DIR / ADMIN_SVC — the backend that owns operator identity. One per product.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

ADMIN_DIR="apps/example-api-python"
ADMIN_SVC="api"

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

Forwards verbatim to ${C_GRN}python manager.py …${C_RESET} — inside the running $ADMIN_SVC container when the
stack is up (ctl up), else on the host as ${C_GRN}cd $ADMIN_DIR && uv run python manager.py …${C_RESET} (ctl dev).
\`ctl manage ops --help\` reaches manager.py's own argparse help. Destructive actions confirm unless -y is given." \
"Operator identity is never reachable through public signup or OAuth. This console is the path."; }

# bare `ctl manage` or `ctl manage -h` → this help; anything else forwards (so `ops --help` reaches argparse)
{ [[ $# -eq 0 ]] || { [[ $# -eq 1 ]] && is_help "$1"; }; } && { usage; exit 0; }

require_env
[[ -f "$ADMIN_DIR/manager.py" ]] || die "$ADMIN_DIR/manager.py missing — the console lives at the backend root"
if [[ "$(docker_state)" == ok && "$(svc_health "$ADMIN_SVC")" =~ ^(healthy|running)$ ]]; then
  say "${C_DIM}→ inside the $ADMIN_SVC container${C_RESET}"
  dc exec "$ADMIN_SVC" python manager.py "$@"; exit $?
fi
require_tools uv
say "${C_DIM}→ on the host (the $ADMIN_SVC container is not running)${C_RESET}"
cd "$ADMIN_DIR" && exec uv run python manager.py "$@"
