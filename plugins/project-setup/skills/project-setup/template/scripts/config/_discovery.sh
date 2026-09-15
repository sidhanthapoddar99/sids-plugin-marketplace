#!/usr/bin/env bash

discover_source_manifests() {
  [[ -d "$CTL_ROOT/apps" ]] || return 0
  find "$CTL_ROOT/apps" -maxdepth 12 \
    -type d \( -name node_modules -o -name target -o -name .venv -o -name venv \
      -o -name build -o -name dist -o -name vendor -o -name .git -o -name .hg \
      -o -name .svn -o -name .cache -o -name __pycache__ -o -name .next \
      -o -name .nuxt -o -name .output -o -name coverage -o -name .tox \
      -o -name third_party -o -name third-party -o -name generated -o -name .generated \) -prune -o \
    -type f \( -name pyproject.toml -o -name package.json -o -name go.mod \
      -o -name Cargo.toml -o -name rust-toolchain.toml \) -print0
}

install_source_dependencies() {
  local manifest directory workspace tool
  local -A fetched_workspaces=()
  for manifest in "$@"; do
    directory=${manifest%/*}
    case "${manifest##*/}" in
      pyproject.toml) tool=uv ;;
      package.json) tool=bun ;;
      go.mod) tool=go ;;
      Cargo.toml) tool=cargo ;;
      *) continue ;;
    esac
    require_tools "$tool" || return 1
    case "$tool" in
      uv) (cd "$directory" && uv sync) ;;
      bun) (cd "$directory" && bun install) ;;
      go) (cd "$directory" && go mod download) ;;
      cargo)
        workspace=$(cd "$directory" && cargo locate-project --workspace --message-format plain) || {
          err "$directory: cargo workspace discovery failed"; return 1;
        }
        [[ -f $workspace && $workspace == /* ]] || { err "$directory: invalid cargo workspace path"; return 1; }
        [[ -v fetched_workspaces["$workspace"] ]] && continue
        (cd "${workspace%/*}" && cargo fetch) || { err "$directory: cargo fetch failed"; return 1; }
        fetched_workspaces["$workspace"]=1
        ;;
    esac || { err "$directory: $tool dependency install failed"; return 1; }
    ok "$directory: $tool dependencies ready"
  done
}
