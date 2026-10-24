#!/usr/bin/env bash
# release/versions.sh — the version step of `ctl merge`. It sets the product's version once, as a
# branch lands on the default branch, so no commit on a branch raises it by hand:
#
#   - The version goes up when the branch changes shipped code since <base>: source under apps/,
#     apart from tests, fixtures and Markdown. The patch part goes up, or the part --minor or
#     --major names.
#   - A branch that already raised it keeps its own number.
#
#   bash scripts/release/versions.sh --base <commit> [--minor | --major] [--dry-run]
#
# It prints one line per version it sets, and `none` when it sets none. --dry-run prints the same and
# writes nothing. A project with versioned parts of its own, such as engines or packages, extends
# this step and records the extension in AGENTS.md § Exceptions; releases.md shows the shape.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

# [ADAPT] VERSION_FILES — the manifests that carry the product's one version, each with its version
# on a line of its own: `"version": "x.y.z"` in package.json, `version = "x.y.z"` in pyproject.toml or
# a Cargo.toml (the first such line, which is [package] or [workspace.package]). Empty: the product
# has no version yet, and the step sets none.
VERSION_FILES=()

base="" part="" write=1
while (( $# )); do case "$1" in
  --base) [[ -n ${2:-} ]] || die "--base needs a commit"; base="$2"; shift ;;
  --minor) part=minor ;;
  --major) part=major ;;
  --dry-run) write=0 ;;
  *) die "unknown argument $1" ;;
esac; shift; done
[[ -n $base ]] || die "--base <commit> names the commit the branch lands on"
(( ${#VERSION_FILES[@]} )) || { echo none; exit 0; }

# version_in <text> — the first x.y.z on a version line
version_in() { sed -nE 's/^[[:space:]]*"?version"?[[:space:]]*[:=][[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' <<<"$1" | head -1; }
# raise <x.y.z> <part> — every part to the right of the raised one becomes 0
raise() {
  local major minor patch; IFS=. read -r major minor patch <<<"$1"
  case $2 in major) echo "$((major + 1)).0.0" ;; minor) echo "$major.$((minor + 1)).0" ;; *) echo "$major.$minor.$((patch + 1))" ;; esac
}
# ships <path> — 0 for a path whose change reaches people
ships() {
  case "$1" in
    apps/*.md|*/tests/*|*/test/*|*/fixtures/*|*/__tests__/*|*.test.*|*_test.go|*_tests.rs) return 1 ;;
    apps/*) return 0 ;;
    *) return 1 ;;
  esac
}

current=$(version_in "$(<"${VERSION_FILES[0]}")")
[[ -n $current ]] || die "${VERSION_FILES[0]} has no x.y.z version line"
before=$(version_in "$(git show "$base:${VERSION_FILES[0]}" 2>/dev/null || true)")
if [[ -n $before && $current != "$before" ]]; then echo "product $before → $current (raised on the branch)"; exit 0; fi
if [[ -z $part ]]; then
  while IFS= read -r path; do ships "$path" && { part=patch; break; }; done < <(git diff --name-only "$base" HEAD)
fi
[[ -n $part ]] || { echo none; exit 0; }
next=$(raise "$current" "$part")
if (( write )); then
  for f in "${VERSION_FILES[@]}"; do
    [[ $(version_in "$(<"$f")") == "$current" ]] || die "$f does not carry $current; keep every VERSION_FILES entry on one version"
    # Only the first version line changes, so a dependency's version stays as it is.
    awk -v from="$current" -v to="$next" '!done && /^[[:space:]]*"?version"?[[:space:]]*[:=]/ && index($0, "\"" from "\"") { sub("\"" from "\"", "\"" to "\""); done=1 } { print }' "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done
fi
echo "product $current → $next"
