#!/usr/bin/env python3
"""Orthographic front/back/side render of a textured walker outfit, for checking a bake.
usage: render.py OUTFIT.ac TEXTURE.png OUT.png"""
import sys, os
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aclib import read_ac

SKIP = ("victory", "handedge", "grip", "thumbsup", "fist", "point")


def render(parts, tex, view, ppm=260):
    # screen: (sx right, sy up, depth toward viewer)
    if view == "front":    # viewer at +x looking -x, right = +y
        M = np.array([[0, 1, 0], [0, 0, 1], [1, 0, 0]], float)
    elif view == "back":   # viewer at -x, right = -y
        M = np.array([[0, -1, 0], [0, 0, 1], [-1, 0, 0]], float)
    else:                  # viewer at -y (wearer's right side), right = +x
        M = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float)
    W, H = int(1.8 * ppm), int(2.0 * ppm)
    img = np.full((H, W, 3), 235.0)
    zb = np.full((H, W), -1e9)
    th, tw = tex.shape[:2]
    for p in parts:
        if any(s in p["name"] for s in SKIP):
            continue
        V = p["verts"] @ M.T
        for (i, j, l), uv in zip(p["tris"], p["uvs"]):
            a, b, c = V[i], V[j], V[l]
            n = np.cross(b - a, c - a); nn = np.linalg.norm(n)
            if nn < 1e-12:
                continue
            shade = 0.35 + 0.65 * abs(n[2]) / nn
            px = np.array([a[0], b[0], c[0]]) * ppm + W / 2
            py = H * 0.52 - np.array([a[1], b[1], c[1]]) * ppm
            x0, x1 = max(0, int(px.min())), min(W - 1, int(px.max()) + 1)
            y0, y1 = max(0, int(py.min())), min(H - 1, int(py.max()) + 1)
            if x1 < x0 or y1 < y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
            if abs(d) < 1e-9:
                continue
            w0 = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
            w1 = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
            w2 = 1 - w0 - w1
            m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not m.any():
                continue
            z = w0 * a[2] + w1 * b[2] + w2 * c[2]
            yy, xx = (gy[m] - 0.5).astype(int), (gx[m] - 0.5).astype(int)
            closer = z[m] > zb[yy, xx]
            if not closer.any():
                continue
            yy, xx = yy[closer], xx[closer]
            uvs = np.array(uv)
            u = (w0[m] * uvs[0, 0] + w1[m] * uvs[1, 0] + w2[m] * uvs[2, 0])[closer]
            v = (w0[m] * uvs[0, 1] + w1[m] * uvs[1, 1] + w2[m] * uvs[2, 1])[closer]
            tx = np.clip((u * tw).astype(int), 0, tw - 1); ty = np.clip(((1 - v) * th).astype(int), 0, th - 1)
            img[yy, xx] = tex[ty, tx, :3] * shade
            zb[yy, xx] = z[m][closer]
    return img


def main():
    parts = read_ac(sys.argv[1])
    tex = np.asarray(Image.open(sys.argv[2]).convert("RGBA"), float)
    views = [render(parts, tex, v) for v in ("front", "back", "side")]
    Image.fromarray(np.clip(np.hstack(views), 0, 255).astype(np.uint8)).save(sys.argv[3])
    print("wrote", sys.argv[3])


if __name__ == "__main__":
    main()
