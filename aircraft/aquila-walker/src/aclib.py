"""Minimal AC3D reader for the walker outfit meshes (all objects have loc 0, no rot)."""
import numpy as np

def read_ac(path):
    """Return list of parts: dict(name, texture, verts (N,3) model coords, tris [(i,j,k)], uvs [(3,2)])."""
    lines = open(path, encoding="latin-1").read().splitlines()
    parts, i, cur = [], 0, None
    loc = np.zeros(3)
    while i < len(lines):
        ln = lines[i].strip()
        if ln.startswith("OBJECT"):
            cur = {"name": "", "texture": None, "verts": None, "tris": [], "uvs": []}
            loc = np.zeros(3)
            parts.append(cur)
        elif ln.startswith("name") and cur is not None:
            cur["name"] = ln.split('"')[1] if '"' in ln else ln.split()[1]
        elif ln.startswith("texture") and cur is not None:
            cur["texture"] = ln.split('"')[1]
        elif ln.startswith("loc") and cur is not None:
            loc = np.array([float(x) for x in ln.split()[1:4]])
        elif ln.startswith("rot") and cur is not None:
            raise SystemExit("rot not supported in " + path)
        elif ln.startswith("numvert"):
            n = int(ln.split()[1])
            v = np.array([[float(x) for x in lines[i + 1 + k].split()[:3]] for k in range(n)]) + loc
            # AC is Y-up: model x = X, y = -Z, z = Y
            cur["verts"] = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)
            i += n
        elif ln.startswith("refs"):
            n = int(ln.split()[1])
            refs = [lines[i + 1 + k].split() for k in range(n)]
            idx = [int(r[0]) for r in refs]
            uv = [(float(r[1]), float(r[2])) for r in refs]
            for k in range(1, n - 1):
                cur["tris"].append((idx[0], idx[k], idx[k + 1]))
                cur["uvs"].append((uv[0], uv[k], uv[k + 1]))
            i += n
        i += 1
    return [p for p in parts if p["verts"] is not None and p["tris"]]
