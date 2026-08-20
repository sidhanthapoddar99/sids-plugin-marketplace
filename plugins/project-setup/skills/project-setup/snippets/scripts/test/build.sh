#!/usr/bin/env bash
# test/build.sh — `ctl build save|start|clean`. Frozen test builds: immutable, provenance-stamped
# production snapshots under test_build/, served independently of the working tree.
#
# Why: a dev tree changes constantly (agents editing, branch switches, hot reload). When a
# human tests a state, they need a build that is FROZEN and labeled with branch/commit/date —
# so "which build am I actually testing?" is always answerable. A stale dev build produces
# phantom bugs that burn a debugging cycle; a frozen build is exactly what was built.
#
#   ctl build save [target] [name]   build <target>, freeze the artifact into
#                                    test_build/build-<date-time>-<target>-<name>/ (+ .build-meta)
#   ctl build start [name|target] [port] [--nqa] [-y] [--dry-run] [--list]
#                                    serve a frozen build — `ctl up`-style guided flow:
#                                    pick build → pick port → plan → confirm (Run/Back/Cancel)
#   ctl build clean [--keep N] [-y]  prune old snapshots (default: keep the newest 5)
#
# Bare `ctl build` (no subverb) stays the container image build (container/build.sh) — the
# router in `ctl` splits on the first arg.
#
# test_build/ is SELF-gitignored: save seeds test_build/.gitignore with exactly `**` +
# `!.gitignore`, so snapshots can never enter history and the convention travels with the
# folder (no root-.gitignore entry needed).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../common/_lib.sh"; cd "$CTL_ROOT"

BUILDS_DIR="$CTL_ROOT/test_build"
KEEP_DEFAULT=5
CUSTOM_LABEL="custom…"
# PORT_PRESETS (the start picker's port list; first one = the --nqa default) comes from
# _lib.sh — shared with `ctl ps`, which scans the same list as the build plane.

# [ADAPT] buildable targets — one record per target:  name|build-cmd|artifact-path|serve|serve-cmd
#   build-cmd      what produces the artifact (run from repo root)
#   artifact-path  the directory that gets snapshotted
#   serve ∈ static   built SPA/site  → served with `bunx serve -s` (SPA fallback)
#           process  artifact runs as a process → serve-cmd runs INSIDE the snapshot;
#                    {port} is replaced with the chosen port (port goes to the process,
#                    not a static server)
#           none     save-only deliverable (wheel/tarball/library) — `start` refuses
#                    politely and points at the folder
BUILD_TARGETS=(
  "frontend|cd apps/frontend && bun run build|apps/frontend/dist|static|"
  "backend|cd apps/backend && uv build|apps/backend/dist|none|"
  # process example — a compiled binary that serves itself from the snapshot:
  # "api|cd apps/api && go build -o bin ./cmd/server|apps/api/bin|process|./server --port {port}"
)

build_help() {
  print_help build "frozen test builds — snapshot, serve, prune" \
"build save  [target] [name]
  ctl build start [name|target] [port] [--nqa] [-y] [--dry-run] [--list]
  ctl build clean [--keep N] [-y] [--dry-run]" \
"Subcommands
  save [target] [name]   build a target, then snapshot the artifact →
                         test_build/build-<date-time>-<target>-<name>/  (name defaults
                         to the git short sha; a .build-meta file records target, serve
                         strategy, branch, commit, and date)
  start                  serve a frozen build. Bare 'ctl build start' in a terminal is
                         guided: pick the build → pick the port (${PORT_PRESETS[*]} or
                         custom) → see the plan → confirm (Run / Back / Cancel). Any
                         axis passed on the CLI is used as-is; the positional may be a
                         save-name or a target (newest match wins) or the folder name.
  clean                  prune old snapshots, keeping the newest N (default $KEEP_DEFAULT)

Targets (from BUILD_TARGETS)
  $(tgt_names | join_sp | or_none)

Options (start)
  --nqa          no questions — don't prompt; defaults = newest build + port ${PORT_PRESETS[0]}
  -y, --yes      skip the final confirmation (clean: skip the delete confirm)
  --dry-run, -n  show the plan and exit without serving (clean: list, don't delete)
  --list         list the frozen builds, then exit
  -h, --help     show this help" \
"Every interactive run prints the exact --nqa command that reproduces it.
Bare 'ctl build' (no subverb) builds the container images (container/build.sh)."
}

sanitize() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g'; }

tgt_names() { local r; for r in "${BUILD_TARGETS[@]}"; do printf '%s\n' "${r%%|*}"; done; }
tgt_rec()   { local r; for r in "${BUILD_TARGETS[@]}"; do [[ ${r%%|*} == "$1" ]] && { printf '%s' "$r"; return 0; }; done; return 1; }

# newest-first list of frozen build folder names
list_builds() { ls -1t "$BUILDS_DIR" 2>/dev/null | grep -E '^build-' || true; }

meta_field() {  # meta_field <folder> <key> — value from .build-meta (empty if absent)
  local f="$BUILDS_DIR/$1/.build-meta"
  [[ -f $f ]] && awk -v k="$2" -F': ' '$1==k{ i=index($0,": "); print substr($0,i+2); exit }' "$f" || true
}

# one-line label for pickers/lists: folder  (branch @ shortsha · date)
build_label() {
  local n="$1" br cm dt
  br="$(meta_field "$n" branch)"; cm="$(meta_field "$n" commit)"; dt="$(meta_field "$n" date)"
  printf '%s  (%s @ %s · %s)' "$n" "${br:-?}" "${cm:0:7}" "${dt%%T*}"
}

# seed the self-gitignoring builds folder (** + !.gitignore — snapshots never enter history)
ensure_builds_dir() {
  mkdir -p "$BUILDS_DIR"
  [[ -f "$BUILDS_DIR/.gitignore" ]] || printf '**\n!.gitignore\n' > "$BUILDS_DIR/.gitignore"
}

build_save() {
  require_tools git
  local target="${1:-}" name="${2:-}" rec
  # target axis — single declared target = auto; else prompt (interactive) or die
  if [[ -z $target ]]; then
    if (( ${#BUILD_TARGETS[@]} == 1 )); then target="${BUILD_TARGETS[0]%%|*}"
    elif [[ -t 1 && -r /dev/tty ]]; then
      local labels=() choice=() r n b a s c
      for r in "${BUILD_TARGETS[@]}"; do IFS='|' read -r n b a s c <<<"$r"; labels+=("$n  ($s · $a)"); done
      tui_select --into choice --header "Target — which one to build + freeze?" \
        --hint "declared in BUILD_TARGETS (test/build.sh)" -- "${labels[@]}" || { say "cancelled."; exit 0; }
      target="${choice[0]%% *}"
      printf '\n'
    else die "no target and no TTY — usage: ctl build save <target> [name]  (targets: $(tgt_names | join_sp))"; fi
  fi
  rec="$(tgt_rec "$target")" || die "unknown target '$target' (targets: $(tgt_names | join_sp))"
  local _n build_cmd artifact serve serve_cmd; IFS='|' read -r _n build_cmd artifact serve serve_cmd <<<"$rec"
  name="$(sanitize "${name:-$(git rev-parse --short HEAD)}")"
  [[ -n $name ]] || die "name sanitised to empty"
  local stamp dir; stamp="$(date +%Y%m%d-%H%M%S)"; dir="$BUILDS_DIR/build-$stamp-$target-$name"
  step "building $target — $build_cmd"
  ( eval "$build_cmd" ) || die "build failed — nothing saved"
  [[ -d $artifact ]] || die "no artifact at $artifact after build (check BUILD_TARGETS)"
  ensure_builds_dir
  mkdir -p "$dir"; cp -r "$artifact/." "$dir/"
  { printf 'name: %s\ntarget: %s\nserve: %s\n' "$name" "$target" "$serve"
    [[ -z $serve_cmd ]] || printf 'serve_cmd: %s\n' "$serve_cmd"
    printf 'date: %s\nbranch: %s\ncommit: %s\n' \
      "$(date -Iseconds)" "$(git branch --show-current)" "$(git rev-parse HEAD)"
  } > "$dir/.build-meta"
  ok "saved $(basename "$dir") ($(du -sh "$dir" | cut -f1))"
  if [[ $serve == none ]]; then
    say "save-only target — artifact frozen at ${C_B}test_build/$(basename "$dir")${C_RESET}"
  else
    say "start it:  ${C_B}ctl build start $name${C_RESET}"
  fi
}

# resolve a user-given token to a frozen build folder:
# exact folder, else newest by save-name, else newest by target (meta-based, target-aware)
resolve_build() {
  local q="$1" s n
  [[ -d "$BUILDS_DIR/$q" ]] && { printf '%s' "$q"; return 0; }
  s="$(sanitize "$q")"
  while IFS= read -r n; do [[ -z $n ]] && continue
    [[ "$(meta_field "$n" name)" == "$s" ]] && { printf '%s' "$n"; return 0; }; done < <(list_builds)
  while IFS= read -r n; do [[ -z $n ]] && continue
    [[ "$(meta_field "$n" target)" == "$s" ]] && { printf '%s' "$n"; return 0; }; done < <(list_builds)
  return 1
}

build_start() {
  # ── parse: at most one name/target and one port positional, plus flags ──
  local folder="" name="" port="" nqa=0 yes=0 dry=0 list=0 a
  for a in "$@"; do case "$a" in
    --nqa|--no-questions-asked) nqa=1 ;;
    -y|--yes)      yes=1 ;;
    --dry-run|-n)  dry=1 ;;
    --list)        list=1 ;;
    -h|--help)     build_help; exit 0 ;;
    --*)           die "unknown flag: $a (try ctl build start --help)" ;;
    *)             if [[ $a =~ ^[0-9]+$ ]]; then
                     [[ -n $port ]] && die "two ports given ('$port' and '$a')"; port="$a"
                   else
                     [[ -n $name ]] && die "two names given ('$name' and '$a')"; name="$a"
                   fi ;;
  esac; done

  if (( list )); then
    printf '%sfrozen builds%s   %s(newest first — test_build/)%s\n' "$C_B" "$C_RESET" "$C_DIM" "$C_RESET"
    local n any=0
    while IFS= read -r n; do [[ -z $n ]] && continue
      printf '  %s-%s %s\n' "$C_DIM" "$C_RESET" "$(build_label "$n")"; any=1; done < <(list_builds)
    (( any )) || printf '  %s(none — create one: ctl build save [target] [name])%s\n' "$C_DIM" "$C_RESET"
    exit 0
  fi

  local interactive=0; [[ -t 1 && -r /dev/tty && $nqa -eq 0 ]] && interactive=1
  local BUILDS=(); mapfile -t BUILDS < <(list_builds)
  (( ${#BUILDS[@]} )) || die "no frozen builds in test_build/ — create one: ctl build save [target] [name]"

  [[ -n $name ]] && { folder="$(resolve_build "$name")" || die "no frozen build matches \"$name\" (ctl build start --list)"; }
  # --nqa = no questions: default the unset axes (newest build, first preset port)
  if (( nqa )); then
    [[ -z $folder ]] && folder="${BUILDS[0]}"
    [[ -z $port ]] && port="${PORT_PRESETS[0]}"
  fi

  # ── selection → plan → confirm (Back re-opens the pickers) ──
  local name_given="$folder" port_given="$port" serve serve_disp plan_ok pid choice=() labels=() i repro
  while true; do
    folder="$name_given"; port="$port_given"

    # axis 1: build (single-select, newest first, labels carry branch @ sha · date)
    if [[ -z $folder ]]; then
      (( interactive )) || die "no build name and no TTY — pass one (ctl build start <name> [port]) or drop --nqa"
      labels=(); for i in "${!BUILDS[@]}"; do labels+=("$(build_label "${BUILDS[$i]}")"); done
      choice=()
      tui_select --into choice --header "Frozen build — which one to serve?" \
        --hint "newest first · saved by 'ctl build save'" -- "${labels[@]}" || { say "cancelled."; exit 0; }
      for i in "${!labels[@]}"; do [[ "${labels[$i]}" == "${choice[0]:-}" ]] && folder="${BUILDS[$i]}"; done
      [[ -n $folder ]] || die "no build selected"
      printf '\n'
    fi

    # save-only snapshots have nothing to serve — point at the folder and stop
    serve="$(meta_field "$folder" serve)"; serve="${serve:-static}"
    if [[ $serve == none ]]; then
      ok "$(build_label "$folder")"
      say "save-only target ($(meta_field "$folder" target)) — nothing to serve."
      say "artifact:  ${C_B}test_build/$folder${C_RESET}   (inspect: ls test_build/$folder)"
      exit 0
    fi

    # axis 2: port (single-select from presets + custom, in-use ports marked)
    if [[ -z $port ]]; then
      (( interactive )) || die "no port and no TTY — pass one, or use --nqa for the default (${PORT_PRESETS[0]})"
      labels=(); local p
      for p in "${PORT_PRESETS[@]}"; do
        if [[ -n "$(port_pid "$p")" ]]; then labels+=("$p  (in use)"); else labels+=("$p"); fi
      done
      labels+=("$CUSTOM_LABEL")
      choice=()
      tui_select --into choice --header "Port — where to serve it?" \
        --hint "greyed '(in use)' ports are already taken" -- "${labels[@]}" || { say "cancelled."; exit 0; }
      case "${choice[0]:-}" in
        "$CUSTOM_LABEL") read -rp "custom port [1024-65535]: " port < /dev/tty ;;
        *)               port="${choice[0]%% *}" ;;
      esac
      printf '\n'
    fi
    [[ $port =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )) || die "invalid port: $port"

    # ── plan (target-aware serve line from .build-meta — no guessing) ──
    case "$serve" in
      static)  serve_disp="bunx serve -s . -l $port" ;;
      process) serve_disp="$(meta_field "$folder" serve_cmd)"; serve_disp="${serve_disp//\{port\}/$port}"
               [[ -n $serve_disp ]] || die "snapshot says serve: process but has no serve_cmd in .build-meta" ;;
      *)       die "unknown serve strategy '$serve' in test_build/$folder/.build-meta" ;;
    esac
    repro="$(meta_field "$folder" name)"; repro="ctl build start ${repro:-$folder} $port"   # save-name form reproduces it
    plan_ok=1; pid="$(port_pid "$port")"
    hr
    printf '%sPlan%s   build=%s   port=%s\n' "$C_B" "$C_RESET" "$folder" "$port"
    printf '  %sname%s    %s\n'   "$C_DIM" "$C_RESET" "$(meta_field "$folder" name)"
    printf '  %starget%s  %s (%s)\n' "$C_DIM" "$C_RESET" "$(meta_field "$folder" target)" "$serve"
    printf '  %sbranch%s  %s\n'   "$C_DIM" "$C_RESET" "$(meta_field "$folder" branch)"
    printf '  %scommit%s  %s\n'   "$C_DIM" "$C_RESET" "$(meta_field "$folder" commit)"
    printf '  %ssaved%s   %s\n'   "$C_DIM" "$C_RESET" "$(meta_field "$folder" date)"
    printf '  %ssize%s    %s\n'   "$C_DIM" "$C_RESET" "$(du -sh "$BUILDS_DIR/$folder" 2>/dev/null | cut -f1)"
    printf '  %sserve%s   %s   (cwd: test_build/%s)\n' "$C_DIM" "$C_RESET" "$serve_disp" "$folder"
    printf '  %surl%s     http://localhost:%s\n' "$C_DIM" "$C_RESET" "$port"
    if [[ -n $pid ]]; then
      err "port $port is already in use (pid $pid)"
      plan_ok=0
    fi
    hr
    printf '%sreproduce%s  (no prompts)\n' "$C_B" "$C_RESET"
    printf '  %s%s --nqa%s\n'    "$C_DIM" "$repro" "$C_RESET"
    printf '  %s%s --nqa -y%s\n' "$C_DIM" "$repro" "$C_RESET"
    hr

    (( dry )) && { (( plan_ok )) && say "(dry-run — nothing served)" || say "(dry-run — invalid, nothing served)"; exit $(( plan_ok ? 0 : 1 )); }
    if (( plan_ok && yes )); then break; fi
    if (( ! interactive )); then
      (( plan_ok )) || die "port busy (see above)"
      die "not a TTY and no -y — re-run with -y to serve, or --dry-run to preview"
    fi

    # valid → Run/Back/Cancel; port busy → Back/Cancel only
    printf '\n'
    choice=()
    if (( plan_ok )); then
      tui_select --into choice --horizontal --header "Serve this build?" -- Run Back Cancel \
        || { say "cancelled."; exit 0; }
    else
      tui_select --into choice --horizontal --header "Port busy — go back and re-pick?" -- Back Cancel \
        || { say "cancelled."; exit 0; }
    fi
    case "${choice[0]:-Cancel}" in
      Run)  break ;;
      Back) name_given=""; port_given=""
            printf '\n%s↻ starting over — re-pick build + port%s\n\n' "$C_DIM" "$C_RESET"; continue ;;
      *)    say "cancelled."; exit 0 ;;
    esac
  done

  # tools per serve strategy (process: only bare command names are checkable)
  local run_cmd first
  case "$serve" in
    static)  require_tools bunx; run_cmd="bunx serve -s . -l $port" ;;
    process) run_cmd="$serve_disp"; first="${run_cmd%% *}"
             [[ $first == ./* || $first == /* ]] || require_tools "$first" ;;
  esac
  step "serving $folder → http://localhost:$port   (Ctrl-C stops it)"
  cd "$BUILDS_DIR/$folder" && exec bash -c "$run_cmd"
}

build_clean() {
  local keep=$KEEP_DEFAULT yes=0 dry=0
  while (( $# )); do case "$1" in
    --keep=*)     keep="${1#*=}"; shift ;;
    --keep)       keep="${2:-}"; shift 2 ;;
    -y|--yes)     yes=1; shift ;;
    --dry-run|-n) dry=1; shift ;;
    -h|--help)    build_help; exit 0 ;;
    *)            die "unknown arg: $1 (try ctl build clean --help)" ;;
  esac; done
  [[ $keep =~ ^[0-9]+$ ]] || die "--keep wants a number (got '${keep:-}')"
  local all=() doomed=() n i=0
  mapfile -t all < <(list_builds)
  for n in "${all[@]}"; do [[ -z $n ]] && continue
    i=$((i+1)); (( i > keep )) && doomed+=("$n"); done
  (( ${#doomed[@]} )) || { ok "nothing to prune (${#all[@]} snapshot(s), keeping newest $keep)"; exit 0; }
  say "pruning ${#doomed[@]} of ${#all[@]} snapshot(s) (keeping the newest $keep):"
  for n in "${doomed[@]}"; do say "  ${C_DIM}✗${C_RESET} $(build_label "$n")"; done
  (( dry )) && { say "(dry-run — nothing deleted)"; exit 0; }
  if (( ! yes )); then
    [[ -t 1 && -r /dev/tty ]] || die "not a TTY and no -y — re-run with -y to delete, or --dry-run to preview"
    local a=()
    tui_select --into a --horizontal --header "Delete these ${#doomed[@]} snapshot(s)?" -- Delete Cancel \
      || { say "cancelled."; exit 0; }
    [[ "${a[0]:-Cancel}" == Delete ]] || { say "cancelled."; exit 0; }
  fi
  for n in "${doomed[@]}"; do rm -rf "${BUILDS_DIR:?}/${n:?}"; done
  ok "pruned ${#doomed[@]} — reproduce: ctl build clean --keep $keep -y"
}

sub="${1:-}"; shift 2>/dev/null || true
case "$sub" in
  save)         is_help "${1:-}" && { build_help; exit 0; }; build_save "$@" ;;
  start)        build_start "$@" ;;
  clean)        build_clean "$@" ;;
  ""|-h|--help) build_help ;;
  *)            die "unknown subcommand '$sub' — ctl build save|start|clean (bare 'ctl build' = container images)" ;;
esac
