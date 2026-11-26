#!/usr/bin/env python3
"""Cosmic Industries fleet model library (2026-11-26).
Geometry helpers and AC3D writer. Everything is built in FlightGear model axes
(x aft, y right, z up, metres) and written as AC (x, z, -y), because FlightGear
reads AC files with Y up (checked against the stock c172-common.ac).
Helpers come from the Cosmic Ag model generator v2."""
import math

MATERIALS = []   # name, rgb, amb, emis, spec, shi, trans
def mat(name, rgb, amb=0.3, emis=0.0, spec=0.3, shi=30, trans=0.0):
    for i, m in enumerate(MATERIALS):
        if m[0] == name:
            return i
    MATERIALS.append((name, rgb, amb, emis, spec, shi, trans))
    return len(MATERIALS) - 1

SMOOTH_2SIDED = 0x30
FLAT_2SIDED = 0x20

class Obj:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []  # (flags, mat, [idx...])

    def add_v(self, p):
        self.v.append(tuple(p))
        return len(self.v) - 1

    def face(self, idx, mat, flags=SMOOTH_2SIDED):
        self.f.append((flags, mat, list(idx)))


# ---------------------------------------------------------------- primitives
def ring_x(x, cy, cz, ry, rz, n=12, squash=1.0):
    """Ring of points around the X axis (fuselage cross-section).
    squash > 1 flattens the sides toward a rounded box."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        if squash != 1.0:
            c = math.copysign(abs(c) ** (1 / squash), c)
            s = math.copysign(abs(s) ** (1 / squash), s)
        pts.append((x, cy + ry * c, cz + rz * s))
    return pts


def loft(obj, rings, mat, cap_start=True, cap_end=True, flags=SMOOTH_2SIDED):
    """Join rings (each the same point count) with quads; cap the ends."""
    n = len(rings[0])
    base = []
    for r in rings:
        base.append([obj.add_v(p) for p in r])
    for a, b in zip(base, base[1:]):
        for i in range(n):
            j = (i + 1) % n
            obj.face([a[i], a[j], b[j], b[i]], mat, flags)
    if cap_start:
        obj.face(list(reversed(base[0])), mat, FLAT_2SIDED)
    if cap_end:
        obj.face(base[-1], mat, FLAT_2SIDED)


def body_of_revolution(obj, stations, mat, n=12, squash=1.0):
    """stations: list of (x, cz, ry, rz). Zero radius allowed at the ends."""
    rings = []
    for x, cz, ry, rz in stations:
        rings.append(ring_x(x, 0.0, cz, max(ry, 1e-4), max(rz, 1e-4), n, squash))
    loft(obj, rings, mat)


def airfoil(chord, t, n=8):
    """Symmetric section in the x-z plane, LE at x=0, TE at x=chord.
    Returns 2n-2 points going round (upper TE->LE, lower LE->TE)."""
    xs = [(1 - math.cos(math.pi * i / (n - 1))) / 2 for i in range(n)]  # 0..1
    def half(xc):
        return 5 * t * (0.2969 * math.sqrt(xc) - 0.1260 * xc - 0.3516 * xc ** 2
                        + 0.2843 * xc ** 3 - 0.1036 * xc ** 4)
    upper = [(xc * chord, half(xc) * chord) for xc in reversed(xs)]
    lower = [(xc * chord, -half(xc) * chord) for xc in xs[1:-1]]
    return upper + lower


def wing(obj, sections, mat, t=0.12, n=8, vertical=False):
    """sections: list of (x_le, y, z, chord) from one tip to the other
    (or root to tip). vertical=True builds a fin in the x-z plane
    (sections are then (x_le, y, z, chord) with z the span station)."""
    rings = []
    for x_le, y, z, chord in sections:
        pts = []
        for px, pz in airfoil(chord, t, n):
            if vertical:
                pts.append((x_le + px, y + pz, z))
            else:
                pts.append((x_le + px, y, z + pz))
        rings.append(pts)
    loft(obj, rings, mat)


def box(obj, cx, cy, cz, sx, sy, sz, mat):
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    v = [obj.add_v(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
    for q in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        obj.face([v[i] for i in q], mat, FLAT_2SIDED)


def cylinder(obj, p0, p1, r, mat, n=8):
    """Round bar between two points."""
    d = [p1[i] - p0[i] for i in range(3)]
    L = math.sqrt(sum(c * c for c in d))
    d = [c / L for c in d]
    # any vector not parallel to d
    a = (0, 0, 1) if abs(d[2]) < 0.9 else (1, 0, 0)
    u = (d[1] * a[2] - d[2] * a[1], d[2] * a[0] - d[0] * a[2], d[0] * a[1] - d[1] * a[0])
    ul = math.sqrt(sum(c * c for c in u)); u = [c / ul for c in u]
    w = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    rings = []
    for p in (p0, p1):
        ring = []
        for i in range(n):
            ang = 2 * math.pi * i / n
            c, s = math.cos(ang) * r, math.sin(ang) * r
            ring.append(tuple(p[k] + u[k] * c + w[k] * s for k in range(3)))
        rings.append(ring)
    loft(obj, rings, mat)


def disc_x(obj, x, cy, cz, r, mat, n=24):
    """Prop disc facing along X."""
    idx = [obj.add_v((x, cy + r * math.cos(2 * math.pi * i / n),
                      cz + r * math.sin(2 * math.pi * i / n))) for i in range(n)]
    obj.face(idx, mat, FLAT_2SIDED)


def mirror_y(obj_src, name):
    o = Obj(name)
    o.v = [(x, -y, z) for x, y, z in obj_src.v]
    o.f = [(fl, m, list(reversed(ix))) for fl, m, ix in obj_src.f]
    return o


# ---------------------------------------------------------------- writer
def write_ac(path, objects):
    out = ["AC3Db"]
    for name, rgb, amb, emis, spec, shi, trans in MATERIALS:
        e = [c * emis for c in rgb]
        out.append('MATERIAL "%s" rgb %.3f %.3f %.3f amb %.2f %.2f %.2f emis %.3f %.3f %.3f '
                   'spec %.2f %.2f %.2f shi %d trans %.2f'
                   % (name, *rgb, amb, amb, amb, *e, spec, spec, spec, shi, trans))
    out += ["OBJECT world", "kids %d" % len(objects)]
    for o in objects:
        out += ["OBJECT poly", 'name "%s"' % o.name, "crease 50.0", "numvert %d" % len(o.v)]
        for x, y, z in o.v:
            # FlightGear model (x, y, z) -> AC3D (x, z, -y)
            out.append("%.4f %.4f %.4f" % (x, z, -y))
        out.append("numsurf %d" % len(o.f))
        for flags, mat, idx in o.f:
            out += ["SURF 0x%02x" % flags, "mat %d" % mat, "refs %d" % len(idx)]
            out += ["%d 0 0" % i for i in idx]
        out.append("kids 0")
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")




# ---------------------------------------------------------------- additions for the fleet round
def loft_mat(obj, rings, matfn, cap_start=True, cap_end=True, capmat=None):
    """Like loft, but each quad's material comes from matfn(centroid) so one skin can be
    part paint, part glass."""
    n = len(rings[0])
    base = [[obj.add_v(p) for p in r] for r in rings]
    for a, b in zip(base, base[1:]):
        for i in range(n):
            j = (i + 1) % n
            q = [a[i], a[j], b[j], b[i]]
            c = [sum(obj.v[k][d] for k in q) / 4 for d in range(3)]
            obj.face(q, matfn(c))
    cm = capmat if capmat is not None else matfn(rings[0][0])
    if cap_start:
        obj.face(list(reversed(base[0])), cm, FLAT_2SIDED)
    if cap_end:
        obj.face(base[-1], cm, FLAT_2SIDED)


def wheel(obj, cx, cy, cz, r, w, mat, n=14):
    """Tyre: a short fat cylinder around the y axis."""
    rings = []
    for yy, rr in [(cy - w / 2, r * 0.55), (cy - w / 2, r * 0.92), (cy - w * 0.35, r),
                   (cy + w * 0.35, r), (cy + w / 2, r * 0.92), (cy + w / 2, r * 0.55)]:
        rings.append([(cx + rr * math.cos(2 * math.pi * i / n), yy, cz + rr * math.sin(2 * math.pi * i / n))
                      for i in range(n)])
    loft(obj, rings, mat)


def blade(obj, hub, r0, r1, chord, twist_root, twist_tip, angle, mat, xoff=0.0):
    """One flat propeller blade in the y-z plane (prop disc faces -x), at polar angle `angle`."""
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for r, tw, c in [(r0, twist_root, chord), (r1, twist_tip, chord * 0.55)]:
        t = math.radians(tw)
        for s in (-0.5, 0.5):
            # chord direction: tangential (perpendicular to radius) twisted toward x
            tang = (-sa, ca)
            dx = s * c * math.sin(t)
            dt = s * c * math.cos(t)
            pts.append((hub[0] + xoff + dx, hub[1] + r * ca + dt * tang[0], hub[2] + r * sa + dt * tang[1]))
    ids = [obj.add_v(p) for p in pts]
    obj.face([ids[0], ids[1], ids[3], ids[2]], mat, FLAT_2SIDED)
