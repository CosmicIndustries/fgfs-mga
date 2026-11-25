#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PRESERVE="$SCRIPT_DIR/preserve-generated-dir.sh"
ROOT=$(mktemp -d)
trap 'rm -rf -- "$ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Missing path remains a no-op.
bash "$PRESERVE" "$ROOT/missing"
[[ ! -e "$ROOT/missing" ]] || fail 'missing directory was created'
pass 'missing generated directory is a no-op'

# Existing generated output is moved intact, not deleted.
mkdir -p "$ROOT/evo-universal/subdir"
printf 'manual inspection note\n' > "$ROOT/evo-universal/NOTES.txt"
printf 'old module bytes\n' > "$ROOT/evo-universal/hid_universal_pidff.ko"
printf 'nested contents\n' > "$ROOT/evo-universal/subdir/keep.txt"
bash "$PRESERVE" "$ROOT/evo-universal"
[[ ! -e "$ROOT/evo-universal" ]] || fail 'original directory path still exists after preservation'
mapfile -t backups < <(find "$ROOT" -maxdepth 1 -type d -name 'evo-universal.backup.*')
[[ "${#backups[@]}" -eq 1 ]] || fail "expected one backup, got ${#backups[@]}"
backup="${backups[0]}/original"
[[ "$(cat "$backup/NOTES.txt")" == 'manual inspection note' ]] || fail 'manual note was not preserved'
[[ "$(cat "$backup/hid_universal_pidff.ko")" == 'old module bytes' ]] || fail 'old module was not preserved'
[[ "$(cat "$backup/subdir/keep.txt")" == 'nested contents' ]] || fail 'nested file was not preserved'
pass 'existing generated output and local notes are moved intact to a unique backup'

# Repeated generations use distinct backup names and do not collide.
mkdir "$ROOT/evo-universal"
printf 'second generation\n' > "$ROOT/evo-universal/generation.txt"
bash "$PRESERVE" "$ROOT/evo-universal"
mapfile -t backups < <(find "$ROOT" -maxdepth 1 -type d -name 'evo-universal.backup.*')
[[ "${#backups[@]}" -eq 2 ]] || fail "expected two distinct backups, got ${#backups[@]}"
pass 'repeated rebuilds receive unique backup directories'

# A symlink is refused and remains exactly as it was.
mkdir "$ROOT/actual"
ln -s "$ROOT/actual" "$ROOT/evo-cyborg-v2"
if bash "$PRESERVE" "$ROOT/evo-cyborg-v2"; then
  fail 'directory symlink was accepted'
fi
[[ -L "$ROOT/evo-cyborg-v2" ]] || fail 'symlink was removed or altered'
[[ "$(readlink "$ROOT/evo-cyborg-v2")" == "$ROOT/actual" ]] || fail 'symlink target changed'
pass 'symlinked generated path is refused without altering the link'

# A regular file is also refused and preserved.
printf 'not a directory\n' > "$ROOT/evo-cyborg"
if bash "$PRESERVE" "$ROOT/evo-cyborg"; then
  fail 'regular file was accepted as a generated directory'
fi
[[ "$(cat "$ROOT/evo-cyborg")" == 'not a directory' ]] || fail 'regular file was changed'
pass 'non-directory generated path is refused without alteration'

printf 'All generated FFB directory preservation tests passed.\n'
