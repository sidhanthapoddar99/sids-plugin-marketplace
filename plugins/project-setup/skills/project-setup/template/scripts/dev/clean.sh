#!/usr/bin/env bash
# dev/clean.sh — remove disposable Rust debug builds and managed Rust dev logs.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/dev/_apps.sh"
source "$CTL_ROOT/scripts/dev/_controllers.sh"

usage() { print_help "clean rust" "Remove local Rust debug builds and managed Rust dev logs." \
  'clean rust [--dry-run] [-h]' \
"Options
  --dry-run      list targets without removing them
  -h, --help     show this help

Removes target/debug beside Rust Cargo.toml files under apps/, plus the managed
dev and controller logs for Rust apps named in scripts/dev/_apps.sh. Stop those
apps first. Keeps target/release, Cargo.lock, data, other app logs, and global
Cargo caches. External CARGO_TARGET_DIR values are not cleaned."; }

dry=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $arg (try ctl clean rust --help)" ;;
  esac
done

load_env_files
expand_env_refs || exit 1
resolve_storage_dirs || exit 1

mapfile -t rust_apps < <(rust_app_names)
declare -A log_names=()
for app in "${rust_apps[@]}"; do
  [[ $app =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid Rust app name: $app"
  log_names["dev-$app"]=1
  while IFS= read -r controller; do
    [[ -n $controller ]] || continue
    [[ $controller =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid controller name: $controller"
    log_names["controller-$controller"]=1
  done < <(controller_names "$app")
done

for name in "${!log_names[@]}"; do
  for record in "$LOGS_DIR/run/$name.process" "$LOGS_DIR"/run/follow-"$name"-*.process; do
    [[ ! -e $record && ! -L $record ]] || die "$record exists — stop the Rust dev process with ctl ps or ctl stop before cleaning"
  done
done

[[ ! -L "$LOGS_DIR/dev" ]] || die "$LOGS_DIR/dev is a symlink — refusing to clean logs outside the configured directory"
targets=()
mapfile -d '' -t manifests < <(discover_source_manifests)
for manifest in "${manifests[@]}"; do
  [[ $manifest == */Cargo.toml ]] || continue
  workspace=${manifest%/Cargo.toml}
  [[ ! -L $workspace/target ]] || die "$workspace/target is a symlink — refusing to clean an external build directory"
  [[ ! -L $workspace/target/debug ]] || die "$workspace/target/debug is a symlink — refusing to clean an external build directory"
  [[ ! -e $workspace/target/debug || -d $workspace/target/debug ]] || die "$workspace/target/debug is not a directory"
  [[ ! -d $workspace/target/debug ]] || targets+=("$workspace/target/debug")
done
for name in "${!log_names[@]}"; do
  log="$LOGS_DIR/dev/$name.log"
  [[ ! -L $log ]] || die "$log is a symlink — refusing to clean an external log"
  [[ ! -e $log || -f $log ]] || die "$log is not a regular file"
  [[ ! -f $log ]] || targets+=("$log")
done

if (( ${#targets[@]} == 0 )); then ok "no Rust debug builds or managed Rust dev logs found"; exit 0; fi
for target in "${targets[@]}"; do
  if (( dry )); then say "would remove $target"; continue; fi
  if [[ -d $target ]]; then rm -r -- "$target"; else rm -- "$target"; fi
  ok "removed $target"
done
