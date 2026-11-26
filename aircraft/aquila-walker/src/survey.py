#!/usr/bin/env python3
"""List each fleet plane's -set file, include chain, walker status, pilot view and model offsets."""
import os, re, glob

HOME = os.path.expanduser("~")
FGROOT = os.environ.get("FGROOT", HOME + "/.fgfs/fgdata_2024_1")
ROOTS = [HOME + "/.fgfs/Aircraft", FGROOT + "/Aircraft"] + \
        [c for c in glob.glob(HOME + "/.fgfs/Aircraft/*/Aircraft") if os.path.exists(os.path.dirname(c) + "/catalog.xml")]
FLEET = [l.split() for l in """warrior PA28 PA28-161-160
archer PA28 PA28-161-180
arrow PA28 PA28R-201
seminole SenecaII PA44-180
seneca SenecaII SenecaII
r22 R22 R22
r44 R44 raven
citabria Cosmic-Citabria citabria
decathlon Cosmic-Decathlon decathlon
zlin Zlin-50lx z50lx
c182 c182s c182s
c182rg c182rg c182rg
pa18 J3Cub PA-18
c337 Cessna337 Cessna337
dromader Dromader Dromader
agcat G-164 G-164
at502b Cosmic-AT502B at502b
at802 Cosmic-AT802 at802
an2 an2 an2""".splitlines()]

def find(folder, ident):
    for r in ROOTS:
        d = os.path.join(r, folder)
        if os.path.isdir(d):
            f = os.path.join(d, ident + "-set.xml")
            if os.path.exists(f):
                return d, f
            c = sorted(glob.glob(d + "/*-set.xml"))
            if c:
                return d, c[0]
    return None, None

def load_chain(f, acdir):
    out, seen = [], set()
    while f and f not in seen:
        seen.add(f)
        txt = open(f, encoding="utf-8", errors="replace").read()
        m = re.search(r"<PropertyList([^>]*)>", txt)
        inc = None
        if m:
            mi = re.search(r'include\s*=\s*"([^"]+)"', m.group(1))
            inc = mi.group(1) if mi else None
        out.append((f, inc))
        if not inc:
            break
        nxt = None
        cands = [os.path.join(os.path.dirname(f), inc), os.path.join(acdir, inc), os.path.join(FGROOT, inc)]
        if inc.startswith("Aircraft/"):
            cands.append(os.path.join(os.path.dirname(acdir), inc[len("Aircraft/"):]))
        for c in cands:
            if os.path.exists(c):
                nxt = c; break
        f = nxt
    return out

if __name__ == "__main__":
    for name, folder, ident in FLEET:
        d, f = find(folder, ident)
        if not f:
            print(f"{name}: NOT FOUND"); continue
        chain = load_chain(f, d)
        alltxt = "".join(open(c[0], errors="replace").read() for c in chain if c[0])
        walker = "walker" in alltxt
        vx = re.search(r"<view>.*?<x-offset-m[^>]*>([-0-9.]+)<.*?<y-offset-m[^>]*>([-0-9.]+)<.*?<z-offset-m[^>]*>([-0-9.]+)<", alltxt, re.S)
        mp = re.search(r"<model>\s*(?:<[^>]*>[^<]*</[^>]*>\s*)*?<path>([^<]+)</path>", alltxt)
        off = re.search(r"<model>.*?<offsets>(.*?)</offsets>", alltxt, re.S)
        print(f"== {name}: {f}")
        for c in chain:
            print(f"   chain: {c[0]} include={c[1]}")
        print(f"   walker={walker} view={vx.groups() if vx else None} model={mp.group(1) if mp else None}")
        if off: print("   offsets:", re.sub(r"\s+", " ", off.group(1))[:200])
        keys = sorted(set(re.findall(r'<key n="(\d+)"', alltxt)), key=int)
        print("   keys:", keys)
