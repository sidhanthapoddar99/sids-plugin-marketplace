#!/usr/bin/env bash
# scripts/common/_transcript.sh — deploy transcripts, `ctl up --background` and `ctl up status`. up.sh
# sources it after _lib.sh and _compose_start.sh.
#
# A deploy (a non-empty TAG that image_tag_local does not call local) writes its whole output, stdout and
# stderr, to LOGS_DIR/deploy/<UTC YYYYmmdd-HHMMSS>-<tag>.log, from the settled plan to the end. No flag
# turns it on. The terminal still shows the output; the transcript gets it without colour codes. An EXIT
# trap writes the last line, `result: ok` or `result: failed (exit N)`, so a run that stops anywhere says
# how it ended, and a transcript without that line was interrupted. While a deploy runs, it holds the
# process record LOGS_DIR/run/up.process, so a second deploy or background run refuses, and ctl db restore
# and ctl dev db stop wait for it.
#
# --background runs the same ctl up again under process_start: its own session, stdin from /dev/null, no
# terminal to lose. That child writes straight to a transcript, whatever the tag, because its output has
# to go somewhere, and process_start's record is the run's record.

TRANSCRIPT_RECORD=up          # the process record name: LOGS_DIR/run/up.process
TRANSCRIPT_FILE=''            # this run's transcript, once it has one
TRANSCRIPT_CONSOLE=''         # the terminal's stdout, while a tee copies the run into the transcript
TRANSCRIPT_STDERR=''          # the terminal's stderr, the same way
TRANSCRIPT_COPIES=()          # the pids of the two copies, stdout's and stderr's
TRANSCRIPT_CLAIM=''           # the record a foreground deploy claimed, removed when it ends

# transcript_wanted — 0 when this run is a deploy, so it writes a transcript.
transcript_wanted() { [[ -n ${TAG-} ]] && ! image_tag_local "$TAG"; }

transcript_record() { printf '%s/run/%s.process\n' "$LOGS_DIR" "$TRANSCRIPT_RECORD"; }

# transcript_refuse_live — stop when another deploy or background run still holds the record.
transcript_refuse_live() {
  local record; record=$(transcript_record)
  [[ -d $record ]] && ! process_stale "$record" || return 0
  die "another ctl up is still running ($record); follow it with ctl up status -f, and start this one when it ends. A record no ctl up holds any more can be removed by hand"
}

# transcript_storage <dir…> — create the folders this run writes, and stop, naming the folder and the fix,
# when the current user cannot write one. It runs before the build, so a root-owned folder never stops a
# deploy halfway.
transcript_storage() {
  local dir problem
  for dir in "$@"; do
    mkdir -p -- "$dir" 2>/dev/null || true
    problem=$(storage_dir_writable "$dir") || die "$problem — this run writes there, so it stops before the build"
  done
}

# transcript_precheck <background 0|1> — before the plan: refuse a deploy or a background run that cannot
# write its folders, or that another run blocks, so nobody waits for a plan that cannot start. The child of
# --background skips it: its parent checked, and its own record is the live one.
transcript_precheck() {
  local -a dirs=("$LOGS_DIR/deploy" "$LOGS_DIR/run")
  [[ -z $TRANSCRIPT_FILE ]] || return 0
  if transcript_wanted; then dirs+=("$DATA_DIR"); elif (( ! $1 )); then return 0; fi
  transcript_storage "${dirs[@]}"
  transcript_refuse_live
}

# transcript_open <tag> — create this run's transcript, <UTC second>-<tag>.log. ctl up status takes the
# last name as the newest run, so a run waits for the next second while any transcript already holds this
# one, whatever its tag: two runs in one second used to sort by tag, and status then named the older
# one. LOGS_DIR/run/transcript.lock makes the check and the create one step, because a --background run
# opens its transcript before it holds the run's record.
transcript_open() {
  local tag="${1:-untagged}" dir="$LOGS_DIR/deploy" stamp file lock attempt
  local -a taken
  exec {lock}> "$LOGS_DIR/run/transcript.lock" || { err "ctl cannot open $LOGS_DIR/run/transcript.lock"; return 1; }
  if ! flock -w 30 "$lock"; then exec {lock}>&-; err "another ctl up holds $LOGS_DIR/run/transcript.lock"; return 1; fi
  for attempt in {1..15}; do
    stamp=$(date -u +%Y%m%d-%H%M%S)
    taken=("$dir/$stamp"-*.log)
    if [[ ! -e ${taken[0]} ]]; then
      file="$dir/$stamp-$tag.log"
      if ( set -o noclobber; : > "$file" ) 2>/dev/null; then exec {lock}>&-; TRANSCRIPT_FILE="$file"; return 0; fi
      break
    fi
    sleep 0.2
  done
  exec {lock}>&-
  err "ctl cannot create a transcript in $dir"
  return 1
}

# transcript_started <file> — the start time a transcript's name holds, as 2026-10-29 10:00:00 UTC.
transcript_started() {
  local stamp="${1##*/}"; stamp="${stamp:0:15}"
  printf '%s-%s-%s %s:%s:%s UTC\n' "${stamp:0:4}" "${stamp:4:2}" "${stamp:6:2}" "${stamp:9:2}" "${stamp:11:2}" "${stamp:13:2}"
}

# transcript_header <argv…> — the transcript's first lines: where it is, what ran, the tag and when.
transcript_header() {
  printf 'transcript  %s\n' "${TRANSCRIPT_FILE#"$CTL_ROOT"/}"
  printf 'command     ctl up %s\n' "$*"
  printf 'tag         %s\n' "$(image_tag_label)"
  printf 'started     %s\n' "$(transcript_started "$TRANSCRIPT_FILE")"
}

# transcript_traps — record how the run ends. A signal exits through the EXIT trap with 128 + its number.
transcript_traps() {
  trap transcript_finish EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# transcript_adopt — in the child of --background, at its start: its output is the transcript already, so
# it only records how it ends, even when it stops before the plan.
transcript_adopt() {
  [[ -n ${CTL_UP_TRANSCRIPT-} ]] || return 0
  TRANSCRIPT_FILE="$CTL_UP_TRANSCRIPT"
  unset CTL_UP_TRANSCRIPT
  transcript_traps
}

# transcript_begin <argv…> — at the settled plan, before the build: a foreground deploy claims the record,
# then a tee copies all its output into a new transcript while the terminal shows it as before. The prompts
# are over by then. Docker sees a pipe, not a terminal, so it prints plain progress, which a log can hold.
transcript_begin() {
  [[ -z $TRANSCRIPT_FILE ]] || return 0      # the background child, adopted at its start
  transcript_wanted || return 0
  transcript_storage "$LOGS_DIR/deploy" "$LOGS_DIR/run" "$DATA_DIR"
  if ! process_claim "$TRANSCRIPT_RECORD" 2>/dev/null; then
    transcript_refuse_live
    die "ctl cannot write the process record $(transcript_record)"
  fi
  TRANSCRIPT_CLAIM="$PROCESS_RECORD"
  transcript_traps
  transcript_open "$TAG" || exit 1
  exec {TRANSCRIPT_CONSOLE}>&1 {TRANSCRIPT_STDERR}>&2
  exec > >(transcript_copy "$TRANSCRIPT_CONSOLE"); TRANSCRIPT_COPIES=("$!")
  exec 2> >(transcript_copy "$TRANSCRIPT_STDERR"); TRANSCRIPT_COPIES+=("$!")
  transcript_header "$@"
}

# transcript_copy <terminal fd> — one stream's copy: to its terminal fd as it was, and to the transcript
# without colour codes. stdout and stderr keep their own terminal fds, so a caller that reads stderr still
# can; in the file each line lands whole, and a line from one stream can land a moment before a line the
# other wrote first. tee keeps going when the terminal goes away (--output-error=warn, signals ignored), so
# the transcript still gets the run's end after an SSH drop. tee writes the terminal copy through the
# handle it inherits, never a reopened /dev/fd path: a reopened file gets its own write position, so a
# later write to the terminal fd (the result line, the attached log stream) would land over earlier
# output, and a socket cannot be reopened at all. Only the pipe to sed is reopened.
transcript_copy() {
  trap '' INT TERM HUP PIPE
  tee --output-error=warn /dev/fd/3 3>&1 >&"$1" | sed -u $'s/\e\\[[0-9;]*m//g' >> "$TRANSCRIPT_FILE"
}

# transcript_finish — the EXIT trap: let both copies drain, write the result line last, release the claim.
transcript_finish() {
  local status=$? attempt result pid live
  trap - EXIT HUP INT TERM
  trap '' PIPE
  if [[ -n $TRANSCRIPT_CONSOLE ]]; then
    exec 1>&"$TRANSCRIPT_CONSOLE" 2>&"$TRANSCRIPT_STDERR"     # closes this shell's ends of the copies' pipes
    for attempt in {1..100}; do
      live=0; for pid in "${TRANSCRIPT_COPIES[@]}"; do kill -0 "$pid" 2>/dev/null && live=1; done
      (( live )) || break; sleep 0.05
    done
  fi
  if [[ -n $TRANSCRIPT_FILE ]]; then
    result='result: ok'; (( status == 0 )) || result="result: failed (exit $status)"
    # written straight to the file once the copies are done, so it is the last line; the background
    # child's stdout is the file already
    printf '%s\n' "$result" >> "$TRANSCRIPT_FILE"
    [[ -z $TRANSCRIPT_CONSOLE ]] || printf '%s\n' "$result"
  fi
  [[ -z $TRANSCRIPT_CLAIM ]] || rm -rf -- "$TRANSCRIPT_CLAIM"
  exit "$status"
}

# transcript_background <up.sh> <argv…> — start this ctl up again, detached, and return at once. The child
# runs the same arguments without --background and with --nqa, and its output is its transcript.
transcript_background() {
  local script="$1" arg nqa=0; shift
  local -a argv=()
  for arg in "$@"; do
    case "$arg" in --background) ;; --nqa|--no-questions-asked) nqa=1; argv+=("$arg") ;; *) argv+=("$arg") ;; esac
  done
  (( nqa )) || argv+=(--nqa)
  process_init         # until process_release, an exit here stops a half-started child and drops its record
  transcript_precheck 1
  transcript_open "${TAG-}" || exit 1
  transcript_header "${argv[@]}" >> "$TRANSCRIPT_FILE"
  if ! PROCESS_LOG="$TRANSCRIPT_FILE" process_start "$TRANSCRIPT_RECORD" "$CTL_ROOT" \
         env CTL_UP_TRANSCRIPT="$TRANSCRIPT_FILE" bash "$script" "${argv[@]}"; then
    printf 'ctl up could not start in the background\nresult: failed (exit 1)\n' >> "$TRANSCRIPT_FILE"
    die "ctl up could not start in the background (named above)"
  fi
  process_release      # the child outlives this shell; nothing here stops it
  ok "ctl up runs in the background"
  say "  transcript  ${TRANSCRIPT_FILE#"$CTL_ROOT"/}"
  say "  follow it   ctl up status -f"
}

# transcript_state <file> — print "<state><TAB><exit>" for a transcript: succeeded 0, failed (exit N) N,
# running 0 while the record's process lives, else interrupted 1.
transcript_state() {
  local last code
  last=$(tail -n 1 -- "$1") || last=''
  case "$last" in
    'result: ok') printf 'succeeded\t0\n' ;;
    'result: failed (exit '*')')
      code="${last#'result: failed (exit '}"; code="${code%)}"
      [[ $code =~ ^[0-9]+$ ]] || code=1
      printf 'failed (exit %s)\t%s\n' "$code" "$code" ;;
    *) if process_running "$(transcript_record)"; then printf 'running\t0\n'; else printf 'interrupted\t1\n'; fi ;;
  esac
}

# transcript_status [-f] — `ctl up status`: the newest transcript, its tag and start, the deploy record,
# the state and the last lines. -f follows a running one to its end and exits with its result. Plain
# status exits 0 when the run succeeded or still runs, and 1 when it failed, was interrupted, or none exists.
transcript_status() {
  local follow=0 file name tag state code commit record shown size lines=15
  local -a files=()
  while (( $# )); do case "$1" in
    -f|--follow) follow=1; shift ;;
    -h|--help) print_help "up status" "The newest deploy transcript: its state and last lines." 'up status [-f] [-h]' \
"Arguments
  -f, --follow    follow a running deploy to its end, then exit with its result
  -h, --help      show this help

States: running (its process record lives) · succeeded · failed (exit N) · interrupted (no result
line, and no process left). Exit 0 when the run succeeded or still runs, 1 when it failed or was
interrupted; with -f, the run's own exit." "Example:  ctl up status -f"; return 0 ;;
    *) die "unknown argument: $1 (try ctl up status --help)" ;;
  esac; done
  files=("$LOGS_DIR"/deploy/*.log)
  [[ -e ${files[0]} ]] || { say "no deploy transcript yet in ${LOGS_DIR#"$CTL_ROOT"/}/deploy"; return 1; }
  file="${files[-1]}"
  name="${file##*/}"; tag="${name:16}"; tag="${tag%.log}"
  record=$(deploy_record_file)
  commit='none yet'; [[ ! -f $record ]] || commit="$(<"$record") (${record#"$CTL_ROOT"/})"
  IFS=$'\t' read -r state code < <(transcript_state "$file")
  printf '%stranscript%s  %s\n' "$C_DIM" "$C_RESET" "${file#"$CTL_ROOT"/}"
  printf '%stag%s         %s\n' "$C_DIM" "$C_RESET" "$tag"
  printf '%sstarted%s     %s\n' "$C_DIM" "$C_RESET" "$(transcript_started "$file")"
  printf '%sdeployed%s    %s\n' "$C_DIM" "$C_RESET" "$commit"
  printf '%sstate%s       %s\n' "$C_DIM" "$C_RESET" "$state"
  hr
  if (( ! follow )); then
    tail -n "$lines" -- "$file"
    [[ $state == succeeded || $state == running ]]; return
  fi
  # Follow by size, not with tail --pid: tail takes a zombie for a live process, and process_running does
  # not. The run writes its result line before its record stops running, so the last read holds it.
  tail -n "$lines" -- "$file"
  shown=$(stat -c %s -- "$file")
  while [[ $state == running ]]; do
    process_running "$(transcript_record)" || state=ended
    size=$(stat -c %s -- "$file")
    if (( size > shown )); then tail -c +"$(( shown + 1 ))" -- "$file" | head -c "$(( size - shown ))"; shown=$size; fi
    [[ $state == running ]] && sleep 0.5
  done
  IFS=$'\t' read -r state code < <(transcript_state "$file")   # the run has ended, or just did
  hr; say "state  $state"
  return "$code"
}
