#!/usr/bin/env bash

activate_tools() {
  local install=false activation mise_bin variable
  local -A preserved=()
  case "${1:-}" in
    '') ;;
    --install) install=true ;;
    *) err "activate_tools: expected --install or no argument"; return 1 ;;
  esac
  [[ -f "$CTL_ROOT/.mise.toml" || -f "$CTL_ROOT/mise.toml" ]] || return 0
  if [[ $install == false && ${CTL_TOOLS_ACTIVE_ROOT:-} == "$CTL_ROOT" ]]; then return 0; fi
  mise_bin=$(command -v mise) || { err "mise is required by the project toolchain declaration"; return 1; }
  if [[ $install == true ]]; then
    (cd "$CTL_ROOT" && "$mise_bin" install) || { err "mise install failed"; return 1; }
  fi
  while IFS= read -r variable; do
    case "$variable" in PATH|JAVA_HOME|GOROOT|RUSTUP_TOOLCHAIN) continue ;; esac
    preserved["$variable"]=${!variable}
  done < <(compgen -e)
  activation=$(cd "$CTL_ROOT" && "$mise_bin" env -s bash) || { err "mise activation failed"; return 1; }
  [[ -n $activation ]] || { err "mise activation returned no environment"; return 1; }
  eval "$activation" || { err "mise activation failed"; return 1; }
  for variable in "${!preserved[@]}"; do export "$variable=${preserved[$variable]}"; done
  hash -r
  CTL_TOOLS_ACTIVE_ROOT=$CTL_ROOT
}

require_tools() {
  local tool
  activate_tools || return 1
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || { err "required tool missing on PATH: $tool"; return 1; }
    case "$tool" in
      go|openssl) "$tool" version >/dev/null 2>&1 ;;
      *) "$tool" --version >/dev/null 2>&1 ;;
    esac || { err "required tool cannot run: $tool"; return 1; }
  done
}
