#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERIFY="$SCRIPT_DIR/../verify-file-sha256.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'hello' > "$TMP/good.bin"
bash "$VERIFY" 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 "$TMP/good.bin"

if bash "$VERIFY" 0000000000000000000000000000000000000000000000000000000000000000 "$TMP/good.bin"; then
  printf 'FAIL: mismatching digest was accepted\n' >&2
  exit 1
fi

if bash "$VERIFY" not-a-digest "$TMP/good.bin"; then
  printf 'FAIL: malformed digest was accepted\n' >&2
  exit 1
else
  rc=$?
  [[ $rc -eq 64 ]] || { printf 'FAIL: malformed digest returned %s\n' "$rc" >&2; exit 1; }
fi

if bash "$VERIFY" 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 "$TMP/missing.bin"; then
  printf 'FAIL: missing file was accepted\n' >&2
  exit 1
else
  rc=$?
  [[ $rc -eq 66 ]] || { printf 'FAIL: missing file returned %s\n' "$rc" >&2; exit 1; }
fi

ln -s "$TMP/good.bin" "$TMP/link.bin"
if bash "$VERIFY" 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 "$TMP/link.bin"; then
  printf 'FAIL: symlink was accepted\n' >&2
  exit 1
else
  rc=$?
  [[ $rc -eq 66 ]] || { printf 'FAIL: symlink returned %s\n' "$rc" >&2; exit 1; }
fi

printf 'All FGData checksum verification tests passed.\n'
