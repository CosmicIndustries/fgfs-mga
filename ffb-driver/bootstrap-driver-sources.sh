#!/usr/bin/env bash
# Materialize the exact upstream sources required by the local Saitek driver patches.
# Safe to rerun: existing checkouts are accepted only when pinned and clean.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SOURCES.lock
source "$SCRIPT_DIR/SOURCES.lock"

CHECK_ONLY=0
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  -h|--help)
    echo "Usage: $0 [--check]"
    echo "  no option  Fetch the pinned source revisions when absent."
    echo "  --check    Verify both pinned, clean source checkouts without network access."
    exit 0
    ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

die() { echo "ERROR: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required to fetch the pinned driver sources."

verify_checkout() {
  local dir="$1" expected="$2" label="$3"
  [[ -d "$dir/.git" ]] || die "$label source missing or not a Git checkout: $dir"
  local actual
  actual="$(git -C "$dir" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] || die "$label source is at $actual; expected $expected. Move $dir aside and rerun bootstrap."
  local dirty
  dirty="$(git -C "$dir" status --porcelain --untracked-files=all)"
  [[ -z "$dirty" ]] || die "$label source has local modifications: $dir. Preserve or remove them, then rerun bootstrap."
}

fetch_checkout() {
  local dir="$1" url="$2" revision="$3" label="$4"
  if [[ -e "$dir" ]]; then
    verify_checkout "$dir" "$revision" "$label"
    printf 'OK  %s %s\n' "$label" "$revision"
    return
  fi

  local tmp
  tmp="$(mktemp -d "${dir}.bootstrap.XXXXXX")"
  if ! git -C "$tmp" init -q ||
     ! git -C "$tmp" remote add origin "$url" ||
     ! git -C "$tmp" fetch --quiet --depth=1 origin "$revision" ||
     ! git -C "$tmp" checkout --quiet --detach FETCH_HEAD; then
    rm -rf -- "$tmp"
    die "could not fetch $label at $revision from $url"
  fi

  local actual
  actual="$(git -C "$tmp" rev-parse HEAD)"
  if [[ "$actual" != "$revision" ]]; then
    rm -rf -- "$tmp"
    die "$label resolved to $actual, not the pinned revision $revision"
  fi

  mv -- "$tmp" "$dir"
  verify_checkout "$dir" "$revision" "$label"
  printf 'FETCHED  %s %s\n' "$label" "$revision"
}

if (( CHECK_ONLY )); then
  verify_checkout "$SCRIPT_DIR/universal-pidff" "$UNIVERSAL_PIDFF_COMMIT" "universal-pidff"
  verify_checkout "$SCRIPT_DIR/cyborg-hid-pidff" "$CYBORG_PIDFF_COMMIT" "cyborg-hid-pidff"
else
  fetch_checkout "$SCRIPT_DIR/universal-pidff" "$UNIVERSAL_PIDFF_URL" "$UNIVERSAL_PIDFF_COMMIT" "universal-pidff"
  fetch_checkout "$SCRIPT_DIR/cyborg-hid-pidff" "$CYBORG_PIDFF_URL" "$CYBORG_PIDFF_COMMIT" "cyborg-hid-pidff"
fi

[[ -f "$SCRIPT_DIR/universal-pidff/Kbuild" ]] || die "universal-pidff Kbuild file is missing."
[[ -f "$SCRIPT_DIR/universal-pidff/hid-universal-pidff.c" ]] || die "universal-pidff driver source is missing."
[[ -f "$SCRIPT_DIR/cyborg-hid-pidff/hid-pidff.c" ]] || die "Cyborg-specific PIDFF source is missing."
echo "Pinned force-feedback sources are ready."
