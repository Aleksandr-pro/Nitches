#!/usr/bin/env python3
"""
Streaming OBJ inspector (stdlib only).

Reads a Wavefront OBJ once, line by line, without loading it into memory,
and writes:
  - report.json / report.md  counts, AABB, per-object and per-material census
  - proj_top.png / proj_front.png / proj_side.png
    density silhouettes from a reservoir sample of vertices, so a human can
    tell at a glance whether the model is a building, terrain, a car, ...

Usage: inspect-obj.py <input.obj> <output-dir>
Exit code 0 on success; the script never modifies the input.
"""

import json
import math
import os
import random
import struct
import sys
import zlib
from array import array

SAMPLE_MAX = 300_000
IMG = 1024
MAX_OBJECTS = 4000


def png_write(path, w, h, gray):
    """Minimal 8-bit grayscale PNG writer (filter 0 rows)."""
    raw = bytearray()
    stride = w
    for y in range(h):
        raw.append(0)
        raw.extend(gray[y * stride:(y + 1) * stride])
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)
    blob = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)


def projection(path, pts, ax, ay, flip_y):
    if not pts:
        return
    xs = [p[ax] for p in pts]
    ys = [p[ay] for p in pts]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    sx = (IMG - 1) / max(1e-9, x1 - x0)
    sy = (IMG - 1) / max(1e-9, y1 - y0)
    grid = array("i", bytes(4 * IMG * IMG))
    for p in pts:
        ix = int((p[ax] - x0) * sx)
        iy = int((p[ay] - y0) * sy)
        if flip_y:
            iy = IMG - 1 - iy
        grid[iy * IMG + ix] += 1
    peak = max(grid) or 1
    denom = math.sqrt(peak)
    gray = bytes(255 - int(255 * (math.sqrt(v) / denom)) if v else 255 for v in grid)
    png_write(path, IMG, IMG, gray)


def main():
    if len(sys.argv) != 3:
        print("usage: inspect-obj.py <input.obj> <output-dir>", file=sys.stderr)
        return 2
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    size = os.path.getsize(src)

    counts = {"v": 0, "vt": 0, "vn": 0, "f": 0, "tris_est": 0, "lines": 0}
    poly_hist = {}
    bmin = [math.inf] * 3
    bmax = [-math.inf] * 3
    sample = []
    rng = random.Random(12345)
    objects = {}          # name -> dict(v, f, min[3], max[3])
    cur_obj = "(default)"
    objects_overflow = 0
    materials = {}        # name -> face count
    cur_mtl = "(none)"
    mtllibs = []
    comments = []
    head_lines = []

    def obj_rec(name):
        rec = objects.get(name)
        if rec is None:
            if len(objects) >= MAX_OBJECTS:
                return None
            rec = {"v": 0, "f": 0, "min": [math.inf] * 3, "max": [-math.inf] * 3}
            objects[name] = rec
        return rec

    obj_rec(cur_obj)
    with open(src, "rb", buffering=1024 * 1024) as fh:
        for raw in fh:
            counts["lines"] += 1
            if len(head_lines) < 40 and not raw.startswith((b"v ", b"f ")):
                head_lines.append(raw.decode("utf-8", "replace").rstrip())
            if raw.startswith(b"v "):
                parts = raw.split()
                if len(parts) < 4:
                    continue
                try:
                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                except ValueError:
                    continue
                counts["v"] += 1
                if x < bmin[0]: bmin[0] = x
                if y < bmin[1]: bmin[1] = y
                if z < bmin[2]: bmin[2] = z
                if x > bmax[0]: bmax[0] = x
                if y > bmax[1]: bmax[1] = y
                if z > bmax[2]: bmax[2] = z
                rec = obj_rec(cur_obj)
                if rec is not None:
                    rec["v"] += 1
                    mn, mx = rec["min"], rec["max"]
                    if x < mn[0]: mn[0] = x
                    if y < mn[1]: mn[1] = y
                    if z < mn[2]: mn[2] = z
                    if x > mx[0]: mx[0] = x
                    if y > mx[1]: mx[1] = y
                    if z > mx[2]: mx[2] = z
                n = counts["v"]
                if len(sample) < SAMPLE_MAX:
                    sample.append((x, y, z))
                else:
                    j = rng.randrange(n)
                    if j < SAMPLE_MAX:
                        sample[j] = (x, y, z)
            elif raw.startswith(b"vt"):
                counts["vt"] += 1
            elif raw.startswith(b"vn"):
                counts["vn"] += 1
            elif raw.startswith(b"f "):
                counts["f"] += 1
                k = len(raw.split()) - 1
                poly_hist[k] = poly_hist.get(k, 0) + 1
                if k >= 3:
                    counts["tris_est"] += k - 2
                materials[cur_mtl] = materials.get(cur_mtl, 0) + 1
                rec = obj_rec(cur_obj)
                if rec is not None:
                    rec["f"] += 1
            elif raw.startswith((b"o ", b"g ")):
                name = raw[2:].decode("utf-8", "replace").strip() or "(unnamed)"
                if name not in objects and len(objects) >= MAX_OBJECTS:
                    objects_overflow += 1
                    cur_obj = "(overflow)"
                    obj_rec(cur_obj)
                else:
                    cur_obj = name
                    obj_rec(cur_obj)
            elif raw.startswith(b"usemtl"):
                cur_mtl = raw[6:].decode("utf-8", "replace").strip() or "(empty)"
                materials.setdefault(cur_mtl, 0)
            elif raw.startswith(b"mtllib"):
                mtllibs.append(raw[6:].decode("utf-8", "replace").strip())
            elif raw.startswith(b"#"):
                if len(comments) < 40:
                    comments.append(raw.decode("utf-8", "replace").rstrip())

    dims = [bmax[i] - bmin[i] for i in range(3)] if counts["v"] else [0, 0, 0]
    obj_list = []
    for name, r in objects.items():
        d = [r["max"][i] - r["min"][i] for i in range(3)] if r["v"] else [0, 0, 0]
        obj_list.append({
            "name": name, "vertices": r["v"], "faces": r["f"],
            "size": [round(v, 3) for v in d],
            "min": [round(v, 3) for v in r["min"]] if r["v"] else None,
            "max": [round(v, 3) for v in r["max"]] if r["v"] else None,
        })
    obj_list.sort(key=lambda o: -o["faces"])

    report = {
        "file": os.path.basename(src),
        "bytes": size,
        "counts": counts,
        "polygon_size_histogram": {str(k): v for k, v in sorted(poly_hist.items())},
        "aabb_min": [round(v, 3) for v in bmin] if counts["v"] else None,
        "aabb_max": [round(v, 3) for v in bmax] if counts["v"] else None,
        "size_xyz": [round(v, 3) for v in dims],
        "mtllib": mtllibs,
        "materials_by_faces": dict(sorted(materials.items(), key=lambda kv: -kv[1])),
        "objects_total": len(obj_list),
        "objects_overflow_groups": objects_overflow,
        "objects_top": obj_list[:60],
        "comments": comments,
        "head_lines": head_lines,
        "sample_vertices": len(sample),
    }
    with open(os.path.join(outdir, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)

    projection(os.path.join(outdir, "proj_top.png"), sample, 0, 2, flip_y=True)
    projection(os.path.join(outdir, "proj_front.png"), sample, 0, 1, flip_y=True)
    projection(os.path.join(outdir, "proj_side.png"), sample, 2, 1, flip_y=True)

    md = []
    md.append(f"# OBJ inspection — {report['file']}")
    md.append("")
    md.append(f"- Bytes: {size} ({size / 1048576:.1f} MiB), lines: {counts['lines']}")
    md.append(f"- Vertices: {counts['v']}, UVs: {counts['vt']}, normals: {counts['vn']}")
    md.append(f"- Faces: {counts['f']} (≈{counts['tris_est']} triangles after fan triangulation)")
    md.append(f"- Polygon sizes: {report['polygon_size_histogram']}")
    md.append(f"- AABB size (x,y,z): {report['size_xyz']}  min {report['aabb_min']}  max {report['aabb_max']}")
    md.append(f"- mtllib: {mtllibs or '—'}")
    md.append(f"- Objects/groups: {len(obj_list)} (+{objects_overflow} overflow)")
    md.append("")
    md.append("## Materials by face count")
    for name, c in list(report["materials_by_faces"].items())[:30]:
        md.append(f"- `{name}`: {c}")
    md.append("")
    md.append("## Largest objects (by faces)")
    md.append("| object | faces | vertices | size xyz |")
    md.append("|---|---:|---:|---|")
    for o in obj_list[:30]:
        md.append(f"| `{o['name']}` | {o['faces']} | {o['vertices']} | {o['size']} |")
    md.append("")
    md.append("## Header / comments")
    md.append("```")
    md.extend(head_lines[:25] or ["(none)"])
    md.append("```")
    md.append("")
    md.append("Projections: `proj_top.png` (X→, Z↓), `proj_front.png` (X→, Y↑), `proj_side.png` (Z→, Y↑).")
    with open(os.path.join(outdir, "report.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(md) + "\n")
    print(json.dumps({"ok": True, "vertices": counts["v"], "faces": counts["f"],
                      "tris_est": counts["tris_est"], "size_xyz": report["size_xyz"]}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
