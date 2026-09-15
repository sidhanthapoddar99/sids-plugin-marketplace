#!/usr/bin/env bash

resolve_storage_dirs() {
  local key value
  : "${CTL_ROOT:?CTL_ROOT must be set}"
  for key in DATA_DIR LOGS_DIR BACKUP_DIR; do
    if [[ ! -v $key ]]; then
      case "$key" in
        DATA_DIR) value=./data ;;
        LOGS_DIR) value=./logs ;;
        BACKUP_DIR) value="$LOGS_DIR/backups" ;;
      esac
    else value="${!key}"; fi
    [[ -n ${value//[[:space:]]/} ]] || { printf '%s is blank\n' "$key" >&2; return 1; }
    [[ $value != *'${'* ]] || { printf '%s requires expanded environment\n' "$key" >&2; return 1; }
    [[ $value == /* ]] || value="$CTL_ROOT/${value#./}"
    printf -v "$key" '%s' "$value"
    export "$key"
  done
}
