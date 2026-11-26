#!/usr/bin/env python3
"""Piper Arrow III cockpit add-ons on the PA28 model: gear selector, gear lights, prop lever.
Usage: gen_arrow.py OUTDIR  -> arrow-addons.ac"""
import os, sys
from fleetlib import *

BLACK = mat("black", (0.05, 0.05, 0.05), spec=0.4)
WHITE = mat("knob_white", (0.92, 0.92, 0.90), spec=0.5)
BLUE = mat("prop_blue", (0.10, 0.25, 0.70), spec=0.5)
GREEN_OFF = mat("green_off", (0.05, 0.20, 0.05))
GREEN_ON = mat("green_on", (0.20, 1.00, 0.25), emis=1.0)
RED_ON = mat("red_on", (1.00, 0.15, 0.10), emis=1.0)
PANEL_X = -1.728          # PA28 panel face (annunciators sit at x -1.73)

def main():
    out = sys.argv[1]
    objs = []
    # gear selector: slot plate, lever arm, wheel-shaped knob (lever up/down animated in XML)
    plate = Obj("ArrowGearPlate")
    box(plate, PANEL_X + 0.002, -0.06, 0.02, 0.004, 0.03, 0.09, BLACK)
    objs.append(plate)
    lever = Obj("ArrowGearLever")
    cylinder(lever, (PANEL_X, -0.06, 0.02), (PANEL_X + 0.045, -0.06, 0.02), 0.004, WHITE, n=6)
    body_of_revolution(lever, [(PANEL_X + 0.040, 0.02, 0.001, 0.001), (PANEL_X + 0.043, 0.02, 0.012, 0.012),
                               (PANEL_X + 0.055, 0.02, 0.012, 0.012), (PANEL_X + 0.058, 0.02, 0.001, 0.001)],
                       WHITE, n=10)
    for o in [lever]:
        o.v = [(x, y - 0.06, z) for x, y, z in o.v]   # body_of_revolution is on y=0
    objs.append(lever)
    # fix: cylinder above was already at y -0.06; undo double shift for its 12 verts
    lever.v = [(x, (y + 0.06) if i < 12 else y, z) for i, (x, y, z) in enumerate(lever.v)]
    # three green lights in a row above the lever, and an amber/red in-transit light
    for i, name in enumerate(["ArrowGearLightNose", "ArrowGearLightLeft", "ArrowGearLightRight"]):
        on = Obj(name + ".on"); off = Obj(name + ".off")
        y = -0.085 + 0.025 * i
        box(on, PANEL_X + 0.004, y, 0.085, 0.006, 0.014, 0.014, GREEN_ON)
        box(off, PANEL_X + 0.004, y, 0.085, 0.006, 0.014, 0.014, GREEN_OFF)
        objs += [on, off]
    transit = Obj("ArrowGearUnsafe")
    box(transit, PANEL_X + 0.004, -0.06, 0.11, 0.006, 0.02, 0.012, RED_ON)
    objs.append(transit)
    # prop lever on the quadrant, between throttle (y 0) and mixture (y 0.05)
    prop = Obj("ArrowPropLever")
    cylinder(prop, (-1.70, 0.027, -0.04), (-1.63, 0.027, -0.04), 0.003, BLACK, n=6)
    box(prop, -1.625, 0.027, -0.04, 0.012, 0.012, 0.022, BLUE)
    objs.append(prop)
    os.makedirs(out, exist_ok=True)
    write_ac(os.path.join(out, "arrow-addons.ac"), objs)
    print("wrote arrow-addons.ac", sum(len(o.v) for o in objs), "verts")

if __name__ == "__main__":
    main()
