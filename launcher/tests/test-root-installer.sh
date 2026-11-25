#!/usr/bin/env bash
# Regression test: the root installer must propagate a failed nested launcher install.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

REPO="$TMP/repo"
HOME_DIR="$TMP/home"
mkdir -p "$REPO/launcher" "$HOME_DIR"
cp "$ROOT/install.sh" "$REPO/install.sh"

cat > "$REPO/launcher/install-fgfs-mga.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub launcher installer failed"
exit 42
STUB

set +e
HOME="$HOME_DIR" bash "$REPO/install.sh" >"$TMP/stdout" 2>"$TMP/stderr"
status=$?
set -e

[[ "$status" -eq 42 ]] || {
  echo "FAIL: expected nested installer status 42, got $status" >&2
  cat "$TMP/stdout" >&2
  cat "$TMP/stderr" >&2
  exit 1
}

grep -q "ERROR: launcher installation failed (exit 42)" "$TMP/stderr" || {
  echo "FAIL: missing propagated launcher-install error message" >&2
  cat "$TMP/stderr" >&2
  exit 1
}

[[ ! -e "$HOME_DIR/.local/share/fgfs-mga/tools" ]] || {
  echo "FAIL: root installer continued after nested launcher failure" >&2
  exit 1
}

echo "PASS  root installer propagates nested launcher failure and stops"
