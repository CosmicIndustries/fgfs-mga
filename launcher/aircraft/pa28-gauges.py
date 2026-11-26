#!/usr/bin/env python3
"""Warrior/Archer EGT and oil temperature gauges from the real engine. Usage: pa28-gauges.py [PA28 dir]
Default dir: ~/.fgfs/Aircraft/PA28. Backs up Systems/libraries.xml to <dir>/mga-backup-<time>/ first.
Safe to run twice: it stops if the change is already in.

The PA28's gauges were fed by two made-up ramps in Systems/pa28-engine-160.xml (fcs/egt-switch climbs
to 1028 and fcs/oil-temp-switch to 177 whenever the engine runs), so mixture and power never moved
them and leaning to peak EGT couldn't be practised. JSBSim's piston engine already computes both
(/engines/engine[0]/egt-degf and /engines/engine[0]/oil-temperature-degf). This feeds the gauges'
existing smoothing filters from those instead. The gauge faces are unchanged: the EGT gauge is an
unnumbered Alcor relative gauge whose bug sits at 1400 F by default, so cruise EGT lands by the bug.
"""
import os, shutil, sys, time
D = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.fgfs/Aircraft/PA28")
F = "Systems/libraries.xml"
p = os.path.join(D, F); s = open(p).read()
if "MGA realism: real engine" in s:
    sys.exit("already applied, nothing changed")
OLD = [("<input>/fdm/jsbsim/fcs/egt-switch</input>", "<input>/engines/engine[0]/egt-degf</input>"),
       ("<input>/fdm/jsbsim/fcs/oil-temp-switch</input>", "<input>/engines/engine[0]/oil-temperature-degf</input>")]
for a, _ in OLD:
    if s.count(a) != 1:
        sys.exit(f"{F} is not the version this was written for; nothing changed")
B = os.path.join(D, "mga-backup-" + time.strftime("%Y%m%d-%H%M%S"), "Systems")
os.makedirs(B, exist_ok=True); shutil.copy2(p, B)
print("backup:", B)
for a, b in OLD:
    s = s.replace(a, b + " <!-- MGA realism: real engine value, was the fixed ramp " + a[7:-8].rsplit("/", 1)[1] + " -->", 1)
open(p, "w").write(s); print("patched", F)
