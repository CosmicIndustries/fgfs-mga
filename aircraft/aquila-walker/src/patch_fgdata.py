#!/usr/bin/env python3
"""Add the Aquila flight suit to FlightGear's shared walker (fgdata Aircraft/Generic/Human).

usage: patch_fgdata.py STAGE_DIR FGROOT BACKUP_DIR [--undo]

STAGE_DIR holds Aircraft/Generic/Human/Models/{outfit,Themes} files to copy in.
Adds outfit 5 (Aquila flight suit, male and female meshes) to walker-inc.xml and
walker.xml, makes the Aquila .ac copies from the stock flight suit meshes, and
two themes for Walker > Select Theme. Originals are backed up once; running it
again changes nothing. --undo puts the backed-up files back and removes ours."""
import os, sys, shutil

MARK = "<!-- aquila-walker outfit5 -->"


def main():
    stage, fgroot, backup = sys.argv[1:4]
    undo = "--undo" in sys.argv
    H = os.path.join(fgroot, "Aircraft/Generic/Human/Models")
    inc, wlk = os.path.join(H, "walker-inc.xml"), os.path.join(H, "walker.xml")
    bdir = os.path.join(backup, "fgdata/Aircraft/Generic/Human/Models")
    ours = ["outfit/aquila-flightsuit-m.xml", "outfit/aquila-flightsuit-f.xml", "outfit/aquila-flightsuit-m.png",
            "outfit/aquila-flightsuit-f.png", "outfit/aquila-flightsuit-m.ac", "outfit/aquila-flightsuit-f.ac",
            "Themes/Waldo_aquila.xml", "Themes/Amelia_aquila.xml"]
    if undo:
        for f in ("walker-inc.xml", "walker.xml"):
            b = os.path.join(bdir, f)
            if os.path.exists(b):
                shutil.copy2(b, os.path.join(H, f)); print("restored", f)
        nb = os.path.join(backup, "fgdata/Aircraft/Generic/Human/Nasal/walk.nas")
        if os.path.exists(nb):
            shutil.copy2(nb, os.path.join(fgroot, "Aircraft/Generic/Human/Nasal/walk.nas")); print("restored walk.nas")
        for f in ours:
            p = os.path.join(H, f)
            if os.path.exists(p):
                os.remove(p); print("removed", f)
        return
    os.makedirs(bdir, exist_ok=True)
    for f in ("walker-inc.xml", "walker.xml"):
        b = os.path.join(bdir, f)
        src = os.path.join(H, f)
        if not os.path.exists(b) and MARK not in open(src).read():
            shutil.copy2(src, b); print("backed up", f)
    sH = os.path.join(stage, "Aircraft/Generic/Human/Models")
    for f in ours:
        if f.endswith(".ac"):
            continue
        shutil.copy2(os.path.join(sH, f), os.path.join(H, f))
    for g in ("m", "f"):
        txt = open(os.path.join(H, f"outfit/flightsuit-{g}.ac"), encoding="latin-1").read()
        n = txt.count('texture "flightsuit.png"')
        txt = txt.replace('texture "flightsuit.png"', f'texture "aquila-flightsuit-{g}.png"')
        open(os.path.join(H, f"outfit/aquila-flightsuit-{g}.ac"), "w", encoding="latin-1").write(txt)
        print(f"aquila-flightsuit-{g}.ac: {n} textures pointed at aquila-flightsuit-{g}.png")

    t = open(inc).read()
    if MARK not in t:
        a = "<outfit4>Aircraft/Generic/Human/Models/outfit/coat-m.xml</outfit4>"
        assert a in t, "walker-inc.xml: outfit4 line not found"
        t = t.replace(a, a + "\n\t\t" + MARK + "\n\t\t<outfit5>Aircraft/Generic/Human/Models/outfit/aquila-flightsuit-m.xml</outfit5>", 1)
        b = "<!-- Outfits -->"
        assert b in t, "walker-inc.xml: Outfits section not found"
        block = ("<!-- Outfits -->\n\n\t" + MARK + "\n\t<model>\n  <path alias=\"../../models/outfit5\"/>\n\t\t<name>outfit5</name>\n\t</model>\n"
                 " <animation>\n  <type>select</type>\n  <object-name>outfit5</object-name>\n  <condition>\n   <equals>\n"
                 "\t\t<property alias=\"../../../../appearence-props/outfit\"/>\n    <value>5</value>\n   </equals>\n  </condition>\n </animation>\n")
        t = t.replace(b, block, 1)
        open(inc, "w").write(t); print("walker-inc.xml: outfit 5 added")
    # walk.nas gives the walker the plane's airspeed as momentum when he steps out, so on the
    # ground in a breeze he lands metres ahead of the door. Momentum over the ground is groundspeed.
    nas = os.path.join(fgroot, "Aircraft/Generic/Human/Nasal/walk.nas")
    n_old = 'var c_airspeed_mps = getprop("velocities/airspeed-kt") * 0.51444444;'
    n_new = 'var c_airspeed_mps = getprop("velocities/groundspeed-kt") * 0.51444444;  # aquila-walker: momentum over the ground'
    nt = open(nas).read()
    if n_old in nt:
        nb = os.path.join(backup, "fgdata/Aircraft/Generic/Human/Nasal/walk.nas")
        os.makedirs(os.path.dirname(nb), exist_ok=True)
        if not os.path.exists(nb):
            shutil.copy2(nas, nb); print("backed up walk.nas")
        open(nas, "w").write(nt.replace(n_old, n_new, 1)); print("walk.nas: exit momentum from groundspeed")
    w = open(wlk).read()
    if MARK not in w:
        a = "<outfit3>Aircraft/Generic/Human/Models/outfit/airliner-f.xml</outfit3>"
        assert a in w, "walker.xml: female outfit3 line not found"
        w = w.replace(a, a + "\n\t\t" + MARK + "\n\t\t<outfit5>Aircraft/Generic/Human/Models/outfit/aquila-flightsuit-f.xml</outfit5>", 1)
        open(wlk, "w").write(w); print("walker.xml: female outfit 5 added")


if __name__ == "__main__":
    main()
