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
  local manifest directory workspace tool locked=false
  local -a uv_args=() bun_args=() cargo_args=()
  if [[ ${1:-} == --locked ]]; then
    locked=true; shift
    uv_args=(--locked); bun_args=(--frozen-lockfile); cargo_args=(--locked)
  fi
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
      uv)
        [[ $locked == false || -f $directory/uv.lock ]] || { err "$directory/uv.lock missing; generate the lockfile first"; return 1; }
        (cd "$directory" && uv sync "${uv_args[@]}") ;;
      bun)
        [[ $locked == false || -f $directory/bun.lock ]] || { err "$directory/bun.lock missing; generate the lockfile first"; return 1; }
        (cd "$directory" && bun install "${bun_args[@]}") ;;
      go)
        # Go checks the module graph in readonly mode; missing checksums can still
        # be added to go.sum by Go, unlike the frozen Bun/uv/Cargo lockfiles.
        if [[ $locked == true ]]; then
          (cd "$directory" && go list -mod=readonly -deps ./... >/dev/null)
        else
          (cd "$directory" && go mod download)
        fi ;;
      cargo)
        workspace=$(cd "$directory" && cargo locate-project --workspace --message-format plain) || {
          err "$directory: cargo workspace discovery failed"; return 1;
        }
        [[ -f $workspace && $workspace == /* ]] || { err "$directory: invalid cargo workspace path"; return 1; }
        [[ -v fetched_workspaces["$workspace"] ]] && continue
        [[ $locked == false || -f ${workspace%/*}/Cargo.lock ]] || { err "${workspace%/*}/Cargo.lock missing; generate the lockfile first"; return 1; }
        (cd "${workspace%/*}" && cargo fetch "${cargo_args[@]}") || { err "$directory: cargo fetch failed"; return 1; }
        fetched_workspaces["$workspace"]=1
        ;;
    esac || { err "$directory: $tool dependency install failed"; return 1; }
    ok "$directory: $tool dependencies ready"
  done
}

# Both setup and dev use the package managers directly; there is no dependency stamp.
sync_source_dependencies() (
  local manifest_list manifest
  local -a manifests=() unresolved=()
  manifest_list=$(mktemp) || return 1
  trap 'rm -f "$manifest_list"' EXIT
  discover_source_manifests > "$manifest_list" || { err "source package discovery failed"; return 1; }
  mapfile -d '' -t manifests < "$manifest_list"
  for manifest in "$CTL_ROOT/.mise.toml" "$CTL_ROOT/mise.toml" "${manifests[@]}"; do
    [[ -f $manifest ]] || continue
    if grep -qF '<version>' "$manifest"; then unresolved+=("$manifest"); fi
  done
  if (( ${#unresolved[@]} )); then
    err "resolve '<version>' placeholders before installing toolchains:"
    printf '%s\n' "${unresolved[@]}" >&2
    err "toolchains were not installed"
    return 1
  fi
  activate_tools --install || return 1
  install_source_dependencies "$@" "${manifests[@]}"
)
