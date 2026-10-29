#!/usr/bin/env bash
# scripts/common/_images.sh — the images ctl builds: TAG, and the deploy steps around it (the rollback
# guard, the deploy record, image retention). _lib.sh sources it; the [ADAPT] knobs MIGRATION_PATHS and
# IMAGE_KEEP stay in _lib.sh with the others.

# ── image tag ──
# TAG names every image ctl builds and starts (image: ${REGISTRY}/<app>:${TAG}). require_env runs
# image_tag_resolve, which turns the setting into that name and exports it. Compose takes the
# shell's value over the --env-file's, so every compose call of the run uses the same tag.
#   dev     local builds: one name, which each build replaces (a worktree slot gets dev-slot-<n>)
#   auto    the checkout's commit (git rev-parse --short=8 HEAD), so each deploy keeps its own images
#   none    no version: the images are called latest, and each build replaces them
#   other   used as written: a commit or a git tag, which a deploy pins (see deploys below)
# CTL_TAG_SETTING keeps the value as written, so a nested ctl resolves auto again at its own commit,
# and the plan can print "auto → <commit>". An unset or empty TAG is left alone: a repo whose compose
# files name no tag needs none. An invalid tag, or auto outside a git checkout, is an error, never a guess.
image_tag_resolve() {
  [[ -v CTL_TAG_SETTING ]] || export CTL_TAG_SETTING="${TAG-}"
  local setting="$CTL_TAG_SETTING" commit
  case "$setting" in
    '') return 0 ;;
    auto)
      commit=$(git -C "$CTL_ROOT" rev-parse --short=8 HEAD 2>/dev/null) || {
        err "TAG=auto names the images after this checkout's commit, but $CTL_ROOT has no git commit; commit, or set TAG=dev or a version"
        return 1; }
      export TAG="$commit" ;;
    none) export TAG=latest ;;
    *)
      [[ $setting =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || {
        err "TAG=$setting is not a Docker image tag; use dev, auto, none, a commit or a version"
        return 1; }
      export TAG="$setting" ;;
  esac
}
# image_tag_buildable — 0 when a build may use the resolved tag. With TAG=auto the images carry the
# commit's name, so a build from a checkout with uncommitted changes (tracked, or untracked and not
# ignored) is refused: the images would not match the commit they are named after.
image_tag_buildable() {
  [[ ${CTL_TAG_SETTING-} == auto ]] || return 0
  local changes
  changes=$(git -C "$CTL_ROOT" status --porcelain 2>/dev/null) || { err "TAG=auto: git cannot read the state of $CTL_ROOT"; return 1; }
  [[ -z $changes ]] && return 0
  err "TAG=auto names the images after commit $TAG, but the checkout has uncommitted changes, so the images would not match it; commit them, or set TAG=dev for a local build"
  return 1
}
# image_tag_label — the tag as the plan prints it: "dev", or "auto → f5744bff" when ctl resolved it.
image_tag_label() {
  if [[ -n ${CTL_TAG_SETTING-} && ${CTL_TAG_SETTING} != "${TAG-}" ]]; then printf '%s → %s' "$CTL_TAG_SETTING" "${TAG-}"
  else printf '%s' "${TAG:-not set}"; fi
}

# ── deploys: the rollback guard and image retention ──
# A deploy is a ctl up with TAG=auto or a pinned tag. dev, dev-<name> (a slot's dev-slot-<n>), none and
# an unset TAG are local builds: no guard, no record, no retention. Each deployment keeps one record,
# DATA_DIR/deployed-commit: the full commit of the last deploy that reached activation. It is written
# before activation, not after readiness, because the schema one-shots may migrate the data even when
# a later service fails; and it sits beside the data it describes, outside git. A deploy whose commit
# is older than the record, or on another line of history, is a rollback. ROLLBACK=off refuses every
# rollback. ROLLBACK=on allows one only when no file under MIGRATION_PATHS differs between the two commits.
deploy_record_file() { printf '%s/deployed-commit\n' "$DATA_DIR"; }

# rollback_setting — print ROLLBACK as ctl reads it: off (also unset or empty) or on. Any other value is an error.
rollback_setting() {
  case "${ROLLBACK:-off}" in
    off|on) printf '%s\n' "${ROLLBACK:-off}" ;;
    *) err "ROLLBACK=$ROLLBACK — use off (every rollback refused) or on (a rollback that crosses no migration allowed)"; return 1 ;;
  esac
}

# deploy_guard — refuse a rollback before anything starts, and print the full commit this run deploys,
# or nothing for a local build. Run it after image_tag_resolve and resolve_storage_dirs. Whatever ctl
# cannot compare (a tag that names no commit, a record this checkout lacks) is refused.
deploy_guard() {
  local setting="${CTL_TAG_SETTING-}" rollback target record file changed kept status=0
  rollback=$(rollback_setting) || return 1
  case "$setting" in
    ''|dev|dev-*|none) return 0 ;;
    auto) target=$(git -C "$CTL_ROOT" rev-parse --verify --quiet 'HEAD^{commit}') || target='' ;;
    *) target=$(git -C "$CTL_ROOT" rev-parse --verify --quiet "$setting^{commit}") || target='' ;;
  esac
  [[ -n $target ]] || {
    err "TAG=$setting names no commit in $CTL_ROOT, so ctl cannot tell whether this deploy is a rollback; pin a commit or a git tag this checkout has, set TAG=auto, or TAG=dev for a local build"
    return 1; }
  file=$(deploy_record_file)
  if [[ -e $file ]]; then
    record=$(<"$file") || { err "ctl cannot read the deploy record $file"; return 1; }
    [[ $record =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || {
      err "the deploy record $file holds no commit, so ctl cannot tell whether this deploy is a rollback; restore it, or delete it only if no deploy ever ran against this data"
      return 1; }
    git -C "$CTL_ROOT" rev-parse --verify --quiet "$record^{commit}" >/dev/null || {
      err "the deploy record $file names commit $record, which this checkout does not have, so ctl cannot tell whether this deploy is a rollback; fetch it (git fetch), or deploy from a checkout that has it"
      return 1; }
    [[ $target == "$record" ]] || git -C "$CTL_ROOT" merge-base --is-ancestor "$record" "$target" || status=$?
    case "$status" in
      0) ;;
      1)
        if [[ $rollback == off ]]; then
          err "TAG=$setting is a rollback: ${target:0:8} is not ahead of the last deploy ${record:0:8} (recorded in $file). ROLLBACK=off refuses every rollback, because the data may hold the newer deploy's migrations; deploy forward with a new commit"
          return 1
        fi
        kept="MIGRATION_PATHS lists no schema files"
        if (( ${#MIGRATION_PATHS[@]} )); then
          changed=$(git -C "$CTL_ROOT" diff --name-only "$target" "$record" -- "${MIGRATION_PATHS[@]}") || {
            err "git cannot compare ${target:0:8} with the last deploy ${record:0:8}"; return 1; }
          [[ -z $changed ]] || {
            err "TAG=$setting is a rollback from ${record:0:8} to ${target:0:8} across a migration, which ROLLBACK=on refuses too; these files differ: $(join_sp <<< "$changed")"
            return 1; }
          kept="no file under ${MIGRATION_PATHS[*]} differs"
        fi
        warn "TAG=$setting rolls back from ${record:0:8} to ${target:0:8}: ROLLBACK=on, and $kept" ;;
      *) err "git cannot compare ${target:0:8} with the last deploy ${record:0:8}"; return 1 ;;
    esac
  fi
  printf '%s\n' "$target"
}

# deploy_record <commit> — write the deploy record. A record ctl cannot write stops the deploy, because
# the next ctl up could not tell a rollback. The new file replaces the old one in a single rename.
deploy_record() {
  local file staged=''
  file=$(deploy_record_file)
  if mkdir -p -- "${file%/*}" && staged=$(mktemp "$file.XXXXXX") && printf '%s\n' "$1" > "$staged" && mv -f -- "$staged" "$file"; then
    return 0
  fi
  [[ -z $staged ]] || rm -f -- "$staged"
  err "ctl cannot write the deploy record $file, so the next ctl up could not tell a rollback; make ${file%/*} writable for $(id -un)"
  return 1
}

# image_retain <compose model JSON> — after a deploy is ready, keep the IMAGE_KEEP newest tags, by
# creation time, of each image ctl builds (the image: of every service with build:), and remove the
# rest. The tag the deploy runs and every tag a container uses, running or stopped, stay. A repository
# no built service names is never listed. Retention never fails the deploy: a docker error is a warning.
image_retain() {
  local model="$1" image repo listing ref used n
  local -a images=() refs=() newest=() removed=()
  [[ $IMAGE_KEEP =~ ^[1-9][0-9]*$ ]] || { warn "IMAGE_KEEP=$IMAGE_KEEP is not a positive count; no image removed"; return 0; }
  listing=$(jq -r '[.services[] | select(.build != null) | .image // empty] | unique[]' <<< "$model") || {
    warn "image retention: jq cannot read the compose model; no image removed"; return 0; }
  mapfile -t images <<< "$listing"
  for image in "${images[@]}"; do
    [[ -n $image && $image != *@* ]] || continue      # a digest names one image, not a repository's tags
    repo="$image"; [[ ${image##*/} != *:* ]] || repo="${image%:*}"
    listing=$(docker image ls --format '{{.Repository}}:{{.Tag}}' "$repo") || { warn "docker cannot list $repo; none of its images removed"; continue; }
    mapfile -t refs < <(grep -v ':<none>$' <<< "$listing" | grep .)
    (( ${#refs[@]} > IMAGE_KEEP )) || continue
    listing=$(docker image inspect "${refs[@]}") || { warn "docker cannot read the images of $repo; none removed"; continue; }
    # inspect answers in argument order; .Created is UTC with up to 9 fraction digits, padded here so it sorts as text
    listing=$(jq -r --args '
      def created: .Created | sub("Z$"; "") | split(".") | .[0] + "." + ((.[1] // "") + "000000000")[0:9];
      [$ARGS.positional, .] | transpose | sort_by(.[1] | created) | reverse | .[][0]' "${refs[@]}" <<< "$listing") || {
      warn "image retention: jq cannot sort the images of $repo; none removed"; continue; }
    mapfile -t newest <<< "$listing"
    n=0
    for ref in "${newest[@]}"; do
      (( ++n > IMAGE_KEEP )) && [[ $ref != "$image" ]] || continue
      used=$(docker ps --all --quiet --filter "ancestor=$ref") || { warn "docker cannot tell whether a container uses $ref; kept"; continue; }
      [[ -z $used ]] || { say "  kept $ref: a container uses it"; continue; }
      if docker image rm "$ref" >/dev/null; then removed+=("$ref"); else warn "docker could not remove $ref; kept"; fi
    done
  done
  if (( ${#removed[@]} )); then ok "image retention: removed ${removed[*]} (each image ctl builds keeps its $IMAGE_KEEP newest tags)"
  else say "image retention: nothing to remove (each image ctl builds keeps its $IMAGE_KEEP newest tags)"; fi
}
