#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$SCRIPT_DIR/../install-fgdata-safe.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

make_archive() {
  local root=$1 version=${2:-2024.1.7}
  mkdir -p "$root/input/fgdata_2024_1"
  printf '%s\n' "$version" > "$root/input/fgdata_2024_1/version"
  printf 'fixture scenery\n' > "$root/input/fgdata_2024_1/README.txt"
  tar -cJf "$root/fgdata.txz" -C "$root/input" fgdata_2024_1
  sha256sum "$root/fgdata.txz" | awk '{print $1}' > "$root/sha256"
}

GOOD="$ROOT/good"
mkdir -p "$GOOD/home/.fgfs/.fgdata-unpack"
printf 'pre-existing staging data\n' > "$GOOD/home/.fgfs/.fgdata-unpack/keep.txt"
make_archive "$GOOD"
digest=$(cat "$GOOD/sha256")
bash "$INSTALLER" "$GOOD/fgdata.txz" "$GOOD/home/.fgfs/fgdata_2024_1" "$digest"
[[ "$(cat "$GOOD/home/.fgfs/fgdata_2024_1/version")" == '2024.1.7' ]] || fail 'version file not installed'
[[ "$(cat "$GOOD/home/.fgfs/.fgdata-unpack/keep.txt")" == 'pre-existing staging data' ]] || fail 'legacy staging directory was altered'
compgen -G "$GOOD/home/.fgfs/.fgdata_2024_1.unpack.*" >/dev/null && fail 'temporary staging directory was not cleaned'
pass 'verified archive installs and pre-existing staging data is untouched'

BAD="$ROOT/bad"
mkdir -p "$BAD"
make_archive "$BAD"
if bash "$INSTALLER" "$BAD/fgdata.txz" "$BAD/target" "$(printf '0%.0s' {1..64})"; then
  fail 'checksum mismatch was accepted'
else
  rc=$?
  [[ $rc -eq 65 ]] || fail "checksum mismatch returned $rc instead of 65"
fi
[[ ! -e "$BAD/target" ]] || fail 'target was created after a checksum mismatch'
pass 'checksum mismatch is rejected before extraction'

EXISTING="$ROOT/existing"
make_archive "$EXISTING"
mkdir -p "$EXISTING/target"
printf 'user data\n' > "$EXISTING/target/keep.txt"
if bash "$INSTALLER" "$EXISTING/fgdata.txz" "$EXISTING/target" "$(cat "$EXISTING/sha256")"; then
  fail 'unrecognized existing target was accepted'
else
  rc=$?
  [[ $rc -eq 73 ]] || fail "existing target returned $rc instead of 73"
fi
[[ "$(cat "$EXISTING/target/keep.txt")" == 'user data' ]] || fail 'existing target contents changed'
pass 'existing unrecognized destination is preserved'

RECOGNIZED="$ROOT/recognized"
make_archive "$RECOGNIZED"
mkdir -p "$RECOGNIZED/target"
printf 'older-version\n' > "$RECOGNIZED/target/version"
if bash "$INSTALLER" "$RECOGNIZED/fgdata.txz" "$RECOGNIZED/target" "$(cat "$RECOGNIZED/sha256")"; then
  fail 'recognized existing target was accepted for replacement'
else
  rc=$?
  [[ $rc -eq 73 ]] || fail "recognized target returned $rc instead of 73"
fi
[[ "$(cat "$RECOGNIZED/target/version")" == 'older-version' ]] || fail 'recognized target was overwritten'
pass 'existing versioned FGData tree is never replaced'

UNEXPECTED="$ROOT/unexpected"
mkdir -p "$UNEXPECTED/input/wrong-root"
printf 'not FGData\n' > "$UNEXPECTED/input/wrong-root/version"
tar -cJf "$UNEXPECTED/fgdata.txz" -C "$UNEXPECTED/input" wrong-root
digest=$(sha256sum "$UNEXPECTED/fgdata.txz" | awk '{print $1}')
if bash "$INSTALLER" "$UNEXPECTED/fgdata.txz" "$UNEXPECTED/target" "$digest"; then
  fail 'unexpected archive root was accepted'
else
  rc=$?
  [[ $rc -eq 74 ]] || fail "unexpected archive returned $rc instead of 74"
fi
[[ ! -e "$UNEXPECTED/target" ]] || fail 'unexpected archive created target'
pass 'unexpected archive layout is rejected'

printf 'All safe FGData extraction tests passed.\n'
