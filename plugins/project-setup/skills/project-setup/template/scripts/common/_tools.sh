#!/usr/bin/env bash
# scripts/common/_tools.sh — the toolchain .mise.toml declares: install, activate, require.
# A missing tool is installed, never worked around. Each failure names the install step, because a
# script that avoids a tool drops what the tool did while every test still passes.

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
  mise_bin=$(command -v mise) || {
    err "mise is required by the project toolchain declaration — install it (curl https://mise.run | sh, or see https://mise.jdx.dev), then run ctl setup"
    return 1
  }
  if [[ $install == true ]]; then
    (cd "$CTL_ROOT" && "$mise_bin" install) || { err "mise install failed"; return 1; }
  fi
  while IFS= read -r variable; do
    case "$variable" in PATH|JAVA_HOME|GOROOT|RUSTUP_TOOLCHAIN) continue ;; esac
    [[ -v $variable ]] || continue
    preserved["$variable"]=${!variable}
  done < <(compgen -e)
  activation=$(cd "$CTL_ROOT" && "$mise_bin" env -s bash) || { err "mise activation failed"; return 1; }
  [[ -n $activation ]] || { err "mise activation returned no environment"; return 1; }
  eval "$activation" || { err "mise activation failed"; return 1; }
  for variable in "${!preserved[@]}"; do export "$variable=${preserved[$variable]}"; done
  hash -r
  CTL_TOOLS_ACTIVE_ROOT=$CTL_ROOT
}

# declared_tool_version <mise tool> — the version .mise.toml declares for it; 1 when it is not declared.
declared_tool_version() {
  local name=$1 file line key value
  for file in "$CTL_ROOT/.mise.toml" "$CTL_ROOT/mise.toml"; do
    [[ -f $file ]] || continue
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line == *=* ]] || continue
      key=${line%%=*}; key=${key//[[:space:]\"]/}
      [[ $key == "$name" ]] || continue
      value=${line#*=}
      [[ $value =~ \"([^\"]*)\" ]] && value=${BASH_REMATCH[1]}
      printf '%s\n' "$value"
      return 0
    done < "$file"
  done
  return 1
}

# tool_install_hint <executable> — the install step for a missing tool, read from .mise.toml.
tool_install_hint() {
  local name version
  case "$1" in cargo|rustc|rustup) name=rust ;; python3) name=python ;; *) name=$1 ;; esac
  if ! version=$(declared_tool_version "$name"); then
    printf 'declare %s in .mise.toml and run ctl setup, or install it with the system package manager' "$name"
  elif [[ $version == *'<version>'* ]]; then
    printf "%s is declared in .mise.toml as '<version>': resolve the version with the user, then run ctl setup" "$name"
  else
    printf '%s is declared in .mise.toml: run ctl setup to install it' "$name"
  fi
}

# A mise shim on PATH runs only when some mise config selects a version for the current directory.
# A tool this repo does not declare can resolve to such a shim and fail, so the hint names the shim.
require_tools() {
  local tool found
  activate_tools || return 1
  for tool in "$@"; do
    found=$(command -v "$tool" 2>/dev/null) \
      || { err "required tool missing on PATH: $tool — $(tool_install_hint "$tool"). Install it; do not code around it."; return 1; }
    case "$tool" in
      go|openssl) "$tool" version >/dev/null 2>&1 ;;
      *) "$tool" --version >/dev/null 2>&1 ;;
    esac || {
      [[ $found == */shims/* ]] && found="$found, a mise shim with no version selected for this repo"
      err "required tool cannot run: $tool ($found) — $(tool_install_hint "$tool"). Install it; do not code around it."
      return 1
    }
  done
}
