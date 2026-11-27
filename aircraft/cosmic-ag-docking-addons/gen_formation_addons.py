#!/usr/bin/env python3
"""Add-on models for the formation modes and the retardant bag.

Builds, in FlightGear model axes (X aft, Y right, Z up, metres) with the
primitives of ../generate_models_v2.py (imported, not changed):
  retardant-bag.ac  mothership frame: a fabric bag of fire retardant cradled
                    in the belly capture ring (ring centre x 0, z 1.05 m,
                    inner radius 0.95 m), straps, shackles and a dump valve.
  remora-modes.ac   drone frame (origin = mast top, already at drone scale):
                    scout gimbal (sweeps when scouting), scout light, and a
                    spray bar with two nozzles under the wing.
Usage: gen_formation_addons.py OUTDIR
"""
import math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import generate_models_v2 as gm

gm.MATERIALS = [
    # name, rgb, amb, emis, spec, shi, trans
    ("bag",     (0.66, 0.14, 0.10), 0.30, 0.0, 0.10, 8, 0.0),    # 0 red retardant bag fabric
    ("strap",   (0.10, 0.10, 0.11), 0.20, 0.0, 0.10, 8, 0.0),    # 1 black webbing
    ("metal",   (0.55, 0.57, 0.60), 0.25, 0.0, 0.60, 60, 0.0),   # 2 hardware
    ("label",   (0.92, 0.92, 0.88), 0.30, 0.0, 0.10, 8, 0.0),    # 3 white band
    ("dark",    (0.13, 0.14, 0.15), 0.20, 0.0, 0.25, 30, 0.0),   # 4 graphite
    ("lens",    (0.05, 0.10, 0.20), 0.20, 0.0, 0.90, 100, 0.0),  # 5 camera lens
    ("lamp",    (0.20, 1.00, 0.35), 0.30, 1.0, 0.30, 30, 0.0),   # 6 green scout light (emissive)
]
BAG, STRAP, METAL, LABEL, DARK, LENS, LAMP = range(7)

RING_Z, RING_IN, RING_OUT = 1.05, 0.95, 1.15

def ring_z(cx, cy, z, r, n=20):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), z) for i in range(n)]

def rev_z(obj, stations, mat, cx=0.0, cy=0.0, n=20):
    """Body of revolution about a vertical axis; stations (z, r) top to bottom."""
    gm.loft(obj, [ring_z(cx, cy, z, max(r, 1e-4), n) for z, r in stations], mat)

# bag profile (z, r): flat top against the belly (z 1.27 at x 0), waist just
# inside the ring, rounded bottom. Sitting on the tailwheel (11 deg nose-up)
# the dump valve is the lowest point.
BAG_PROFILE = [(1.255, 0.02), (1.25, 0.50), (1.22, 0.74), (1.15, 0.88), (1.05, 0.925),
               (0.95, 0.89), (0.86, 0.78), (0.78, 0.60), (0.73, 0.38), (0.705, 0.12), (0.70, 0.02)]

def bag_volume_l():
    v = 0.0
    for (z0, r0), (z1, r1) in zip(BAG_PROFILE, BAG_PROFILE[1:]):
        h = z0 - z1
        v += math.pi * h * (r0 * r0 + r0 * r1 + r1 * r1) / 3
    return v * 1000

def radius_at(z):
    for (z0, r0), (z1, r1) in zip(BAG_PROFILE, BAG_PROFILE[1:]):
        if z1 <= z <= z0:
            return r1 + (r0 - r1) * (z - z1) / (z0 - z1)
    return 0.0

def retardant_bag():
    objs = []
    bag = gm.Obj("retardant_bag")
    rev_z(bag, BAG_PROFILE, BAG, n=24)
    objs.append(bag)
    band = gm.Obj("retardant_bag_band")      # white band with room for a label
    rev_z(band, [(1.19, radius_at(1.19) + 0.006), (1.11, radius_at(1.11) + 0.006)], LABEL, n=24)
    objs.append(band)
    straps = gm.Obj("retardant_bag_straps")  # four webbing straps from the ring under the bag
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        zs = [1.05, 0.95, 0.86, 0.78, 0.73, 0.705]
        pts = [((radius_at(z) + 0.012) * ca, (radius_at(z) + 0.012) * sa, z) for z in zs]
        pts[0] = (RING_IN * ca, RING_IN * sa, RING_Z)
        pts.append((0.10 * ca, 0.10 * sa, 0.695))
        for p, q in zip(pts, pts[1:]):
            gm.cylinder(straps, p, q, 0.018, STRAP, n=5)
    objs.append(straps)
    shackles = gm.Obj("retardant_bag_shackles")
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        gm.box(shackles, 1.02 * math.cos(a), 1.02 * math.sin(a), RING_Z, 0.09, 0.09, 0.06, METAL)
    objs.append(shackles)
    valve = gm.Obj("retardant_dump_valve")   # dump gate at the bottom centre
    rev_z(valve, [(0.71, 0.11), (0.69, 0.11), (0.675, 0.08), (0.655, 0.08), (0.65, 0.02)], METAL, n=16)
    objs.append(valve)
    return objs

def remora_modes():
    s = gm.DRONE_SCALE
    objs = []
    # scout gimbal: stalk under the forward pod, ball with a lens looking ahead
    gx, gz = (-0.30 + 0.12) * s, (-0.20 - 0.10) * s     # under the pod, forward of the spray tank
    stalk = gm.Obj("scout_gimbal_stalk")
    gm.cylinder(stalk, (gx, 0, gz + 0.03), (gx, 0, gz + 0.012), 0.006, DARK, n=6)
    objs.append(stalk)
    ball = gm.Obj("scout_gimbal")
    gm.body_of_revolution(ball, [(gx - 0.02, gz, 0.002, 0.002), (gx - 0.014, gz, 0.015, 0.015),
                                 (gx, gz, 0.02, 0.02), (gx + 0.014, gz, 0.015, 0.015),
                                 (gx + 0.02, gz, 0.002, 0.002)], DARK, n=10)
    gm.body_of_revolution(ball, [(gx - 0.024, gz, 0.002, 0.002), (gx - 0.019, gz, 0.009, 0.009),
                                 (gx - 0.012, gz, 0.010, 0.010)], LENS, n=8)
    objs.append(ball)
    lamp = gm.Obj("scout_light")
    gm.box(lamp, gx + 0.04, 0, (-0.20 - 0.083) * s, 0.025, 0.012, 0.008, LAMP)
    objs.append(lamp)
    # spray bar along the wing trailing edge, with two drop nozzles
    bar = gm.Obj("spray_bar")
    bx, bz = (0.04 + 0.12) * s + 0.005, (-0.15 - 0.03) * s
    gm.cylinder(bar, (bx, -0.36, bz), (bx, 0.36, bz), 0.005, DARK, n=6)
    for y in (-0.30, 0.30):
        gm.cylinder(bar, (bx, y, bz), (bx + 0.004, y, bz - 0.014), 0.004, METAL, n=5)
    objs.append(bar)
    return objs, (gx, 0.0, gz), [(bx + 0.004, -0.30, bz - 0.016), (bx + 0.004, 0.30, bz - 0.016),
                                  ((0.10 + 0.12) * s, 0.0, (-0.20 - 0.16) * s - 0.002)]

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    gm.write_ac(os.path.join(out, "retardant-bag.ac"), retardant_bag())
    objs, gimbal, nozzles = remora_modes()
    gm.write_ac(os.path.join(out, "remora-modes.ac"), objs)
    vol = bag_volume_l()
    print("bag volume %.0f L, about %.0f kg of mixed retardant at 1.08 kg/L" % (vol, vol * 1.08))
    print("gimbal centre x %.4f y %.4f z %.4f" % gimbal)
    for p in nozzles:
        print("nozzle x %.4f y %.4f z %.4f" % p)

if __name__ == "__main__":
    main()
