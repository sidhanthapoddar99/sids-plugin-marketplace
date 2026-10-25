#!/usr/bin/env bash
# release/versions.sh — the version step of `ctl merge`. Versions move once, as a branch lands on the
# default branch, so no commit on a branch raises one by hand.
#
# A part is something people receive with its own version: a product, a service, a package, a CLI, a
# WASM module. Each part names where its version lives and which paths ship it.
#   - It goes up when the branch changes a path that ships it since <base>: the patch part, or the
#     part --minor or --major names. Tests, fixtures and Markdown ship nothing.
#   - A part whose version the branch already raised keeps that number.
#   - A repo with no parts sets none, and so does a branch that ships nothing.
#
#   bash scripts/release/versions.sh --base <commit> [--minor[=<part>]] [--major[=<part>]] [--dry-run]
#
# It prints one line per version it sets, `<part> <old> → <new>`, and `none` when it sets none. A part
# whose version is a git tag ends its line with `(tag <name>)`, and ctl merge creates that tag on the
# landed commit. --dry-run prints the same and writes nothing. A project whose parts move on another
# trigger, such as an engine's input hash, extends this step and records it in AGENTS.md § Exceptions.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] VERSION_PARTS — one line per versioned part: "<part> <where> [<path that ships it>…]".
#   <where> is where the version lives:
#     a manifest    package.json ("version"), pyproject.toml ([project] version), Cargo.toml ([package]
#                   or [workspace.package] version), or a VERSION file that holds only x.y.z, which
#                   serves any language. Manifests that carry one version are joined by commas and must
#                   agree: "product apps/api/pyproject.toml,apps/web/package.json apps".
#     tag:<prefix>  the version is the newest git tag <prefix>x.y.z, as a Go module's is:
#                   "cli tag:apps/cli/v apps/cli" lands as the tag apps/cli/v1.4.0. With no tag yet the
#                   part starts from 0.0.0.
#   The paths default to the folder of the first manifest; a tag: part names its own.
# Empty: the repo has no version yet, and the step sets none.
VERSION_PARTS=(
)

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'
base="" write=1
declare -A asked=()
while (( $# )); do case "$1" in
  --base) [[ -n ${2:-} ]] || die "--base needs a commit"; base="$2"; shift ;;
  --minor|--major) asked['*']=${1#--} ;;
  --minor=*|--major=*) level=${1%%=*}; asked[${1#*=}]=${level#--} ;;
  --dry-run) write=0 ;;
  *) die "unknown argument $1" ;;
esac; shift; done
[[ -n $base ]] || die "--base <commit> names the commit the branch lands on"
(( ${#VERSION_PARTS[@]} )) || { echo none; exit 0; }

names=()
for line in "${VERSION_PARTS[@]}"; do read -r name _ <<<"$line"; names+=("$name"); done
for key in "${!asked[@]}"; do
  if [[ $key == '*' ]]; then
    (( ${#names[@]} == 1 )) || die "name the part: --${asked[$key]}=<part>, one of: ${names[*]}"
    asked[${names[0]}]=${asked[$key]}; unset 'asked[*]'
  else
    [[ " ${names[*]} " == *" $key "* ]] || die "no part named $key; the parts are: ${names[*]}"
  fi
done

# toml_version <tables> — the version a TOML file on stdin keeps in one of <tables> (an awk regex of
# table names), so a dependency's or a tool's version line is never read.
toml_version() {
  awk -v tables="^[[]($1)[]][[:space:]]*(#.*)?$" '
    /^[[:space:]]*[[]/ { inside = ($0 ~ tables) }
    inside && /^[[:space:]]*version[[:space:]]*=/ { if (match($0, /"[^"]*"/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }'
}
toml_tables() { case "$(basename "$1")" in pyproject.toml) echo 'project' ;; *) echo 'package|workspace\.package' ;; esac; }
# read_version <file> — the x.y.z the file's text on stdin holds where its kind keeps the version.
read_version() {
  case "$(basename "$1")" in
    package.json) jq -r '.version // empty' 2>/dev/null ;;
    pyproject.toml|Cargo.toml) toml_version "$(toml_tables "$1")" ;;
    *) tr -d '[:space:]' ;;
  esac | grep -xE "$SEMVER" || true
}
# write_version <file> <from> <to> — change only the line read_version reads, then read it back.
write_version() {
  local f=$1 from=$2 to=$3
  case "$(basename "$f")" in
    package.json) sed -i -E "0,/\"version\"[[:space:]]*:[[:space:]]*\"${from//./\\.}\"/s//\"version\": \"$to\"/" "$f" ;;
    pyproject.toml|Cargo.toml)
      awk -v tables="^[[]($(toml_tables "$f"))[]][[:space:]]*(#.*)?$" -v from="\"$from\"" -v to="\"$to\"" '
        /^[[:space:]]*[[]/ { inside = ($0 ~ tables) }
        inside && !done && /^[[:space:]]*version[[:space:]]*=/ && (i = index($0, from)) {
          $0 = substr($0, 1, i - 1) to substr($0, i + length(from)); done = 1 } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
    *) printf '%s\n' "$to" > "$f" ;;
  esac
  [[ $(read_version "$f" < "$f") == "$to" ]] || die "$f does not read $to after the change; set it by hand and run again"
}
# lock_dir <dir> <lock name> — the nearest folder at or above <dir> holding the lock, inside the repo.
lock_dir() {
  local dir=$1
  while :; do
    [[ -f $dir/$2 ]] && { printf '%s\n' "$dir"; return 0; }
    [[ $dir == . || $dir == / ]] && return 1
    dir=$(dirname "$dir")
  done
}
# refresh_lock <manifest> — a lock that records the manifest's own version moves with it, because a
# locked install refuses a lock that disagrees. --offline changes no dependency. bun.lock records no
# workspace version, so a Bun package needs none.
refresh_lock() {
  local dir; dir=$(dirname "$1")
  case "$(basename "$1")" in
    Cargo.toml) if lock_dir "$dir" Cargo.lock >/dev/null; then require_tools cargo
      (cd "$dir" && cargo update --workspace --offline --quiet) || die "cargo could not update the Cargo.lock above $dir"; fi ;;
    pyproject.toml) if lock=$(lock_dir "$dir" uv.lock); then require_tools uv
      (cd "$lock" && uv lock --offline --quiet) || die "uv could not update $lock/uv.lock"; fi ;;
    package.json) if lock=$(lock_dir "$dir" package-lock.json); then require_tools npm
      (cd "$lock" && npm install --package-lock-only --ignore-scripts --offline --silent) || die "npm could not update $lock/package-lock.json"; fi ;;
  esac
}
# raise <x.y.z> <part> — every part to the right of the raised one becomes 0.
raise() {
  local major minor patch; IFS=. read -r major minor patch <<<"$1"
  case $2 in major) echo "$((major + 1)).0.0" ;; minor) echo "$major.$((minor + 1)).0" ;; *) echo "$major.$minor.$((patch + 1))" ;; esac
}
# ships <path> <paths…> — 0 for a changed path under one of the part's paths that reaches people.
ships() {
  local path=$1 dir; shift
  case "$path" in *.md|*/tests/*|*/test/*|*/fixtures/*|*/__tests__/*|*.test.*|*_test.go|*_test.rs|test_*.py|*/test_*.py) return 1 ;; esac
  for dir in "$@"; do
    if [[ $dir == . ]]; then case "$path" in ctl|scripts/*|.github/*|docker/*) continue ;; esac; return 0; fi
    [[ $path == "$dir" || $path == "$dir"/* ]] && return 0
  done
  return 1
}

mapfile -t changed < <(git diff --name-only --no-renames "$base" HEAD)
# shipped_level <paths…> — patch when a changed path ships the part, else nothing.
shipped_level() {
  local path
  for path in "${changed[@]}"; do if ships "$path" "$@"; then echo patch; return 0; fi; done
}
set_any=0
for line in "${VERSION_PARTS[@]}"; do
  read -r -a fields <<<"$line"
  name=${fields[0]} where=${fields[1]:-}
  [[ -n $where ]] || die "VERSION_PARTS: '$line' names no place for its version"
  paths=("${fields[@]:2}")
  level=${asked[$name]:-}

  if [[ $where == tag:* ]]; then
    prefix=${where#tag:}
    (( ${#paths[@]} )) || die "VERSION_PARTS: $name keeps its version in a tag, so it must name the paths that ship it"
    current=$(git tag --list "$prefix*" | sed "s|^$prefix||" | grep -xE "$SEMVER" | sort -V | tail -1 || true)
    current=${current:-0.0.0}
    [[ -n $level ]] || level=$(shipped_level "${paths[@]}")
    [[ -n $level ]] || continue
    next=$(raise "$current" "$level")
    ! git rev-parse -q --verify "refs/tags/$prefix$next" >/dev/null || die "the tag $prefix$next already exists"
    echo "$name $current → $next (tag $prefix$next)"; set_any=1
    continue
  fi

  IFS=, read -r -a files <<<"$where"
  (( ${#paths[@]} )) || paths=("$(dirname "${files[0]}")")
  current="" before=""
  for f in "${files[@]}"; do
    [[ -f $f ]] || die "VERSION_PARTS: $name names $f, which does not exist"
    v=$(read_version "$f" < "$f")
    [[ -n $v ]] || die "$f holds no x.y.z version where its kind keeps one; a version that comes from git tags is tag:<prefix>"
    [[ -z $current || $v == "$current" ]] || die "$name's manifests disagree ($current, and $v in $f); put them on one version"
    current=$v
  done
  before=$( { git show "$base:${files[0]}" 2>/dev/null || true; } | read_version "${files[0]}")
  if [[ -n $before && $current != "$before" ]]; then echo "$name $before → $current (raised on the branch)"; set_any=1; continue; fi
  [[ -n $level ]] || level=$(shipped_level "${paths[@]}")
  [[ -n $level ]] || continue
  next=$(raise "$current" "$level")
  if (( write )); then for f in "${files[@]}"; do write_version "$f" "$current" "$next"; refresh_lock "$f"; done; fi
  echo "$name $current → $next"; set_any=1
done
(( set_any )) || echo none
