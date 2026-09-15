#!/usr/bin/env bash

sync_env_template() {
  local file key line
  for file in "${ENV_FILES[@]}"; do
    [[ -f "$file.template" ]] || { err "no $file.template to create $file from"; return 1; }
    if [[ ! -f $file ]]; then
      (umask 077; cp "$file.template" "$file"; chmod 600 "$file") || return 1
      ok "created $file from $file.template"
    fi
    while IFS= read -r line || [[ -n $line ]]; do
      key=${line%%=*}
      [[ $line == *=* && $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      if ! grep -q "^${key}=" "$file"; then
        if [[ -s $file && -n $(tail -c 1 "$file") ]]; then printf '\n' >> "$file"; fi
        printf '%s\n' "$line" >> "$file" || return 1
        ok "$file: added missing key $key"
      fi
    done < "$file.template"
  done
}

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

validate_setup_credentials() {
  local declarations=$1 required=$2 key generator extra
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
  while IFS= read -r key; do
    [[ -v $key && -z ${!key} ]] || continue
    warn "blank setting: $key (not required by setup; application requirements still apply)"
  done < <(env_keys .env.template)
}
