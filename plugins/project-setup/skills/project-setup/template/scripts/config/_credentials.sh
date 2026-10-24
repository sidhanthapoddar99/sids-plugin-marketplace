#!/usr/bin/env bash

# sync_env_template, step 1 of the env step, lives in _env-merge.sh.

generate_credential() {
  local generator=$1 value='' chunk
  case "$generator" in
    hex32) openssl rand -hex 32 ;;
    password24)
      while (( ${#value} < 24 )); do
        chunk=$(openssl rand -base64 24) || return 1
        chunk=${chunk//[+\/=]/}
        value+=$chunk
      done
      printf '%s\n' "${value:0:24}"
      ;;
    *) err "unknown credential generator: $generator"; return 1 ;;
  esac
}

generate_local_credentials() {
  local declarations=$1 key generator extra line value temporary
  local -A generators=() generated=()
  [[ -r $declarations ]] || { err "missing or unreadable local credential declarations: $declarations"; return 1; }
  [[ -f $declarations ]] || { err "missing local credential declarations: $declarations"; return 1; }
  while read -r key generator extra || [[ -n $key ]]; do
    [[ -z $key || $key == \#* ]] && continue
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -z $extra ]] || { err "invalid credential declaration"; return 1; }
    case "$generator" in hex32|password24) ;; *) err "unknown credential generator for $key"; return 1 ;; esac
    [[ ! -v generators["$key"] ]] || { err "duplicate credential declaration: $key"; return 1; }
    generators["$key"]=$generator
  done < "$declarations"
  while IFS='=' read -r key value || [[ -n $key ]]; do
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -v generators["$key"] && ! -v $key ]] || continue
    grep -q "^${key}=" .env.template || continue
    value=${value%$'\r'}; value=${value%%[[:space:]]#*}; value=${value%"${value##*[![:space:]]}"}
    [[ -z $value ]] || continue
    generated["$key"]=$(generate_credential "${generators[$key]}") || { err "credential generation failed for $key"; return 1; }
  done < .env
  (( ${#generated[@]} )) || return 0
  temporary=$(mktemp "$CTL_ROOT/.env.setup.XXXXXX") || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    key=${line%%=*}
    if [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -v generated["$key"] ]]; then
      printf '%s=%s\n' "$key" "${generated[$key]}"
    else
      printf '%s\n' "$line"
    fi
  done < .env > "$temporary" || { rm -f "$temporary"; return 1; }
  mv "$temporary" .env || { rm -f "$temporary"; return 1; }
  for key in "${!generated[@]}"; do ok "generated $key"; done
}

# blank_by_design_keys <template> — each key whose comment line right above it says what an empty
# value means, such as "empty: every core" or "Empty or 0: off". Such a key is blank on purpose.
blank_by_design_keys() {
  local line note=0 pattern='empty( or [^:]*)?:'
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == \#* ]]; then
      if [[ ${line,,} =~ $pattern ]]; then note=1; else note=0; fi
    elif (( note )) && [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"; note=0
    else
      note=0
    fi
  done < "$1"
}

validate_setup_credentials() {
  local declarations=$1 required=$2 key generator extra
  local -A by_design=()
  while read -r key generator extra || [[ -n $key ]]; do
    [[ -z $key || $key == \#* ]] && continue
    if ! grep -q "^${key}=" .env.template; then
      if grep -q "^${key}=" .env; then warn "inactive local credential declaration: $key is absent from .env.template"; fi
      continue
    fi
    [[ -n ${!key} ]] || { err "required local credential is blank: $key (including process overrides)"; return 1; }
  done < "$declarations"
  [[ -f $required ]] || { err "missing required credential declarations: $required"; return 1; }
  while read -r key extra || [[ -n $key ]]; do
    [[ -z $key || $key == \#* ]] && continue
    [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -z $extra ]] || { err "invalid required credential declaration"; return 1; }
    grep -q "^${key}=" .env.template || { err "required credential is absent from .env.template: $key"; return 1; }
    [[ -v $key && -n ${!key} ]] || { err "required supplied credential is blank: $key"; return 1; }
  done < "$required"
  while IFS= read -r key; do by_design["$key"]=1; done < <(blank_by_design_keys .env.template)
  while IFS= read -r key; do
    [[ -v $key && -z ${!key} && ! -v by_design["$key"] ]] || continue
    warn "blank setting: $key (not required by setup; application requirements still apply)"
  done < <(env_keys .env.template)
}
