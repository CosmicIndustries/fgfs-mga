#!/usr/bin/env bash
# Temporarily load a built Saitek Cyborg Evo Force FFB module; no boot files are changed.
#   sudo bash try-evo-ffb.sh             test evo-universal
#   sudo bash try-evo-ffb.sh cyborg      test evo-cyborg
#   sudo bash try-evo-ffb.sh cyborg-v2  test evo-cyborg-v2
#   sudo bash try-evo-ffb.sh off         unload the test driver
set -u
cd "$(dirname -- "${BASH_SOURCE[0]}")"
[[ $EUID -eq 0 ]] || { echo "run it with sudo"; exit 1; }

DEV="$(grep -il "06a3" /sys/bus/hid/devices/*/uevent 2>/dev/null | xargs -r grep -il "ffb5" | head -1 | xargs -r dirname)"
unload() {
  if lsmod | grep -q '^hid_universal_pidff'; then
    rmmod hid_universal_pidff && echo "driver unloaded"
  fi
}
case "${1:-universal}" in
  off) unload; exit 0 ;;
  universal) KO=evo-universal/hid_universal_pidff.ko; NEXT=cyborg ;;
  cyborg) KO=evo-cyborg/hid_universal_pidff.ko; NEXT=cyborg-v2 ;;
  cyborg-v2) KO=evo-cyborg-v2/hid_universal_pidff.ko; NEXT=universal ;;
  *) echo "Usage: sudo bash $0 [universal|cyborg|cyborg-v2|off]"; exit 2 ;;
esac

[[ -s "$KO" ]] || { echo "missing $KO; build the requested variant first"; exit 1; }
unload
insmod "$KO" || { echo "insmod failed; see: dmesg | tail"; exit 1; }
echo "loaded $KO"
sleep 2

# If hid-generic still owns this device, hand it to the newly loaded driver.
if [[ -n "$DEV" ]] && [[ "$(basename "$(readlink -f "$DEV/driver" 2>/dev/null || true)")" != hid-universal-pidff ]]; then
  id="$(basename "$DEV")"
  echo "$id" > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null || true
  echo "$id" > /sys/bus/hid/drivers/hid-universal-pidff/bind 2>/dev/null || true
  sleep 2
fi

echo "--- kernel says:"
dmesg | tail -n 12 | grep -iE "pidff|saitek|ffb|hid" || true
N=/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick
if [[ ! -e "$N" ]]; then
  echo "Could not find $N. Check the device event symlink and dmesg."
  exit 1
fi
EV="$(basename "$(readlink -f "$N")")"
echo "--- stick is /dev/input/$EV"
if grep -q "^B: FF=" "/sys/class/input/$EV/device/capabilities/ff" 2>/dev/null ||
   [[ "$(cat "/sys/class/input/$EV/device/capabilities/ff" 2>/dev/null)" != "0" ]]; then
  echo "Force feedback is on. Start at low strength and test the stick carefully (no sudo needed): fftest $N"
else
  echo "No force feedback yet. Try the other driver: sudo bash $0 $NEXT"
fi
