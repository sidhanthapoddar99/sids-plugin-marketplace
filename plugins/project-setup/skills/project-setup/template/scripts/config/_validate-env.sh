#!/usr/bin/env bash
# Basic environment checks before dev installs or starts anything. Values stay private.
validate_dev_env() {
  local file key value default rc=0
  check_env_schema || die "configuration is out of date — run ctl setup"
  for file in .env.template .env; do
    awk '
      /^[[:space:]]*(#|$)/ { next }
      !/^[A-Za-z_][A-Za-z0-9_]*=/ {
        printf "%s:%d: expected an unquoted KEY=value assignment\n", FILENAME, FNR > "/dev/stderr"; bad=1; next
      }
      { key=$0; sub(/=.*/, "", key); if (seen[key]++) {
        printf "%s: duplicate key %s\n", FILENAME, key > "/dev/stderr"; bad=1
      } }
      END { exit bad }
    ' "$file" || rc=1
  done
  (( rc == 0 )) || die "fix the configuration lines above before starting development"
  require_env
  source "$CTL_ROOT/scripts/config/_credentials.sh"
  validate_setup_credentials "$CTL_ROOT/scripts/config/generated-credentials.conf" \
    "$CTL_ROOT/scripts/config/required-credentials.conf" || die "configure required credentials before starting development"
  while IFS='=' read -r key default || [[ -n $key ]]; do
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    default=${default%$'\r'}; default=${default%%[[:space:]]#*}
    default=${default%"${default##*[![:space:]]}"}
    value=${!key:-}
    if [[ -z ${value//[[:space:]]/} ]]; then
      [[ -z $default ]] || { err "$key needs a value; its template default is nonempty"; rc=1; }
      continue
    fi
    if [[ $value == \"* || $value == \'* || $value =~ \<[^\>]+\> ]]; then
      err "$key must have an unquoted value with placeholders filled"; rc=1; continue
    fi
    case "$key" in
      *_PORT)
        if [[ ! $value =~ ^[0-9]{1,5}$ ]] || (( 10#$value < 1 || 10#$value > 65535 )); then
          err "$key must be a port between 1 and 65535"; rc=1
        fi ;;
      *_URL|*_ENDPOINT)
        [[ $value =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]]+[^[:space:]]*$ ]] || { err "$key must be an absolute service URL"; rc=1; } ;;
      *_PREFIX)
        [[ $value == /* && $value != *[[:space:]?#]* ]] || { err "$key must be an absolute URL path without a query or fragment"; rc=1; } ;;
    esac
  done < .env.template
  (( rc == 0 )) || die "configuration is invalid — fix the named settings and retry"
  ok "development configuration is valid"
}
