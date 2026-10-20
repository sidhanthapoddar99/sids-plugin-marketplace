#!/usr/bin/env bash
# scripts/template.sh — copy this skill's template/ into a repo, and verify a repo against it.
# Runs the same way on every host: the template is found beside this script, never by search.
set -euo pipefail
skill_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
template="$skill_dir/template"

usage() {
  cat <<'USAGE'
usage: template.sh copy <target>     copy template/ whole into <target>
       template.sh verify <target>   compare <target>'s ctl and scripts/ with template/

copy    refuses a target that already has ctl or scripts/, and copies nothing when a file it
        would write already exists; it names those files instead. Exit 0 when it copied.
verify  prints a verdict on its first line. Red: ctl is not the template router (hand-made), or a
        shared helper in scripts/common/ differs from this skill's template-core.sha256 outside its
        [ADAPT] blocks. A template copy then gets the list of every file of ctl and scripts/ that is
        changed, removed or added, for the report. Exit 0 only for a green verdict.
USAGE
}

die() { printf 'template.sh: %s\n' "$*" >&2; exit 1; }

resolve_target() {
  [[ -d $1 ]] || die "target is not a directory: $1"
  (cd -- "$1" && pwd)
}

copy_template() {
  local target path count
  local -a collisions=()
  target=$(resolve_target "$1")
  [[ -f $template/ctl ]] || die "no template/ctl beside this script: $template"
  [[ $target/ != "$skill_dir"/* ]] || die "target is inside the skill folder: $target"
  if [[ -e $target/ctl || -L $target/ctl || -e $target/scripts ]]; then
    die "$target already has ctl or scripts/. Copy into an empty staging folder instead
  (template.sh copy \"\$(mktemp -d)\"), then merge the staged files into the repo by hand."
  fi
  while IFS= read -r -d '' path; do
    [[ -e $target/$path || -L $target/$path ]] && collisions+=("$path")
  done < <(cd "$template" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0')
  if (( ${#collisions[@]} )); then
    printf 'template.sh: copied nothing. These files exist in both %s and template/:\n' "$target" >&2
    printf '  %s\n' "${collisions[@]}" >&2
    printf 'Rename each one (for example README.md to README.md.orig), run the copy again,\n' >&2
    printf 'then merge the old text into the new file.\n' >&2
    exit 1
  fi
  cp -a -- "$template/." "$target/"
  while IFS= read -r -d '' path; do chmod -R u+w -- "$target/$path"; done \
    < <(cd "$template" && find . -mindepth 1 -maxdepth 1 -printf '%P\0')
  count=$(cd "$template" && find . -type f | wc -l)
  printf 'copied %s files from %s into %s\n' "$count" "$template" "$target"
}

# list_differences <target> — every file of ctl and scripts/ that is changed, removed or added.
list_differences() {
  local target=$1 path
  if [[ -f $target/ctl ]] && ! cmp -s "$template/ctl" "$target/ctl"; then printf 'changed  ctl\n'; fi
  while IFS= read -r -d '' path; do
    if [[ ! -e $target/scripts/$path ]]; then printf 'removed  scripts/%s\n' "$path"
    elif ! cmp -s "$template/scripts/$path" "$target/scripts/$path"; then printf 'changed  scripts/%s\n' "$path"; fi
  done < <(cd "$template/scripts" && find . -type f -printf '%P\0' | sort -z)
  [[ -d $target/scripts ]] || return 0
  while IFS= read -r -d '' path; do
    [[ -e $template/scripts/$path ]] || printf 'added    scripts/%s\n' "$path"
  done < <(cd "$target/scripts" && find . -type f -not -path '*/__pycache__/*' -printf '%P\0' | sort -z)
}

# hand_made_reason <target> — why <target>'s router is not the template's; nothing when it is.
hand_made_reason() {
  if [[ ! -x $1/ctl ]]; then printf 'ctl is missing or not executable'
  elif ! grep -qF 'scripts/common/_lib.sh' "$1/ctl"; then printf 'ctl does not source scripts/common/_lib.sh'
  elif [[ ! -f $1/scripts/common/_lib.sh ]]; then printf 'scripts/common/_lib.sh is missing'
  fi
}

# verify_copy <target> — the verdict on line one, then the evidence. Exit 0 only for a green verdict.
verify_copy() {
  local target reason path
  local -a problems=() differences=()
  target=$(resolve_target "$1")
  # shellcheck source=../template/scripts/common/_template-core.sh
  source "$template/scripts/common/_template-core.sh"
  reason=$(hand_made_reason "$target")
  mapfile -t problems < <(template_core_problems "$target" "$template/scripts/common/template-core.sha256")
  mapfile -t differences < <(list_differences "$target")
  if [[ -n $reason ]]; then
    printf 'verdict: red — not from the template (%s). Offer to adopt the template; ask before you extend this ctl.\n' "$reason"
    printf '%s\n' "${differences[@]}" | awk '{ n[$1]++ } END { printf "  %d template files missing, %d files added, %d changed\n", n["removed"], n["added"], n["changed"] }'
    return 1
  fi
  if (( ${#problems[@]} )); then
    if [[ ! -f $target/scripts/common/template-core.sha256 ]]; then
      printf 'verdict: red — a template copy older than template-core.sha256. Offer the update, and on a yes copy scripts/common/ whole from %s, then restore or record each local change.\n' "$template"
    elif template_core_problems "$target" >/dev/null; then
      printf 'verdict: red — a copy of another template version. Offer the update, and on a yes copy scripts/common/ whole from %s.\n' "$template"
    else
      printf 'verdict: red — a template copy whose shared helpers were changed. Ask the user whether to restore each one or record it in AGENTS.md.\n'
    fi
  else
    printf "verdict: green — a template copy; the shared helpers match this skill's template.\n"
  fi
  (( ${#problems[@]} == 0 )) || printf 'FAIL  %s\n' "${problems[@]}"
  while IFS= read -r path; do printf 'NOTE  AGENTS.md records template-core %s as an exception\n' "$path"; done \
    < <(template_core_recorded "$target")
  printf 'Differences from %s; explain each one in the report:\n' "$template"
  (( ${#differences[@]} == 0 )) || printf '  %s\n' "${differences[@]}"
  (( ${#problems[@]} == 0 ))
}

case "${1:-}" in
  copy)   (( $# == 2 )) || { usage >&2; exit 2; }; copy_template "$2" ;;
  verify) (( $# == 2 )) || { usage >&2; exit 2; }; verify_copy "$2" ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
