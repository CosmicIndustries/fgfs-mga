#!/usr/bin/env python3
"""Point-cloud views and ground-clearance pitch sweep for FlightGear models.
Inputs are AC files (read the way FlightGear orients them: AC (x,y,z) -> FG (x,-z,y),
with nested 'loc' offsets) or point files from ac_points.py (name x y z per line).
Spec: path[@dx,dy,dz][!hide1,hide2,...]
  views.png:  fleetview.py views OUT.png TITLE spec...
  ground:     fleetview.py ground OUT.png TITLE PIVOT_X PIVOT_Z MAXDEG TAILNAMES spec...
              pitches nose-up about the main-wheel contact (PIVOT_X, PIVOT_Z) from 0 to MAXDEG,
              reports every part's clearance, plots side views; parts below ground are red.
              TAILNAMES: comma list of objects that are the tail wheel/skid (allowed to touch)."""
import math, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load_ac(path):
    L = open(path, errors="replace").read().splitlines()
    i = 0
    out = {}

    def rd(parent):
        nonlocal i
        name, loc, verts, kids = "", [0, 0, 0], [], 0
        while i < len(L):
            t = L[i].split(); i += 1
            if not t:
                continue
            if t[0] == "name":
                name = " ".join(t[1:]).strip('"')
            elif t[0] == "loc":
                loc = [float(v) for v in t[1:4]]
            elif t[0] == "numvert":
                n = int(t[1])
                verts = [[float(v) for v in L[i + j].split()[:3]] for j in range(n)]
                i += n
            elif t[0] == "kids":
                kids = int(t[1]); break
        g = [parent[c] + loc[c] for c in range(3)]
        if verts:
            out.setdefault(name, []).extend((v[0] + g[0], -(v[2] + g[2]), v[1] + g[1]) for v in verts)
        for _ in range(kids):
            while i < len(L) and not L[i].startswith("OBJECT"):
                i += 1
            i += 1
            rd(g)
    while i < len(L) and not L[i].startswith("OBJECT"):
        i += 1
    i += 1
    rd([0, 0, 0])
    return out


def load(spec):
    hide = []
    if "!" in spec:
        spec, h = spec.split("!", 1); hide = h.split(",")
    off = (0, 0, 0)
    if "@" in spec:
        spec, o = spec.split("@", 1); off = tuple(float(v) for v in o.split(","))
    if spec.endswith(".ac"):
        objs = load_ac(spec)
    else:
        objs = {}
        for l in open(spec):
            n, x, y, z = l.split()
            objs.setdefault(n, []).append((float(x), float(y), float(z)))
    res = {}
    for n, vs in objs.items():
        if any(n == h or (h.endswith("*") and n.startswith(h[:-1])) for h in hide):
            continue
        res[n] = [(x + off[0], y + off[1], z + off[2]) for x, y, z in vs]
    return res


def merged(specs):
    allo = {}
    for s in specs:
        for n, vs in load(s).items():
            allo.setdefault(n, []).extend(vs)
    return allo


def views(out, title, specs):
    objs = merged(specs)
    P = [p for vs in objs.values() for p in vs]
    fig, ax = plt.subplots(1, 3, figsize=(18, 6))
    for a, (i, j, t) in zip(ax, [(0, 2, "side (nose left)"), (1, 2, "front"), (0, 1, "top")]):
        for n, vs in objs.items():
            a.scatter([p[i] for p in vs], [p[j] for p in vs], s=0.6)
        a.set_aspect("equal"); a.set_title(t); a.grid(alpha=0.3)
        a.set_xlabel(["x aft (m)", "y right (m)", "z up (m)"][i]); a.set_ylabel(["x aft", "y right", "z up (m)"][j])
    lo = [min(p[k] for p in P) for k in range(3)]; hi = [max(p[k] for p in P) for k in range(3)]
    fig.suptitle("%s   length %.2f m  span %.2f m  height %.2f m" % (title, hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
    plt.tight_layout(); plt.savefig(out, dpi=60)
    print("wrote", out, "length %.2f span %.2f height %.2f" % (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))


def ground(out, title, px, pz, maxdeg, tails, specs):
    objs = merged(specs)
    tails = [t for t in tails.split(",") if t]
    steps = sorted(set([0] + list(range(2, int(maxdeg) + 1, 2)) + [maxdeg]))
    fig, axes = plt.subplots(len(steps), 1, figsize=(13, 2.3 * len(steps)))
    first_hit = None
    for ax, deg in zip(axes, steps):
        a = math.radians(deg)
        lows = {}
        for n, vs in objs.items():
            pv = [(px + (p[0] - px) * math.cos(a) + (p[2] - pz) * math.sin(a),
                   pz - (p[0] - px) * math.sin(a) + (p[2] - pz) * math.cos(a)) for p in vs]
            # only parts aft of the mains can strike when pitching nose-up
            lows[n] = min(z for x, z in pv) - pz
            bad = lows[n] < -0.02 and n not in tails and not n.lower().startswith(("wheel", "gear", "main", "tire", "tyre"))
            ax.scatter([x for x, z in pv], [z for x, z in pv], s=0.4, color="red" if bad else "tab:blue")
        hits = sorted([(z, n) for n, z in lows.items() if z < -0.02 and n not in tails
                       and not n.lower().startswith(("wheel", "gear", "main", "tire", "tyre"))])
        tw = [lows[t] for t in tails if t in lows]
        tws = (" | tailwheel %.2f m" % min(tw)) if tw else ""
        msg = ("BELOW GROUND: " + ", ".join("%s %.2f" % (n, z) for z, n in hits[:4])) if hits else "clear"
        if hits and first_hit is None:
            first_hit = deg
        aft = sorted((z, n) for n, z in lows.items() if n not in tails)[:3]
        print("%5.1f deg  %-60s lowest: %s%s" % (deg, msg[:60], ", ".join("%s %.2f" % (n, z) for z, n in aft), tws))
        ax.axhline(pz, color="saddlebrown", lw=2)
        ax.set_aspect("equal"); ax.set_title("%s  nose-up %.1f deg: %s%s" % (title, deg, msg[:80], tws), fontsize=9)
        ax.set_ylim(pz - 0.6, None)
    plt.tight_layout(); plt.savefig(out, dpi=55)
    print("first part below ground at:", first_hit, "deg" if first_hit is not None else "(none up to %.1f deg)" % maxdeg)


if __name__ == "__main__":
    if sys.argv[1] == "views":
        views(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        ground(sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6]), sys.argv[7], sys.argv[8:])
