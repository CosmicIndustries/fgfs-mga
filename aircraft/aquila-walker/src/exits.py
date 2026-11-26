#!/usr/bin/env python3
"""Find a walker exit beside each fleet plane's door: the nearest spot on the
door side, at or aft of the pilot's seat, where a person (0.3 m radius, 1.9 m
tall) stands on the ground clear of the airframe.

Prints one line per plane: name side eye_x eye_y pitch exit_x exit_y.
Exit offsets are in the walker's frame (x aft, y right, metres from the
aircraft reference point), what /sim/model/map/default_exit takes."""
import os, re, sys, math, glob
import numpy as np
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from survey import FLEET, find, load_chain, FGROOT, HOME

DOOR = {  # side the walker leaves by: +1 right, -1 left
    "warrior": 1, "archer": 1, "arrow": 1, "seminole": 1, "seneca": 1, "r22": -1, "r44": -1,
    "citabria": 1, "decathlon": 1, "zlin": -1, "c182": -1, "c182rg": -1, "pa18": 1, "c337": 1,
    "dromader": -1, "agcat": -1, "at502b": -1, "at802": -1, "an2": -1,
}
SKIP_MODEL = re.compile(r"(Instruments|instrument|Panel|panel|gauge|Interior|interior|cockpit|Cockpit|pilot|Pilot|"
                        r"Human|Effects|light|Light|Immat|immat|Livery|shadow|Shadow|beacon|strobe|Tie|tie|chock)")

def rpath(p, base_dir, acdir):
    cands = [os.path.join(base_dir, p)]
    if p.startswith("Aircraft/"):
        rest = p[len("Aircraft/"):]
        cands += [os.path.join(os.path.dirname(acdir), rest), os.path.join(FGROOT, p)]
    cands.append(os.path.join(acdir, p))
    for c in cands:
        if os.path.exists(c):
            return c
    return None

def rot(h, p, r):
    h, p, r = map(math.radians, (h, p, r))
    # FG offsets: heading about z, pitch about y (nose up +), roll about x
    Rz = np.array([[math.cos(h), -math.sin(h), 0], [math.sin(h), math.cos(h), 0], [0, 0, 1]])
    Ry = np.array([[math.cos(p), 0, -math.sin(p)], [0, 1, 0], [math.sin(p), 0, math.cos(p)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(r), -math.sin(r)], [0, math.sin(r), math.cos(r)]])
    return Rz @ Ry @ Rx

def offsets(node):
    o = node.find("offsets") if node is not None else None
    g = lambda k: float(o.findtext(k, "0") or 0) if o is not None else 0.0
    return np.array([g("x-m"), g("y-m"), g("z-m")]), rot(g("heading-deg"), g("pitch-deg"), g("roll-deg"))

def read_ac_tris(path):
    """All triangles of an AC file, in model coords (x aft, y right, z up), with object transforms."""
    lines = [l for l in open(path, encoding="latin-1").read().splitlines() if l.strip()]
    tris = []
    def obj(i, M, T):
        loc = np.zeros(3); R = np.eye(3); verts = None
        i += 1
        while i < len(lines):
            ln = lines[i].split()
            if not ln:
                i += 1; continue
            k = ln[0]
            if k == "loc":
                loc = np.array([float(x) for x in ln[1:4]])
            elif k == "rot":
                R = np.array([float(x) for x in ln[1:10]]).reshape(3, 3)
            elif k == "numvert":
                n = int(ln[1])
                verts = np.array([[float(x) for x in lines[i + 1 + j].split()[:3]] for j in range(n)])
                i += n
            elif k == "data":
                i += 1  # the object's data string sits on the next line
            elif k == "numsurf":
                pass
            elif k == "refs":
                n = int(ln[1])
                idx = [int(lines[i + 1 + j].split()[0]) for j in range(n)]
                if verts is not None:
                    Mw = M @ R.T if False else M @ R
                    W = (verts @ (M @ R).T) + (M @ loc + T)
                    for j in range(1, n - 1):
                        tris.append(W[[idx[0], idx[j], idx[j + 1]]])
                i += n
            elif k == "kids":
                nk = int(ln[1])
                M2 = M @ R; T2 = M @ loc + T
                for _ in range(nk):
                    while not lines[i + 1].startswith("OBJECT"):
                        i += 1
                    i = obj(i + 1, M2, T2)
                return i
            i += 1
        return i
    i = 0
    while i < len(lines) and not lines[i].startswith("OBJECT"):
        i += 1
    if i < len(lines):
        try:
            obj(i, np.eye(3), np.zeros(3))
        except (IndexError, ValueError) as e:
            import traceback; traceback.print_exc() if os.environ.get("ACDEBUG") else None
            print("  warning: stopped reading", os.path.basename(path), "early:", e, file=sys.stderr)
    if not tris:
        return np.zeros((0, 3, 3))
    T = np.array(tris)
    # AC is Y-up: x = X, y = -Z, z = Y
    return np.stack([T[..., 0], -T[..., 2], T[..., 1]], -1)

def load_model(path, acdir, depth=0):
    """Triangles of a model file (.ac or .xml with submodels), in that model's frame."""
    if path.endswith(".ac"):
        return read_ac_tris(path)
    try:
        root = ET.parse(path).getroot()
    except Exception:
        return np.zeros((0, 3, 3))
    out = []
    base = os.path.dirname(path)
    p = root.findtext("path")
    if p:
        f = rpath(p.strip(), base, acdir)
        if f and not SKIP_MODEL.search(p):
            t = load_model(f, acdir, depth + 1)
            if len(t):
                off, R = offsets(root)
                out.append(t @ R.T + off)
    if depth < 2:
        for m in root.findall("model"):
            mp = (m.findtext("path") or "").strip()
            if not mp or SKIP_MODEL.search(mp) or SKIP_MODEL.search(m.findtext("name") or ""):
                continue
            f = rpath(mp, base, acdir)
            if not f:
                continue
            t = load_model(f, acdir, depth + 1)
            if len(t):
                off, R = offsets(m)
                out.append(t @ R.T + off)
    return np.concatenate(out) if out else np.zeros((0, 3, 3))

def merged_tree(chain):
    """Concatenate the chain's roots (base first), enough for find-first lookups."""
    roots = []
    for f, _ in reversed(chain):
        try:
            roots.append(ET.parse(f).getroot())
        except Exception as e:
            print("parse fail", f, e, file=sys.stderr)
    return roots

def first(roots, xpath):
    for r in reversed(roots):  # the aircraft's own file wins
        for n in r.findall(xpath):
            if xpath != "sim/model" or (n.findtext("path") or "").strip():
                return n
    return None

def eye_of(roots, acdir):
    extra = []
    for f in glob.glob(os.path.join(acdir, "**", "*view*.xml"), recursive=True):
        try:
            r = ET.parse(f).getroot()
            extra.append(r if r.find("sim/view") is not None else ET.fromstring("<PropertyList><sim>%s</sim></PropertyList>"
                                                                                % ET.tostring(r, encoding="unicode").replace("PropertyList", "x")))
        except Exception:
            pass
    for r in list(reversed(roots)) + extra:
        views = r.findall("sim/view") + r.findall("sim/x/view") + r.findall("view")
        for v in views:
            if v.get("n", "0") == "0":
                c = v.find("config")
                if c is not None and c.find("z-offset-m") is not None:
                    return np.array([float(c.findtext("z-offset-m")), float(c.findtext("x-offset-m", "0")),
                                     float(c.findtext("y-offset-m", "0"))])
    return None

def ground_pitch(T):
    """Nose-up pitch at rest: 0 for tricycles, tail-down angle for taildraggers."""
    V = T.reshape(-1, 3)
    x0 = V[np.argmin(V[:, 2]), 0]
    prev = 0.0
    for th in np.arange(0, 16.01, 0.25):
        s, c = math.sin(math.radians(th)), math.cos(math.radians(th))
        z = V[:, 2] * c - V[:, 0] * s
        xl = V[np.argmin(z), 0]
        if xl > x0 + 1.5:
            return prev
        prev = th
    return 0.0

def clear(T2, gz, X, Y, r=0.32, h=1.9):
    """T2: triangles in the ground frame. Is a person-sized column at (X, Y) free?"""
    xy = T2[..., :2]
    mn, mx = xy.min(1), xy.max(1)
    near = (mn[:, 0] < X + r) & (mx[:, 0] > X - r) & (mn[:, 1] < Y + r) & (mx[:, 1] > Y - r)
    zmn, zmx = T2[..., 2].min(1), T2[..., 2].max(1)
    near &= (zmx > gz + 0.05) & (zmn < gz + h)
    if not near.any():
        return True
    tr = T2[near]
    pts = [(X, Y)] + [(X + r * math.cos(a), Y + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 12, endpoint=False)]
    a, b, c = tr[:, 0], tr[:, 1], tr[:, 2]
    for px, py in pts:
        d = (b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1])
        ok = np.abs(d) > 1e-12
        d = np.where(ok, d, 1)
        w0 = ((b[:, 1] - c[:, 1]) * (px - c[:, 0]) + (c[:, 0] - b[:, 0]) * (py - c[:, 1])) / d
        w1 = ((c[:, 1] - a[:, 1]) * (px - c[:, 0]) + (a[:, 0] - c[:, 0]) * (py - c[:, 1])) / d
        w2 = 1 - w0 - w1
        inside = ok & (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        z = w0 * a[:, 2] + w1 * b[:, 2] + w2 * c[:, 2]
        if (inside & (z > gz + 0.05) & (z < gz + h)).any():
            return False
    # a triangle vertex inside the disc within the height band
    v = tr.reshape(-1, 3)
    if (((v[:, 0] - X) ** 2 + (v[:, 1] - Y) ** 2 < r * r) & (v[:, 2] > gz + 0.05) & (v[:, 2] < gz + h)).any():
        return False
    return True

def exit_for(name, folder, ident):
    d, f = find(folder, ident)
    chain = load_chain(f, d)
    roots = merged_tree(chain)
    mnode = first(roots, "sim/model")
    mpath = (mnode.findtext("path") or "").strip() if mnode is not None else ""
    mf = rpath(mpath, d, d) if mpath else None
    if not mf:
        return None, "no model"
    T = load_model(mf, d)
    if not len(T):
        return None, "no geometry"
    off, R = offsets(mnode)
    T = T @ R.T + off
    eye = eye_of(roots, d)
    pitch = ground_pitch(T)
    s, c = math.sin(math.radians(pitch)), math.cos(math.radians(pitch))
    # ground frame: rotate nose-up by pitch (x aft, z up)
    T2 = T.copy()
    T2[..., 0] = T[..., 0] * c + T[..., 2] * s
    T2[..., 2] = T[..., 2] * c - T[..., 0] * s
    gz = T2[..., 2].min()
    side = DOOR[name]
    V = T.reshape(-1, 3)
    if eye is None:
        eye = np.array([V[:, 0].min() + 0.35 * (V[:, 0].max() - V[:, 0].min()), 0, 0])
    ex = eye[0] * c + eye[2] * s
    # fuselage half width at the seat
    band = np.abs(T2.reshape(-1, 3)[:, 0] - ex) < 0.4
    vy = T2.reshape(-1, 3)[band]
    vy = vy[(vy[:, 2] > gz + 0.3)]
    best = None
    for dy in np.arange(0.45, 6.01, 0.15):
        for dx in np.arange(-0.6, 4.01, 0.15):
            X, Y = ex + dx, side * (0.35 + dy) + eye[1] * 0
            cost = abs(dx) * 1.0 + dy * 1.4
            if best is not None and cost >= best[0]:
                continue
            if clear(T2, gz, X, Y):
                best = (cost, X, Y)
    if best is None:
        return None, "no clear spot"
    # back to the walker's offsets: walk.nas multiplies x by cos(pitch)
    return dict(eye=eye, pitch=pitch, gz=gz, x=best[1] / c, y=best[2], ntris=len(T)), "ok"

if __name__ == "__main__":
    only = sys.argv[1:]
    for name, folder, ident in FLEET:
        if only and name not in only:
            continue
        r, msg = exit_for(name, folder, ident)
        if r is None:
            print(f"{name:9s} {msg}")
        else:
            e = r["eye"]
            print(f"{name:9s} side={DOOR[name]:+d} eye=({e[0]:.2f},{e[1]:.2f},{e[2]:.2f}) pitch={r['pitch']:.1f} "
                  f"ground_z={r['gz']:.2f} tris={r['ntris']} exit x={r['x']:.2f} y={r['y']:.2f}")
