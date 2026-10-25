#!/usr/bin/env bash
# scripts/worktree/_pool.sh — the pool of warm worktree slots behind `ctl worktree`, and the
# main-tree guard that `ctl` runs before the build verbs. SOURCE it after _lib.sh.
#
# THE MAIN TREE is the repository's main checkout, whatever branch it has checked out. It owns
# .worktrees/, its .env is the one every slot's .env is written from, and merging happens there.
# A SLOT is a git worktree at <main tree>/.worktrees/slot-<n>. Its path never changes, so the build
# folders inside it (target/, node_modules/, .venv/) stay valid for every branch it carries. A slot is
# FREE when its HEAD is detached, and TAKEN when it is on a branch.
# A NAME is a branch name. Git's own worktree list is the one record of which slot holds which
# branch, so work happens in .worktrees/slot-<n>, the path ctl worktree create prints.
# THE STATE MUST MATCH: every slot folder is a worktree git lists, and a branch sits in one slot.
# Every command reads the whole pool first and stops, changing nothing, when it finds anything else,
# because a guess here could put work on the wrong branch.
source "$CTL_ROOT/scripts/worktree/_git.sh"

# wt_setting <key> <default> <env file> — the shell's value when the shell sets the key, even to
# empty, as load_env_file lets the shell win; else the env file's. An empty value keeps <default>.
wt_setting() {
  local value
  if [[ -v $1 ]]; then value=${!1}; else value=$(load_env_file "$3"; printf '%s' "${!1-}"); fi
  printf '%s\n' "${value:-$2}"
}

# worktree_guard <command> [args…] — unless WORKTREE_ONLY=0, the verbs that write build outputs into a
# checkout refuse in the main tree, so the main tree stays a checkout for git, ctl up, ctl setup and
# ctl worktree, its size stays flat, and no build runs cold beside the warm slots. Empty means on. `build start` only serves a frozen build and `build clean`
# frees space, so both pass, and help anywhere passes. `dev db` runs the data core in Docker, as
# ctl up does, and `dev stop` only stops processes, so both pass: stopping must always work. ctl setup
# is never guarded, because a new checkout must always be able to set itself up. Only the main tree
# is guarded, so its own .env is the one read. Outside a git checkout there is no worktree to work
# in, so nothing is guarded.
worktree_guard() {
  local cmd=$1 arg only; shift
  for arg; do ! is_help "$arg" || return 0; done
  [[ $cmd != build || ( ${1:-} != start && ${1:-} != clean ) ]] || return 0
  [[ $cmd != dev || ( ${1:-} != db && ${1:-} != stop ) ]] || return 0
  only=$(wt_setting WORKTREE_ONLY 1 "$CTL_ROOT/.env")
  case $only in 0) return 0 ;; 1) ;; *) die "WORKTREE_ONLY must be empty, 0 or 1 (got: $only)" ;; esac
  wt_in_main_tree "$CTL_ROOT" || return 0
  die "ctl $cmd writes build outputs into this checkout, and WORKTREE_ONLY=1 keeps the main tree for git, ctl up, ctl setup and ctl worktree. Work in a worktree: ctl worktree create <name>. A checkout with no slots, such as CI, sets WORKTREE_ONLY=0"
}

# wt_need_tools — the commands the pool runs; a missing one is named, so it gets installed
wt_need_tools() {
  local tool
  for tool in git flock timeout numfmt du find; do
    command -v "$tool" >/dev/null 2>&1 || die "ctl worktree needs $tool on PATH; install it, then run the command again"
  done
}

# wt_init — find the main tree and the pool folder. Sets WT_MAIN and WT_DIR.
wt_init() {
  wt_need_tools
  WT_MAIN=$(wt_main_tree "$CTL_ROOT") || die "ctl worktree needs a git checkout with a main tree (not a bare repository)"
  WT_DIR="$WT_MAIN/.worktrees"
}

# wt_settings — WORKTREE_SLOTS and WORKTREE_TRIM_DAYS from the shell or the main tree's .env, which
# owns the pool whichever checkout runs ctl. Sets WT_MAX and WT_TRIM_DAYS.
wt_settings() {
  WT_MAX=$(wt_setting WORKTREE_SLOTS 4 "$WT_MAIN/.env")
  [[ $WT_MAX =~ ^[1-9][0-9]?$ ]] || die "WORKTREE_SLOTS must be a whole number from 1 to 99 (got: $WT_MAX)"
  WT_TRIM_DAYS=$(wt_setting WORKTREE_TRIM_DAYS 7 "$WT_MAIN/.env")
  [[ $WT_TRIM_DAYS =~ ^[1-9][0-9]{0,4}$ ]] || die "WORKTREE_TRIM_DAYS must be a whole number of days, 1 or more (got: $WT_TRIM_DAYS)"
}

# wt_lock — hold .worktrees/.slots.lock until the command exits, so two pool commands never
# interleave; a second one says so and waits. It first checks that git ignores .worktrees/, because
# a slot that git can see could be committed into the main tree.
wt_lock() {
  wt_ignored "$WT_MAIN" .worktrees/ \
    || die "git does not ignore .worktrees/ here; add /.worktrees/ to .gitignore first, so a slot can never be committed"
  mkdir -p -- "$WT_DIR"
  exec {WT_LOCK_FD}>>"$WT_DIR/.slots.lock" || die "cannot open $WT_DIR/.slots.lock"
  if ! flock -n "$WT_LOCK_FD"; then
    say "· another ctl worktree command holds .worktrees/.slots.lock; waiting for it" >&2
    flock "$WT_LOCK_FD" || die "cannot take $WT_DIR/.slots.lock"
  fi
}

# wt_pool_load — read the pool. Sets WT_SLOTS (the slot numbers, ascending), WT_SLOT_BRANCH[n] (empty
# when free), WT_BRANCH_SLOT[branch]=n, WT_OTHER (other worktrees under .worktrees/), WT_OUTSIDE
# (worktrees outside .worktrees/), WT_OLD_LINKS (name links an older ctl made) and WT_PROBLEMS (each
# way the pool differs from the rules at the top of this file).
wt_pool_load() {
  local i path n links
  WT_SLOTS=() WT_OTHER=() WT_OUTSIDE=() WT_OLD_LINKS=() WT_PROBLEMS=()
  declare -gA WT_SLOT_BRANCH=() WT_BRANCH_SLOT=()
  wt_worktrees "$WT_MAIN" || die "git could not list the worktrees of $WT_MAIN"
  for i in "${!WT_LIST_PATH[@]}"; do
    (( i > 0 )) || continue                     # the first entry is the main tree
    path=${WT_LIST_PATH[$i]}
    if [[ $path =~ ^"$WT_DIR"/slot-([1-9][0-9]*)$ ]]; then
      n=${BASH_REMATCH[1]}
      [[ -d $path && ${WT_LIST_STATE[$i]} != prunable ]] || WT_PROBLEMS+=("git lists slot-$n, but its folder is missing")
      WT_SLOTS+=("$n"); WT_SLOT_BRANCH[$n]=${WT_LIST_BRANCH[$i]}
      [[ -z ${WT_LIST_BRANCH[$i]} ]] || WT_BRANCH_SLOT[${WT_LIST_BRANCH[$i]}]=$n
    elif [[ $path == "$WT_DIR"/* ]]; then WT_OTHER+=("${path#"$WT_DIR"/}")
    else WT_OUTSIDE+=("$path"); fi
  done
  mapfile -t WT_SLOTS < <(printf '%s\n' ${WT_SLOTS[@]+"${WT_SLOTS[@]}"} | sort -n | sed '/^$/d')
  for path in "$WT_DIR"/slot-*; do
    [[ -e $path || -L $path ]] || continue
    n=${path##*/slot-}
    [[ $n =~ ^[1-9][0-9]*$ && -v WT_SLOT_BRANCH[$n] ]] || WT_PROBLEMS+=(".worktrees/${path##*/} exists, but git does not list it as a slot")
  done
  [[ -d $WT_DIR ]] || return 0
  # An older ctl named each slot with a link, .worktrees/<branch> → ../…/slot-<n>. Git now holds that
  # record, so such a link only repeats it; wt_drop_old_links removes it. Other links are left alone.
  # A worktree folder is never walked into, so a big slot costs nothing here.
  links=$(find "$WT_DIR" -mindepth 1 \( -type d -exec test -e '{}/.git' \; -prune \) -o -type l -print0 | tr '\0' '\n') \
    || die "find could not read all of $WT_DIR"
  while IFS= read -r path; do
    [[ -n $path && $(readlink -- "$path") =~ ^(\.\./)*slot-[1-9][0-9]*$ ]] && WT_OLD_LINKS+=("$path")
  done <<< "$links"
  return 0
}

# wt_drop_old_links — remove the name links an older ctl made, and the folders they leave empty.
# Call it holding the pool lock, once the command has done its work, so a refusal changes nothing.
wt_drop_old_links() {
  local link dir
  for link in ${WT_OLD_LINKS[@]+"${WT_OLD_LINKS[@]}"}; do
    rm -f -- "$link" || continue
    say "· removed .worktrees/${link#"$WT_DIR"/}, a name link an older ctl made; git's worktree list names each slot's branch" >&2
    dir=$(dirname -- "$link")
    while [[ $dir != "$WT_DIR" ]] && rmdir -- "$dir" 2>/dev/null; do dir=$(dirname -- "$dir"); done
  done
  WT_OLD_LINKS=()
}

# wt_pool_check — stop, changing nothing, when the pool differs from the rules
wt_pool_check() {
  (( ${#WT_PROBLEMS[@]} )) || return 0
  local problem
  err "the slots under .worktrees/ are not in a state ctl worktree knows, so it changed nothing:"
  for problem in "${WT_PROBLEMS[@]}"; do printf '  - %s\n' "$problem" >&2; done
  die "fix each item by hand, then run the command again"
}

# wt_name_ok <name> — a worktree name is a branch name of letters, digits, '.', '_', '-' and '/',
# starting with a letter or digit, that git accepts
wt_name_ok() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] && wt_ref_name_ok "$WT_MAIN" "$1" \
    || die "'$1' is not a usable worktree name: use a branch name of letters, digits, '.', '_', '-' and '/', starting with a letter or digit"
}

# wt_compose_name <text> — <text> as compose turns a folder name into a project name: lower case,
# only a-z, 0-9, '_' and '-', and no leading '_' or '-'
wt_compose_name() {
  local s=${1,,}
  s=${s//[^a-z0-9_-]/}
  while [[ $s == [_-]* ]]; do s=${s#?}; done
  printf '%s\n' "$s"
}
