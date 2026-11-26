#!/usr/bin/env python3
"""Cosmic Industries fleet round 2026-11-26: rough FlightGear models for the
American Champion Decathlon 8KCAB, Citabria 7GCAA, Air Tractor AT-502B and AT-802.

Each plane gets: Models/<id>.ac (exterior + simple cockpit), Models/<id>.xml (animations,
3D instruments from fgdata), <id>-yasim.xml (YASim flight model) and <id>-set.xml.
Model axes: x aft from the spinner tip, y right, z up from the thrust line (metres).
YASim axes: x forward, y left, z up, same origin: yasim = (-x, -y, z).
Sizes are from published specs (Wikipedia spec tables read 2026-11-26).
Usage: gen_fleet.py OUTROOT [id ...]"""
import math, os, sys
from fleetlib import *

FT = 0.3048


def mats(paint, trim):
    return dict(
        PAINT=mat("paint_" + str(paint), paint, spec=0.45, shi=50),
        TRIM=mat("trim_" + str(trim), trim, spec=0.4),
        GLASS=mat("glass", (0.55, 0.65, 0.72), amb=0.2, spec=0.9, shi=100, trans=0.6),
        DARK=mat("dark", (0.10, 0.10, 0.11), spec=0.3),
        METAL=mat("metal", (0.62, 0.63, 0.65), spec=0.7, shi=60),
        TYRE=mat("tyre", (0.06, 0.06, 0.06), spec=0.1),
        INT=mat("interior", (0.22, 0.22, 0.24), spec=0.1),
        SEAT=mat("seat", (0.30, 0.18, 0.12), spec=0.1),
        PANEL=mat("panel", (0.16, 0.16, 0.17), spec=0.2),
        BLADE=mat("blade", (0.08, 0.08, 0.08), spec=0.3),
        TIP=mat("bladetip", (0.95, 0.85, 0.10)),
        DISC=mat("propdisc", (0.25, 0.25, 0.25), spec=0.0, shi=1, trans=0.82),
    )


# nose ballast (lb) per plane, in SPECS order: decathlon, citabria, at502b, at802
BALLAST_LB = [302, 234, 1257, 1363]

SPECS = {
    "decathlon": dict(
        folder="Cosmic-Decathlon", aircraft_id="decathlon",
        name="American Champion 8KCAB Decathlon (rough)",
        desc="Aerobatic tandem two-seat taildragger used for MGA's upset recovery and aerobatics courses. "
             "Rough model sized from published specs: 32 ft span, 169 sq ft wing, 1,340 lb empty, 1,950 lb gross, "
             "180 hp Lycoming AEIO-360 with a constant-speed prop.",
        paint=(0.93, 0.92, 0.88), trim=(0.70, 0.10, 0.10),
        length=7.00, span=9.80, area=15.71, chord_taper=1.0, wing_z=0.86, wing_le=1.50, dihedral=1.0,
        high=True, flaps=None, aileron=(0.50, 0.97),
        fus=[(0.30, -0.02, 0.30, 0.30), (0.55, 0.0, 0.37, 0.38), (1.20, 0.02, 0.39, 0.45), (1.45, 0.10, 0.39, 0.62),
             (2.00, 0.17, 0.38, 0.66), (2.90, 0.17, 0.37, 0.64), (3.40, 0.17, 0.33, 0.52), (4.50, 0.17, 0.22, 0.34),
             (5.60, 0.18, 0.13, 0.22), (6.35, 0.20, 0.06, 0.12), (6.55, 0.22, 0.02, 0.05)],
        glass=(1.45, 3.30, 0.22), squash=2.2,
        prop_r=0.94, blades=2, spinner=(0.0, 0.30, 0.13),
        main=dict(x=1.30, y=0.92, r=0.21, w=0.13, clearance=0.25, root_y=0.36, root_z=-0.42),
        tail=dict(x=6.45, r=0.075, angle=12.5),
        hstab=dict(le=5.85, z=0.22, semi=1.62, c_root=0.95, c_tip=0.72, elev=0.45),
        fin=dict(root=(5.45, 0.30, 1.00), tip=(6.12, 1.55, 0.50), rudder_to=7.00, rudder_bottom=0.22),
        struts=[((1.62, 2.55, 0.82), (1.62, 0.37, -0.36)), ((2.70, 2.55, 0.82), (1.80, 0.37, -0.36))],
        cockpit=dict(panel_x=1.62, panel_z=0.34, panel_w=0.62, seats=[2.30, 3.05], eye=(2.20, 0.0, 0.62),
                     floor_z=-0.40, turbine=False, stick=True),
        boom=None, exhaust=[(1.10, 0.30, -0.38)],
        fdm=dict(empty=1340, gross=1950, eng="piston", hp=180, rpm=2700, disp=361, comp=8.7, cs=True,
                 min_rpm=1800, max_rpm=2700, prop_cruise_speed=110, prop_cruise_rpm=2500,
                 approach=(60, 7.0, 0.25, 0.0), cruise=(123, 6000, 1.0), fuel_lb=240, stall_aoa=15,
                 camber=0.03, idrag=1.0, ballast_x=0.5, ballast_lb=BALLAST_LB[0], payload=[("Front seat", 2.30, 170), ("Rear seat", 3.05, 0)],
                 hopper=None),
    ),
    "citabria": dict(
        folder="Cosmic-Citabria", aircraft_id="citabria",
        name="American Champion 7GCAA Citabria (rough)",
        desc="Tandem two-seat taildragger used for MGA's tailwheel endorsement. Rough model sized from published specs: "
             "33 ft 5 in span, 165 sq ft wing, 1,037 lb empty, 1,650 lb gross, 150 hp Lycoming O-320 with a fixed-pitch prop.",
        paint=(0.95, 0.80, 0.20), trim=(0.12, 0.12, 0.40),
        length=6.91, span=10.19, area=15.30, chord_taper=1.0, wing_z=0.86, wing_le=1.50, dihedral=1.0,
        high=True, flaps=None, aileron=(0.52, 0.97),
        fus=[(0.30, -0.02, 0.29, 0.29), (0.55, 0.0, 0.36, 0.37), (1.18, 0.02, 0.38, 0.44), (1.45, 0.10, 0.38, 0.61),
             (2.00, 0.17, 0.37, 0.65), (2.90, 0.17, 0.36, 0.63), (3.40, 0.17, 0.32, 0.51), (4.50, 0.17, 0.21, 0.33),
             (5.55, 0.18, 0.12, 0.21), (6.28, 0.20, 0.06, 0.12), (6.48, 0.22, 0.02, 0.05)],
        glass=(1.45, 3.30, 0.22), squash=2.2,
        prop_r=0.94, blades=2, spinner=(0.0, 0.28, 0.12),
        main=dict(x=1.30, y=0.90, r=0.20, w=0.13, clearance=0.24, root_y=0.36, root_z=-0.42),
        tail=dict(x=6.38, r=0.075, angle=12.0),
        hstab=dict(le=5.80, z=0.22, semi=1.60, c_root=0.92, c_tip=0.72, elev=0.45),
        fin=dict(root=(5.40, 0.30, 0.98), tip=(6.05, 1.50, 0.50), rudder_to=6.91, rudder_bottom=0.22),
        struts=[((1.60, 2.65, 0.82), (1.60, 0.36, -0.36)), ((2.62, 2.65, 0.82), (1.78, 0.36, -0.36))],
        cockpit=dict(panel_x=1.62, panel_z=0.34, panel_w=0.60, seats=[2.30, 3.05], eye=(2.20, 0.0, 0.62),
                     floor_z=-0.40, turbine=False, stick=True),
        boom=None, exhaust=[(1.10, 0.30, -0.38)],
        fdm=dict(empty=1037, gross=1650, eng="piston", hp=150, rpm=2700, disp=320, comp=7.0, cs=False,
                 prop_cruise_speed=100, prop_cruise_rpm=2450,
                 approach=(55, 7.5, 0.25, 0.0), cruise=(109, 8000, 1.0), fuel_lb=234, stall_aoa=15,
                 camber=0.06, idrag=1.0, ballast_x=0.5, ballast_lb=BALLAST_LB[1], payload=[("Front seat", 2.30, 170), ("Rear seat", 3.05, 0)],
                 hopper=None),
    ),
    "at502b": dict(
        folder="Cosmic-AT502B", aircraft_id="at502b",
        name="Air Tractor AT-502B (rough)",
        desc="Single-seat turboprop ag plane. Rough model sized from published specs: 52 ft span, 288 sq ft wing, "
             "4,650 lb empty, 10,480 lb max (ag), 750 shp PT6A-34AG, 3-blade 9 ft 3 in prop, 500 gal hopper.",
        paint=(0.95, 0.80, 0.08), trim=(0.10, 0.10, 0.10),
        length=10.21, span=15.85, area=26.76, chord_taper=1.0, wing_z=-0.40, wing_le=3.00, dihedral=3.5,
        high=False, flaps=(0.07, 0.55), aileron=(0.57, 0.98),
        fus=[(0.35, 0.0, 0.30, 0.30), (0.80, 0.0, 0.42, 0.44), (2.40, 0.05, 0.48, 0.55), (2.60, 0.10, 0.50, 0.62),
             (3.20, 0.20, 0.50, 0.76), (4.00, 0.24, 0.48, 0.78), (4.40, 0.28, 0.46, 0.80), (5.60, 0.30, 0.42, 0.78),
             (6.20, 0.32, 0.34, 0.60), (7.50, 0.36, 0.22, 0.40), (8.80, 0.42, 0.13, 0.26), (9.50, 0.46, 0.07, 0.15),
             (9.80, 0.48, 0.02, 0.05)],
        glass=(4.15, 5.65, 0.62), squash=2.0, canopy=(4.10, 5.75, 0.95, 1.28, 0.42),
        prop_r=1.41, blades=3, spinner=(0.0, 0.35, 0.16),
        main=dict(x=2.75, y=1.40, r=0.33, w=0.22, clearance=0.26, root_y=0.48, root_z=-0.45),
        tail=dict(x=9.30, r=0.13, angle=11.5),
        hstab=dict(le=8.60, z=0.48, semi=3.00, c_root=1.15, c_tip=0.85, elev=0.40),
        fin=dict(root=(7.90, 0.55, 1.55), tip=(9.05, 2.00, 0.80), rudder_to=10.21, rudder_bottom=0.30),
        struts=[],
        cockpit=dict(panel_x=4.35, panel_z=0.95, panel_w=0.70, seats=[5.05], eye=(4.95, 0.0, 1.10),
                     floor_z=-0.05, turbine=True, stick=True),
        boom=dict(x=4.85, z=-0.62, semi=7.4), exhaust=[(1.10, 0.46, 0.05)],
        fdm=dict(empty=4650, gross=10480, eng="turbine", hp=750, rpm=2200, min_rpm=1600, max_rpm=2200,
                 prop_cruise_speed=130, prop_cruise_rpm=2000,
                 approach=(80, 6.0, 0.25, 0.5), cruise=(134, 1000, 1.0), fuel_lb=1450, stall_aoa=15,
                 camber=0.05, idrag=1.1, ballast_x=0.5, ballast_lb=BALLAST_LB[2], payload=[("Pilot", 5.05, 190)],
                 hopper=dict(x=3.20, max=4170)),
    ),
    "at802": dict(
        folder="Cosmic-AT802", aircraft_id="at802",
        name="Air Tractor AT-802 (rough)",
        desc="Single-seat turboprop ag plane. Rough model sized from published specs: 59 ft 3 in span, 401 sq ft wing, "
             "6,505 lb empty, 16,000 lb max, 1,350 shp PT6A-67AG, 800 gal hopper.",
        paint=(0.95, 0.80, 0.08), trim=(0.10, 0.10, 0.10),
        length=10.95, span=18.06, area=37.25, chord_taper=1.0, wing_z=-0.45, wing_le=3.30, dihedral=3.5,
        high=False, flaps=(0.07, 0.56), aileron=(0.58, 0.98),
        fus=[(0.38, 0.0, 0.33, 0.33), (0.90, 0.0, 0.46, 0.48), (2.70, 0.06, 0.52, 0.58), (2.90, 0.12, 0.55, 0.66),
             (3.60, 0.22, 0.56, 0.82), (4.40, 0.27, 0.54, 0.84), (4.80, 0.30, 0.50, 0.86), (6.05, 0.32, 0.46, 0.84),
             (6.70, 0.35, 0.37, 0.64), (8.00, 0.40, 0.24, 0.42), (9.40, 0.46, 0.14, 0.28), (10.15, 0.50, 0.07, 0.16),
             (10.45, 0.52, 0.02, 0.05)],
        glass=(4.55, 6.10, 0.66), squash=2.0, canopy=(4.50, 6.20, 1.03, 1.38, 0.46),
        prop_r=1.45, blades=5, spinner=(0.0, 0.38, 0.18),
        main=dict(x=3.05, y=1.60, r=0.38, w=0.26, clearance=0.28, root_y=0.52, root_z=-0.50),
        tail=dict(x=9.95, r=0.14, angle=11.0),
        hstab=dict(le=9.25, z=0.52, semi=3.40, c_root=1.30, c_tip=0.95, elev=0.40),
        fin=dict(root=(8.45, 0.60, 1.70), tip=(9.70, 2.25, 0.85), rudder_to=10.95, rudder_bottom=0.32),
        struts=[],
        cockpit=dict(panel_x=4.75, panel_z=1.02, panel_w=0.74, seats=[5.45], eye=(5.35, 0.0, 1.18),
                     floor_z=0.0, turbine=True, stick=True),
        boom=dict(x=5.40, z=-0.68, semi=8.4), exhaust=[(1.20, 0.50, 0.06)],
        fdm=dict(empty=6505, gross=16000, eng="turbine", hp=1350, rpm=1700, min_rpm=1450, max_rpm=1700,
                 prop_cruise_speed=170, prop_cruise_rpm=1600,
                 approach=(85, 6.0, 0.25, 0.5), cruise=(192, 8000, 1.0), fuel_lb=1700, stall_aoa=15,
                 camber=0.05, idrag=1.1, ballast_x=0.5, ballast_lb=BALLAST_LB[3], payload=[("Pilot", 5.45, 190)],
                 hopper=dict(x=3.60, max=6670)),
    ),
}


def ground_z(s):
    return -(s["prop_r"] + s["main"]["clearance"])


def tail_contact_z(s):
    m, t = s["main"], s["tail"]
    return ground_z(s) + (t["x"] - m["x"]) * math.tan(math.radians(t["angle"]))


def build(s):
    M = mats(s["paint"], s["trim"])
    P, T, G = M["PAINT"], M["TRIM"], M["GLASS"]
    objs = []
    # ---------------- fuselage, with glass over the cabin
    fus = Obj("Fuselage")
    gx0, gx1, gz = s["glass"]
    rings = [ring_x(x, 0.0, zc, hw, hh, 16, s["squash"]) for x, zc, hw, hh in s["fus"]]

    def fmat(c):
        if gx0 <= c[0] <= gx1 and c[2] > gz and "canopy" not in s:
            return G
        return P
    loft_mat(fus, rings, fmat, capmat=P)
    objs.append(fus)
    # stripe along the side
    stripe = Obj("Stripe")
    for side in (-1, 1):
        xs = [st for st in s["fus"] if st[0] > s["fus"][1][0]]
        for a, b in zip(xs, xs[1:]):
            za, zb = a[1] - a[3] * 0.15, b[1] - b[3] * 0.15
            ya, yb = side * (a[2] + 0.004), side * (b[2] + 0.004)
            ids = [stripe.add_v(p) for p in [(a[0], ya, za - 0.04), (b[0], yb, zb - 0.04),
                                              (b[0], yb, zb + 0.04), (a[0], ya, za + 0.04)]]
            stripe.face(ids, T, FLAT_2SIDED)
    objs.append(stripe)
    # Air Tractor bubble canopy
    if "canopy" in s:
        x0, x1, zb, zt, hw = s["canopy"]
        can = Obj("Canopy")
        st = []
        for f in [0.0, 0.08, 0.30, 0.65, 0.92, 1.0]:
            x = x0 + (x1 - x0) * f
            h = (zt - zb) * (math.sin(math.pi * min(1.0, f * 1.15)) ** 0.5 if f < 0.95 else 0.25)
            w = hw * (0.55 + 0.45 * math.sin(math.pi * f) ** 0.4)
            st.append((x, zb, w, max(0.02, h)))
        can_rings = []
        for x, z0, w, h in st:
            ring = []
            for i in range(13):
                a = math.pi * i / 12
                ring.append((x, -w * math.cos(a), z0 + h * math.sin(a)))
            can_rings.append(ring)
        loft(can, can_rings, G, cap_start=False, cap_end=False)
        objs.append(can)
    # ---------------- spinner, prop blades, prop disc
    sx0, sx1, sr = s["spinner"]
    spin = Obj("Spinner")
    body_of_revolution(spin, [(sx0, 0, 0.002, 0.002), (sx0 + 0.08, 0, sr * 0.75, sr * 0.75), (sx1 * 0.7, 0, sr, sr),
                              (sx1, 0, sr, sr)], M["METAL"], n=12)
    objs.append(spin)
    props = Obj("PropBlades")
    for k in range(s["blades"]):
        a = 2 * math.pi * k / s["blades"] + 0.3
        blade(props, (0.12, 0.0, 0.0), sr * 0.8, s["prop_r"] - 0.06, 0.18 * s["prop_r"] / 0.94 * (0.8 if s["blades"] > 3 else 1),
              35, 12, a, M["BLADE"])
        blade(props, (0.12, 0.0, 0.0), s["prop_r"] - 0.06, s["prop_r"], 0.10, 12, 10, a, M["TIP"])
    objs.append(props)
    disc = Obj("PropDisc")
    disc_x(disc, 0.12, 0.0, 0.0, s["prop_r"], M["DISC"], n=32)
    objs.append(disc)
    # exhausts
    ex = Obj("Exhaust")
    for x, y, z in s["exhaust"]:
        for sd in (-1, 1):
            cylinder(ex, (x, sd * (y - 0.06), z), (x + 0.18, sd * (y + 0.04), z - 0.06), 0.05, M["DARK"], n=8)
    objs.append(ex)
    # ---------------- wing: inner (full chord), outer front, ailerons, flaps
    span, area = s["span"], s["area"]
    chord = area / span
    semi = span / 2
    le, wz, dih = s["wing_le"], s["wing_z"], math.radians(s["dihedral"])
    t = 0.12 if s["high"] else 0.15
    a0, a1 = s["aileron"]
    f0, f1 = s["flaps"] if s["flaps"] else (None, None)

    def zat(y):
        return wz + abs(y) * math.tan(dih)
    hinge = 0.75
    for side, nm in ((-1, "Left"), (1, "Right")):
        w = Obj(nm + "Wing")
        root_y = 0.0 if s["high"] else 0.0
        # stations along the span where the trailing edge changes
        cuts = [0.0]
        if f0 is not None:
            cuts += [f0 * semi, f1 * semi]
        cuts += [a0 * semi, min(a1 * semi, semi - 0.12), semi - 0.12]
        cuts = sorted(set(round(c, 4) for c in cuts))
        for ya, yb in zip(cuts, cuts[1:]):
            mid = (ya + yb) / 2 / semi
            movable = (a0 <= mid <= a1) or (f0 is not None and f0 <= mid <= f1)
            c_front = chord * (hinge if movable else 1.0)
            tt = t / (hinge if movable else 1.0)
            secs = [(le, side * ya, zat(ya), c_front), (le, side * yb, zat(yb), c_front)]
            if side < 0:
                secs = secs[::-1]
            wing(w, secs, P, t=tt, n=8)
        # rounded tip cap
        tip = semi - 0.12
        cap = [(le + chord * 0.12, side * semi, zat(semi), chord * 0.72),
               (le, side * tip, zat(tip), chord)]
        if side > 0:
            cap = cap[::-1]
        wing(w, cap, P, t=t * 0.8, n=8)
        objs.append(w)
        ail = Obj(nm + "Aileron")
        secs = [(le + chord * hinge, side * a0 * semi, zat(a0 * semi), chord * (1 - hinge)),
                (le + chord * hinge, side * min(a1 * semi, semi - 0.12), zat(semi - 0.12), chord * (1 - hinge))]
        wing(ail, secs if side > 0 else secs[::-1], T if not s["high"] else P, t=0.10, n=6)
        objs.append(ail)
        if f0 is not None:
            fl = Obj(nm + "Flap")
            secs = [(le + chord * hinge, side * f0 * semi, zat(f0 * semi), chord * (1 - hinge)),
                    (le + chord * hinge, side * f1 * semi, zat(f1 * semi), chord * (1 - hinge))]
            wing(fl, secs if side > 0 else secs[::-1], P, t=0.10, n=6)
            objs.append(fl)
    # struts
    if s["struts"]:
        st = Obj("Struts")
        for (p0, p1) in s["struts"]:
            for sd in (-1, 1):
                cylinder(st, (p0[0], sd * p0[1], p0[2]), (p1[0], sd * p1[1], p1[2]), 0.025, P, n=6)
        objs.append(st)
    # spray boom with nozzles
    if s.get("boom"):
        b = s["boom"]
        boom = Obj("SprayBoom")
        cylinder(boom, (b["x"], -b["semi"], b["z"] + b["semi"] * math.tan(dih) * 0.9),
                 (b["x"], 0.0, b["z"]), 0.025, M["METAL"], n=6)
        cylinder(boom, (b["x"], 0.0, b["z"]), (b["x"], b["semi"], b["z"] + b["semi"] * math.tan(dih) * 0.9),
                 0.025, M["METAL"], n=6)
        for k in range(-int(b["semi"] / 0.5), int(b["semi"] / 0.5) + 1):
            y = k * 0.5
            zz = b["z"] + abs(y) * math.tan(dih) * 0.9
            cylinder(boom, (b["x"], y, zz), (b["x"] + 0.02, y, zz - 0.07), 0.008, M["DARK"], n=4)
        # hangers to the wing
        for y in (-b["semi"] * 0.7, -b["semi"] * 0.3, b["semi"] * 0.3, b["semi"] * 0.7):
            zz = b["z"] + abs(y) * math.tan(dih) * 0.9
            cylinder(boom, (b["x"], y, zz), (b["x"] - 0.15, y, zat(y) - 0.08), 0.012, M["METAL"], n=4)
        objs.append(boom)
    # ---------------- tail
    h = s["hstab"]
    for side, nm in ((-1, "Left"), (1, "Right")):
        stab = Obj(nm + "Stabilizer")
        secs = [(h["le"], side * 0.0, h["z"], h["c_root"] * (1 - h["elev"])),
                (h["le"] + (h["c_root"] - h["c_tip"]) * 0.5, side * h["semi"], h["z"], h["c_tip"] * (1 - h["elev"]))]
        wing(stab, secs if side > 0 else secs[::-1], P, t=0.12 / (1 - h["elev"]), n=6)
        objs.append(stab)
    elev = Obj("Elevator")
    hx = h["le"] + h["c_root"] * (1 - h["elev"])
    for side in (-1, 1):
        secs = [(hx, side * 0.05, h["z"], h["c_root"] * h["elev"]),
                (hx, side * h["semi"], h["z"], h["c_tip"] * h["elev"] * 1.15)]
        wing(elev, secs if side > 0 else secs[::-1], T if not s["high"] else P, t=0.10, n=6)
    objs.append(elev)
    f = s["fin"]
    (rx, rz, rc), (tx, tz, tc) = f["root"], f["tip"]
    fin = Obj("Fin")
    wing(fin, [(rx, 0, rz, rc), (tx, 0, tz, tc)], P, t=0.11, n=8, vertical=True)
    objs.append(fin)
    rud = Obj("Rudder")
    r_root_x, r_tip_x = rx + rc, tx + tc
    wing(rud, [(r_root_x, 0, f["rudder_bottom"], f["rudder_to"] - r_root_x - 0.05),
               (r_root_x, 0, rz, f["rudder_to"] - r_root_x),
               (r_tip_x, 0, tz + 0.04, max(0.25, f["rudder_to"] - r_tip_x - 0.08))], T, t=0.09, n=6, vertical=True)
    objs.append(rud)
    # ---------------- landing gear
    m = s["main"]
    gz_ = ground_z(s)
    axle_z = gz_ + m["r"]
    gear = Obj("GearLegs")
    for sd in (-1, 1):
        cylinder(gear, (m["x"] + 0.03, sd * m["root_y"], m["root_z"]), (m["x"], sd * (m["y"] - m["w"] * 0.7), axle_z),
                 0.035 * (1.4 if not s["high"] else 1.0), M["METAL"] if s["high"] else P, n=6)
    objs.append(gear)
    for sd, nm in ((-1, "WheelL"), (1, "WheelR")):
        wh = Obj(nm)
        wheel(wh, m["x"], sd * m["y"], axle_z, m["r"], m["w"], M["TYRE"])
        objs.append(wh)
    tl = s["tail"]
    tcz = tail_contact_z(s)
    tw = Obj("TailWheel")
    wheel(tw, tl["x"], 0.0, tcz + tl["r"], tl["r"], tl["r"] * 0.7, M["TYRE"], n=10)
    objs.append(tw)
    tleg = Obj("TailWheelLeg")
    # fuselage bottom just ahead of the tailwheel
    fz = None
    for (xa, za, wa, ha), (xb, zb, wb, hb) in zip(s["fus"], s["fus"][1:]):
        if xa <= tl["x"] - 0.30 <= xb:
            u = (tl["x"] - 0.30 - xa) / (xb - xa)
            fz = (za + (zb - za) * u) - (ha + (hb - ha) * u) * 0.9
    cylinder(tleg, (tl["x"] - 0.30, 0, fz), (tl["x"], 0, tcz + tl["r"]), 0.02, M["METAL"], n=5)
    objs.append(tleg)
    # ---------------- cockpit
    c = s["cockpit"]
    ck = Obj("CockpitInterior")
    box(ck, c["panel_x"] - 0.02, 0, c["panel_z"], 0.04, c["panel_w"], 0.24, M["PANEL"])
    box(ck, c["panel_x"] - 0.10, 0, c["panel_z"] + 0.13, 0.20, c["panel_w"] + 0.02, 0.03, M["PANEL"])  # glareshield
    box(ck, (c["panel_x"] + c["seats"][-1]) / 2 + 0.3, 0, c["floor_z"], c["seats"][-1] - c["panel_x"] + 0.6,
        c["panel_w"] * 0.95, 0.02, M["INT"])
    for sx in c["seats"]:
        box(ck, sx, 0, c["floor_z"] + 0.18, 0.45, 0.44, 0.10, M["SEAT"])
        box(ck, sx + 0.24, 0, c["floor_z"] + 0.50, 0.08, 0.44, 0.60, M["SEAT"])
    objs.append(ck)
    stick = Obj("Stick")
    sx = c["seats"][0] - 0.42
    cylinder(stick, (sx, 0, c["floor_z"]), (sx, 0, c["floor_z"] + 0.55), 0.012, M["DARK"], n=6)
    box(stick, sx, 0, c["floor_z"] + 0.57, 0.04, 0.04, 0.08, M["DARK"])
    objs.append(stick)
    thr = Obj("ThrottleLever")
    tx_ = c["seats"][0] - 0.30
    cylinder(thr, (tx_, -0.30, c["floor_z"] + 0.45), (tx_ - 0.10, -0.30, c["floor_z"] + 0.55), 0.008, M["DARK"], n=5)
    box(thr, tx_ - 0.11, -0.30, c["floor_z"] + 0.56, 0.03, 0.03, 0.03, M["DARK"])
    objs.append(thr)
    return objs


INSTR_PISTON = [("asi/asi.xml", -1, 1), ("ai/ai.xml", 0, 1), ("alt/alt.xml", 1, 1),
                ("tc/tc.xml", -1, 0), ("hi/hi.xml", 0, 0), ("vsi/vsi.xml", 1, 0), ("tach/tach.xml", 2, 1)]


def model_xml(s):
    c = s["cockpit"]
    ins = []
    for path, col, row in INSTR_PISTON:
        y = -0.12 + col * 0.095
        z = c["panel_z"] - 0.05 + row * 0.095
        ins.append("""
	<model>
		<path>Aircraft/Instruments-3d/%s</path>
		<offsets><x-m>%.3f</x-m><y-m>%.3f</y-m><z-m>%.3f</z-m></offsets>
	</model>""" % (path, c["panel_x"] + 0.005, y, z))
    ins.append("""
	<model>
		<path>Aircraft/Instruments-3d/comp/comp.xml</path>
		<offsets><x-m>%.3f</x-m><y-m>0</y-m><z-m>%.3f</z-m></offsets>
	</model>""" % (c["panel_x"] - 0.05, c["panel_z"] + 0.15))
    rpm_prop = "engines/engine[0]/rpm"
    flaps = ""
    if s["flaps"]:
        f0, f1 = s["flaps"]
        chord = s["area"] / s["span"]
        hx = s["wing_le"] + chord * 0.75
        for nm, sd in (("Left", -1), ("Right", 1)):
            flaps += """
	<animation>
		<type>rotate</type>
		<object-name>%sFlap</object-name>
		<property>surface-positions/flap-pos-norm</property>
		<factor>30</factor>
		<axis><x1-m>%.3f</x1-m><y1-m>%.3f</y1-m><z1-m>%.3f</z1-m><x2-m>%.3f</x2-m><y2-m>%.3f</y2-m><z2-m>%.3f</z2-m></axis>
	</animation>""" % (nm, hx, sd * 0.0, s["wing_z"], hx, sd * 5.0, s["wing_z"] + 5.0 * math.tan(math.radians(s["dihedral"])))
    chord = s["area"] / s["span"]
    hx = s["wing_le"] + chord * 0.75
    dz = 5.0 * math.tan(math.radians(s["dihedral"]))
    h = s["hstab"]
    ehx = h["le"] + h["c_root"] * (1 - h["elev"])
    f = s["fin"]
    r0 = (f["root"][0] + f["root"][2], f["root"][1])
    r1 = (f["tip"][0] + f["tip"][2], f["tip"][1])
    return """<?xml version="1.0"?>
<!-- %s. Cosmic Industries fleet round 2026-11-26. Rough model generated by gen_fleet.py. -->
<PropertyList>
	<path>%s.ac</path>

	<animation>
		<type>select</type>
		<object-name>PropBlades</object-name>
		<condition><less-than><property>%s</property><value>500</value></less-than></condition>
	</animation>
	<animation>
		<type>select</type>
		<object-name>PropDisc</object-name>
		<condition><greater-than-equals><property>%s</property><value>500</value></greater-than-equals></condition>
	</animation>
	<animation>
		<type>spin</type>
		<object-name>PropBlades</object-name>
		<object-name>Spinner</object-name>
		<property>%s</property>
		<factor>1</factor>
		<center><x-m>0.12</x-m><y-m>0</y-m><z-m>0</z-m></center>
		<axis><x>-1</x><y>0</y><z>0</z></axis>
	</animation>

	<animation>
		<type>rotate</type>
		<object-name>LeftAileron</object-name>
		<property>surface-positions/left-aileron-pos-norm</property>
		<factor>20</factor>
		<axis><x1-m>%.3f</x1-m><y1-m>0</y1-m><z1-m>%.3f</z1-m><x2-m>%.3f</x2-m><y2-m>-5</y2-m><z2-m>%.3f</z2-m></axis>
	</animation>
	<animation>
		<type>rotate</type>
		<object-name>RightAileron</object-name>
		<property>surface-positions/right-aileron-pos-norm</property>
		<factor>-20</factor>
		<axis><x1-m>%.3f</x1-m><y1-m>0</y1-m><z1-m>%.3f</z1-m><x2-m>%.3f</x2-m><y2-m>5</y2-m><z2-m>%.3f</z2-m></axis>
	</animation>%s
	<animation>
		<type>rotate</type>
		<object-name>Elevator</object-name>
		<property>surface-positions/elevator-pos-norm</property>
		<factor>25</factor>
		<center><x-m>%.3f</x-m><y-m>0</y-m><z-m>%.3f</z-m></center>
		<axis><x>0</x><y>1</y><z>0</z></axis>
	</animation>
	<animation>
		<type>rotate</type>
		<object-name>Rudder</object-name>
		<property>surface-positions/rudder-pos-norm</property>
		<factor>25</factor>
		<axis><x1-m>%.3f</x1-m><y1-m>0</y1-m><z1-m>%.3f</z1-m><x2-m>%.3f</x2-m><y2-m>0</y2-m><z2-m>%.3f</z2-m></axis>
	</animation>
	<animation>
		<type>rotate</type>
		<object-name>Stick</object-name>
		<property>controls/flight/elevator</property>
		<factor>15</factor>
		<center><x-m>%.3f</x-m><y-m>0</y-m><z-m>%.3f</z-m></center>
		<axis><x>0</x><y>1</y><z>0</z></axis>
	</animation>
	<animation>
		<type>rotate</type>
		<object-name>Stick</object-name>
		<property>controls/flight/aileron</property>
		<factor>15</factor>
		<center><x-m>%.3f</x-m><y-m>0</y-m><z-m>%.3f</z-m></center>
		<axis><x>1</x><y>0</y><z>0</z></axis>
	</animation>
	<animation>
		<type>translate</type>
		<object-name>ThrottleLever</object-name>
		<property>controls/engines/engine[0]/throttle</property>
		<factor>-0.08</factor>
		<axis><x>1</x><y>0</y><z>0</z></axis>
	</animation>
	<animation>
		<type>rotate</type>
		<object-name>TailWheel</object-name>
		<property>surface-positions/rudder-pos-norm</property>
		<factor>-20</factor>
		<center><x-m>%.3f</x-m><y-m>0</y-m><z-m>0</z-m></center>
		<axis><x>0</x><y>0</y><z>1</z></axis>
	</animation>
%s
</PropertyList>
""" % (s["name"], s["folder"], rpm_prop, rpm_prop, rpm_prop,
       hx, s["wing_z"], hx, s["wing_z"] + dz, hx, s["wing_z"], hx, s["wing_z"] + dz, flaps,
       ehx, h["z"], r0[0], r0[1], r1[0], r1[1],
       c["seats"][0] - 0.42, c["floor_z"], c["seats"][0] - 0.42, c["floor_z"],
       s["tail"]["x"], "".join(ins))


def yasim_xml(s):
    d = s["fdm"]
    Y = lambda x, y, z: 'x="%.3f" y="%.3f" z="%.3f"' % (-x, -y, z)
    chord = s["area"] / s["span"]
    semi = s["span"] / 2
    le, wz = s["wing_le"], s["wing_z"]
    fus_len = s["fus"][-1][0] - s["fus"][0][0]
    maxw = max(st[2] for st in s["fus"]) * 2
    c = s["cockpit"]
    m, tl, h, f = s["main"], s["tail"], s["hstab"], s["fin"]
    gz = ground_z(s)
    tz = tail_contact_z(s)
    a_spd, a_aoa, a_thr, a_flap = d["approach"]
    c_spd, c_alt, c_thr = d["cruise"]
    flaps = ""
    if s["flaps"]:
        flaps = """
    <flap0 start="%.2f" end="%.2f" lift="1.45" drag="1.8"/>""" % s["flaps"]
    ail = """
    <flap1 start="%.2f" end="%.2f" lift="1.3" drag="1.1"/>""" % s["aileron"]
    if d["eng"] == "piston":
        eng = """
    <piston-engine eng-power="%d" eng-rpm="%d" displacement="%d" compression="%.1f">
      <control-input axis="/controls/engines/engine[0]/magnetos" control="MAGNETOS"/>
      <control-input axis="/controls/engines/engine[0]/throttle" control="THROTTLE"/>
      <control-input axis="/controls/engines/engine[0]/starter" control="STARTER"/>
      <control-input axis="/controls/engines/engine[0]/mixture" control="MIXTURE"/>
    </piston-engine>""" % (d["hp"], d["rpm"], d["disp"], d["comp"])
        cs = ""
        if d.get("cs"):
            cs = ' min-rpm="%d" max-rpm="%d"' % (d["min_rpm"], d["max_rpm"])
            eng += """
    <control-input axis="/controls/engines/engine[0]/propeller-pitch" control="ADVANCE"/>"""
        mass_eng = {180: 380, 150: 300}.get(d["hp"], 350)
    else:
        eng = """
    <turbine-engine eng-power="%d" eng-rpm="%d" alt="0" flat-rating="%d" min-n2="52" max-n2="101" bsfc="0.60">
      <control-input axis="/controls/engines/engine[0]/throttle" control="THROTTLE"/>
      <control-input axis="/controls/engines/engine[0]/condition" control="CONDLEVER"/>
      <control-input axis="/controls/engines/engine[0]/starter" control="STARTER"/>
    </turbine-engine>
    <control-input axis="/controls/engines/engine[0]/propeller-pitch" control="ADVANCE"/>""" % (
            int(d["hp"] * 1.15), d["rpm"], d["hp"])
        cs = ' min-rpm="%d" max-rpm="%d" fine-stop="0.40" coarse-stop="2.5"' % (d["min_rpm"], d["max_rpm"])
        mass_eng = 650 if d["hp"] < 1000 else 900
    hopper = ""
    weights = ""
    for i, (nm, x, w) in enumerate(d["payload"]):
        weights += '\n  <weight %s mass-prop="/sim/weight[%d]/weight-lb"/>' % (Y(x, 0, c["floor_z"] + 0.35), i)
    if d["hopper"]:
        weights += '\n  <weight %s mass-prop="/sim/weight[%d]/weight-lb"/>' % (Y(d["hopper"]["x"], 0, 0.2), len(d["payload"]))
    return """<?xml version="1.0"?>
<!-- %s: YASim flight model (surface x/y/z are YASim mid-chord root points), Cosmic Industries fleet round 2026-11-26.
     Solved by YASim from published figures: approach %d kt at %.1f deg AoA, cruise %d kt at %d ft.
     Empty %d lb, gross %d lb. Model x aft = YASim -x. -->
<airplane mass="%d" version="YASIM_VERSION_CURRENT">

  <approach speed="%d" aoa="%.1f" fuel="0.3">
    <control-setting axis="/controls/engines/engine[0]/throttle" value="%.2f"/>
    <control-setting axis="/controls/engines/engine[0]/mixture" value="1"/>
    <control-setting axis="/controls/engines/engine[0]/condition" value="1"/>
    <control-setting axis="/controls/engines/engine[0]/propeller-pitch" value="1"/>
    <control-setting axis="/controls/flight/flaps" value="%.2f"/>
    <solve-weight idx="0" weight="%d"/>
  </approach>

  <cruise speed="%d" alt="%d" fuel="0.5">
    <control-setting axis="/controls/engines/engine[0]/throttle" value="%.2f"/>
    <control-setting axis="/controls/engines/engine[0]/mixture" value="1"/>
    <control-setting axis="/controls/engines/engine[0]/condition" value="1"/>
    <control-setting axis="/controls/engines/engine[0]/propeller-pitch" value="0.9"/>
    <control-setting axis="/controls/flight/flaps" value="0"/>
    <solve-weight idx="0" weight="%d"/>
  </cruise>

  <cockpit %s/>

  <fuselage ax="%.3f" ay="0" az="%.3f" bx="%.3f" by="0" bz="%.3f" width="%.2f" taper="0.35" midpoint="0.3"/>

  <wing %s length="%.3f" chord="%.3f" sweep="0" dihedral="%.1f" camber="%.3f" incidence="1.5" twist="-1.5" taper="%.2f" idrag="%.2f">
    <stall aoa="%d" width="4" peak="1.5"/>%s%s
    <control-input axis="/controls/flight/flaps" control="FLAP0"/>
    <control-input axis="/controls/flight/aileron" control="FLAP1" split="true"/>
    <control-input axis="/controls/flight/aileron-trim" control="FLAP1" split="true"/>
    <control-output control="FLAP0" prop="/surface-positions/flap-pos-norm"/>
    <control-output control="FLAP1" side="left" prop="/surface-positions/left-aileron-pos-norm"/>
    <control-output control="FLAP1" side="right" prop="/surface-positions/right-aileron-pos-norm"/>
    <control-speed control="FLAP0" transition-time="6"/>
  </wing>

  <hstab %s length="%.3f" chord="%.3f" sweep="0" taper="%.2f" incidence="0">
    <stall aoa="16" width="4" peak="1.5"/>
    <flap0 start="0" end="1" lift="1.9" drag="1.2"/>
    <control-input axis="/controls/flight/elevator" control="FLAP0"/>
    <control-input axis="/controls/flight/elevator-trim" control="FLAP0"/>
    <control-output control="FLAP0" prop="/surface-positions/elevator-pos-norm"/>
  </hstab>

  <vstab %s length="%.3f" chord="%.3f" sweep="%.1f" taper="%.2f">
    <stall aoa="16" width="4" peak="1.5"/>
    <flap0 start="0" end="1" lift="1.4" drag="1.2"/>
    <control-input axis="/controls/flight/rudder" control="FLAP0" invert="true"/>
    <control-input axis="/controls/flight/rudder-trim" control="FLAP0" invert="true"/>
    <control-output control="FLAP0" prop="/surface-positions/rudder-pos-norm" min="1" max="-1"/>
  </vstab>

  <propeller %s mass="%d" moment="%.1f" radius="%.3f" cruise-speed="%d" cruise-rpm="%d" cruise-alt="%d"
             cruise-power="%d" takeoff-power="%d" takeoff-rpm="%d"%s>
    <actionpt %s/>%s
  </propeller>

  <!-- main gear (spring steel legs) and steerable tailwheel; tail sits on its wheel at %.1f deg -->
  <gear %s compression="0.12" spring="0.9" damp="1.2">
    <control-input axis="/controls/gear/brake-left" control="BRAKE"/>
    <control-input axis="/controls/gear/brake-parking" control="BRAKE"/>
  </gear>
  <gear %s compression="0.12" spring="0.9" damp="1.2">
    <control-input axis="/controls/gear/brake-right" control="BRAKE"/>
    <control-input axis="/controls/gear/brake-parking" control="BRAKE"/>
  </gear>
  <gear %s compression="0.06" spring="0.6" damp="1.5" sfric="0.8" dfric="0.6">
    <control-input axis="/controls/flight/rudder" control="STEER" square="true" src0="-1" src1="1" dst0="-0.45" dst1="0.45"/>
  </gear>

  <tank %s capacity="%d"/>
  <tank %s capacity="%d"/>
%s
  <!-- nose ballast: engine and firewall-forward mass, tuned with the YASim solver to put the CG near 25-28%% MAC -->
  <ballast %s mass="%d"/>
</airplane>
""" % (s["name"], a_spd, a_aoa, c_spd, c_alt, d["empty"], d["gross"], d["empty"],
       a_spd, a_aoa, a_thr, a_flap, d["payload"][0][2], c_spd, c_alt, c_thr, d["payload"][0][2],
       Y(*c["eye"]),
       -s["fus"][0][0], 0.0, -s["fus"][-1][0], s["fus"][-1][1], maxw,
       Y(le + chord * 0.5, 0, wz), semi, chord, s["dihedral"], d["camber"],
       s["chord_taper"], d["idrag"], d["stall_aoa"], flaps, ail,
       Y(h["le"] + h["c_root"] * 0.5, 0, h["z"]), h["semi"], h["c_root"], h["c_tip"] / h["c_root"],
       Y(f["root"][0] + (f["root"][2] + 0.4) * 0.5, 0, f["root"][1]), f["tip"][1] - f["root"][1], f["root"][2] + 0.4,
       math.degrees(math.atan2(f["tip"][0] - f["root"][0], f["tip"][1] - f["root"][1])),
       (f["tip"][2] + 0.3) / (f["root"][2] + 0.4),
       Y(0.6, 0, 0), mass_eng, (s["prop_r"] ** 2) * 25 / 3 * (1 if d["eng"] == "piston" else 2), s["prop_r"],
       d["prop_cruise_speed"], d["prop_cruise_rpm"], c_alt, int(d["hp"] * 0.75), d["hp"], d.get("max_rpm", d["rpm"]), cs,
       Y(0.12, 0, 0), eng, tl["angle"],
       Y(m["x"], -m["y"], gz), Y(m["x"], m["y"], gz), Y(tl["x"], 0, tz),
       Y(le + chord * 0.4, -semi * 0.3, wz), d["fuel_lb"] // 2, Y(le + chord * 0.4, semi * 0.3, wz), d["fuel_lb"] // 2,
       weights, Y(d["ballast_x"], 0, 0), d["ballast_lb"])


def set_xml(s):
    d = s["fdm"]
    c = s["cockpit"]
    w = ""
    pl = list(d["payload"])
    if d["hopper"]:
        pl.append(("Hopper load", d["hopper"]["x"], 0))
    for i, (nm, x, wt) in enumerate(pl):
        mx = d["hopper"]["max"] if (d["hopper"] and nm.startswith("Hopper")) else 300
        w += """
		<weight n="%d">
			<name>%s</name>
			<weight-lb>%d</weight-lb>
			<max-lb>%d</max-lb>
		</weight>""" % (i, nm, wt, mx)
    eng_state = """
			<engine n="0">
				<magnetos type="int">3</magnetos>
				<mixture type="double">1</mixture>
				<condition type="double">1</condition>
				<propeller-pitch type="double">1</propeller-pitch>
			</engine>"""
    return """<?xml version="1.0"?>
<!-- %s. Cosmic Industries fleet round 2026-11-26. -->
<PropertyList>
	<sim>
		<description>%s</description>
		<long-description>%s</long-description>
		<author>Cosmic Industries (rough model, generated)</author>
		<status>alpha</status>
		<aircraft-version>0.1</aircraft-version>
		<flight-model>yasim</flight-model>
		<aero>%s-yasim</aero>
		<fuel-fraction>0.6</fuel-fraction>
		<model>
			<path>Aircraft/%s/Models/%s.xml</path>
		</model>
		<view n="0">
			<internal archive="y">true</internal>
			<config>
				<x-offset-m archive="y">%.3f</x-offset-m>
				<y-offset-m archive="y">%.3f</y-offset-m>
				<z-offset-m archive="y">%.3f</z-offset-m>
				<pitch-offset-deg>-8</pitch-offset-deg>
			</config>
		</view>%s
		<tags>
			<tag>%s</tag>
			<tag>tailwheel</tag>
			<tag>single-engine</tag>
		</tags>
	</sim>
	<controls>
		<engines>%s
		</engines>
	</controls>
	<consumables>
		<fuel>
			<tank n="0"><selected type="bool">true</selected></tank>
			<tank n="1"><selected type="bool">true</selected></tank>
		</fuel>
	</consumables>
</PropertyList>
""" % (s["name"], s["name"], s["desc"], s["aircraft_id"], s["folder"], s["folder"],
       c["eye"][1], c["eye"][2], c["eye"][0], w,
       "agricultural" if s["fdm"]["hopper"] else "aerobatic", eng_state)


def main():
    root = sys.argv[1]
    ids = sys.argv[2:] or list(SPECS)
    for k in ids:
        s = SPECS[k]
        d = os.path.join(root, s["folder"])
        os.makedirs(os.path.join(d, "Models"), exist_ok=True)
        MATERIALS.clear()
        objs = build(s)
        write_ac(os.path.join(d, "Models", s["folder"] + ".ac"), objs)
        open(os.path.join(d, "Models", s["folder"] + ".xml"), "w").write(model_xml(s))
        open(os.path.join(d, s["aircraft_id"] + "-yasim.xml"), "w").write(yasim_xml(s))
        open(os.path.join(d, s["aircraft_id"] + "-set.xml"), "w").write(set_xml(s))
        print("%-10s ground z %.2f  tail contact z %.2f  verts %d" % (k, ground_z(s), tail_contact_z(s), sum(len(o.v) for o in objs)))


if __name__ == "__main__":
    main()
