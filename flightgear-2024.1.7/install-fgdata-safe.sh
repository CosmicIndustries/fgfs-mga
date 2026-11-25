#!/usr/bin/env bash
# Verify and safely stage FlightGear FGData without deleting existing user data.
# Usage: install-fgdata-safe.sh ARCHIVE DESTINATION EXPECTED_SHA256
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: %s ARCHIVE DESTINATION EXPECTED_SHA256\n' "$0" >&2
  exit 64
fi

archive=$1
destination=$2
expected_sha256=$3

[[ -f "$archive" && ! -L "$archive" ]] || {
  printf 'ERROR: archive must be a regular non-symlink file: %s\n' "$archive" >&2
  exit 66
}
[[ "$expected_sha256" =~ ^[[:xdigit:]]{64}$ ]] || {
  printf 'ERROR: expected SHA-256 must be exactly 64 hexadecimal characters\n' "$expected_sha256" >&2
  exit 64
}

if [[ -e "$destination" || -L "$destination" ]]; then
  if [[ -f "$destination/version" && ! -L "$destination/version" ]]; then
    printf 'ERROR: FGData destination already contains a versioned data tree: %s\n' "$destination" >&2
  else
    printf 'ERROR: FGData destination already exists but is not a recognized versioned data tree; leaving it untouched: %s\n' "$destination" >&2
  fi
  exit 73
fi

if ! printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum --check --status; then
  printf 'ERROR: FGData archive SHA-256 mismatch: %s\n' "$archive" >&2
  exit 65
fi

parent=$(dirname -- "$destination")
base=$(basename -- "$destination")
mkdir -p -- "$parent"
stage=$(mktemp -d "$parent/.${base}.unpack.XXXXXXXX")
cleanup() {
  local rc=$?
  if [[ -n "${stage:-}" && -d "$stage" ]]; then rm -rf -- "$stage"; fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Permit members only under FlightGear's expected top-level data directory.
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  [[ "$member" != /* ]] || {
    printf 'ERROR: absolute archive member path refused: %s\n' "$member" >&2
    exit 74
  }
  normalized=$member
  while [[ "$normalized" == ./* ]]; do normalized=${normalized#./}; done
  case "$normalized" in
    fgdata_2024_1|fgdata_2024_1/*) ;;
    *) printf 'ERROR: unexpected FGData archive path refused: %s\n' "$member" >&2; exit 74 ;;
  esac
  IFS='/' read -r -a parts <<< "$normalized"
  for part in "${parts[@]}"; do
    [[ "$part" != .. ]] || {
      printf 'ERROR: parent traversal in archive member refused: %s\n' "$member" >&2
      exit 74
    }
  done
done < <(tar -tJf "$archive")

tar --extract --xz --file="$archive" --directory="$stage" \
  --no-same-owner --no-same-permissions

tree="$stage/fgdata_2024_1"
[[ -d "$tree" && ! -L "$tree" ]] || {
  printf 'ERROR: archive did not produce a real fgdata_2024_1 directory\n' >&2
  exit 75
}
[[ -f "$tree/version" && ! -L "$tree/version" ]] || {
  printf 'ERROR: extracted FGData tree has no regular version file\n' >&2
  exit 75
}

# Recheck before publication; -T prevents nesting and -n refuses replacement.
if [[ -e "$destination" || -L "$destination" ]]; then
  printf 'ERROR: destination appeared during extraction; refusing to replace it: %s\n' "$destination" >&2
  exit 73
fi
mv -Tn -- "$tree" "$destination"
if [[ -e "$tree" || ! -f "$destination/version" ]]; then
  printf 'ERROR: could not publish FGData directory without replacing existing data: %s\n' "$destination" >&2
  exit 73
fi

printf 'FGData archive verified and safely installed: %s (%s)\n' \
  "$destination" "$(cat "$destination/version")"
