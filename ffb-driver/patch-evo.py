import re, sys
NOTE = "#undef hid_pidff_init   /* hid.h defines it as NULL when CONFIG_HID_PID is off */\n"
for v in ("evo-universal", "evo-cyborg"):
    p = v + "/hid-ids.h"; s = open(p).read()
    s += "\n#define USB_VENDOR_ID_SAITEK_FFB\t0x06a3\n#define USB_DEVICE_ID_SAITEK_CYBORG_EVO_FORCE\t0xffb5\n"
    open(p, "w").write(s)
    p = v + "/hid-pidff.h"; s = open(p).read()
    s = s.replace("#include <linux/hid.h>\n", "#include <linux/hid.h>\n" + NOTE, 1)
    assert NOTE in s
    open(p, "w").write(s)
    p = v + "/hid-universal-pidff.c"; s = open(p).read()
    a = "static const struct hid_device_id universal_pidff_devices[] = {\n"
    assert a in s
    s = s.replace(a, a + "\t{ HID_USB_DEVICE(USB_VENDOR_ID_SAITEK_FFB, USB_DEVICE_ID_SAITEK_CYBORG_EVO_FORCE),\n"
                  "\t  .driver_data = HID_PIDFF_QUIRK_PERMISSIVE_CONTROL },\n", 1)
    open(p, "w").write(s)
# evo-cyborg: cyborg-hid-pidff's driver-managed pidff behind the same entry point
s = open("cyborg-hid-pidff/hid-pidff.c").read()
assert "int hid_pidff_init(struct hid_device *hid)" in s
s = s.replace("int hid_pidff_init(struct hid_device *hid)", "static int cyborg_pidff_init(struct hid_device *hid)", 1)
s = s.replace('#include "usbhid.h"', '#include <linux/usb.h>')
s = s.replace("#include <linux/hid.h>\n", "#include <linux/hid.h>\n" + NOTE, 1)
s += "\nint hid_pidff_init_with_quirks(struct hid_device *hid, u32 initial_quirks)\n{\n\treturn cyborg_pidff_init(hid);\n}\n"
open("evo-cyborg/hid-pidff.c", "w").write(s)
print("patched")
