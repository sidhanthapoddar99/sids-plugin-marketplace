#!/usr/bin/env bash
# scripts/common/_paths.sh — the storage paths every host operation uses. _lib.sh sources it.
#
# .env.template hangs every storage path off one root, so one setting moves them all:
#   BASE_DIR=.   DATA_DIR=${BASE_DIR}/data   LOGS_DIR=${BASE_DIR}/logs   BACKUP_DIR=${LOGS_DIR}/backups
# expand_env_refs has already replaced each ${NAME}, so a shell value (BASE_DIR=/srv/app ctl up)
# reaches every path that derives from it. resolve_storage_dirs then makes the four paths absolute.
# A relative path is anchored at CTL_ROOT, the checkout's root, the way compose anchors it at
# --project-directory, so ctl and compose see one path. A relative BASE_DIR therefore gives each
# checkout, and each worktree slot, its own data/ and logs/.

# storage_path <var> <value> — set <var> to <value> as an absolute path, anchored at CTL_ROOT when
# relative, without `.` segments, doubled slashes or a trailing slash. It never resolves `..`;
# resolve_storage_dirs refuses that segment instead.
storage_path() {
  local path="$2"
  [[ $path == /* ]] || path="$CTL_ROOT/$path"
  while [[ $path == *//* ]]; do path="${path//\/\//\/}"; done
  while [[ $path == */./* ]]; do path="${path//\/.\//\/}"; done
  [[ $path != */. ]] || path="${path%/.}"
  [[ $path == / ]] || path="${path%/}"
  printf -v "$1" '%s' "${path:-/}"
}

# resolve_storage_dirs — export BASE_DIR, DATA_DIR, LOGS_DIR and BACKUP_DIR as absolute paths.
# Call it after require_env (or load_env_soft). An unset key takes its template default, derived
# from the keys before it. A blank value, an unexpanded ${NAME} and a `..` segment fail naming the
# key, because each would select a directory nobody configured. A second call changes nothing.
resolve_storage_dirs() {
  local key value
  : "${CTL_ROOT:?CTL_ROOT must be set}"
  for key in BASE_DIR DATA_DIR LOGS_DIR BACKUP_DIR; do
    if [[ -v $key ]]; then value="${!key}"
    else
      case "$key" in
        BASE_DIR)   value=. ;;
        DATA_DIR)   value="$BASE_DIR/data" ;;
        LOGS_DIR)   value="$BASE_DIR/logs" ;;
        BACKUP_DIR) value="$LOGS_DIR/backups" ;;
      esac
    fi
    [[ -n ${value//[[:space:]]/} ]] || { printf '%s is blank\n' "$key" >&2; return 1; }
    [[ $value != *'${'* ]] || { printf '%s requires expanded environment\n' "$key" >&2; return 1; }
    [[ /$value/ != */../* ]] || { printf '%s=%s has a .. segment — write the path from the repo root, or as an absolute path\n' "$key" "$value" >&2; return 1; }
    storage_path "$key" "$value"
    export "${key?}"
  done
}

# storage_dir_writable <dir> — 0 when the folder exists and the current user may create files in it.
# Otherwise it prints what is wrong and the fix, and returns 1. ctl check runs it on DATA_DIR, LOGS_DIR
# and BACKUP_DIR, and a deploy on the folders it writes, before the build: a root-owned folder used to
# stop a deploy only at its first write there. A missing folder names its nearest existing parent.
storage_dir_writable() {
  local dir="$1" parent="$1" owner
  [[ -d $dir && -w $dir && -x $dir ]] && return 0
  owner="$(id -un):$(id -gn)"
  if [[ -e $dir && ! -d $dir ]]; then
    printf '%s is not a folder; move that file away, then ctl setup env creates the folder\n' "$dir"
    return 1
  fi
  if [[ -d $dir ]]; then
    printf '%s is not writable by %s; the deploy user must own it: sudo chown %s %s\n' "$dir" "$(id -un)" "$owner" "$dir"
    return 1
  fi
  while [[ ! -d $parent ]]; do
    [[ $parent == */* ]] || { parent=.; break; }   # a relative name with no folder left: the current one
    parent="${parent%/*}"; parent="${parent:-/}"
  done
  if [[ -w $parent && -x $parent ]]; then
    printf '%s does not exist; ctl setup env creates it\n' "$dir"
  else
    printf '%s does not exist, and %s is not writable by %s; the deploy user must own it: sudo chown %s %s\n' \
      "$dir" "$parent" "$(id -un)" "$owner" "$parent"
  fi
  return 1
}
