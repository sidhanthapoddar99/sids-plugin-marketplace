#!/usr/bin/env bash
# scripts/gate/_targets.sh — the apps that `ctl gate lint`, `ctl gate typecheck` and `ctl test`
# check, in one table. SOURCE it after _lib.sh. The three rungs read it, and so does the
# changed-only selection (scripts/gate/_changed.sh), which maps a changed path to the row whose
# folder holds it. One table, so a renamed or deleted app is edited once, and the selection can
# never name an app the rungs do not know.
#
# [ADAPT] GATE_TARGETS. One row per app: the target name, the folder, the ecosystem (python, rust,
# bun or go) and the rungs that check it. Delete the rows of apps the repo dropped, and change the
# folder here when you rename one. A run with no target skips a row whose folder is absent, because
# a repo deletes the apps it does not have. A target named on the command line must exist, because
# a typo that passes teaches the caller nothing. The word `db` among the rungs marks an app whose
# tests read the data core: ctl test starts a stopped core before that suite runs.
GATE_TARGETS=(
  # name     folder                              ecosystem  rungs
  "api       apps/example-api-python             python     lint typecheck test db"
  "database  apps/database/postgres              python     lint test db"
  "engine    apps/example-engine-rust            rust       lint typecheck test"
  "single    apps/example-single-web-app-vite    bun        lint typecheck test"
  "landing   apps/example-multi-web-app/landing  bun        lint typecheck test"
  "app       apps/example-multi-web-app/app      bun        lint typecheck test"
  "docs      apps/example-multi-web-app/docs     bun        lint typecheck test"
  "dashboard apps/example-dashboard-nextjs       bun        lint typecheck test"
  "cli       apps/example-tui-go                 go         lint typecheck test"
)

# gate_target_rows <rung> — "name folder ecosystem", one line per row that lists <rung>
gate_target_rows() {
  local row name folder ecosystem rungs
  for row in "${GATE_TARGETS[@]}"; do
    read -r name folder ecosystem rungs <<< "$row"
    [[ " $rungs " == *" $1 "* ]] && printf '%s %s %s\n' "$name" "$folder" "$ecosystem"
  done
  return 0
}

# gate_target_needs_db <name> — 0 when the row of <name> marks its tests as reading the data core
gate_target_needs_db() {
  local row name folder ecosystem rungs
  for row in "${GATE_TARGETS[@]}"; do
    read -r name folder ecosystem rungs <<< "$row"
    [[ $name == "$1" && " $rungs " == *" db "* ]] && return 0
  done
  return 1
}

# gate_target_names <rung> — the rung's target names, joined with |
gate_target_names() {
  local name _ names=()
  while read -r name _; do names+=("$name"); done < <(gate_target_rows "$1")
  local IFS='|'; printf '%s\n' "${names[*]}"
}

# gate_target_help <rung> — the help lines that list the rung's targets
gate_target_help() {
  local name folder ecosystem
  while read -r name folder ecosystem; do printf '  %-14s%s  (%s)\n' "$name" "$folder" "$ecosystem"; done < <(gate_target_rows "$1")
}

# gate_target_select <rung> [name…] — fill GATE_SELECTED with the rows to run, "name folder
# ecosystem", in table order. No name, or the single word `all`: every row of the rung whose folder
# exists. A name must be a row of the rung and its folder must exist, or the run stops by name.
gate_target_select() {
  local rung="$1" name folder ecosystem asked found verb="gate $1"
  shift
  [[ $rung != test ]] || verb=test
  GATE_SELECTED=()
  [[ $# -ne 1 || $1 != all ]] || shift
  for asked; do
    found=0
    while read -r name folder ecosystem; do [[ $name == "$asked" ]] && found=1; done < <(gate_target_rows "$rung")
    (( found )) || die "unknown target: $asked (ctl $verb takes $(gate_target_names "$rung"), or none for every target)"
  done
  while read -r name folder ecosystem; do
    if (( $# )); then
      [[ " $* " == *" $name "* ]] || continue
      [[ -d $CTL_ROOT/$folder ]] || die "$folder not found — the target '$name' has no folder to $rung"
    else
      [[ -d $CTL_ROOT/$folder ]] || continue
    fi
    GATE_SELECTED+=("$name $folder $ecosystem")
  done < <(gate_target_rows "$rung")
  return 0
}

# gate_target_of <path> — the name of the row whose folder holds the repo-relative <path>; the
# longest folder wins, so a nested app is its own target. Nothing when no row holds it.
gate_target_of() {
  local row name folder best="" length=0
  for row in "${GATE_TARGETS[@]}"; do
    read -r name folder _ <<< "$row"
    [[ $1 == "$folder"/* || $1 == "$folder" ]] || continue
    (( ${#folder} > length )) && { best=$name; length=${#folder}; }
  done
  [[ -z $best ]] || printf '%s\n' "$best"
}

# gate_target_known <name> — 0 when <name> is a row of the table
gate_target_known() {
  local row name
  for row in "${GATE_TARGETS[@]}"; do read -r name _ <<< "$row"; [[ $name == "$1" ]] && return 0; done
  return 1
}
