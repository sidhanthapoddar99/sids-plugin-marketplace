#!/usr/bin/env bash
# config/_env-merge.sh — step 1 of the env step: each ENV_FILES entry rebuilt in the shape of its
# template, every existing value kept. SOURCE it after _lib.sh.
#
#   - The result has the template's sections, comments, blank lines and key order. Each key line
#     .env holds is copied byte for byte; a key .env lacks takes the template's line.
#   - A key .env sets that the template only shows commented out (`# KEY=`) takes that line's place.
#   - A key only .env has goes to a last section, "# Not in .env.template (kept by ctl setup)". It
#     is removed only on a yes at the terminal or with --remove-unlisted, because a value is never
#     changed or dropped unasked.
#   - A comment line of .env that neither the template nor the copy of the template from the last
#     run (.env.template.synced) holds is a local comment, and it is kept with its key (env_merge).
#   - A key set twice in .env stops the step, because which value wins would be a guess.
#   - The file is written only when the result differs: a temporary file in the same folder, mode
#     600, then mv. The previous file is kept as .env.bak first, so a failure leaves .env whole.

ENV_KEY_RE='^([A-Za-z_][A-Za-z0-9_]*)='
ENV_SLOT_RE='^#[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)='
ENV_BLANK_RE='^[[:space:]]*$'

# env_unlisted_header <file> — the comment line that opens the last section of <file>.
env_unlisted_header() { printf '# Not in %s.template (kept by ctl setup)' "${1##*/}"; }

# env_merge <file> <template> <synced> <drop> — the merged lines in ENV_MERGED. Also sets ENV_ADDED
# (keys taken from the template), ENV_UNLISTED (keys only <file> has, in its order) and ENV_LOCAL
# (local comment lines kept). <synced> is the template of the last run, or a path that does not
# exist. <drop> 1 leaves out the unlisted keys and their local comments.
#
# Where a local comment goes, by the first rule that fits:
#   1. a key line below it with no blank line between: directly above that key;
#   2. no key line above it in <file>: at the top of the file;
#   3. else at the end of the paragraph that holds the nearest key line above it.
# Each rule puts the comment where the same rule finds it on the next run, so a rerun changes nothing.
env_merge() {
  local file=$1 template=$2 synced=$3 drop=$4 header i j k line
  local -a tl=() el=() sl=() out=() top=() before=() after=() below_key=() above_key=() dups=()
  local -A known=() tkey=() slot=() eidx=() oidx=()
  header=$(env_unlisted_header "$file")
  mapfile -t tl < "$template" || return 1
  mapfile -t el < "$file" || return 1
  if [[ -f $synced ]]; then mapfile -t sl < "$synced" || return 1; fi
  # A line the template or the last run's template holds came from the template, not from a person.
  # The "x" prefix keeps a line such as "@" a plain key.
  for line in "${tl[@]}" "${sl[@]}" "$header"; do known["x$line"]=1; done

  for (( j = 0; j < ${#tl[@]}; j++ )); do
    if [[ ${tl[j]} =~ $ENV_KEY_RE ]]; then
      k=${BASH_REMATCH[1]}
      [[ -z ${tkey[$k]+x} ]] || { err "$template declares $k twice, so ctl setup cannot know where it goes. Nothing was changed"; return 1; }
      tkey[$k]=$j
    elif [[ ${tl[j]} =~ $ENV_SLOT_RE ]]; then
      k=${BASH_REMATCH[1]}; [[ -n ${slot[$k]+x} ]] || slot[$k]=$j
    fi
  done
  for (( i = 0; i < ${#el[@]}; i++ )); do
    [[ ${el[i]} =~ $ENV_KEY_RE ]] || continue
    k=${BASH_REMATCH[1]}
    if [[ -n ${eidx[$k]+x} ]]; then dups+=("$k (lines $(( ${eidx[$k]} + 1 )) and $(( i + 1 )))"); else eidx[$k]=$i; fi
  done
  if (( ${#dups[@]} )); then
    err "$file sets a key twice: ${dups[*]}. Delete one line of each, because ctl setup cannot know which value wins. Nothing was changed"
    return 1
  fi

  # The template's lines, each key line replaced by the one <file> holds.
  ENV_ADDED=() ENV_UNLISTED=() ENV_LOCAL=0
  for (( j = 0; j < ${#tl[@]}; j++ )); do
    line=${tl[j]} k=""
    if [[ $line =~ $ENV_KEY_RE ]]; then
      k=${BASH_REMATCH[1]}
      if [[ -n ${eidx[$k]+x} ]]; then line=${el[${eidx[$k]}]}; else ENV_ADDED+=("$k"); fi
    elif [[ $line =~ $ENV_SLOT_RE ]]; then
      k=${BASH_REMATCH[1]}
      if [[ ${slot[$k]} == "$j" && -z ${tkey[$k]+x} && -n ${eidx[$k]+x} ]]; then line=${el[${eidx[$k]}]}; else k=""; fi
    fi
    [[ -z $k ]] || oidx[$k]=${#out[@]}
    out+=("$line")
  done
  for (( i = 0; i < ${#el[@]}; i++ )); do
    [[ ${el[i]} =~ $ENV_KEY_RE ]] || continue
    k=${BASH_REMATCH[1]}
    [[ -n ${oidx[$k]+x} ]] || ENV_UNLISTED+=("$k")
  done
  if (( ${#ENV_UNLISTED[@]} && ! drop )); then
    if (( ${#out[@]} )) && [[ ! ${out[-1]} =~ $ENV_BLANK_RE ]]; then out+=(""); fi
    out+=("$header")
    for k in "${ENV_UNLISTED[@]}"; do oidx[$k]=${#out[@]}; out+=("${el[${eidx[$k]}]}"); done
  fi

  # The local comments, each placed by the rules above.
  k=""
  for (( i = ${#el[@]} - 1; i >= 0; i-- )); do
    if [[ ${el[i]} =~ $ENV_BLANK_RE ]]; then k=""; elif [[ ${el[i]} =~ $ENV_KEY_RE ]]; then k=${BASH_REMATCH[1]}; fi
    below_key[i]=$k
  done
  k=""
  for (( i = 0; i < ${#el[@]}; i++ )); do
    if [[ ${el[i]} =~ $ENV_KEY_RE ]]; then k=${BASH_REMATCH[1]}; fi
    above_key[i]=$k
  done
  for (( i = 0; i < ${#el[@]}; i++ )); do
    line=${el[i]}
    [[ $line =~ $ENV_BLANK_RE || $line =~ $ENV_KEY_RE || -n ${known["x$line"]+x} ]] && continue
    if [[ -n ${below_key[i]} ]]; then
      k=${below_key[i]}; [[ -n ${oidx[$k]+x} ]] || continue   # its key was removed, and the comment with it
      before[${oidx[$k]}]+="$line"$'\n'
    elif [[ -z ${above_key[i]} ]]; then
      top+=("$line")
    else
      k=${above_key[i]}; [[ -n ${oidx[$k]+x} ]] || continue
      j=${oidx[$k]}
      while (( j + 1 < ${#out[@]} )) && [[ ! ${out[j + 1]} =~ $ENV_BLANK_RE ]]; do j=$(( j + 1 )); done
      after[j]+="$line"$'\n'
    fi
    ENV_LOCAL=$(( ENV_LOCAL + 1 ))
  done

  ENV_MERGED=()
  if (( ${#top[@]} )); then
    ENV_MERGED+=("${top[@]}")
    # A blank line keeps them a paragraph of their own when the first one holds a key, so rule 1
    # does not move them next run.
    for line in "${out[@]}"; do
      [[ ! $line =~ $ENV_BLANK_RE ]] || break
      if [[ $line =~ $ENV_KEY_RE ]]; then ENV_MERGED+=(""); break; fi
    done
  fi
  for (( j = 0; j < ${#out[@]}; j++ )); do
    [[ -z ${before[j]-} ]] || mapfile -t -O "${#ENV_MERGED[@]}" ENV_MERGED <<< "${before[j]%$'\n'}"
    ENV_MERGED+=("${out[j]}")
    [[ -z ${after[j]-} ]] || mapfile -t -O "${#ENV_MERGED[@]}" ENV_MERGED <<< "${after[j]%$'\n'}"
  done
}

# env_files_same <a> <b> — 0 when the two files hold the same lines and the same last byte.
env_files_same() {
  local -a a=() b=(); local i
  mapfile -t a < "$1" && mapfile -t b < "$2" || return 1
  (( ${#a[@]} == ${#b[@]} )) || return 1
  for (( i = 0; i < ${#a[@]}; i++ )); do [[ ${a[i]} == "${b[i]}" ]] || return 1; done
  [[ $(tail -c 1 "$1") == "$(tail -c 1 "$2")" ]]
}

# env_replace <file> <new> — put <new> in place of <file>, after keeping <file> as <file>.bak. Both
# are mode 600. A failure at any point leaves <file> as it was and removes <new>.
env_replace() {
  local file=$1 new=$2 bak
  [[ ! -L $file ]] || { rm -f -- "$new"; err "$file is a link. ctl setup writes a new file and renames it into place, which would replace the link. Merge it by hand from $file.template. Nothing was changed"; return 1; }
  [[ ! -d $file.bak ]] || { rm -f -- "$new"; err "$file.bak is a folder, so ctl setup cannot keep the previous $file there. Nothing was changed"; return 1; }
  bak=$(umask 077; mktemp "$file.bak.XXXXXX") \
    && cp -- "$file" "$bak" && chmod 600 -- "$bak" && mv -f -- "$bak" "$file.bak" \
    || { rm -f -- "$new" ${bak:+"$bak"}; err "could not keep the previous $file as $file.bak. Nothing was changed"; return 1; }
  chmod 600 -- "$new" && mv -f -- "$new" "$file" \
    || { rm -f -- "$new"; err "could not write $file. It is as it was, and $file.bak holds the same text"; return 1; }
}

# env_record_template <file> — keep a copy of <file>.template as <file>.template.synced, which the
# next run reads to tell a template comment from a local one.
env_record_template() {
  local file=$1 synced="$1.template.synced" new
  [[ ! -f $synced ]] || ! env_files_same "$file.template" "$synced" || return 0
  new=$(umask 077; mktemp "$synced.XXXXXX") && cp -- "$file.template" "$new" && mv -f -- "$new" "$synced" \
    || { rm -f -- ${new:+"$new"}; err "could not record $file.template as $synced"; return 1; }
}

# env_slot_ports <file> <slot> — in a slot, stop when the template declares a numbered *_PORT that
# <file> lacks. A slot's ports carry the offset ctl worktree gave it, which this step cannot know,
# and the main tree's port would let the slot's apps reach the main tree's.
env_slot_ports() {
  local file=$1 slot=$2 line key value ports=()
  while IFS= read -r line || [[ -n $line ]]; do
    key=${line%%=*} value=${line#*=}; value=${value%$'\r'}; value=${value%%[[:space:]]#*}
    [[ $line == *=* && $key =~ ^[A-Za-z_][A-Za-z0-9_]*_PORT$ && ${value%"${value##*[![:space:]]}"} =~ ^[0-9]+$ ]] || continue
    grep -q "^${key}=" "$file" || ports+=("$key")
  done < "$file.template"
  (( ${#ports[@]} == 0 )) && return 0
  err "$file lacks ${ports[*]}, a port $file.template declares. In $slot, add each one by hand with the slot's offset, which the first line of $file names, then run this again. Nothing was changed"
  return 1
}

# sync_env_template [remove] — step 1 for every ENV_FILES entry. <remove> 1 (--remove-unlisted)
# removes the keys only the file has without asking. Otherwise a terminal is asked once for the
# whole list, and no terminal keeps them. Output names keys only, never a value or a comment,
# because .env holds secrets and a screen or a log may be read by someone else.
sync_env_template() {
  local remove=${1:-0} file slot="" drop new k
  [[ $CTL_ROOT =~ /\.worktrees/(slot-[0-9]+)$ ]] && slot=${BASH_REMATCH[1]}
  for file in "${ENV_FILES[@]}"; do
    [[ -f "$file.template" ]] || { err "no $file.template to create $file from"; return 1; }
    if [[ ! -f $file ]]; then
      [[ -z $slot ]] || { err "$slot has no $file. A copy of $file.template would hold the main tree's ports; ctl worktree create writes a slot's own $file when it takes a free slot"; return 1; }
      (umask 077; cp "$file.template" "$file"; chmod 600 "$file") || return 1
      env_record_template "$file" || return 1
      ok "created $file from $file.template"
      continue
    fi
    [[ -z $slot ]] || env_slot_ports "$file" "$slot" || return 1
    env_merge "$file" "$file.template" "$file.template.synced" 0 || return 1
    drop=0
    if (( ${#ENV_UNLISTED[@]} )); then
      if (( remove )); then
        drop=1
      elif can_ask 0; then
        say "These keys are in $file but not in $file.template:"
        printf '  %s\n' "${ENV_UNLISTED[@]}"
        if ask_yes "Remove them from $file?" n; then drop=1; fi
      fi
      if (( drop )); then env_merge "$file" "$file.template" "$file.template.synced" 1 || return 1; fi
    fi
    new=$(umask 077; mktemp "$file.setup.XXXXXX") || { err "cannot write a temporary file beside $file"; return 1; }
    { (( ${#ENV_MERGED[@]} == 0 )) || printf '%s\n' "${ENV_MERGED[@]}"; } > "$new" \
      || { rm -f -- "$new"; err "could not write the merged $file. Nothing was changed"; return 1; }
    if env_files_same "$file" "$new"; then
      rm -f -- "$new"
      ok "$file is in the shape of $file.template"
    else
      env_replace "$file" "$new" || return 1
      ok "$file rebuilt in the shape of $file.template; the previous file is $file.bak"
      (( ${#ENV_ADDED[@]} == 0 )) || say "  added from the template: ${ENV_ADDED[*]}"
      (( ENV_LOCAL == 0 )) || say "  local comment lines kept: $ENV_LOCAL"
      if (( ENV_LOCAL )) && [[ ! -f $file.template.synced ]]; then
        warn "$file had no record of the template it last matched, so every comment line $file.template lacks was kept as a local comment. Delete any that is old template text; later runs tell the two apart"
      fi
    fi
    if (( drop )); then
      ok "removed from $file, not in $file.template: ${ENV_UNLISTED[*]} ($file.bak holds them)"
    elif (( ${#ENV_UNLISTED[@]} )); then
      warn "kept in the last section of $file, not in $file.template: ${ENV_UNLISTED[*]}. Remove them with ctl setup --remove-unlisted, or answer y at the prompt in a terminal"
    fi
    env_record_template "$file" || return 1
  done
}
