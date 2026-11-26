#!/usr/bin/env python3
"""Dump a decimated point cloud of an AC3D file in FlightGear model axes.
Usage: ac_points.py file.ac out.txt [max_points_per_object] [dx dy dz]
Each line: object_name x y z   (metres, x aft, y right, z up; dx..dz added)"""
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from ac_info import parse  # noqa: E402


def points(path):
    L = open(path, errors="replace").read().splitlines()
    i = 0
    out = []

    def read_obj(parent_loc):
        nonlocal i
        name, loc, verts, kids = "", [0.0, 0.0, 0.0], [], 0
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
            elif k == "kids":
                kids = int(t[1])
                break
        g = [parent_loc[c] + loc[c] for c in range(3)]
        if verts:
            out.append((name, [(v[0] + g[0], -(v[2] + g[2]), v[1] + g[1]) for v in verts]))
        for _ in range(kids):
            while i < len(L) and not L[i].startswith("OBJECT"):
                i += 1
            i += 1
            read_obj(g)

    while i < len(L) and not L[i].startswith("OBJECT"):
        i += 1
    i += 1
    read_obj([0.0, 0.0, 0.0])
    return out


def main():
    mx = int(sys.argv[3]) if len(sys.argv) > 3 else 400
    off = [float(v) for v in sys.argv[4:7]] if len(sys.argv) > 6 else [0, 0, 0]
    with open(sys.argv[2], "w") as fh:
        for name, vs in points(sys.argv[1]):
            step = max(1, len(vs) // mx)
            for v in vs[::step]:
                fh.write("%s %.3f %.3f %.3f\n" % (name.replace(" ", "_"), v[0] + off[0], v[1] + off[1], v[2] + off[2]))


if __name__ == "__main__":
    main()
