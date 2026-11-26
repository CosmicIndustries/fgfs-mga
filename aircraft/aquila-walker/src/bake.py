#!/usr/bin/env python3
"""Bake the Aquila flight suit texture for a FlightGear walker outfit mesh.

usage: bake.py OUTFIT.ac ORIGINAL.png LOGO.png WINGS.png OUT.png [size]

Each texel of the outfit's UV layout is traced back to the 3D point of the
mesh it paints, and the suit design is decided from that point: yoke above the
chest line, lime side panels, outer leg and top-of-arm stripes, cyan piping,
segmented reflective bands, logo patch and pilot wings projected on the chest
and a large logo on the back. Hands keep the original skin texels and boots
stay dark.
"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aclib import read_ac

BASE = np.array([0x0B, 0x22, 0x20], float)   # Aquila black-seafoam
LIME = np.array([0xDF, 0xFF, 0x00], float)   # acid lime
CYAN = np.array([0x00, 0xE5, 0xFF], float)   # electric cyan piping
IVORY = np.array([0xF8, 0xF8, 0xF0], float)  # reflective ivory
SILVER = np.array([0xB8, 0xC0, 0xC0], float)
BOOT = np.array([0x14, 0x18, 0x18], float)

HANDS = ("victory", "handedge", "hand.", "grip", "thumbsup", "fist", "point")


def kind(name):
    if name in ("chest", "hip"):
        return "torso"
    if name.startswith("leg"):
        return "leg"
    if name.startswith("arm"):
        return "arm"
    if name.startswith("foot"):
        return "foot"
    return "hand"


def rasterize(parts, size):
    """Per texel: 3D position and part index (or -1)."""
    pos = np.zeros((size, size, 3), np.float32)
    pid = -np.ones((size, size), np.int16)
    for k, p in enumerate(parts):
        V = p["verts"]
        for (i, j, l), uv in zip(p["tris"], p["uvs"]):
            uv = np.array(uv, float)
            px = uv[:, 0] * size - 0.5
            py = (1.0 - uv[:, 1]) * size - 0.5
            x0, x1 = int(max(0, math.floor(px.min()))), int(min(size - 1, math.ceil(px.max())))
            y0, y1 = int(max(0, math.floor(py.min()))), int(min(size - 1, math.ceil(py.max())))
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
            if abs(d) < 1e-12:
                continue
            a = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
            b = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
            c = 1 - a - b
            e = -0.6 / max(1.0, abs(d) ** 0.5)  # a little over half a texel of slack
            m = (a >= e) & (b >= e) & (c >= e)
            if not m.any():
                continue
            P = a[m, None] * V[i] + b[m, None] * V[j] + c[m, None] * V[l]
            pos[gy[m], gx[m]] = P
            pid[gy[m], gx[m]] = k
    return pos, pid


def slice_frame(V, axis, step=0.01, win=0.045):
    """Centre and half-extent of the cross-section along an axis, per bin
    (each bin looks at the vertices within +-win, so sparse meshes stay smooth)."""
    o = [a for a in range(3) if a != axis]
    lo = V[:, axis].min()
    nb = int((V[:, axis].max() - lo) / step) + 1
    cen = np.zeros((nb, 2)); half = np.zeros((nb, 2)); have = np.zeros(nb, bool)
    for k in range(nb):
        zc = lo + (k + 0.5) * step
        s = V[np.abs(V[:, axis] - zc) <= win][:, o]
        if len(s):
            mn, mx = s.min(0), s.max(0)
            cen[k] = (mn + mx) / 2; half[k] = np.maximum((mx - mn) / 2, 1e-3); have[k] = True
    idx = np.arange(nb)
    for c in range(2):  # fill empty bins
        cen[:, c] = np.interp(idx, idx[have], cen[have, c])
        half[:, c] = np.interp(idx, idx[have], half[have, c])
    return lo, step, cen, half, o


def angle_about(P, frame):
    lo, step, cen, half, o = frame
    ax = [a for a in range(3) if a not in o][0]
    k = np.clip(((P[:, ax] - lo) / step).astype(int), 0, len(cen) - 1)
    d = (P[:, o] - cen[k]) / half[k]
    return d, cen[k]


def project(img, P_u, P_v, u0, v0, w, h):
    """Sample RGBA image where (P_u, P_v) fall in the box centred (u0, v0) of size w x h.
    u grows to the image's right, v grows upward."""
    H, W = img.shape[:2]
    s = (P_u - (u0 - w / 2)) / w
    t = ((v0 + h / 2) - P_v) / h
    inside = (s >= 0) & (s < 1) & (t >= 0) & (t < 1)
    out = np.zeros((len(P_u), 4))
    if inside.any():
        xs = s[inside] * (W - 1); ys = t[inside] * (H - 1)
        x0 = np.floor(xs).astype(int); y0 = np.floor(ys).astype(int)
        x1 = np.minimum(x0 + 1, W - 1); y1 = np.minimum(y0 + 1, H - 1)
        fx = (xs - x0)[:, None]; fy = (ys - y0)[:, None]
        out[inside] = (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x1] * fx * (1 - fy)
                       + img[y1, x0] * (1 - fx) * fy + img[y1, x1] * fx * fy)
    return out


def rounded_alpha(img, r):
    h, w = img.shape[:2]
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    img[..., 3] = np.asarray(m, float)
    return img


def main():
    ac, orig_png, logo_png, wings_png, out_png = sys.argv[1:6]
    size = int(sys.argv[6]) if len(sys.argv) > 6 else 1024
    parts = read_ac(ac)
    orig = np.asarray(Image.open(orig_png).convert("RGBA").resize((size, size), Image.BICUBIC), float)
    logo = rounded_alpha(np.asarray(Image.open(logo_png).convert("RGBA"), float), 10)
    wings = np.asarray(Image.open(wings_png).convert("RGBA"), float)

    pos, pid = rasterize(parts, size)
    out = orig.copy()
    lum = orig[..., :3] @ np.array([0.299, 0.587, 0.114])
    skin = (orig[..., 0] > orig[..., 1] + 25) & (orig[..., 0] > 120)
    dark = (lum < 60) & ((orig[..., :3].max(-1) - orig[..., :3].min(-1)) < 30)

    frames = {}
    torso_V = np.concatenate([p["verts"] for p in parts if kind(p["name"]) == "torso"])
    frames["torso"] = slice_frame(torso_V, 2)
    for p in parts:
        if kind(p["name"]) == "leg":
            frames[p["name"]] = slice_frame(p["verts"], 2)
        elif kind(p["name"]) == "arm":
            frames[p["name"]] = slice_frame(p["verts"], 1)

    fabric = np.zeros((size, size), bool)
    suit_mean = None
    for k, p in enumerate(parts):
        kd = kind(p["name"])
        m = pid == k
        if kd == "hand" or not m.any():
            continue
        P = pos[m].astype(float)
        col = np.tile(BASE, (len(P), 1))
        if kd == "foot":
            col[:] = BOOT
            out[m, :3] = np.where(skin[m][:, None], orig[m, :3], col)
            continue
        if kd == "torso":
            d, c = angle_about(P, frames["torso"])
            th = np.degrees(np.arctan2(d[:, 1], d[:, 0]))      # 0 front (+x), +90 at +y
            ath = np.abs(th); z = P[:, 2]; y = P[:, 1]
            yoke = z > 0.445
            col[yoke] = LIME
            col[(z > 0.437) & (z <= 0.445)] = CYAN
            col[z > 0.578] = BASE                               # collar
            col[(z > 0.572) & (z <= 0.578)] = CYAN
            side = (ath > 72) & (ath < 108) & (z < 0.437) & (z > -0.06)
            col[side] = LIME
            pip = ((np.abs(ath - 68) < 3) | (np.abs(ath - 112) < 3)) & (z < 0.437) & (z > -0.06)
            col[pip] = CYAN
            zip_ = (np.abs(y - c[:, 1]) < 0.0055) & (ath < 60) & (z < 0.572) & (z > -0.07)
            col[zip_] = CYAN
            fab = ~zip_
            front = ath < 55
            back = ath > 125
            layers = [  # (image, mask, u coordinate, centre u, centre z, width, height)
                (logo, front, P[:, 1], -0.074, 0.352, 0.112, 0.078),
                (wings, front, P[:, 1], 0.074, 0.392, 0.104, 0.032),
                (logo, back, -P[:, 1], 0.0, 0.335, 0.20, 0.14),
            ]
            for img, msk, u, u0, z0, w, h in layers:
                s = project(img, u, z, u0, z0, w, h)
                a = (s[:, 3:4] / 255.0) * msk[:, None]
                col = col * (1 - a) + s[:, :3] * a
                fab &= a[:, 0] < 0.5
        elif kd == "leg":
            d, c = angle_about(P, frames[p["name"]])
            th = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
            outward = 90.0 if p["verts"][:, 1].mean() > 0 else -90.0
            dev = np.abs((th - outward + 180) % 360 - 180)
            z = P[:, 2]
            col[dev < 20] = LIME
            col[(dev >= 20) & (dev < 25)] = CYAN
            band = (z < -0.600) & (z > -0.628)
            seg = (np.floor((th + 180) / 18).astype(int) % 2) == 0
            col[band & seg] = IVORY; col[band & ~seg] = SILVER
            col[z < -0.832] = LIME
            col[(z >= -0.832) & (z < -0.825)] = CYAN
            fab = ~band
        else:  # arm, axis along y; angle in the x-z plane, 0 front, +90 top
            d, c = angle_about(P, frames[p["name"]])
            th = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
            dev = np.abs((th - 90 + 180) % 360 - 180)
            ay = np.abs(P[:, 1])
            col[dev < 18] = LIME
            col[(dev >= 18) & (dev < 23)] = CYAN
            col[ay < 0.19] = LIME
            col[(ay >= 0.19) & (ay < 0.198)] = CYAN
            band = (ay > 0.300) & (ay < 0.318)
            seg = (np.floor((th + 180) / 18).astype(int) % 2) == 0
            col[band & seg] = IVORY; col[band & ~seg] = SILVER
            col[ay > 0.655] = LIME
            col[(ay > 0.645) & (ay <= 0.655)] = CYAN
            fab = ~band
        keep = skin[m]
        col = np.where(keep[:, None], orig[m, :3], col)
        out[m, :3] = col
        out[m, 3] = 255
        f = np.zeros_like(m); f[m] = fab & ~keep
        fabric |= f

    # fabric grain from the original weave, kept gentle
    g = lum[fabric]
    if g.size:
        fac = np.clip(1 + 0.9 * (g - g.mean()) / 255.0, 0.88, 1.12)
        out[fabric, :3] = np.clip(out[fabric, :3] * fac[:, None], 0, 255)

    # bleed painted texels a few pixels into the gaps so mip-maps don't show seams
    covered = (pid >= 0) & ~np.isin(pid, [k for k, p in enumerate(parts) if kind(p["name"]) == "hand"])
    rgb = out[..., :3].copy(); cov = covered.copy()
    for _ in range(4):
        acc = np.zeros_like(rgb); n = np.zeros(cov.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            acc += np.roll(np.roll(rgb * cov[..., None], dy, 0), dx, 1)
            n += np.roll(np.roll(cov, dy, 0), dx, 1)
        grow = (~cov) & (n > 0) & (pid < 0)
        rgb[grow] = acc[grow] / n[grow, None]
        cov |= grow
    out[..., :3] = np.where(((pid < 0) & cov)[..., None], rgb, out[..., :3])
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA").save(out_png, optimize=True)
    print("wrote", out_png, size, "covered texels", int(covered.sum()))


if __name__ == "__main__":
    main()
