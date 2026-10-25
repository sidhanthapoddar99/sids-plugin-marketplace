#!/usr/bin/env bash
# scripts/gate/_receipt.sh — the record of each green gate run. SOURCE it after _lib.sh and
# _changed.sh; scripts/gate/all.sh is the one caller.
#
# A green run writes a receipt named by three things: the tree it checked, the tree it compared with,
# and its group. The checked tree is the working state, untracked files included. The compared tree
# is the base's tree (HEAD for a changed run, the delta base for a delta run), or `all` for --all. A
# later run with the same three names prints that the tree is already green and runs nothing,
# because the same inputs give the same result. Receipts live in the repository's common git folder,
# so a worktree's green run also covers the main tree after a fast-forward. Outside git no run keeps
# a receipt.

# gate_work_tree — print the tree hash of the working state: tracked changes and untracked files
# that git does not ignore. It writes through a copy of the index, so the real index never changes.
gate_work_tree() {
  local index rc=0 tree
  index=$(mktemp) || return 1
  # -p keeps the index's own time. Git trusts a file's cached size and time only when the file is
  # older than the index, so a copy stamped now would hide a same-size edit made in the same second
  # as the last commit, and the key would name a tree the run never had.
  cp -p "$(git rev-parse --git-path index)" "$index" 2>/dev/null || : > "$index"
  tree=$(GIT_INDEX_FILE="$index" git add -A -- . >/dev/null 2>&1 && GIT_INDEX_FILE="$index" git write-tree) || rc=$?
  rm -f "$index"
  (( rc == 0 )) && [[ -n $tree ]] || return 1
  printf '%s\n' "$tree"
}

# gate_receipt_dir — the folder every checkout of this repository shares.
gate_receipt_dir() { printf '%s/ctl-gate-green\n' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

# gate_receipt_key <full> <base commit> — set GATE_RECEIPT_TREE and GATE_RECEIPT_BASE. Returns 1
# outside git or when the tree cannot be written; the run then keeps no receipt.
gate_receipt_key() {
  [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == true ]] || return 1
  GATE_RECEIPT_TREE=$(gate_work_tree) || return 1
  if (( $1 )); then GATE_RECEIPT_BASE=all
  else
    [[ -n $2 ]] || return 1
    GATE_RECEIPT_BASE=$(git rev-parse "$2^{tree}" 2>/dev/null) || return 1
  fi
}

# gate_receipt_find <group> — print the receipt that covers this run, if one exists. A run of the
# whole ladder covers a static or dynamic run with the same base, and an --all run covers every base.
gate_receipt_find() {
  local dir name
  dir=$(gate_receipt_dir)
  for name in "$GATE_RECEIPT_TREE.$GATE_RECEIPT_BASE.$1" "$GATE_RECEIPT_TREE.$GATE_RECEIPT_BASE.all" \
              "$GATE_RECEIPT_TREE.all.$1" "$GATE_RECEIPT_TREE.all.all"; do
    [[ -f $dir/$name ]] && { printf '%s\n' "$dir/$name"; return 0; }
  done
  return 1
}

# gate_receipt_write <group> <summary> — record this green run, and drop receipts older than 30 days.
gate_receipt_write() {
  local dir
  dir=$(gate_receipt_dir)
  mkdir -p "$dir" || return 1
  printf '%s · gate %s · %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$2" > "$dir/$GATE_RECEIPT_TREE.$GATE_RECEIPT_BASE.$1"
  find "$dir" -type f -mtime +30 -delete 2>/dev/null || true
}
