#!/usr/bin/env bash
# Install the built Cyborg v2 module for the running kernel and load it at boot.
#   sudo bash install-evo-ffb-boot.sh          install
#   sudo bash install-evo-ffb-boot.sh off      undo and unload it now
# Built for the kernel whose headers were used by build-evo-cyborg-v2.sh. After a
# kernel update, rebuild and reinstall; this installer checks the module vermagic.
set -Eeuo pipefail

[[ "$(id -u)" == 0 ]] || { echo "run it with sudo" >&2; exit 1; }
MODE="${1:-install}"
case "$MODE" in
  install) ;;
  off)
    DEST="/lib/modules/$(uname -r)/extra/hid_universal_pidff.ko"
    CONF="/etc/modules-load.d/evo-ffb.conf"
    rm -f -- "$DEST" "$CONF"
    depmod -a
    rmmod hid_universal_pidff 2>/dev/null || true
    echo "Removed. The Evo works as a plain joystick again after you replug it."
    exit 0
    ;;
  *)
    echo "Usage: sudo bash $0 [install|off]" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KO="$SCRIPT_DIR/evo-cyborg-v2/hid_universal_pidff.ko"
DEST="/lib/modules/$(uname -r)/extra/hid_universal_pidff.ko"
CONF="/etc/modules-load.d/evo-ffb.conf"

[[ -s "$KO" ]] || { echo "missing $KO; run build-evo-cyborg-v2.sh first" >&2; exit 1; }
command -v modinfo >/dev/null 2>&1 || { echo "modinfo is required (install kmod)" >&2; exit 1; }
command -v depmod >/dev/null 2>&1 || { echo "depmod is required" >&2; exit 1; }

vermagic="$(modinfo -F vermagic "$KO")"
[[ "${vermagic%% *}" == "$(uname -r)" ]] || {
  echo "module is for $vermagic, kernel is $(uname -r): rebuild first" >&2
  exit 1
}

install -D -m 644 "$KO" "$DEST"
depmod -a
printf '%s\n' hid_universal_pidff > "$CONF"
echo "Installed: $DEST and $CONF"
echo "Undo: sudo bash $0 off"
