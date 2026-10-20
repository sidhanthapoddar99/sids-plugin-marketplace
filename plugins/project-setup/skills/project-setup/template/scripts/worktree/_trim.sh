#!/usr/bin/env bash
# scripts/worktree/_trim.sh — `ctl worktree trim`: delete the Cargo build outputs that no build used
# for N days, in every slot. SOURCE it after _busy.sh, and hold the pool lock.
#
# WHY. Cargo never deletes an old output, so a slot that lives for good keeps every build of every
# branch it carried. Deleting whole target folders makes the next build rewrite all of them, so the
# trim deletes by age, entry by entry, and keeps everything a build still uses.
#
# SCOPE. Only the entries of deps/, build/, .fingerprint/ and incremental/ inside a Cargo profile
# folder: <target>/<profile> or <target>/<triple>/<profile>, beside the CACHEDIR.TAG that Cargo
# writes. Never sources, .env, data/, logs/, node_modules/ or .venv/, and never a profile's own files,
# such as an uplifted binary. An entry goes when the newest read and the newest write of everything in
# it are older than N days. A file counts its access time and its modification time. A folder counts
# only its modification time, because walking it (this scan, du, ctl worktree list) sets its access
# time. A file with another hard link frees nothing. Cargo rebuilds a unit whose output or fingerprint
# is missing, so a trimmed entry costs one rebuild and nothing else.
#
# SAFETY. A slot where a process ctl started or a gate still runs is skipped whole (slot_busy with
# builds). Its containers do not hold it back, because they read no build output. A profile whose
# .cargo-lock a running Cargo holds is skipped too, because a build outside ctl, such as an editor's
# cargo check, may be writing there. The trim holds that lock while it deletes, so no Cargo build
# starts there halfway.

WT_TRIM_PARTS=(deps build .fingerprint incremental)
WT_TRIM_EVERY_DAYS=7        # create and remove trim on their own when the last trim is older than this
WT_TRIM_STAMP=.trim-stamp   # in .worktrees/; its modification time is the last real trim

# wt_trim_due — 0 when the last trim is more than WT_TRIM_EVERY_DAYS old, or there was none
wt_trim_due() {
  [[ -e $WT_DIR/$WT_TRIM_STAMP ]] || return 0
  [[ -n $(find "$WT_DIR/$WT_TRIM_STAMP" -mmin +$(( WT_TRIM_EVERY_DAYS * 1440 )) 2>/dev/null) ]]
}

# wt_cargo_profiles <slot folder> — each Cargo profile folder in the slot, one per line. A Cargo
# target that a build script made inside another unit's build/ folder belongs to that unit, so it is
# left out. A find that cannot read a folder only leaves profiles out, which trims less, never more.
wt_cargo_profiles() {
  local slot=$1 fingerprint profile other tag keep profiles=()
  while IFS= read -r -d '' fingerprint; do profiles+=("${fingerprint%/.fingerprint}"); done < <(
    find "$slot" -mindepth 1 \( -path "$slot/data" -o -path "$slot/logs" -o -name .git -o -name node_modules \
      -o -name .venv -o -name deps -o -name incremental \) -prune -o -type d -name .fingerprint -print0 -prune 2>/dev/null)
  for profile in ${profiles[@]+"${profiles[@]}"}; do
    keep=1
    for other in "${profiles[@]}"; do [[ $profile != "$other"/build/* ]] || keep=0; done
    (( keep )) && [[ ! -L $profile ]] || continue
    for tag in "$(dirname -- "$profile")/CACHEDIR.TAG" "$(dirname -- "$(dirname -- "$profile")")/CACHEDIR.TAG"; do
      if grep -qs -- 'created by cargo' "$tag"; then printf '%s\n' "$profile"; break; fi
    done
  done
  return 0
}

# _wt_old_entries <folder> <cutoff epoch> — "<bytes freed>\t<entry>" for each entry of the folder
# whose newest read and write, over everything inside it, are before the cutoff
_wt_old_entries() {
  find "$1" -mindepth 1 -printf '%y\t%n\t%b\t%A@\t%T@\t%P\n' 2>/dev/null | awk -F '\t' -v cut="$2" '
    { split($6, part, "/"); top = part[1]
      t = ($1 == "d" || $4 + 0 < $5 + 0) ? $5 + 0 : $4 + 0
      if (!(top in newest) || t > newest[top]) newest[top] = t
      if ($1 != "d" && $2 == 1) freed[top] += $3 * 512 }
    END { for (e in newest) if (newest[e] < cut) printf "%.0f\t%s\n", freed[e], e }'
}

# wt_trim_profile <label> <profile> <cutoff> <dry> — trim one profile folder under Cargo's own lock
wt_trim_profile() {
  local label=$1 profile=$2 cutoff=$3 dry=$4 fd part bytes entry count=0 freed=0 verb=freed
  (( dry )) && verb="would free"
  if ! { exec {fd}>>"$profile/.cargo-lock"; } 2>/dev/null; then say "  $label: skipped, its .cargo-lock cannot be opened"; return 0; fi
  if ! flock -n "$fd"; then exec {fd}>&-; say "  $label: skipped, Cargo is building there"; return 0; fi
  for part in "${WT_TRIM_PARTS[@]}"; do
    [[ -d $profile/$part && ! -L $profile/$part ]] || continue
    while IFS=$'\t' read -r bytes entry; do
      [[ -n $entry && $entry != */* && $entry != . && $entry != .. ]] || continue
      (( dry )) || rm -rf -- "${profile:?}/$part/$entry"
      freed=$(( freed + bytes )) count=$(( count + 1 ))
    done < <(_wt_old_entries "$profile/$part" "$cutoff")
  done
  exec {fd}>&-
  if (( count )); then say "  $label: $count output(s), $verb $(wt_human "$freed")"; fi
  WT_TRIM_COUNT=$(( WT_TRIM_COUNT + count )) WT_TRIM_BYTES=$(( WT_TRIM_BYTES + freed ))
}

# wt_trim <days> <dry> — trim every slot, or with dry=1 only count; write the stamp after a real trim
wt_trim() {
  local days=$1 dry=$2 n slot cutoff reasons profile
  cutoff=$(( $(date +%s) - days * 86400 ))
  WT_TRIM_COUNT=0 WT_TRIM_BYTES=0
  for n in ${WT_SLOTS[@]+"${WT_SLOTS[@]}"}; do
    slot="$WT_DIR/slot-$n"
    [[ -d $slot ]] || continue
    # A dev loop, build or gate running there could lose outputs halfway, so a slot in use waits.
    if reasons=$(slot_busy "$slot" builds); then warn "trim skipped slot-$n, which is in use: ${reasons//$'\n'/; }"; continue; fi
    while IFS= read -r profile; do
      [[ -z $profile ]] || wt_trim_profile "slot-$n/${profile#"$slot"/}" "$profile" "$cutoff" "$dry"
    done < <(wt_cargo_profiles "$slot")
  done
  if (( dry )); then
    ok "trim, dry run: $WT_TRIM_COUNT Cargo output(s) unused for $days day(s) would free $(wt_human "$WT_TRIM_BYTES"); nothing deleted"
  else
    touch -- "$WT_DIR/$WT_TRIM_STAMP"
    ok "trim: deleted $WT_TRIM_COUNT Cargo output(s) unused for $days day(s), freed $(wt_human "$WT_TRIM_BYTES")"
  fi
}

wt_human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }
