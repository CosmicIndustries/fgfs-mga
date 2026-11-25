#!/usr/bin/env bash
# Network-backed source bootstrap plus offline validation of the local patch pipeline.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/bootstrap-driver-sources.sh"
bash -n "$SCRIPT_DIR/bootstrap-driver-sources.sh"
python3 -m py_compile "$SCRIPT_DIR/patch-evo.py" "$SCRIPT_DIR/patch-evo-cyborg-v2.py"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/evo-universal" "$tmp/evo-cyborg" "$tmp/cyborg-hid-pidff"
git -C "$SCRIPT_DIR/universal-pidff" archive HEAD | tar -x -C "$tmp/evo-universal"
git -C "$SCRIPT_DIR/universal-pidff" archive HEAD | tar -x -C "$tmp/evo-cyborg"
git -C "$SCRIPT_DIR/cyborg-hid-pidff" archive HEAD | tar -x -C "$tmp/cyborg-hid-pidff"

(
  cd "$tmp"
  python3 "$SCRIPT_DIR/patch-evo.py"
  cp -a evo-cyborg evo-cyborg-v2
  python3 "$SCRIPT_DIR/patch-evo-cyborg-v2.py"

  python3 - <<'PY'
from pathlib import Path
import sys

note = "#undef hid_pidff_init"
device = "HID_USB_DEVICE(USB_VENDOR_ID_SAITEK_FFB, USB_DEVICE_ID_SAITEK_CYBORG_EVO_FORCE)"
for name in ("evo-universal", "evo-cyborg", "evo-cyborg-v2"):
    source = Path(name, "hid-universal-pidff.c").read_text()
    header = Path(name, "hid-pidff.h").read_text()
    if source.count(device) != 1:
        sys.exit(f"{name}: expected exactly one Saitek VID/PID entry")
    if header.count(note) != 1:
        sys.exit(f"{name}: expected exactly one hid_pidff_init macro guard")

cyborg = Path("evo-cyborg", "hid-pidff.c").read_text()
if "static int cyborg_pidff_init(struct hid_device *hid)" not in cyborg:
    sys.exit("cyborg variant did not receive the device-managed implementation")
if "int hid_pidff_init_with_quirks(struct hid_device *hid, u32 initial_quirks)" not in cyborg:
    sys.exit("cyborg variant is missing the adapter entry point")

v2 = Path("evo-cyborg-v2", "hid-universal-pidff.c").read_text()
if v2.count("goto err_stop;") != 1 or v2.count("hid_hw_stop(hdev);") != 1:
    sys.exit("v2 probe-failure cleanup patch is missing or duplicated")
print("PASS  pinned sources and all local patch transformations")
PY
)

bash "$SCRIPT_DIR/bootstrap-driver-sources.sh" --check
echo "PASS  clean, pinned FFB source bootstrap"
