#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PRESERVE="$SCRIPT_DIR/preserve-build-copy.sh"
ROOT=$(mktemp -d)
trap 'rm -rf -- "$ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

bash "$PRESERVE" "$ROOT/not-yet-created"
[[ ! -e "$ROOT/not-yet-created" ]] || fail 'missing path was created'
pass 'missing build copy is a no-op'

mkdir -p "$ROOT/aeonwave-fixed/source" "$ROOT/aeonwave-fixed/build"
printf 'manual patch note\n' > "$ROOT/aeonwave-fixed/NOTES.txt"
printf 'old source\n' > "$ROOT/aeonwave-fixed/source/file.c"
printf 'old build output\n' > "$ROOT/aeonwave-fixed/build/libaax.so"
bash "$PRESERVE" "$ROOT/aeonwave-fixed"
[[ ! -e "$ROOT/aeonwave-fixed" ]] || fail 'old build copy path was not moved'
mapfile -t backups < <(find "$ROOT" -maxdepth 1 -type d -name 'aeonwave-fixed.backup.*')
[[ "${#backups[@]}" -eq 1 ]] || fail "expected one backup, found ${#backups[@]}"
backup="${backups[0]}/original"
[[ "$(cat "$backup/NOTES.txt")" == 'manual patch note' ]] || fail 'manual patch note was lost'
[[ "$(cat "$backup/source/file.c")" == 'old source' ]] || fail 'old source file was lost'
[[ "$(cat "$backup/build/libaax.so")" == 'old build output' ]] || fail 'old build artifact was lost'
pass 'existing generated copy and nested build outputs are preserved intact'

mkdir "$ROOT/aeonwave-fixed"
printf 'new build generation\n' > "$ROOT/aeonwave-fixed/generation"
bash "$PRESERVE" "$ROOT/aeonwave-fixed"
mapfile -t backups < <(find "$ROOT" -maxdepth 1 -type d -name 'aeonwave-fixed.backup.*')
[[ "${#backups[@]}" -eq 2 ]] || fail 'repeated rebuild did not produce a second unique backup'
pass 'successive rebuilds get distinct backup directories'

mkdir "$ROOT/source-target"
ln -s "$ROOT/source-target" "$ROOT/aeonwave-fixed-link"
if bash "$PRESERVE" "$ROOT/aeonwave-fixed-link"; then
  fail 'symlinked build copy was accepted'
fi
[[ -L "$ROOT/aeonwave-fixed-link" ]] || fail 'build-copy symlink was altered'
pass 'symlinked build-copy path is refused without changes'

printf 'not a directory\n' > "$ROOT/aeonwave-fixed-file"
if bash "$PRESERVE" "$ROOT/aeonwave-fixed-file"; then
  fail 'regular file was accepted as build-copy directory'
fi
[[ "$(cat "$ROOT/aeonwave-fixed-file")" == 'not a directory' ]] || fail 'regular file was altered'
pass 'non-directory build-copy path is refused without changes'

printf 'All AeonWave build-copy preservation tests passed.\n'
