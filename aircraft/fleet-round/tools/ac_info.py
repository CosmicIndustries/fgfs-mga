#!/usr/bin/env python3
"""Print every named object in an AC3D file with its bounding box in
FlightGear model axes (x aft, y right, z up, metres). AC (x,y,z) -> FG (x,-z,y).
Usage: ac_info.py file.ac [name-filter]"""
import sys


def parse(path):
    L = open(path, errors="replace").read().splitlines()
    i = 0
    out = []

    def read_obj(parent_loc, depth):
        nonlocal i
        name, loc, verts, kids, nsurf = "", [0.0, 0.0, 0.0], [], 0, 0
        while i < len(L):
            t = L[i].split()
            i += 1
            if not t:
                continue
            k = t[0]
            if k == "name":
                name = " ".join(t[1:]).strip('"')
            elif k == "loc":
                loc = [float(v) for v in t[1:4]]
            elif k == "numvert":
                n = int(t[1])
                for j in range(n):
                    verts.append([float(v) for v in L[i + j].split()[:3]])
                i += n
            elif k == "numsurf":
                nsurf = int(t[1])
            elif k == "kids":
                kids = int(t[1])
                break
        g = [parent_loc[c] + loc[c] for c in range(3)]
        if verts:
            fg = [(v[0] + g[0], -(v[2] + g[2]), v[1] + g[1]) for v in verts]
            lo = [min(p[c] for p in fg) for c in range(3)]
            hi = [max(p[c] for p in fg) for c in range(3)]
            out.append((depth, name, len(verts), nsurf, lo, hi))
        for _ in range(kids):
            while i < len(L) and not L[i].startswith("OBJECT"):
                i += 1
            i += 1
            read_obj(g, depth + 1)

    while i < len(L) and not L[i].startswith("OBJECT"):
        i += 1
    i += 1
    read_obj([0.0, 0.0, 0.0], 0)
    return out


def main():
    flt = sys.argv[2].lower() if len(sys.argv) > 2 else ""
    rows = parse(sys.argv[1])
    lo = [min(r[4][c] for r in rows) for c in range(3)]
    hi = [max(r[5][c] for r in rows) for c in range(3)]
    print("ALL x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    for d, n, nv, ns, a, b in rows:
        if flt and flt not in n.lower():
            continue
        print("%-34s v%-6d x %6.2f..%6.2f  y %6.2f..%6.2f  z %6.2f..%6.2f" % (n[:34], nv, a[0], b[0], a[1], b[1], a[2], b[2]))


if __name__ == "__main__":
    main()
