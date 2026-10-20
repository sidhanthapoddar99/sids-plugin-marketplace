#!/usr/bin/env bash
# Print the manifest of the template's shared helpers, scripts/common/template-core.sha256.
# Run it with --write after any change to a file in template/scripts/common/, because
# test_template_copy.py fails while the shipped manifest disagrees with the helpers.
set -euo pipefail
skill=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
common="$skill/template/scripts/common"
source "$common/_template-core.sh"

manifest() {
  local file
  printf '%s\n' "# SHA-256 of each shared helper without its [ADAPT] blocks. ctl check compares them." \
    "# Replace this file with the template's copy when you update scripts/common/; never edit it by hand."
  for file in "$common"/*; do
    [[ -f $file && ${file##*/} != template-core.sha256 ]] || continue
    printf '%s  scripts/common/%s\n' "$(template_core_digest "$file")" "${file##*/}"
  done
}

case "${1:-}" in
  '') manifest ;;
  --write) staged=$(mktemp); manifest > "$staged" && cat "$staged" > "$common/template-core.sha256"; rm -f "$staged" ;;
  *) printf 'usage: %s [--write]\n' "${0##*/}" >&2; exit 2 ;;
esac
