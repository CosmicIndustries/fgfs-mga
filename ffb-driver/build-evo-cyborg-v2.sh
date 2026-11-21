#!/bin/bash
# evo-cyborg-v2 = evo-cyborg (the force feedback driver that works) with its error path fixed: when force
# feedback setup fails after the stick has started, it now stops the stick again (hid_hw_stop), so a failed
# load can't leave dead copies of the Evo behind. Builds only, at low priority; evo-cyborg is left as is.
set -u
cd "$(dirname "$0")"
exec > build-evo-cyborg-v2.log 2>&1
rm -rf evo-cyborg-v2
cp -r evo-cyborg evo-cyborg-v2
rm -f evo-cyborg-v2/*.o evo-cyborg-v2/*.ko evo-cyborg-v2/*.mod* evo-cyborg-v2/.*.cmd 2>/dev/null
python3 - <<'EOF'
p = "evo-cyborg-v2/hid-universal-pidff.c"
s = open(p).read()
a = '''	error = init_function(hdev, id->driver_data);
	if (error) {
		hid_warn(hdev, "Error initialising force feedback\\n");
		goto err;
	}
'''
assert s.count(a) == 1, "anchor"
s = s.replace(a, '''	error = init_function(hdev, id->driver_data);
	if (error) {
		hid_warn(hdev, "Error initialising force feedback\\n");
		goto err_stop;
	}
''')
b = '''	return 0;
err:
	return error;
}
'''
assert s.count(b) == 1, "anchor2"
s = s.replace(b, '''	return 0;
err_stop:
	hid_hw_stop(hdev);	/* undo hid_hw_start, so no input devices are left behind */
err:
	return error;
}
''')
open(p, "w").write(s)
print("patched")
EOF
( cd evo-cyborg-v2 && nice -n 19 make -C /lib/modules/$(uname -r)/build M="$PWD" -j2 modules ) || exit 1
modinfo evo-cyborg-v2/hid_universal_pidff.ko | grep -E 'vermagic|06A3'
echo DONE
