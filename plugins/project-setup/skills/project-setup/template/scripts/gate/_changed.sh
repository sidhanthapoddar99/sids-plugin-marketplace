#!/usr/bin/env bash
# scripts/gate/_changed.sh — what a changed-only `ctl gate` runs. SOURCE it after _lib.sh and
# scripts/gate/_targets.sh. scripts/gate/all.sh is the one caller.
#
# THE CHANGE SET
#   ctl gate, ctl gate --changed   the uncommitted changes: the diff against HEAD, plus untracked files.
#   ctl gate --delta <base>        the diff from the merge base of <base> and HEAD to the working
#                                  tree, plus untracked files. gate_resolve_base says which commit
#                                  <base> names.
# A deleted file counts, and a rename counts at both ends. A repository with no commit yet compares
# with the empty tree, so every file counts. Outside a git checkout there is no change set, so the
# run widens to everything. Paths are relative to the ctl root, which may sit inside a larger repo.
#
# FAIL TOWARD MORE. Each changed path gets one owner (changed_owner):
#   everything   ctl and scripts/, the toolchain file, a shared package under apps/packages/, root
#                config such as .env.template, and any path no rule names. Every rung runs on every
#                target.
#   check        docker/ and documentation no suite reads: AGENTS.md, CLAUDE.md and README.md
#                anywhere, and any other Markdown outside apps/. Only the check rung reads them.
#   a target     a path inside a folder of GATE_TARGETS (_targets.sh), plus the targets that
#                GATE_REACHES adds for it.
# A skipped check that looks green is a wrong answer that looks right, so a path with no rule
# widens the run instead of narrowing it.
#
# [ADAPT] GATE_REACHES, and the rules in changed_owner, when one app's change can break another.
# A narrower rule is the repo's choice to record; a missing rule only costs time.
declare -A GATE_REACHES=(
  [database]="api engine"   # the backends' integration tests run against the migrated schema
)

GATE_LIST_MAX=40   # the changed paths a real run prints; --dry-run prints every one

# changed_owner <path> — "<owner>|<reason>", owner ∈ everything · check · a target name
changed_owner() {
  local target
  case "$1" in
    ctl|scripts/*)           echo "everything|ctl and scripts/ drive every rung"; return ;;
    .mise.toml|mise.toml)    echo "everything|the toolchains"; return ;;
    apps/packages/*)         echo "everything|a shared package; every app that imports it"; return ;;
  esac
  case "$1" in
    AGENTS.md|CLAUDE.md|README.md|*/AGENTS.md|*/CLAUDE.md|*/README.md|LICENSE)
                             echo "check|documentation; only the check rung reads it"; return ;;
  esac
  target=$(gate_target_of "$1")
  [[ -z $target ]] || { echo "$target|"; return; }
  case "$1" in
    docker/*|*.md)           echo "check|only the check rung reads it" ;;
    */*)                     echo "everything|no rule names it" ;;
    *)                       echo "everything|root config" ;;
  esac
}

# gate_resolve_base <base> — print the full hash of the commit a --delta base names, or refuse.
#   A branch, tag or commit: what `git rev-parse --verify <base>^{commit}` resolves. A reflog date
#     (name@{…}) is refused, because git reads its date leniently.
#   A date-time: YYYY-MM-DD, or YYYY-MM-DD HH:MM[:SS] with a space or a T, in local time; a date
#     alone means its first moment, 00:00:00. It names the last commit at or before that moment on
#     HEAD's first-parent line. The text is checked here and git gets an exact timestamp with its
#     offset, because git's own date parser quietly turns text it cannot read into "now".
#   A date with no commit at or before it, a name that is both a date and a git name, and anything
#   else are refused by name.
gate_resolve_base() {
  local base="$1" is_date=0 moment="" epoch commit
  [[ $base != *'@{'* ]] || die "--delta: $base uses a reflog date, which git reads leniently; give a commit, a branch or a date-time"
  if [[ $base =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2}))?)?$ ]]; then
    is_date=1
    moment="${BASH_REMATCH[1]} ${BASH_REMATCH[3]:-00}:${BASH_REMATCH[4]:-00}:${BASH_REMATCH[6]:-00}"
    # date -d accepts the moment only when it exists; the round trip refuses one it would shift.
    epoch=$(date -d "$moment" +%s 2>/dev/null) && [[ $(date -d "@$epoch" '+%Y-%m-%d %H:%M:%S') == "$moment" ]] \
      || die "--delta: $base is not a real date and time"
  fi
  if commit=$(git rev-parse --verify --quiet "$base^{commit}" 2>/dev/null); then
    (( ! is_date )) || die "--delta: $base is both a date-time and a git name here; give the commit hash instead"
  elif (( is_date )); then
    commit=$(git rev-list -1 --first-parent --before="$(date -d "@$epoch" +%Y-%m-%dT%H:%M:%S%z)" HEAD) \
      || die "--delta: git could not search the history for $base"
    [[ -n $commit ]] || die "--delta: no commit on HEAD's first-parent line is at or before $base"
  else
    die "--delta: $base is neither a branch or commit here nor a date-time (YYYY-MM-DD, or YYYY-MM-DD HH:MM[:SS] with a space or a T)"
  fi
  printf '%s\n' "$commit"
}

# _changed_commit <commit> — "<short> (<local date and time>) <subject>", one line
_changed_commit() { git log -1 --format='%h (%cd) %s' --date=format-local:'%Y-%m-%d %H:%M' "$1"; }

# _changed_widen <why> — no change set can be read: every rung runs on every target
_changed_widen() {
  CHANGED_FULL=1 CHANGED_TARGETS="" CHANGED_COUNT=0
  CHANGED_SCOPE="$1" CHANGED_WHY="$1"
  step "no change set: $1"
  say "  every rung runs on every target"
}

# gate_reaches_check — stop when GATE_REACHES names a target that is no row of GATE_TARGETS, so a
# renamed or deleted app cannot drop out of the selection without a word. Every gate run calls it,
# --all included, so a stale name shows up on the first run after the rename.
gate_reaches_check() {
  local key reached_name
  for key in "${!GATE_REACHES[@]}"; do
    for reached_name in $key ${GATE_REACHES[$key]}; do
      gate_target_known "$reached_name" \
        || die "GATE_REACHES in scripts/gate/_changed.sh names '$reached_name', which is no row of GATE_TARGETS (scripts/gate/_targets.sh)"
    done
  done
}

# gate_changed_select [base] [all] — print the change set's header, then each path and its owner;
# a second argument `all` lists every path, else the first GATE_LIST_MAX. No base: the uncommitted
# changes. Sets, for the plan and the closing line:
#   CHANGED_FULL     1 when every rung must run on every target
#   CHANGED_TARGETS  the targets reached, in GATE_TARGETS order
#   CHANGED_COUNT    how many paths changed
#   CHANGED_SCOPE    the change set in words; CHANGED_NONE its words when it is empty
#   CHANGED_WHY      why the run widened, when CHANGED_FULL is 1
#   CHANGED_BASE     the commit the change set counts from, empty outside git
gate_changed_select() {
  local asked="${1:-}" list_all="${2:-}" commit base list path line owner reason target name extra shown=0 wide_shown=0
  CHANGED_NONE="" CHANGED_WHY="" CHANGED_BASE=""
  gate_reaches_check
  if ! command -v git >/dev/null 2>&1 || [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) != true ]]; then
    [[ -z $asked ]] || die "--delta needs a git checkout to find the changes since $asked"
    _changed_widen "this is no git checkout"
    return 0
  fi
  if [[ -n $asked ]]; then
    commit=$(gate_resolve_base "$asked") || exit 1
    base=$(git merge-base "$commit" HEAD) || die "--delta: $asked has no merge base with HEAD"
    CHANGED_SCOPE="the changes since $asked ($(git rev-parse --short "$commit"))"
    CHANGED_NONE="no changes since $asked ($(git rev-parse --short "$commit"))"
    step "delta since $asked → $(_changed_commit "$commit")"
    [[ $base == "$commit" ]] || say "  it is not on HEAD's line, so the delta starts at their merge base: $(_changed_commit "$base")"
  elif git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    base=$(git rev-parse HEAD)
    CHANGED_SCOPE="the uncommitted changes" CHANGED_NONE="no uncommitted changes"
    step "uncommitted changes, against HEAD $(_changed_commit HEAD)"
  else
    base=$(git hash-object -t tree /dev/null) || die "git could not name the empty tree"
    CHANGED_SCOPE="every file, because the repository has no commit yet" CHANGED_NONE="no file yet"
    step "no commit yet, so every file counts as changed"
  fi
  CHANGED_BASE=$base
  list=$(mktemp) || die "cannot create a temporary file"
  { git diff --name-only --no-renames --relative -z "$base" -- . && git ls-files --others --exclude-standard -z -- .; } >"$list" \
    || { rm -f "$list"; die "git could not list the changed files"; }
  local -a paths=()
  mapfile -d '' -t paths < <(sort -zu "$list"); rm -f "$list"
  local -A reached=()
  CHANGED_COUNT=${#paths[@]}
  say "  ${CHANGED_COUNT} changed path(s)"
  for path in ${paths[@]+"${paths[@]}"}; do
    line=$(changed_owner "$path"); owner=${line%%|*}; reason=${line#*|}
    reached[$owner]=1
    extra=""
    if [[ -n ${GATE_REACHES[$owner]:-} ]]; then
      for name in ${GATE_REACHES[$owner]}; do reached[$name]=1; done
      extra=", and so ${GATE_REACHES[$owner]} (GATE_REACHES)"
    fi
    # The first path that widens the run always prints, so the closing line's "listed above" holds.
    if [[ $list_all == all ]] || (( shown < GATE_LIST_MAX )) || [[ $owner == everything && $wide_shown == 0 ]]; then
      say "  $path → $owner${reason:+ ($reason)}$extra"; shown=$(( shown + 1 ))
      [[ $owner != everything ]] || wide_shown=1
    fi
  done
  (( shown == CHANGED_COUNT )) || say "  … and $(( CHANGED_COUNT - shown )) more path(s); \`ctl gate --dry-run\` lists every one"
  CHANGED_FULL=0 CHANGED_TARGETS=""
  if [[ -n ${reached[everything]:-} ]]; then
    CHANGED_FULL=1
    CHANGED_WHY="${CHANGED_SCOPE} reach shared tooling or a path no rule maps (listed above)"
  fi
  while read -r target _; do
    [[ -z ${reached[$target]:-} ]] || CHANGED_TARGETS+=" $target"
  done < <(printf '%s\n' "${GATE_TARGETS[@]}")
  CHANGED_TARGETS=${CHANGED_TARGETS# }
  return 0
}
