#!/bin/bash
# Loads the Evo Force force feedback driver (hid_universal_pidff, cyborg build) at every boot.
#   sudo bash ~/builds/saitek-ffb/install-evo-ffb-boot.sh        install
#   sudo bash ~/builds/saitek-ffb/install-evo-ffb-boot.sh off    undo (and unload it now)
# Built for kernel 6.1.84-8-rk2410 only. After a kernel update the module won't load
# (it's skipped, the board still boots) until it's rebuilt with build-evo-ffb.sh.
set -e
[ "$(id -u)" = 0 ] || { echo "run it with sudo"; exit 1; }
KO=/home/radxa/builds/saitek-ffb/evo-cyborg-v2/hid_universal_pidff.ko   # v2: failed loads clean up after themselves
DEST=/lib/modules/$(uname -r)/extra/hid_universal_pidff.ko
CONF=/etc/modules-load.d/evo-ffb.conf

if [ "$1" = off ]; then
  rm -f "$DEST" "$CONF"
  depmod -a
  rmmod hid_universal_pidff 2>/dev/null || true
  echo "Removed. The Evo works as a plain joystick again after you replug it."
  exit 0
fi

[ -f "$KO" ] || { echo "missing $KO"; exit 1; }
vm=$(modinfo -F vermagic "$KO" | cut -d' ' -f1)
[ "$vm" = "$(uname -r)" ] || { echo "module is for $vm, kernel is $(uname -r): rebuild first"; exit 1; }
mkdir -p "$(dirname "$DEST")"
install -m 644 "$KO" "$DEST"
depmod -a
echo hid_universal_pidff > "$CONF"
echo "Installed: $DEST and $CONF"
echo "Undo: sudo bash $0 off"
