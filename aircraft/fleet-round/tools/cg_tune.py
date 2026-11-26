#!/usr/bin/env python3
"""Tune each YASim file's nose ballast so the solved CG sits at a target % of MAC.
usage: cg_tune.py TARGET_PCT BALLAST_X_MODEL file.xml [file.xml ...]
BALLAST_X_MODEL is metres aft of the model origin (YASim x = -value)."""
import re, subprocess, sys, shutil
Y = "/home/radxa/builds/flightgear/build/src/FDM/YASim/yasim"
target = float(sys.argv[1]); bx = float(sys.argv[2])

def solve(path):
    out = subprocess.run([Y, path], capture_output=True, text=True, timeout=120).stdout
    m = re.search(r"CG-x rel\. MAC\s*:\s*(-?[\d.]+)%", out)
    conv = "convergence problem" in out
    d = re.search(r"Drag Coefficient\s*:\s*([\d.]+)", out)
    l = re.search(r"Lift Ratio\s*:\s*([\d.]+)", out)
    t = re.search(r"Tail Incidence\s*:\s*(-?[\d.]+)", out)
    e = re.search(r"Approach Elevator\s*:\s*(-?[\d.]+)", out)
    a = re.search(r"Cruise AoA\s*:\s*(-?[\d.]+)", out)
    return (float(m.group(1)) if m else None, conv,
            [x.group(1) if x else "?" for x in (d, l, a, t, e)])

def setb(src, dst, mass):
    txt = open(src).read()
    txt = re.sub(r'<ballast [^>]*/>', '<ballast x="%.3f" y="0.000" z="0.000" mass="%d"/>' % (-bx, mass), txt)
    open(dst, "w").write(txt)

for f in sys.argv[3:]:
    empty = int(re.search(r'<airplane mass="(\d+)"', open(f).read()).group(1))
    tmp = f + ".tune.xml"
    lo, hi = 0, int(empty * 0.6)
    best = None
    for _ in range(9):
        mid = (lo + hi) // 2
        setb(f, tmp, mid)
        pct, conv, info = solve(tmp)
        if pct is None:
            hi = mid; continue
        best = (mid, pct, conv, info)
        if pct > target: lo = mid
        else: hi = mid
    mid, pct, conv, info = best
    setb(f, f, mid)
    pct, conv, info = solve(f)
    print("%-40s ballast %4d lb (%.0f%% of empty) at x %.2f -> CG %.0f%% MAC conv_warn=%s Cd=%s L=%s aoa=%s tail=%s elev=%s"
          % (f, mid, 100.0 * mid / empty, bx, pct, conv, *info))
    import os; os.remove(tmp)
