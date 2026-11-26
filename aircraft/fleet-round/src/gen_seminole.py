#!/usr/bin/env python3
"""Piper PA-44-180 Seminole T-tail, in SenecaII.ac coordinates (FG axes before the
Seneca model's x +0.83 offset). Replaces the Seneca's low tail.
Seminole: overall height 8.5 ft (2.59 m), stabilator span about 12.8 ft.
Usage: gen_seminole.py OUTDIR -> seminole-ttail.ac"""
import math, os, sys
from fleetlib import *

WHITE = mat("seminole_white", (0.93, 0.93, 0.91), spec=0.45, shi=50)
BLUE = mat("seminole_blue", (0.08, 0.18, 0.45), spec=0.4)
DARK = mat("seminole_dark", (0.12, 0.12, 0.13))

# fin: (x_le, y, z, chord) root -> tip; z is the span station (vertical fin)
FIN_ROOT = (2.30, 0.0, 1.42, 1.32)     # to the hinge line at x 3.62
FIN_TIP = (3.18, 0.0, 2.47, 0.62)      # hinge at x 3.80
RUD_ROOT = (3.62, 0.0, 1.47, 0.36)
RUD_TIP = (3.80, 0.0, 2.45, 0.26)
STAB_Z = 2.53
STAB_LE, STAB_ROOT_C, STAB_TIP_C, STAB_SEMI = 3.30, 0.86, 0.74, 1.95
PIVOT_X = STAB_LE + 0.25 * STAB_ROOT_C

def main():
    out = sys.argv[1]
    objs = []
    fin = Obj("SeminoleFin")
    wing(fin, [FIN_ROOT, ((FIN_ROOT[0] + FIN_TIP[0]) / 2, 0, (FIN_ROOT[2] + FIN_TIP[2]) / 2,
                          (FIN_ROOT[3] + FIN_TIP[3]) / 2), FIN_TIP], WHITE, t=0.11, n=8, vertical=True)
    # dorsal fillet blending the fin into the tail cone
    wing(fin, [(1.75, 0, 1.58, 0.75), (2.20, 0, 1.70, 0.30), (2.42, 0, 1.78, 0.05)], WHITE, t=0.10, n=6, vertical=True)
    objs.append(fin)
    stripe = Obj("SeminoleFinStripe")
    wing(stripe, [(2.86, 0.0, 1.95, 0.88), (2.99, 0.0, 2.10, 0.78)], BLUE, t=0.115, n=8, vertical=True)
    objs.append(stripe)
    rud = Obj("SeminoleRudder")
    wing(rud, [RUD_ROOT, RUD_TIP], WHITE, t=0.06, n=6, vertical=True)
    objs.append(rud)
    # fin-top fairing (bullet) the stabilator pivots on
    pod = Obj("SeminoleTailPod")
    body_of_revolution(pod, [(3.10, STAB_Z, 0.005, 0.005), (3.22, STAB_Z, 0.06, 0.05), (3.60, STAB_Z, 0.07, 0.06),
                             (4.02, STAB_Z, 0.05, 0.04), (4.16, STAB_Z, 0.005, 0.005)], WHITE, n=10)
    objs.append(pod)
    stab = Obj("SeminoleStabilator")
    secs = []
    for s in [-1, 1]:
        pass
    # left tip -> right tip, slight LE sweep, 0 dihedral (T-tail)
    for y in [-STAB_SEMI, -0.08, 0.08, STAB_SEMI]:
        f = abs(y) / STAB_SEMI
        c = STAB_ROOT_C + (STAB_TIP_C - STAB_ROOT_C) * f
        secs.append((STAB_LE + 0.10 * f, y, STAB_Z, c))
    wing(stab, secs, WHITE, t=0.10, n=8)
    objs.append(stab)
    os.makedirs(out, exist_ok=True)
    write_ac(os.path.join(out, "seminole-ttail.ac"), objs)
    print("pivot x %.3f z %.3f; hinge (%.2f,%.2f)-(%.2f,%.2f)" % (PIVOT_X, STAB_Z, RUD_ROOT[0], RUD_ROOT[2], RUD_TIP[0], RUD_TIP[2]))

if __name__ == "__main__":
    main()
