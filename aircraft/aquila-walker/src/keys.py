#!/usr/bin/env python3
"""Show the global and aircraft bindings for the keys the walker include uses."""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from survey import FLEET, find, load_chain, FGROOT

WK = ["6", "65", "68", "83", "87", "97", "100", "106", "115", "119"]

def keyblocks(txt):
    out = {}
    for m in re.finditer(r'<key n="(\d+)">(.*?)</key>', txt, re.S):
        out.setdefault(m.group(1), []).append(re.sub(r"\s+", " ", m.group(2))[:400])
    return out

g = keyblocks(open(FGROOT + "/keyboard.xml", errors="replace").read())
print("GLOBAL")
for k in WK:
    for b in g.get(k, []):
        print(f"  {k}: {b[:300]}")
for name, folder, ident in FLEET:
    d, f = find(folder, ident)
    chain = load_chain(f, d)
    for c, _ in chain:
        if "Generic/Human" in c: continue
        kb = keyblocks(open(c, errors="replace").read())
        for k in WK:
            for b in kb.get(k, []):
                print(f"{name} {os.path.basename(c)} {k}: {b[:400]}")
