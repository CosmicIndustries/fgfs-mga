#!/usr/bin/env bash
# Safely prepare side-by-side FlightGear/SimGear 2024.1.7 worktrees.
# Existing source trees and existing target worktrees are never overwritten.
set -Eeuo pipefail
umask 077

BUILDS_DIR=${BUILDS_DIR:-"$HOME/builds"}
WORK_DIR=${PREP_WORK_DIR:-"$BUILDS_DIR/fg-2024.1.7"}
TAG=${FG_TAG:-2024.1.7}
FETCH_RETRIES=${FETCH_RETRIES:-5}
FETCH_RETRY_DELAY=${FETCH_RETRY_DELAY:-10}

mkdir -p "$WORK_DIR/patches"
LOG_FILE="$WORK_DIR/prep.log"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'rc=$?; printf "ERROR: command failed at line %s (exit %s)\n" "$LINENO" "$rc" >&2; exit "$rc"' ERR

die() {
  local code=$1
  shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "$code"
}

upstream_url() {
  case "$1" in
    simgear) printf '%s\n' "${SIMGEAR_UPSTREAM_URL:-https://gitlab.com/flightgear/simgear.git}" ;;
    flightgear) printf '%s\n' "${FLIGHTGEAR_UPSTREAM_URL:-https://gitlab.com/flightgear/flightgear.git}" ;;
    *) die 64 "unsupported project: $1" ;;
  esac
}

# Preserve the existing GitHub remote before repointing origin. If another
# non-official origin exists, leave it alone and add a dedicated upstream remote.
configure_remote() {
  local repo_dir=$1 project=$2 url=$3 origin_url mirror_url upstream_url_value
  if git -C "$repo_dir" remote get-url origin >/dev/null 2>&1; then
    origin_url=$(git -C "$repo_dir" remote get-url origin)
    if [[ "$origin_url" == "$url" ]]; then
      printf 'origin\n'
      return 0
    fi

    case "$origin_url" in
      *github.com*)
        if git -C "$repo_dir" remote get-url github-mirror >/dev/null 2>&1; then
          mirror_url=$(git -C "$repo_dir" remote get-url github-mirror)
          [[ "$mirror_url" == "$origin_url" ]] || die 5 "$project: github-mirror already exists with a different URL; refusing to overwrite it"
          git -C "$repo_dir" remote set-url origin "$url"
        else
          git -C "$repo_dir" remote rename origin github-mirror
          git -C "$repo_dir" remote add origin "$url"
        fi
        printf 'origin\n'
        return 0
        ;;
    esac
  fi

  if git -C "$repo_dir" remote get-url mga-upstream >/dev/null 2>&1; then
    upstream_url_value=$(git -C "$repo_dir" remote get-url mga-upstream)
    [[ "$upstream_url_value" == "$url" ]] || die 5 "$project: mga-upstream already exists with a different URL; refusing to overwrite it"
  else
    git -C "$repo_dir" remote add mga-upstream "$url"
  fi
  printf 'mga-upstream\n'
}

backup_source_tree() {
  local project=$1 source_dir=$2 snapshot_dir=$3
  local project_snapshot="$snapshot_dir/$project"
  mkdir -p "$project_snapshot"
  git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 2 "$source_dir is not a Git working tree"

  # Comparing the worktree to HEAD captures both staged and unstaged edits.
  git -C "$source_dir" diff HEAD --binary --full-index > "$project_snapshot/local.patch"
  git -C "$source_dir" status --porcelain=v1 -z > "$project_snapshot/status.porcelain0"
  git -C "$source_dir" rev-parse HEAD > "$project_snapshot/source-head.txt"

  # NUL-delimited path lists and GNU tar's --null preserve whitespace, newlines,
  # leading dashes, and other legal filename characters without word splitting.
  git -C "$source_dir" ls-files --others --exclude-standard -z > "$project_snapshot/untracked.list0"
  if [[ -s "$project_snapshot/untracked.list0" ]]; then
    tar --null --verbatim-files-from -czf "$project_snapshot/untracked.tar.gz" \
      -C "$source_dir" --files-from="$project_snapshot/untracked.list0"
    local count
    count=$(tr -cd '\0' < "$project_snapshot/untracked.list0" | wc -c)
    printf 'Saved %s untracked path(s) for %s\n' "$count" "$project"
  else
    printf 'No untracked files for %s\n' "$project"
  fi

  if [[ -s "$project_snapshot/local.patch" ]]; then
    printf 'Saved tracked changes for %s\n' "$project"
  else
    printf 'No tracked changes for %s\n' "$project"
  fi
}

# Reject extraction when any destination file already exists or an ancestor is
# a symlink/non-directory. This makes restoration non-destructive and prevents
# a symlink in the target worktree from redirecting archive writes elsewhere.
check_restore_collisions() {
  local target_dir=$1 list_file=$2 relative remaining component prefix candidate
  while IFS= read -r -d '' relative; do
    [[ -n "$relative" ]] || die 6 'empty path found in untracked-file manifest'
    [[ "$relative" != /* ]] || die 6 "absolute path in untracked-file manifest: $relative"

    remaining=$relative
    prefix=''
    while [[ "$remaining" == */* ]]; do
      component=${remaining%%/*}
      [[ "$component" != '' && "$component" != '.' && "$component" != '..' ]] || die 6 "unsafe path component in untracked-file manifest: $relative"
      prefix=${prefix:+$prefix/}$component
      candidate="$target_dir/$prefix"
      if [[ -L "$candidate" ]] || { [[ -e "$candidate" ]] && [[ ! -d "$candidate" ]]; }; then
        die 6 "cannot restore '$relative': destination ancestor is not a real directory: $candidate"
      fi
      remaining=${remaining#*/}
    done

    [[ "$remaining" != '' && "$remaining" != '.' && "$remaining" != '..' ]] || die 6 "unsafe path in untracked-file manifest: $relative"
    candidate="$target_dir/$relative"
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      die 6 "cannot restore '$relative': destination already exists in $target_dir"
    fi
  done < "$list_file"
}

prepare_worktree() {
  local project=$1 source_dir=$2 snapshot_dir=$3
  local target_dir="$BUILDS_DIR/$project-$TAG"
  local branch="mga-$TAG"
  local url remote attempt fetched=0 tag_commit patch_file list_file archive_file

  url=$(upstream_url "$project")
  remote=$(configure_remote "$source_dir" "$project" "$url")
  printf '%s remotes:\n' "$project"
  git -C "$source_dir" remote -v

  for ((attempt = 1; attempt <= FETCH_RETRIES; attempt++)); do
    if git -C "$source_dir" fetch --no-tags "$remote" \
      "refs/tags/$TAG:refs/tags/$TAG" \
      "refs/heads/release/2024.1:refs/remotes/$remote/release/2024.1"; then
      fetched=1
      break
    fi
    printf 'Fetch attempt %s/%s failed for %s\n' "$attempt" "$FETCH_RETRIES" "$project" >&2
    if ((attempt < FETCH_RETRIES)); then sleep "$FETCH_RETRY_DELAY"; fi
  done
  ((fetched == 1)) || die 3 "fetch failed for $project from $remote"

  tag_commit=$(git -C "$source_dir" rev-parse --verify "$TAG^{commit}") || die 3 "$project: tag $TAG does not resolve to a commit"
  printf '%s tag %s -> %s\n' "$project" "$TAG" "$tag_commit"

  if [[ -L "$target_dir" ]]; then
    die 4 "$target_dir is a symlink; refusing to use an ambiguous worktree path"
  fi
  if [[ -e "$target_dir" ]]; then
    if git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local current_branch source_common target_common
      current_branch=$(git -C "$target_dir" symbolic-ref --quiet --short HEAD || true)
      [[ "$current_branch" == "$branch" ]] || die 4 "$target_dir already exists as a worktree on '$current_branch'; leaving it untouched"
      source_common=$(git -C "$source_dir" rev-parse --path-format=absolute --git-common-dir)
      target_common=$(git -C "$target_dir" rev-parse --path-format=absolute --git-common-dir)
      [[ "$source_common" == "$target_common" ]] || die 4 "$target_dir is not linked to the source repository; leaving it untouched"
      printf 'Existing %s worktree found on branch %s; leaving it untouched (no patch reapplication).\n' "$project" "$branch"
      return 0
    fi
    die 4 "$target_dir already exists and is not a Git worktree; refusing to overwrite it"
  fi

  if git -C "$source_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    local existing_branch_commit
    existing_branch_commit=$(git -C "$source_dir" rev-parse "refs/heads/$branch")
    [[ "$existing_branch_commit" == "$tag_commit" ]] || die 4 "$project branch $branch exists at $existing_branch_commit, not tag commit $tag_commit; refusing to reuse it"
    if git -C "$source_dir" worktree list --porcelain | grep -F -x "branch refs/heads/$branch" >/dev/null; then
      die 4 "$project branch $branch is already checked out in another worktree; leaving it untouched"
    fi
    printf 'Recovering previously-created branch %s at the expected tag commit.\n' "$branch"
    git -C "$source_dir" worktree add "$target_dir" "$branch"
  else
    git -C "$source_dir" worktree add -b "$branch" "$target_dir" "$TAG"
  fi

  patch_file="$snapshot_dir/$project/local.patch"
  list_file="$snapshot_dir/$project/untracked.list0"
  archive_file="$snapshot_dir/$project/untracked.tar.gz"

  if [[ -s "$patch_file" ]]; then
    if ! git -C "$target_dir" apply --3way --index "$patch_file"; then
      printf 'PATCH CONFLICT: %s. The worktree is retained for inspection; backup remains at %s\n' "$project" "$snapshot_dir" >&2
      git -C "$target_dir" status --short >&2 || true
      return 7
    fi
    printf 'Tracked changes applied to %s\n' "$project"
  fi

  if [[ -f "$archive_file" ]]; then
    check_restore_collisions "$target_dir" "$list_file"
    tar --null --verbatim-files-from -xzf "$archive_file" -C "$target_dir" \
      --no-same-owner --no-same-permissions
    printf 'Restored %s untracked path(s) to %s\n' \
      "$(tr -cd '\0' < "$list_file" | wc -c)" "$project"
  fi

  printf 'Prepared %s worktree: %s\n' "$project" "$target_dir"
}

[[ "$FETCH_RETRIES" =~ ^[1-9][0-9]*$ ]] || die 64 'FETCH_RETRIES must be a positive integer'
[[ "$FETCH_RETRY_DELAY" =~ ^[0-9]+$ ]] || die 64 'FETCH_RETRY_DELAY must be a nonnegative integer'
[[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]] || die 64 'FG_TAG contains unsupported characters'

for project in simgear flightgear; do
  source_dir="$BUILDS_DIR/$project"
  [[ -d "$source_dir" ]] || die 2 "required source tree not found: $source_dir"
done

snapshot_dir=$(mktemp -d "$WORK_DIR/patches/prep-$(date +%Y%m%d-%H%M%S)-XXXXXX")
printf 'Backup snapshot: %s\n' "$snapshot_dir"

# Back up both repositories before mutating remotes or creating either worktree.
for project in simgear flightgear; do
  backup_source_tree "$project" "$BUILDS_DIR/$project" "$snapshot_dir"
done

for project in simgear flightgear; do
  prepare_worktree "$project" "$BUILDS_DIR/$project" "$snapshot_dir"
done

printf 'DONE %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Backups retained at: %s\n' "$snapshot_dir"
