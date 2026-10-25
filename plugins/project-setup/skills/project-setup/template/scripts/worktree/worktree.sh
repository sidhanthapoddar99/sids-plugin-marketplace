#!/usr/bin/env bash
# worktree/worktree.sh — `ctl worktree create|list|remove|trim`: named worktrees on a fixed pool of
# warm slots under .worktrees/.
#
# Work happens in the slot (.worktrees/slot-<n>) that holds branch <name>; git's worktree list is
# the one record of which slot that is. A slot's path never changes, so its build folders stay warm
# across branches, and the repository stops growing with every new worktree. create takes a free slot, or adds one up to
# WORKTREE_SLOTS. remove frees a clean slot whose branch the main tree has merged. Nothing deletes a
# slot, a build folder or a branch; trim deletes only Cargo outputs that no build used for N days.
# _pool.sh holds the pool rules and the main-tree guard, _git.sh every git command, _env.sh a slot's
# .env, _busy.sh what still runs in a slot, and _trim.sh the trim.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/worktree/_pool.sh"
source "$CTL_ROOT/scripts/worktree/_env.sh"
source "$CTL_ROOT/scripts/worktree/_busy.sh"
source "$CTL_ROOT/scripts/worktree/_trim.sh"

usage() { print_help "worktree" "named worktrees on a fixed pool of warm slots under .worktrees/" \
  'worktree create <name> [--from <ref>]  ·  worktree list  ·  worktree remove <name>  ·  worktree trim [--days N] [--dry-run]' \
"Subcommands
  create <name> [--from <ref>]   take the lowest free slot, or add one up to WORKTREE_SLOTS, and put it
                                 on branch <name>: the existing branch, or a new one from <ref> (default:
                                 the main tree's HEAD). Prints the slot's path, .worktrees/slot-<n>,
                                 the one to work in. On a slot's first use it writes the
                                 slot's .env from the main tree's, with every port + 100 × the slot
                                 number and COMPOSE_PROJECT_NAME ending in -slot-<n>
  list                           each slot: its branch or free, clean or dirty, merged into the main tree
                                 or not, the size of its builds, and its last checkout or commit
  remove <name>                  free the slot that holds branch <name>. Refuses uncommitted changes, untracked files git does not
                                 ignore, and a branch whose work is not in the main tree's HEAD (merged,
                                 rebased or squashed in). Keeps the branch, the slot and its builds
  trim [--days N] [--dry-run]    in every slot, delete Cargo outputs that no build used for N days
                                 (default: WORKTREE_TRIM_DAYS). create and remove run it on their own
                                 when the last trim is more than 7 days old

create and remove refuse, and trim skips the slot, while anything ctl started there still runs: a
process it recorded, a container of the slot's compose project, or a gate run.

Settings (the main tree's .env, WORKTREES section; a value set in the shell wins)
  WORKTREE_SLOTS       the most slots. Empty: 4
  WORKTREE_TRIM_DAYS   the trim's age in days. Empty: 7
  WORKTREE_ONLY        1 or empty: ctl dev, test, gate and build refuse in the main tree. 0: off

Terms
  main tree            the repository's main checkout, whatever branch it has checked out
  slot                 a git worktree at .worktrees/slot-<n>. It is never deleted, and keeps its builds
  name                 a branch name; git's worktree list names the slot that holds it

Never move, delete or git-worktree-remove a slot: its fixed path keeps its builds valid. Switch a
slot's branch only through ctl worktree, so the slot stays free or taken as the pool expects." \
"Every command reads the whole pool first, and changes nothing when the pool is not in a state it knows."; }

# wt_refuse_busy <n> [<name>] — stop, changing nothing, while anything ctl started in slot-<n> runs
wt_refuse_busy() {
  local reasons line
  reasons=$(slot_busy "$WT_DIR/slot-$1") || return 0
  err "slot-$1${2:+ (branch $2)} is in use, so ctl worktree changed nothing:"
  while IFS= read -r line; do printf '  - %s\n' "$line" >&2; done <<< "$reasons"
  die "stop it there first with ctl stop, which stops its dev apps and its containers, the data core included, or let the gate finish; then run the command again"
}

# wt_auto_trim — the weekly trim that create and remove run, so nobody has to remember it. Its
# output goes to stderr, so create's stdout stays the one path. A failed trim never undoes the
# command that ran it; the next create or remove tries again.
wt_auto_trim() {
  wt_trim_due || return 0
  say "· no trim in the last $WT_TRIM_EVERY_DAYS days, so this command trims too: Cargo outputs unused for $WT_TRIM_DAYS days" >&2
  ( wt_trim "$WT_TRIM_DAYS" 0 ) >&2 || warn "the trim failed; the next create or remove tries it again"
}

wt_create() {
  local name="" from="" n="" new=0 slot commit="" holder="" origin="" i used=()
  while (( $# )); do case $1 in
    --from)   (( $# >= 2 )) && [[ -n $2 && $2 != -* ]] || die "--from needs a branch or a commit"; from=$2; shift ;;
    --from=*) from=${1#--from=}; [[ -n $from ]] || die "--from needs a branch or a commit" ;;
    -*)       die "unknown option $1 (ctl worktree create <name> [--from <ref>])" ;;
    *)        [[ -z $name ]] || die "ctl worktree create takes one name (got: $name and $1)"; name=$1 ;;
  esac; shift; done
  [[ -n $name ]] || die "usage: ctl worktree create <name> [--from <ref>]"
  wt_init; wt_name_ok "$name"; wt_settings; wt_lock; wt_pool_load; wt_pool_check
  if wt_branch_exists "$WT_MAIN" "$name"; then
    [[ -z $from ]] || die "branch $name exists, so --from does not apply; run create without --from"
    for i in "${!WT_LIST_BRANCH[@]}"; do [[ ${WT_LIST_BRANCH[$i]} != "$name" ]] || holder=${WT_LIST_PATH[$i]}; done
    [[ -z $holder ]] || die "branch $name is checked out at $holder, and a branch can be checked out in one worktree at a time"
    commit=$(wt_commit "$WT_MAIN" "refs/heads/$name") || die "git cannot read branch $name"
  else
    commit=$(wt_commit "$WT_MAIN" "${from:-HEAD}") || die "--from ${from:-HEAD} is not a commit of this repository"
    origin=", a new branch from ${from:-HEAD of the main tree}"
  fi
  for i in ${WT_SLOTS[@]+"${WT_SLOTS[@]}"}; do [[ -n ${WT_SLOT_BRANCH[$i]} ]] || { n=$i; break; }; done
  if [[ -n $n ]]; then
    [[ -z $(wt_dirty "$WT_DIR/slot-$n") ]] \
      || die "slot-$n is free, but it holds uncommitted changes or untracked files; ctl worktree does not guess whose they are, so it changed nothing"
    wt_refuse_busy "$n"
  elif (( ${#WT_SLOTS[@]} < WT_MAX )); then
    n=1; while [[ -v WT_SLOT_BRANCH[$n] ]]; do n=$(( n + 1 )); done; new=1
  else
    for i in "${WT_SLOTS[@]}"; do used+=("slot-$i (${WT_SLOT_BRANCH[$i]})"); done
    die "every slot is in use (WORKTREE_SLOTS=$WT_MAX): ${used[*]}. Free a merged one with ctl worktree remove <name>, or raise WORKTREE_SLOTS"
  fi
  # The .env is checked and written aside before anything changes, so a refusal leaves the pool as it was.
  slot="$WT_DIR/slot-$n" WT_ENV_TMP=""
  trap '[[ -z ${WT_ENV_TMP:-} ]] || rm -f -- "$WT_ENV_TMP"' EXIT
  if (( new )) || [[ ! -e $slot/.env && ! -L $slot/.env ]]; then wt_env_prepare "$n"; fi
  if (( new )); then
    say "· adding slot-$n ($(( ${#WT_SLOTS[@]} + 1 )) of WORKTREE_SLOTS=$WT_MAX)" >&2
    wt_add_slot "$WT_MAIN" "$slot" "$commit" || die "git could not add slot-$n"
  fi
  if wt_branch_exists "$WT_MAIN" "$name"; then wt_switch "$slot" "$name"; else wt_switch_new "$slot" "$name" "$commit"; fi \
    || die "git could not put slot-$n on branch $name; the slot stays free"
  [[ $(wt_current_branch "$slot") == "$name" ]] || die "slot-$n is not on branch $name after the switch; check it by hand"
  wt_env_install "$n"
  wt_drop_old_links
  ok "worktree $name is in slot-$n$origin" >&2
  (( ! new )) || say "· a new slot builds from cold once: run ctl setup in .worktrees/slot-$n to install its dependencies" >&2
  wt_auto_trim
  printf '%s\n' "$slot"
}

wt_remove() {
  local name=${1:-} n slot dirty head label rc=0
  [[ -n $name && $# -eq 1 ]] || die "usage: ctl worktree remove <name>"
  wt_init; wt_settings; wt_lock; wt_pool_load; wt_pool_check
  n=${WT_BRANCH_SLOT[$name]:-}
  [[ -n $n ]] || die "no slot holds branch $name; ctl worktree list shows them"
  slot="$WT_DIR/slot-$n"
  dirty=$(wt_dirty "$slot") || die "git cannot read the state of slot-$n"
  if [[ -n $dirty ]]; then
    err "slot-$n (branch $name) has uncommitted changes or untracked files git does not ignore:"
    head -n 10 <<< "$dirty" | sed 's/^/  /' >&2
    die "commit them or delete them first; ignored build files may stay"
  fi
  head=$(wt_commit "$WT_MAIN" HEAD) || die "the main tree has no HEAD commit"
  label=$(wt_current_branch "$WT_MAIN"); label=${label:+branch $label}; label=${label:-a detached HEAD}
  wt_merged "$WT_MAIN" "$name" "$head" || rc=$?
  case $rc in
    0) ;;
    1) die "branch $name is not merged into the main tree ($label at $(wt_short "$WT_MAIN" "$head")); merge it there first" ;;
    *) die "git could not tell whether branch $name is merged into the main tree (merge-tree --write-tree needs git 2.38 or later), so ctl worktree changed nothing" ;;
  esac
  wt_refuse_busy "$n" "$name"
  wt_detach "$slot" || die "git could not detach slot-$n; nothing else changed"
  [[ -z $(wt_current_branch "$slot") ]] || die "slot-$n is still on a branch after detaching; check it by hand"
  wt_drop_old_links
  ok "freed slot-$n: it keeps its builds, and branch $name is kept"
  wt_auto_trim
}

# wt_build_kib <slot folder> — the disk use, in KiB, of the slot's builds: its Cargo profiles,
# node_modules and .venv folders. du counts a hard-linked file once.
wt_build_kib() {
  local slot=$1 kib
  kib=$( { wt_cargo_profiles "$slot"
           find "$slot" \( -name .git -o -name target -o -path "$slot/data" -o -path "$slot/logs" \) -prune \
             -o -type d \( -name node_modules -o -name .venv \) -print -prune 2>/dev/null || true
         } | tr '\n' '\0' | du -sck --files0-from=- 2>/dev/null | tail -n 1 | cut -f1) || true
  printf '%s\n' "${kib:-0}"
}

wt_list() {
  (( $# == 0 )) || die "ctl worktree list takes no arguments"
  local n slot name state merged size used head file rc problem
  wt_init; wt_settings; wt_pool_load
  head=$(wt_commit "$WT_MAIN" HEAD || true)
  if (( ${#WT_SLOTS[@]} == 0 )); then
    say "no slots yet (WORKTREE_SLOTS=$WT_MAX); ctl worktree create <name> adds the first"
  else
    printf '%-8s %-36s %-7s %-7s %-7s %s\n' slot branch state merged builds 'last use'
  fi
  for n in ${WT_SLOTS[@]+"${WT_SLOTS[@]}"}; do
    slot="$WT_DIR/slot-$n" name=${WT_SLOT_BRANCH[$n]:-free} state=missing merged=- size=- used=-
    if [[ -d $slot ]]; then
      if ! state=$(wt_dirty "$slot" 2>/dev/null); then state=unknown; elif [[ -z $state ]]; then state=clean; else state=dirty; fi
      if [[ -n ${WT_SLOT_BRANCH[$n]} && -n $head ]]; then
        rc=0; wt_merged "$WT_MAIN" "${WT_SLOT_BRANCH[$n]}" "$head" || rc=$?
        case $rc in 0) merged=yes ;; 1) merged=no ;; *) merged=unknown ;; esac
      fi
      size="$(numfmt --from-unit=1024 --to=iec "$(wt_build_kib "$slot")")B"
      file=$(wt_reflog_file "$slot" 2>/dev/null || true)
      [[ ! -f $file ]] || used=$(date -r "$file" '+%Y-%m-%d %H:%M')
    fi
    printf '%-8s %-36s %-7s %-7s %-7s %s\n' "slot-$n" "$name" "$state" "$merged" "$size" "$used"
  done
  (( ${#WT_SLOTS[@]} == 0 )) || say "main tree: $WT_MAIN"
  (( ${#WT_OTHER[@]} == 0 )) || say "· other worktrees under .worktrees/, not slots: ${WT_OTHER[*]}"
  (( ${#WT_OUTSIDE[@]} == 0 )) || warn "worktrees outside .worktrees/, which this repo's rules do not allow: ${WT_OUTSIDE[*]}"
  (( ${#WT_OLD_LINKS[@]} == 0 )) || say "· name links an older ctl made, which the next create, remove or trim removes: ${WT_OLD_LINKS[*]#"$WT_DIR"/}"
  (( ${#WT_PROBLEMS[@]} )) || return 0
  err "the slots are not in a state ctl worktree knows; create, remove and trim refuse until each is fixed:"
  for problem in "${WT_PROBLEMS[@]}"; do printf '  - %s\n' "$problem" >&2; done
  exit 1
}

wt_trim_command() {
  local days="" dry=0
  while (( $# )); do case $1 in
    --days)    (( $# >= 2 )) || die "--days needs a number of days"; days=$2; shift ;;
    --days=*)  days=${1#--days=} ;;
    --dry-run) dry=1 ;;
    *)         die "unknown option $1 (ctl worktree trim [--days N] [--dry-run])" ;;
  esac; shift; done
  wt_init; wt_settings
  days=${days:-$WT_TRIM_DAYS}
  [[ $days =~ ^[1-9][0-9]{0,4}$ ]] || die "--days wants a whole number of days, 1 or more (got: $days)"
  wt_lock; wt_pool_load; wt_pool_check
  wt_trim "$days" "$dry"
  (( dry )) || wt_drop_old_links
}

sub=${1:-}; shift || true
case $sub in
  ""|help|-h|--help) usage ;;
  create|list|remove|trim)
    for arg; do ! is_help "$arg" || { usage; exit 0; }; done
    case $sub in create) wt_create "$@" ;; list) wt_list "$@" ;; remove) wt_remove "$@" ;; trim) wt_trim_command "$@" ;; esac ;;
  *) err "unknown worktree subcommand: $sub (create · list · remove · trim)"; say "run ${C_B}ctl worktree --help${C_RESET}"; exit 1 ;;
esac
