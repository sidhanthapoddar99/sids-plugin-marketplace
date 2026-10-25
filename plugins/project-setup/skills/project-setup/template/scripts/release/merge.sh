#!/usr/bin/env bash
# release/merge.sh — `ctl merge <branch>`: land a worktree branch on the default branch, the one way
# work reaches it. In the branch's worktree it merges the default branch in, sets the versions the
# branch changes (versions.sh), commits them, and runs one gate on the merged tree with CTL_MERGE=1,
# which a project's checks may read to apply their merge-time rules. Then it fast-forwards the main
# tree, so the default branch gets exactly the tree the gate passed. It pushes nothing.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"
source "$CTL_ROOT/scripts/worktree/_git.sh"

usage() { print_help "merge" "land a worktree branch on the default branch: versions, one gate, fast-forward" \
  'merge <branch> [--minor[=PART]] [--major[=PART]] [--dry-run] [-h]' \
"What it does, in the worktree that holds <branch>
  1. merges the default branch into <branch> when the branch does not already contain it. A conflict
     stops the run and leaves nothing half merged: merge it in that worktree, then run ctl merge again
  2. sets the version of each part the branch changes (VERSION_PARTS in scripts/release/versions.sh)
     and commits them: a part's patch number goes up when the branch changes a path that ships it,
     or the number --minor or --major names. A version the branch raised by hand is kept. A repo
     with no parts sets none
  3. runs ctl gate --delta <default branch> with CTL_MERGE=1. A tree that already passed costs nothing
  4. fast-forwards the main tree's default branch to <branch>, and creates the tag of each part whose
     version is a git tag, such as a Go module's

Options
  --minor[=PART]   raise PART's minor number instead of its patch number; PART may be left out when
                   the repo has one part. Repeat it for several parts
  --major[=PART]   the same for the major number
  --dry-run        print the plan and the versions it would set; change nothing
  -h, --help       show this help

The main tree must hold the default branch with no uncommitted change, and the worktree must be
clean. Push afterwards with git push --follow-tags." \
"It never pushes, never rewrites a commit, and fast-forwards only."; }

branch="" dry=0 version_args=()
while (( $# )); do case "$1" in
  -h|--help) usage; exit 0 ;;
  --dry-run) dry=1 ;;
  --minor|--major|--minor=*|--major=*) version_args+=("$1") ;;
  -*) die "unknown flag $1" ;;
  *) [[ -z $branch ]] || die "ctl merge lands one branch"; branch="$1" ;;
esac; shift; done
[[ -n $branch ]] || { usage; exit 1; }
require_tools git

main_tree=$(wt_main_tree "$CTL_ROOT") || die "cannot find the main tree of this repository"
default=$(wt_default_branch "$main_tree")
[[ $branch != "$default" ]] || die "$branch is the default branch; name the branch to land on it"
wt_branch_exists "$main_tree" "$branch" || die "no branch $branch in this repository"
[[ $(wt_current_branch "$main_tree") == "$default" ]] || die "the main tree ($main_tree) is not on $default; switch it back first"
[[ -z $(wt_dirty "$main_tree") ]] || die "the main tree has uncommitted changes; commit or move them first"

# The worktree that holds the branch: where its builds are warm and where the gate runs. Every step
# there runs with that worktree as CTL_ROOT, because ctl exports the root of the checkout it ran from.
wt_worktrees "$main_tree" || die "cannot list the worktrees of this repository"
slot=""
for i in "${!WT_LIST_PATH[@]}"; do [[ ${WT_LIST_BRANCH[$i]} != "$branch" ]] || slot=${WT_LIST_PATH[$i]}; done
[[ -n $slot && $slot != "$main_tree" ]] || die "no worktree holds $branch; ctl merge runs where the branch's builds are (ctl worktree create $branch)"
[[ -z $(wt_dirty "$slot") ]] || die "$slot has uncommitted changes; commit them on $branch first"

target=$(wt_commit "$main_tree" "$default") || die "cannot read $default"
needs_merge=1; wt_git "$slot" merge-base --is-ancestor "$target" HEAD && needs_merge=0
step "merge $branch into $default ($(wt_short "$main_tree" "$target"))"
if (( dry )); then
  if (( needs_merge )); then say "  would merge $default into $branch"; else say "  $branch already contains $default"; fi
  say "  versions it would set:"
  (cd "$slot" && export CTL_ROOT="$slot" && bash scripts/release/versions.sh --base "$target" --dry-run ${version_args[@]+"${version_args[@]}"}) | sed 's/^/    /'
  say "  then: ctl gate --delta $default with CTL_MERGE=1, and a fast-forward of $default"
  exit 0
fi

if (( needs_merge )); then
  if ! wt_git "$slot" merge --quiet --no-edit "$default"; then
    wt_git "$slot" merge --abort || true
    die "merging $default into $branch conflicts; merge it in $slot by hand, commit, then run ctl merge $branch again"
  fi
  ok "merged $default into $branch"
fi

say "· setting versions"
versions=$(cd "$slot" && export CTL_ROOT="$slot" && bash scripts/release/versions.sh --base "$target" ${version_args[@]+"${version_args[@]}"}) \
  || die "the version step failed; nothing is committed, and $slot holds what it wrote (git -C $slot status)"
sed 's/^/  /' <<<"$versions"
if [[ -n $(wt_dirty "$slot") ]]; then
  wt_git "$slot" add -A
  wt_git "$slot" commit --quiet -m "Release: $(paste -sd ';' <<<"$versions" | sed 's/;/; /g')"
  ok "committed the versions on $branch"
fi

say "· one gate on the merged tree"
(cd "$slot" && CTL_MERGE=1 ./ctl gate --delta "$default") || die "the gate is red; fix it on $branch, then run ctl merge $branch again"

wt_git "$main_tree" merge --quiet --ff-only "$branch" || die "$default moved while the gate ran; run ctl merge $branch again"
# A part whose version is a git tag gets its tag on the commit that landed, only once the gate passed.
tag_line='^([^ ]+) [^ ]+ → ([^ ]+) \(tag ([^)]+)\)$'
while IFS= read -r line; do
  [[ $line =~ $tag_line ]] || continue
  wt_git "$main_tree" tag -a "${BASH_REMATCH[3]}" -m "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}" || die "could not create the tag ${BASH_REMATCH[3]}"
  ok "tagged ${BASH_REMATCH[3]}"
done <<<"$versions"
ok "$default is at $(wt_short "$main_tree" HEAD) — push it with: git push --follow-tags origin $default"
grep -q '→' <<<"$versions" && say "  record each new version in the changelog or version log the project keeps"
exit 0
