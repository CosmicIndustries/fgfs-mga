#!/usr/bin/env bash
# Build two Saitek Cyborg Evo Force (06a3:ffb5) module variants for the running kernel.
# universal-pidff supplies the device-managed implementation; the Cyborg variant uses
# the older device-specific driver-managed implementation behind the same HID wrapper.
# Source checkouts are fetched at immutable commits by bootstrap-driver-sources.sh.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG="$SCRIPT_DIR/build-evo-ffb.log"
exec > >(tee "$LOG") 2>&1

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD="/lib/modules/$KERNEL_RELEASE/build"

for command in git make modinfo python3 tar tee; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command"
    exit 1
  }
done
[[ -d "$KERNEL_BUILD" ]] || {
  echo "ERROR: matching kernel headers are missing: $KERNEL_BUILD"
  echo "Install the headers for the running kernel ($KERNEL_RELEASE), then rerun."
  exit 1
}

bash "$SCRIPT_DIR/bootstrap-driver-sources.sh"

for variant in evo-universal evo-cyborg; do
  rm -rf -- "$variant"
  mkdir -p "$variant"
  git -C "$SCRIPT_DIR/universal-pidff" archive HEAD | tar -x -C "$variant"
done

python3 "$SCRIPT_DIR/patch-evo.py"

for variant in evo-universal evo-cyborg; do
  echo "=== Building $variant for $KERNEL_RELEASE"
  (
    cd "$variant"
    make -C "$KERNEL_BUILD" M="$PWD" -j2 modules
  )
  module="$SCRIPT_DIR/$variant/hid_universal_pidff.ko"
  [[ -s "$module" ]] || {
    echo "ERROR: expected module was not produced: $module"
    exit 1
  }
  vermagic="$(modinfo -F vermagic "$module")"
  [[ "${vermagic%% *}" == "$KERNEL_RELEASE" ]] || {
    echo "ERROR: module vermagic '$vermagic' does not match running kernel '$KERNEL_RELEASE'"
    exit 1
  }
  modinfo "$module" | grep -E '^(alias|vermagic):' || true
  ls -lh "$module"
done

echo "DONE: both driver variants built for $KERNEL_RELEASE"
echo "Build log: $LOG"
