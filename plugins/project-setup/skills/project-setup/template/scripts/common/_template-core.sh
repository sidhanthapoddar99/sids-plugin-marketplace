#!/usr/bin/env bash
# scripts/common/_template-core.sh — proves the shared helpers in scripts/common/ are the template's.
# SOURCE this, do not execute it. `ctl check` runs it on this repo.
#
# scripts/common/ is copied whole from the template and kept whole, because these helpers carry env
# loading, process ownership, locks and failure handling, and a smaller rewrite still passes every
# app test. template-core.sha256 lists each helper with the SHA-256 of its text. The lines of an
# [ADAPT] block are left out of the digest, so a project sets its knobs freely. A block starts at a
# line that begins with `# [ADAPT]`, takes the comment lines under it and the code lines after
# them, and ends at the next blank line or the next comment line after its code.
#
# A helper the project changes on purpose is recorded in AGENTS.md, under the heading
# "## Exceptions to the standard layout", as one line that holds `template-core <path>` and the reason.

# template_core_digest <file> — SHA-256 of the file without its [ADAPT] blocks.
template_core_digest() {
  awk '
    /^# \[ADAPT\]/              { block = 1; code = 0; next }
    block && /^[[:space:]]*$/   { block = 0 }
    block && /^#/ && code       { block = 0 }
    block && /^#/               { next }
    block                       { code = 1; next }
                                { print }
  ' "$1" | sha256sum | cut -d' ' -f1
}

# template_core_recorded <root> — each path AGENTS.md records as a `template-core <path>` exception.
template_core_recorded() {
  [[ -f $1/AGENTS.md ]] || return 0
  awk '/^## Exceptions to the standard layout/ { f = 1; next } /^## / { f = 0 } f' "$1/AGENTS.md" \
    | grep -oE 'template-core [^[:space:]`]+' | cut -d' ' -f2 || true
}

# template_core_problems <root> [manifest] — one line per listed helper that is missing or changed,
# skipping recorded exceptions. Returns 1 when it printed a line. The manifest defaults to the
# repo's own copy; a fresh bootstrap is checked against the template's copy instead.
template_core_problems() {
  local root=$1 manifest=${2:-$1/scripts/common/template-core.sha256} expected path found=0
  local -A recorded=()
  command -v sha256sum >/dev/null 2>&1 \
    || { printf '%s\n' "sha256sum is required to compare scripts/common/ with the template"; return 1; }
  [[ -f $manifest ]] \
    || { printf '%s\n' "${manifest#"$root/"} is missing — copy scripts/common/ whole from the template"; return 1; }
  while IFS= read -r path; do recorded["$path"]=1; done < <(template_core_recorded "$root")
  while read -r expected path || [[ -n $expected ]]; do
    [[ -z $expected || $expected == \#* || -v recorded["$path"] ]] && continue
    if [[ ! -f $root/$path ]]; then
      printf '%s\n' "$path is missing — copy it again from the template's scripts/common/"; found=1
    elif [[ $(template_core_digest "$root/$path") != "$expected" ]]; then
      printf '%s\n' "$path differs from the template outside its [ADAPT] blocks — copy it again from the template, or record 'template-core $path' with the reason under '## Exceptions to the standard layout' in AGENTS.md"
      found=1
    fi
  done < "$manifest"
  return $found
}
