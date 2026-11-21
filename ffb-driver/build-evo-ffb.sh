#!/bin/bash
# Builds two candidate force-feedback modules for the Saitek Cyborg Evo Force (06a3:ffb5) against the
# running kernel's headers. This kernel has CONFIG_HID_PID off and usbhid built in, so the stock
# hid-pidff can't be used; these are standalone HID drivers that take the stick over from hid-generic.
#   evo-universal: universal-pidff (current upstream pidff, device-managed effect memory) + the Evo's id
#   evo-cyborg:    the same driver shell around cyborg-hid-pidff's pidff (driver-managed memory, written
#                  and tested for this exact stick)
# Builds only. Installing/loading needs sudo; see INSTALL-evo-ffb.txt.
set -u
cd "$(dirname "$0")"
exec > build-evo-ffb.log 2>&1
for v in evo-universal evo-cyborg; do
  rm -rf "$v"; cp -r universal-pidff "$v"; rm -f "$v"/*.o "$v"/*.ko "$v"/*.mod* "$v"/.*.cmd 2>/dev/null
done
python3 patch-evo.py || exit 1
for v in evo-universal evo-cyborg; do
  echo "=== $v"
  ( cd "$v" && make -C /lib/modules/$(uname -r)/build M="$PWD" -j2 modules ) && ls -la "$v"/*.ko && modinfo "$v"/hid-universal-pidff.ko 2>/dev/null | grep -E "alias.*06A3|vermagic"
done
echo DONE
