#!/usr/bin/env bash
# Shared helpers, sourced by ctl and every worker. No side effects on source.
#
# log <level> <msg>       coloured stderr
# die <msg>               log error, exit 1
# load_env                export .env with skip-if-set. Never `source .env`.
# require_env KEY...      die if any key is blank
# compose_files <mode> [+mod...]
#                         prints the -f list:
#                           dev  → compose.db.yaml
#                           up   → compose.db.yaml compose.base.yaml + modifiers (default +expose_nginx)
#                         +env_override runs require_env on the keys it maps
# compose <mode> [+mod...] -- <args>
#                         docker compose with the assembled -f list
# route <verb> [args]     find scripts/<group>/<verb>.sh, groups in order config dev container db test; exec it
