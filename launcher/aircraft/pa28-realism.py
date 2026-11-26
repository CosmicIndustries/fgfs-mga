#!/usr/bin/env python3
"""Warrior (PA28-161-160) realism fixes. Usage: pa28-realism.py [PA28 aircraft dir]
Default dir: ~/.fgfs/Aircraft/PA28. Backs up both files to <dir>/mga-backup-<time>/ first.
Safe to run twice: it stops if the fixes are already in.

1. Stall horn. The POH says it sounds 5-10 KIAS above the stall in every configuration.
   The aircraft's fixed 6.3 deg alpha threshold fired about 14 kt early with flaps up. The new
   thresholds put it about 7.5 kt above the stall, worked out from the model's own lift table
   (CLalpha x 0.8581 plus CLflap) for flaps 0 / 10 / 25 / 40: 8.3 / 8.0 / 7.2 / 6.8 deg.
2. Touchdown squeal on each main wheel (fgdata Sounds/squeal.wav), above 25 kt groundspeed.
3. Fuel. POH: 50 US gal total, 48 usable. The tanks were 168 lb (28 gal) each with no unusable
   fuel; now 150 lb (25 gal) each with 1 gal unusable.
"""
import os, re, shutil, sys, time
D = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.fgfs/Aircraft/PA28")
FILES = ["Sounds/sound.xml", "PA28-161-160.xml"]
if "MGA realism" in open(os.path.join(D, FILES[0])).read():
    sys.exit("already applied, nothing changed")
B = os.path.join(D, "mga-backup-" + time.strftime("%Y%m%d-%H%M%S"))
for f in FILES:
    os.makedirs(os.path.dirname(os.path.join(B, f)), exist_ok=True)
    shutil.copy2(os.path.join(D, f), os.path.join(B, f))
print("backup:", B)

def edit(path, fn):
    p = os.path.join(D, path); s = open(p).read(); t = fn(s)
    open(p, "w").write(t); print("patched", path)

def band(lo, hi, a):
    c = []
    if lo is not None: c.append(f"<greater-than><property>/fdm/jsbsim/fcs/flap-pos-deg</property><value>{lo}</value></greater-than>")
    if hi is not None: c.append(f"<less-than><property>/fdm/jsbsim/fcs/flap-pos-deg</property><value>{hi}</value></less-than>")
    c.append(f"<greater-than><property>/fdm/jsbsim/aero/alpha-deg</property><value>{a}</value></greater-than>")
    return "<and>" + "".join(c) + "</and>"
HORN = ("<!-- MGA realism: horn ~7.5 kt above stall per flap setting (POH: 5-10 KIAS) -->\n\t\t\t\t\t<or>"
        + band(None, 5, 8.3) + band(5, 17, 8.0) + band(17, 32, 7.2) + band(32, None, 6.8) + "</or>")
def sound(s):
    pat = re.compile(r"<greater-than>\s*<property>/fdm/jsbsim/aero/alpha-deg</property>\s*<value>6\.3</value>\s*</greater-than>")
    mark = "<!-- Touchdown --><!-- Needs a sound file -->"
    if len(pat.findall(s)) != 1 or s.count(mark) != 1:
        sys.exit("sound.xml is not the version this was written for; nothing changed (backup kept)")
    s = pat.sub(lambda m: HORN, s)
    sq = ""
    for g, side in ((1, "left"), (2, "right")):
        sq += f"""
		<squeal>
			<name>touchdown squeal {side}</name>
			<mode>once</mode>
			<path>Sounds/squeal.wav</path>
			<condition>
				<and>
					<property>/gear/gear[{g}]/wow</property>
					<greater-than><property>/velocities/groundspeed-kt</property><value>25</value></greater-than>
				</and>
			</condition>
			<volume><property>/velocities/groundspeed-kt</property><factor>0.006</factor><max>0.45</max></volume>
		</squeal>
"""
    return s.replace(mark, "<!-- Touchdown: MGA realism, squeal on each main wheel -->" + sq, 1)

def fuel(s):
    pat = re.compile(r'<capacity unit="LBS">168</capacity>')
    if len(pat.findall(s)) != 2:
        sys.exit("PA28-161-160.xml tanks are not the 168 lb version; fuel left unchanged")
    return pat.sub('<capacity unit="LBS">150</capacity> <!-- MGA realism: POH 25 gal, 24 usable -->\n\t\t\t<unusable-volume unit="GAL">1</unusable-volume>', s)

edit(FILES[0], sound)
edit(FILES[1], fuel)
print("undo: copy the files in", B, "back over", D)
