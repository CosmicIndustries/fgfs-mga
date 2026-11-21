#!/bin/bash
# Try force feedback on the Saitek Cyborg Evo Force without changing anything permanent.
#   sudo bash ~/builds/saitek-ffb/try-evo-ffb.sh            load the upstream-style driver (evo-universal)
#   sudo bash ~/builds/saitek-ffb/try-evo-ffb.sh cyborg     load the driver written for this stick (evo-cyborg)
#   sudo bash ~/builds/saitek-ffb/try-evo-ffb.sh off        unload it; the stick goes back to plain input
# Nothing is installed into /lib/modules and nothing touches /boot: a reboot always undoes it.
set -u
cd "$(dirname "$0")"
[[ $EUID -eq 0 ]] || { echo "run it with sudo"; exit 1; }
DEV=$(grep -il "06a3" /sys/bus/hid/devices/*/uevent 2>/dev/null | xargs -r grep -il "ffb5" | head -1 | xargs -r dirname)
unload() { lsmod | grep -q '^hid_universal_pidff' && rmmod hid_universal_pidff && echo "driver unloaded"; }
case "${1:-universal}" in
  off) unload; exit 0 ;;
  cyborg) KO=evo-cyborg/hid_universal_pidff.ko ;;
  *) KO=evo-universal/hid_universal_pidff.ko ;;
esac
unload
insmod "$KO" || { echo "insmod failed; see: dmesg | tail"; exit 1; }
echo "loaded $KO"
sleep 2
# hid-generic usually lets go by itself; if not, hand the stick over
if [[ -n "$DEV" ]] && [[ "$(basename "$(readlink -f "$DEV/driver")")" != hid-universal-pidff ]]; then
  id=$(basename "$DEV")
  echo "$id" > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null
  echo "$id" > /sys/bus/hid/drivers/hid-universal-pidff/bind 2>/dev/null
  sleep 2
fi
echo "--- kernel says:"; dmesg | tail -n 12 | grep -iE "pidff|saitek|ffb|hid" || true
N=/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick
EV=$(basename "$(readlink -f "$N")")
echo "--- stick is /dev/input/$EV"
if grep -q "^B: FF=" "/sys/class/input/$EV/device/capabilities/ff" 2>/dev/null || [[ "$(cat /sys/class/input/$EV/device/capabilities/ff 2>/dev/null)" != "0" ]]; then
  echo "Force feedback is on. Test it, holding the stick loosely (no sudo needed): fftest $N"
else
  echo "No force feedback yet. Try the other driver: sudo bash $0 $([[ $KO == evo-cyborg* ]] && echo universal || echo cyborg)"
fi
