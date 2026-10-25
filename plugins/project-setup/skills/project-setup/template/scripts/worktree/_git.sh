#!/usr/bin/env bash
# scripts/worktree/_git.sh — every git command that `ctl worktree` and the main-tree guard run.
# SOURCE it after _lib.sh. One file holds them, so the whole git surface of the pool reads in one
# place: it adds a worktree, switches or detaches one, and reads state. Nothing here removes a
# worktree, deletes a branch or rewrites history, because those stay a person's call.

# wt_git <dir> <args…> — git in <dir>, never paging and never prompting
wt_git() { local dir=$1; shift; GIT_TERMINAL_PROMPT=0 git -C "$dir" --no-pager "$@"; }

# wt_worktrees <dir> — every worktree of the repository <dir> belongs to, as `git worktree list`
# reports it: WT_LIST_PATH, WT_LIST_BRANCH (the short branch name, empty when detached) and
# WT_LIST_STATE (bare, prunable or empty). The first entry is the main tree. 1 when git fails.
wt_worktrees() {
  local out field path="" branch="" state=""
  WT_LIST_PATH=() WT_LIST_BRANCH=() WT_LIST_STATE=()
  out=$(wt_git "$1" worktree list --porcelain -z 2>/dev/null | tr '\0' '\n') || return 1
  while IFS= read -r field; do
    case $field in
      "worktree "*)          path=${field#worktree } ;;
      "branch refs/heads/"*) branch=${field#branch refs/heads/} ;;
      bare)                  state=bare ;;
      prunable*)             state=prunable ;;
      "")                    if [[ -n $path ]]; then WT_LIST_PATH+=("$path") WT_LIST_BRANCH+=("$branch") WT_LIST_STATE+=("$state"); fi
                             path="" branch="" state="" ;;
    esac
  done <<< "$out"$'\n'
}

# wt_main_tree <dir> — print the physical path of the main tree: the repository's main checkout,
# whatever branch it has checked out. Fails outside a git checkout and in a bare repository.
wt_main_tree() {
  wt_worktrees "$1" || return 1
  (( ${#WT_LIST_PATH[@]} )) && [[ ${WT_LIST_STATE[0]} != bare && -d ${WT_LIST_PATH[0]} ]] || return 1
  (cd -- "${WT_LIST_PATH[0]}" && pwd -P)
}

# wt_in_main_tree <dir> — 0 when <dir> is inside the main tree itself, not inside a linked worktree
wt_in_main_tree() {
  local own common
  own=$(wt_git "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  common=$(wt_git "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [[ $own == "$common" ]]
}

# wt_ref_name_ok <dir> <name> — 0 when <name> is a valid branch name
wt_ref_name_ok() { wt_git "$1" check-ref-format --branch "$2" >/dev/null 2>&1; }
# wt_branch_exists <dir> <name> — 0 when the local branch <name> exists
wt_branch_exists() { wt_git "$1" show-ref --verify --quiet "refs/heads/$2"; }
# wt_commit <dir> <ref> — print the full hash of the commit <ref> names
wt_commit() { wt_git "$1" rev-parse --verify --quiet --end-of-options "$2^{commit}"; }
# wt_short <dir> <commit> — print the short hash
wt_short() { wt_git "$1" rev-parse --short "$2"; }
# wt_current_branch <dir> — print the branch <dir> has checked out; nothing when its HEAD is detached
wt_current_branch() { wt_git "$1" symbolic-ref --quiet --short HEAD || true; }
# wt_default_branch <dir> — the branch origin/HEAD names; with no remote HEAD, main, else master when
# only that exists.
wt_default_branch() {
  local name
  name=$(wt_git "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  name=${name#origin/}
  if [[ -z $name ]]; then
    name=main
    ! wt_branch_exists "$1" main && wt_branch_exists "$1" master && name=master
  fi
  printf '%s\n' "$name"
}
# wt_ignored <dir> <path> — 0 when git ignores <path> (relative to <dir>)
wt_ignored() { wt_git "$1" check-ignore -q -- "$2"; }

# wt_add_slot <main tree> <path> <commit> — add a worktree at <path> with a detached HEAD
wt_add_slot() { wt_git "$1" worktree add --quiet --detach "$2" "$3"; }
# wt_switch <dir> <branch> — switch to an existing local branch, never guessing a remote one
wt_switch() { wt_git "$1" switch --quiet --no-guess "$2"; }
# wt_switch_new <dir> <branch> <commit> — create <branch> at <commit> and switch to it
wt_switch_new() { wt_git "$1" switch --quiet --no-guess --create "$2" "$3"; }
# wt_detach <dir> — detach HEAD at its current commit. The branch and every file stay.
wt_detach() { wt_git "$1" switch --quiet --detach; }

# wt_dirty <dir> — print uncommitted changes and untracked files git does not ignore, one per line.
# Ignored files (build folders, .env, data/, logs/) are not listed.
wt_dirty() { wt_git "$1" status --porcelain=v1 --untracked-files=normal; }

# wt_merged <dir> <branch> <commit> — 0 when <commit> holds <branch>'s work: the branch is an
# ancestor of <commit>, or merging it into <commit> would change nothing (merge-tree writes <commit>'s
# own tree). The second covers a branch merged by rebase or squash, whose old commits stay outside
# <commit>'s history although their work is in. 1 when the work is not in: a conflict, or any other
# tree. 2 when git cannot tell, for example a git older than 2.38 without merge-tree --write-tree.
wt_merged() {
  local merged tree rc=0
  wt_git "$1" merge-base --is-ancestor "refs/heads/$2" "$3" 2>/dev/null || rc=$?
  (( rc != 0 )) || return 0
  (( rc == 1 )) || return 2
  rc=0; merged=$(wt_git "$1" merge-tree --write-tree "$3" "refs/heads/$2" 2>/dev/null) || rc=$?
  (( rc == 0 )) || { (( rc == 1 )) && return 1; return 2; }
  tree=$(wt_git "$1" rev-parse --verify --quiet "$3^{tree}") || return 2
  [[ ${merged%%$'\n'*} == "$tree" ]]
}

# wt_reflog_file <dir> — the path of <dir>'s HEAD reflog, which changes on every checkout and commit
wt_reflog_file() { wt_git "$1" rev-parse --path-format=absolute --git-path logs/HEAD; }
