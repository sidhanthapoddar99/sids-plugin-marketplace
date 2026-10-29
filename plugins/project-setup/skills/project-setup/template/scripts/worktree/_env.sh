#!/usr/bin/env bash
# scripts/worktree/_env.sh — the .env a slot gets on its first use. SOURCE it after _pool.sh.
#
# It is the main tree's .env with three changes, so the stacks, images and dev servers of two slots
# never collide with each other or with the main tree:
#   every KEY_PORT that holds a number   + WT_PORT_STEP × the slot number (+ 100 for slot-1)
#   COMPOSE_PROJECT_NAME                 <name>-slot-<n>; an empty one starts from the main tree's
#                                        folder name, as compose names the main tree's stack
#   TAG                                  dev-slot-<n>, whatever the main tree's TAG is, so each slot
#                                        builds and runs its own images: with one shared tag, one
#                                        slot's migration image could migrate another slot's
#                                        database. A slot is for development, so it never takes a
#                                        main tree's auto, none or pinned production name
# BASE_DIR and the storage paths are copied as they are. They must be relative, so each slot keeps
# its own data/ and logs/. Later uses of a slot keep its .env; ctl worktree never rewrites one.
#
# A value the offset cannot make safe is refused, and nothing changes, because the slot would
# quietly reach the main tree's services or files. Each refusal names the key, so the fix is one edit:
#   - a port written as a number inside another value: write ${API_PORT}, so the offset reaches it
#   - a KEY_PORT that is neither a number nor a ${NAME} reference, or one that would pass 65535
#   - BASE_DIR, DATA_DIR, LOGS_DIR or BACKUP_DIR that is absolute, has a .. part, or is built from
#     another key than these four: two checkouts could then share one database
#   - a KEY_PORT that .env.template declares and the main tree's .env lacks: the slot would lack it
#     too, and ctl setup never adds a port number to a slot, because it cannot know the offset
#   - a port that the main tree's .env, another slot's .env or PORT_PRESETS already uses
# Messages name keys and ports only, because a value may hold a credential.

WT_PORT_STEP=100   # a step of 100 keeps each port's last two digits, so a port stays recognisable in every slot
WT_STORAGE_KEYS=(BASE_DIR DATA_DIR LOGS_DIR BACKUP_DIR)

# wt_env_split <line> — 0 for a KEY=value line. Sets WT_KEY, and WT_VALUE as load_env_file reads it:
# no CR, no trailing " # comment", no trailing blanks.
wt_env_split() {
  [[ $1 =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || return 1
  WT_KEY=${BASH_REMATCH[1]} WT_VALUE=${BASH_REMATCH[2]%$'\r'}
  WT_VALUE=${WT_VALUE%%[[:space:]]#*}; WT_VALUE=${WT_VALUE%"${WT_VALUE##*[![:space:]]}"}
}

# wt_env_ports <file> — "<port> <KEY>" for each KEY_PORT of an env file that holds a number. A
# missing file has none; a file that cannot be read returns 1, because a check that cannot read
# must not pass.
wt_env_ports() {
  local line
  [[ -e $1 || -L $1 ]] || return 0
  [[ -f $1 && -r $1 ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    wt_env_split "$line" && [[ $WT_KEY == *_PORT && $WT_VALUE =~ ^[0-9]{1,9}$ ]] || continue
    printf '%s %s\n' "$(( 10#$WT_VALUE ))" "$WT_KEY"
  done < "$1"
}

# _wt_storage_problem <key> <value> — print why a storage path could leave the slot; nothing when it
# stays inside. The reference check follows ${NAME} the way the env loader expands it.
_wt_storage_problem() {
  local key=$1 value=$2 rest=$2 ref
  if [[ $value == /* ]]; then printf '%s is an absolute path' "$key"; return 0; fi
  if [[ /$value/ == */../* ]]; then printf '%s has a .. part, which leads out of the slot' "$key"; return 0; fi
  while [[ $rest =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
    ref=${BASH_REMATCH[1]}
    if [[ " ${WT_STORAGE_KEYS[*]} " != *" $ref "* ]]; then
      printf '%s is built from ${%s}, which ctl worktree cannot prove stays inside the slot' "$key" "$ref"; return 0
    fi
    rest=${rest#*"\${$ref}"}
  done
}

# wt_env_render <n> — print slot-<n>'s first .env, or name every problem on stderr and return 1
wt_env_render() {
  local n=$1 src="$WT_MAIN/.env" line key port new found=0 base problem problems=()
  local -A ports=() present=()
  while IFS= read -r line || [[ -n $line ]]; do
    wt_env_split "$line" || continue
    present[$WT_KEY]=1
    if [[ $WT_KEY == *_PORT && $WT_VALUE =~ ^[0-9]{1,9}$ ]]; then ports[$(( 10#$WT_VALUE ))]=$WT_KEY; fi
  done < "$src"
  if [[ -f $WT_MAIN/.env.template ]]; then
    while IFS= read -r key; do
      [[ $key != *_PORT || -n ${present[$key]:-} ]] \
        || problems+=("it lacks $key, which .env.template declares, so slot-$n would lack it too, and ctl setup there would stop on it; run ctl setup in the main tree first")
    done < <(env_keys "$WT_MAIN/.env.template")
  fi
  base=$(wt_compose_name "$(basename -- "$WT_MAIN")")
  printf '# Written by ctl worktree for slot-%s from the main tree'\''s .env: ports + %s, and COMPOSE_PROJECT_NAME\n' "$n" "$(( WT_PORT_STEP * n ))"
  printf '# and TAG end in -slot-%s. Later uses of the slot keep this file.\n' "$n"
  while IFS= read -r line || [[ -n $line ]]; do
    if wt_env_split "$line"; then
      case $WT_KEY in
        *_PORT)
          if [[ $WT_VALUE =~ ^[0-9]{1,9}$ ]]; then
            new=$(( 10#$WT_VALUE + WT_PORT_STEP * n ))
            (( new <= 65535 )) || problems+=("$WT_KEY would be $new in slot-$n, past the last port, 65535")
            line="$WT_KEY=$new"
          elif [[ -n $WT_VALUE && ! $WT_VALUE =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*\}$ ]]; then
            problems+=("$WT_KEY is neither a port number nor a \${NAME} reference, so ctl worktree cannot move it")
          fi ;;
        COMPOSE_PROJECT_NAME)
          line="COMPOSE_PROJECT_NAME=${WT_VALUE:-$base}-slot-$n"; found=1 ;;
        TAG)
          [[ -z $WT_VALUE ]] || line="TAG=dev-slot-$n" ;;
        BASE_DIR|DATA_DIR|LOGS_DIR|BACKUP_DIR)
          problem=$(_wt_storage_problem "$WT_KEY" "$WT_VALUE")
          [[ -z $problem ]] || problems+=("$problem, so slot-$n could share the main tree's data; make it relative, like ./data") ;;
        *)
          for port in "${!ports[@]}"; do
            [[ ! $WT_VALUE =~ :$port([^0-9]|$) ]] \
              || problems+=("$WT_KEY names port $port as a number; write \${${ports[$port]}} instead, so a slot's offset reaches it")
          done ;;
      esac
    fi
    printf '%s\n' "$line"
  done < "$src"
  (( found )) || printf 'COMPOSE_PROJECT_NAME=%s-slot-%s\n' "$base" "$n"
  (( ${#problems[@]} )) || return 0
  err "the main tree's .env cannot become slot-$n's .env as it is, so ctl worktree changed nothing:"
  printf '  - %s\n' "${problems[@]}" >&2
  return 1
}

# wt_env_clashes <new .env> <n> — print one line for each port of slot-<n>'s new .env that something
# else already uses, naming both sides: the main tree's .env, the .env of every other slot as it is
# on disk (a hand-edited slot keeps its own ports), and the ctl build start ports (PORT_PRESETS).
# Prints nothing when every port is clear; returns 1 when an env file cannot be read.
wt_env_clashes() {
  local file=$1 n=$2 port key m list
  local -A mine=()
  list=$(wt_env_ports "$file") || { err "cannot read the ports of slot-$n's new .env"; return 1; }
  while read -r port key; do [[ -z $port ]] || mine[$port]=$key; done <<< "$list"
  list=$(wt_env_ports "$WT_MAIN/.env") || { err "cannot read the ports in $WT_MAIN/.env"; return 1; }
  while read -r port key; do
    [[ -z $port || -z ${mine[$port]:-} ]] || printf "slot-%s's %s=%s is the main tree's %s too (.env)\n" "$n" "${mine[$port]}" "$port" "$key"
  done <<< "$list"
  for m in ${WT_SLOTS[@]+"${WT_SLOTS[@]}"}; do
    [[ $m != "$n" ]] || continue
    list=$(wt_env_ports "$WT_DIR/slot-$m/.env") || { err "cannot read the ports in $WT_DIR/slot-$m/.env"; return 1; }
    while read -r port key; do
      [[ -z $port || -z ${mine[$port]:-} ]] || printf "slot-%s's %s=%s is slot-%s's %s too (.worktrees/slot-%s/.env)\n" "$n" "${mine[$port]}" "$port" "$m" "$key" "$m"
    done <<< "$list"
  done
  for port in ${PORT_PRESETS[@]+"${PORT_PRESETS[@]}"}; do
    [[ -z ${mine[$port]:-} ]] || printf "slot-%s's %s=%s is a ctl build start port too (PORT_PRESETS)\n" "$n" "${mine[$port]}" "$port"
  done
  return 0
}

# wt_env_prepare <n> — check and render slot-<n>'s first .env before anything changes, into
# WT_ENV_TMP (mode 600, under .worktrees/), which wt_env_install puts in place. The caller's EXIT
# trap removes the file when the command stops early.
wt_env_prepare() {
  local n=$1 clashes line
  [[ -f $WT_MAIN/.env ]] || die "the main tree has no .env to write slot-$n's from; run ctl setup in the main tree first"
  WT_ENV_TMP=$(umask 077; mktemp "$WT_DIR/.env.slot-$n.XXXXXX") || die "cannot write a temporary file in $WT_DIR"
  wt_env_render "$n" > "$WT_ENV_TMP" || exit 1
  clashes=$(wt_env_clashes "$WT_ENV_TMP" "$n") || exit 1
  [[ -n $clashes ]] || return 0
  err "slot-$n's ports would clash, so ctl worktree changed nothing:"
  while IFS= read -r line; do printf '  - %s\n' "$line" >&2; done <<< "$clashes"
  die "change the clashing ports in the main tree's .env, then run the command again"
}

# wt_env_install <n> — put the prepared .env in place. An existing .env is never replaced.
wt_env_install() {
  local dest="$WT_DIR/slot-$1/.env"
  [[ -n ${WT_ENV_TMP:-} ]] || return 0
  if [[ -e $dest || -L $dest ]]; then rm -f -- "$WT_ENV_TMP"; WT_ENV_TMP=""; say "· slot-$1 already has a .env; kept it" >&2; return 0; fi
  chmod 600 -- "$WT_ENV_TMP"
  mv -T -- "$WT_ENV_TMP" "$dest"; WT_ENV_TMP=""
  say "· wrote slot-$1/.env from the main tree's .env: ports + $(( WT_PORT_STEP * $1 )), COMPOSE_PROJECT_NAME and TAG …-slot-$1 (mode 600)" >&2
}
