#!/usr/bin/env bash
# Build evo-cyborg-v2: the Cyborg driver-managed variant with probe-failure cleanup.
# Run build-evo-ffb.sh first; this script will refuse to use an absent base variant.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG="$SCRIPT_DIR/build-evo-cyborg-v2.log"
exec > >(tee "$LOG") 2>&1

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD="/lib/modules/$KERNEL_RELEASE/build"

command -v make >/dev/null 2>&1 || { echo "ERROR: make is required"; exit 1; }
command -v modinfo >/dev/null 2>&1 || { echo "ERROR: modinfo is required (install kmod)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required"; exit 1; }
[[ -d "$KERNEL_BUILD" ]] || {
  echo "ERROR: matching kernel headers are missing: $KERNEL_BUILD" >&2
  exit 1
}
[[ -f evo-cyborg/hid-universal-pidff.c ]] || {
  echo "ERROR: evo-cyborg source is absent." >&2
  echo "Run: bash $SCRIPT_DIR/build-evo-ffb.sh" >&2
  exit 1
}

rm -rf -- evo-cyborg-v2
cp -a evo-cyborg evo-cyborg-v2
rm -f -- evo-cyborg-v2/*.o evo-cyborg-v2/*.ko evo-cyborg-v2/*.mod* evo-cyborg-v2/.*.cmd 2>/dev/null || true

python3 "$SCRIPT_DIR/patch-evo-cyborg-v2.py"
echo "=== Building evo-cyborg-v2 for $KERNEL_RELEASE"
(
  cd evo-cyborg-v2
  nice -n 19 make -C "$KERNEL_BUILD" M="$PWD" -j2 modules
)

module="$SCRIPT_DIR/evo-cyborg-v2/hid_universal_pidff.ko"
[[ -s "$module" ]] || { echo "ERROR: expected module was not produced: $module"; exit 1; }
vermagic="$(modinfo -F vermagic "$module")"
[[ "${vermagic%% *}" == "$KERNEL_RELEASE" ]] || {
  echo "ERROR: module vermagic '$vermagic' does not match running kernel '$KERNEL_RELEASE'" >&2
  exit 1
}
modinfo "$module" | grep -E '^(alias|vermagic):' || true
echo "DONE: $module"
echo "Build log: $LOG"
