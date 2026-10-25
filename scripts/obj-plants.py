#!/usr/bin/env python3
"""
OBJ plants pipeline: census + species conversion to a compact GLB.

Modes:
  census  <model.obj> <outdir>
      True per-object census segmented by 'o' lines: face-referenced AABB in
      metres (source units assumed millimetres), triangle counts, sampled
      connected-component estimate (leaf-card detection), plus Pillow contact
      sheets of front silhouettes so species can be picked by eye.

  convert <model.obj> <config.json> <out.glb>
      config: {"species":[{"key":"tree2","object":"plant007","tris":7000,
                            "strategy":"thin|cluster|cluster+thin",
                            "bark":true}]}
      For each species: extract object, reduce to the triangle budget,
      recentre (base at origin), mm->m scale, optional trunk(bark) split by
      central-column heuristic, smooth normals, box-projected UVs, then all
      parts are written as one GLB with meshes named <key>_foliage/_bark and
      two placeholder materials (nh_foliage / nh_bark) that the game replaces
      with its own photo textures.

Requires: numpy (convert + census), Pillow (census contact sheets only).
"""

import json
import math
import os
import struct
import sys
from array import array

import numpy as np

MM_TO_M = 0.001


# --------------------------------------------------------------------------
# Streaming OBJ parse: global positions + per-object triangulated indices.
# --------------------------------------------------------------------------
def parse_obj(path):
    pos = array("f")
    objects = {}   # unique key -> {"name": str, "tris": array('i')}
    order = []
    cur = None
    vcount = 0

    def new_object(name):
        key = name
        n = 2
        while key in objects:
            key = f"{name}#{n}"
            n += 1
        objects[key] = {"name": name, "tris": array("i")}
        order.append(key)
        return objects[key]

    cur = new_object("(default)")
    with open(path, "rb", buffering=1024 * 1024) as fh:
        for raw in fh:
            if raw.startswith(b"v "):
                p = raw.split()
                if len(p) >= 4:
                    pos.extend((float(p[1]), float(p[2]), float(p[3])))
                    vcount += 1
            elif raw.startswith(b"o "):
                name = raw[2:].decode("utf-8", "replace").strip() or "(unnamed)"
                cur = new_object(name)
            elif raw.startswith(b"f "):
                toks = raw.split()
                if len(toks) < 4:
                    continue
                idx = []
                for tok in toks[1:]:
                    head = tok.split(b"/", 1)[0]
                    v = int(head)
                    idx.append(v - 1 if v > 0 else vcount + v)
                tris = cur["tris"]
                a = idx[0]
                for k in range(1, len(idx) - 1):
                    tris.extend((a, idx[k], idx[k + 1]))
    positions = np.frombuffer(bytes(pos), dtype=np.float32).reshape(-1, 3).copy()
    return positions, objects, order


def object_arrays(positions, rec):
    tris = np.frombuffer(bytes(rec["tris"]), dtype=np.int32).reshape(-1, 3).astype(np.int64)
    return tris


def referenced_aabb(positions, tris):
    if len(tris) == 0:
        return None, None, 0
    ref = np.unique(tris)
    pts = positions[ref]
    return pts.min(axis=0), pts.max(axis=0), len(ref)


def components_sample(tris, cap=40_000):
    t = tris[:cap]
    if len(t) == 0:
        return 0, 0
    parent = {}

    def find(x):
        root = x
        while parent.get(root, root) != root:
            root = parent[root]
        while parent.get(x, x) != root:
            parent[x], x = root, parent[x]
        return root

    for a, b, c in t:
        for u, v in ((a, b), (b, c)):
            ru, rv = find(int(u)), find(int(v))
            if ru != rv:
                parent[ru] = rv
    roots = {find(int(v)) for tri in t for v in tri}
    return len(roots), len(t)


# --------------------------------------------------------------------------
# Census
# --------------------------------------------------------------------------
def front_density(positions, tris, size=320):
    ref = np.unique(tris)
    if len(ref) > 60_000:
        ref = ref[:: max(1, len(ref) // 60_000)]
    pts = positions[ref]
    x, y = pts[:, 0], pts[:, 1]
    hist, _, _ = np.histogram2d(y, x, bins=size)
    hist = np.flipud(hist)
    if hist.max() > 0:
        img = 255 - (np.sqrt(hist) / np.sqrt(hist.max()) * 255)
    else:
        img = np.full_like(hist, 255)
    return img.astype(np.uint8)


def shape_tag(size_m):
    w = max(size_m[0], size_m[2])
    h = size_m[1]
    if h < 0.05:
        return "empty"
    if w / max(h, 1e-6) >= 2.2:
        return "wide-patch?"
    if h >= 2.2:
        return "tree?"
    if h < 0.4:
        return "low-tuft?"
    if h / w >= 1.35:
        return "cone?"
    return "bush?"


def do_census(src, outdir):
    from PIL import Image, ImageDraw, ImageFont

    os.makedirs(outdir, exist_ok=True)
    positions, objects, order = parse_obj(src)
    rows = []
    for key in order:
        rec = objects[key]
        tris = object_arrays(positions, rec)
        mn, mx, nref = referenced_aabb(positions, tris)
        if mn is None or len(tris) == 0:
            continue
        size_m = ((mx - mn) * MM_TO_M).tolist()
        comp, sampled = components_sample(tris)
        rows.append({
            "key": key, "name": rec["name"], "tris": int(len(tris)),
            "verts_referenced": int(nref),
            "size_m": [round(v, 3) for v in size_m],
            "min_m": [round(v * MM_TO_M, 3) for v in mn.tolist()],
            "h_over_w": round(size_m[1] / max(size_m[0], size_m[2], 1e-6), 2),
            "components_sample": comp, "components_sample_tris": sampled,
            "components_per_1k_tris": round(comp / max(1, sampled) * 1000, 2),
            "tag": shape_tag(size_m),
            "_tris": tris,
        })
    rows.sort(key=lambda r: -r["size_m"][1])

    # Contact sheets: 4 columns, front silhouette + labels.
    cell_w, cell_h, label_h, cols = 340, 320, 64, 4
    per_sheet = cols * 5
    font = ImageFont.load_default()
    sheets = []
    for s0 in range(0, len(rows), per_sheet):
        chunk = rows[s0:s0 + per_sheet]
        nrows = math.ceil(len(chunk) / cols)
        sheet = Image.new("L", (cols * cell_w, nrows * (cell_h + label_h)), 255)
        draw = ImageDraw.Draw(sheet)
        for i, r in enumerate(chunk):
            cx, cy = (i % cols) * cell_w, (i // cols) * (cell_h + label_h)
            img = Image.fromarray(front_density(positions, r["_tris"], 320), "L")
            sheet.paste(img, (cx + 10, cy))
            sz = r["size_m"]
            txt = (f"{r['name']}  h{sz[1]:.2f}m w{max(sz[0], sz[2]):.2f}m\n"
                   f"tris {r['tris'] // 1000}k  comp/1k {r['components_per_1k_tris']}  {r['tag']}")
            draw.multiline_text((cx + 10, cy + cell_h + 4), txt, fill=0, font=font)
        name = f"sheet-{s0 // per_sheet + 1}.png"
        sheet.save(os.path.join(outdir, name))
        sheets.append(name)

    public = [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows]
    with open(os.path.join(outdir, "census.json"), "w", encoding="utf-8") as fh:
        json.dump({"objects": public, "sheets": sheets}, fh, ensure_ascii=False, indent=1)
    md = ["# OBJ plants census (units read as mm -> m)", "",
          "| object | tris | size m (x,y,z) | h/w | comp/1k | tag |", "|---|---:|---|---:|---:|---|"]
    for r in public:
        md.append(f"| `{r['name']}` | {r['tris']} | {r['size_m']} | {r['h_over_w']} | {r['components_per_1k_tris']} | {r['tag']} |")
    md.append("")
    md.append("Sheets: " + ", ".join(sheets))
    with open(os.path.join(outdir, "census.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(md) + "\n")
    print(json.dumps({"ok": True, "objects": len(public), "sheets": sheets}))
    return 0


# --------------------------------------------------------------------------
# Conversion helpers
# --------------------------------------------------------------------------
def compact(pos, tris):
    ref, inv = np.unique(tris, return_inverse=True)
    return pos[ref].astype(np.float32), inv.reshape(-1, 3).astype(np.int64)


def thin(tris, budget, seed=42):
    if len(tris) <= budget:
        return tris
    rng = np.random.default_rng(seed)
    keep = np.sort(rng.permutation(len(tris))[:budget])
    return tris[keep]


def cluster_once(pos, tris, cell):
    q = np.floor(pos / cell).astype(np.int64)
    _, inv = np.unique(q, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    n = int(inv.max()) + 1
    cnt = np.bincount(inv, minlength=n).astype(np.float64)
    newpos = np.stack([
        np.bincount(inv, weights=pos[:, ax], minlength=n) / cnt for ax in range(3)
    ], axis=1)
    t = inv[tris]
    keep = (t[:, 0] != t[:, 1]) & (t[:, 1] != t[:, 2]) & (t[:, 0] != t[:, 2])
    t = t[keep]
    ts = np.sort(t, axis=1)
    _, uidx = np.unique(ts, axis=0, return_index=True)
    return newpos.astype(np.float32), t[np.sort(uidx)].astype(np.int64)


def cluster_to_budget(pos, tris, budget):
    if len(tris) <= budget:
        return pos, tris
    diag = float(np.linalg.norm(pos.max(axis=0) - pos.min(axis=0)))
    cell = diag / 90.0
    best = (pos, tris)
    for _ in range(14):
        p2, t2 = cluster_once(pos, tris, cell)
        best = (p2, t2)
        if len(t2) <= budget:
            return p2, t2
        cell *= 1.35
    return best


def smooth_normals(pos, tris):
    n = np.zeros((len(pos), 3), dtype=np.float64)
    v0, v1, v2 = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    for ax in range(3):
        np.add.at(n[:, ax], tris[:, 0], fn[:, ax])
        np.add.at(n[:, ax], tris[:, 1], fn[:, ax])
        np.add.at(n[:, ax], tris[:, 2], fn[:, ax])
    ln = np.linalg.norm(n, axis=1)
    ln[ln == 0] = 1.0
    return (n / ln[:, None]).astype(np.float32)


def box_uv(pos, nrm, tile):
    axis = np.argmax(np.abs(nrm), axis=1)
    uv = np.zeros((len(pos), 2), dtype=np.float32)
    for ax, (u, v) in ((0, (2, 1)), (1, (0, 2)), (2, (0, 1))):
        m = axis == ax
        uv[m, 0] = pos[m, u] / tile
        uv[m, 1] = pos[m, v] / tile
    return uv


def write_glb(path, meshes):
    """meshes: list of dicts name/material/pos/nrm/uv/idx (numpy arrays)."""
    binbuf = bytearray()
    views, accessors, gltf_meshes, nodes = [], [], [], []

    def add_accessor(data: bytes, target, comp_type, count, acc_type, mn=None, mx=None):
        while len(binbuf) % 4:
            binbuf.append(0)
        views.append({"buffer": 0, "byteOffset": len(binbuf), "byteLength": len(data), "target": target})
        binbuf.extend(data)
        acc = {"bufferView": len(views) - 1, "componentType": comp_type, "count": int(count), "type": acc_type}
        if mn is not None:
            acc["min"] = [float(v) for v in mn]
            acc["max"] = [float(v) for v in mx]
        accessors.append(acc)
        return len(accessors) - 1

    materials = [
        {"name": "nh_foliage", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "roughnessFactor": 1.0, "metallicFactor": 0.0}, "doubleSided": True},
        {"name": "nh_bark", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "roughnessFactor": 1.0, "metallicFactor": 0.0}},
    ]
    mat_index = {"nh_foliage": 0, "nh_bark": 1}
    for m in meshes:
        pos, nrm, uv, idx = m["pos"], m["nrm"], m["uv"], m["idx"]
        a_pos = add_accessor(pos.astype(np.float32).tobytes(), 34962, 5126, len(pos), "VEC3",
                             pos.min(axis=0), pos.max(axis=0))
        a_nrm = add_accessor(nrm.astype(np.float32).tobytes(), 34962, 5126, len(nrm), "VEC3")
        a_uv = add_accessor(uv.astype(np.float32).tobytes(), 34962, 5126, len(uv), "VEC2")
        a_idx = add_accessor(idx.astype(np.uint32).tobytes(), 34963, 5125, len(idx) * 3, "SCALAR")
        gltf_meshes.append({
            "name": m["name"],
            "primitives": [{
                "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
                "indices": a_idx, "material": mat_index[m["material"]], "mode": 4,
            }],
        })
        nodes.append({"name": m["name"], "mesh": len(gltf_meshes) - 1})
    gltf = {
        "asset": {"version": "2.0", "generator": "obj-plants.py (Nitches Horizon)"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gltf_meshes,
        "materials": materials,
        "buffers": [{"byteLength": len(binbuf)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(binbuf) % 4:
        binbuf.append(0)
    total = 12 + 8 + len(js) + 8 + len(binbuf)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, total))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A))
        fh.write(js)
        fh.write(struct.pack("<II", len(binbuf), 0x004E4942))
        fh.write(binbuf)


def convert_species(positions, rec, spec):
    tris = object_arrays(positions, rec)
    pos, tris = compact(positions, tris)
    budget = int(spec["tris"])
    strategy = spec.get("strategy", "cluster+thin")
    if strategy == "thin":
        tris = thin(tris, budget)
    elif strategy == "cluster":
        pos, tris = cluster_to_budget(pos, tris, budget)
    else:  # cluster+thin: gentle cluster, then thin leftovers
        pos, tris = cluster_to_budget(pos, tris, max(budget * 2, budget + 500))
        tris = thin(tris, budget)
    pos, tris = compact(pos, tris)
    # mm -> m, recentre: AABB centre XZ to origin, base to y=0.
    pos = pos * MM_TO_M
    mn, mx = pos.min(axis=0), pos.max(axis=0)
    pos[:, 0] -= (mn[0] + mx[0]) / 2
    pos[:, 2] -= (mn[2] + mx[2]) / 2
    pos[:, 1] -= mn[1]
    height = float(mx[1] - mn[1])
    width = float(max(mx[0] - mn[0], mx[2] - mn[2]))

    # Optional bark split: central low column reads as trunk.
    parts = []
    if spec.get("bark") and height > 1.0:
        cent = pos[tris].mean(axis=1)
        r2 = cent[:, 0] ** 2 + cent[:, 2] ** 2
        is_bark = (r2 < (0.17 * width) ** 2) & (cent[:, 1] < 0.45 * height)
        if is_bark.any() and (~is_bark).any():
            parts.append(("bark", tris[is_bark], 0.85))
            parts.append(("foliage", tris[~is_bark], 1.15))
    if not parts:
        parts.append(("foliage", tris, 1.15))

    out = []
    for kind, t, tile in parts:
        p2, t2 = compact(pos, t)
        nrm = smooth_normals(p2, t2)
        uv = box_uv(p2, nrm, tile)
        out.append({
            "name": f"{spec['key']}_{kind}",
            "material": "nh_bark" if kind == "bark" else "nh_foliage",
            "pos": p2, "nrm": nrm, "uv": uv, "idx": t2,
            "tris": int(len(t2)), "height_m": round(height, 3),
        })
    return out


def do_convert(src, cfg_path, out_path):
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    positions, objects, _ = parse_obj(src)
    meshes, summary = [], []
    for spec in cfg["species"]:
        rec = objects.get(spec["object"])
        if rec is None:
            # allow addressing by source name when unique
            matches = [r for r in objects.values() if r["name"] == spec["object"]]
            if len(matches) != 1:
                print(f"object not found or ambiguous: {spec['object']}", file=sys.stderr)
                return 3
            rec = matches[0]
        parts = convert_species(positions, rec, spec)
        meshes.extend(parts)
        summary.append({
            "key": spec["key"], "object": spec["object"],
            "parts": [{"name": p["name"], "tris": p["tris"], "height_m": p["height_m"]} for p in parts],
        })
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    write_glb(out_path, meshes)
    print(json.dumps({"ok": True, "glb_bytes": os.path.getsize(out_path), "species": summary}, indent=1))
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "census" and len(sys.argv) == 4:
        return do_census(sys.argv[2], sys.argv[3])
    if len(sys.argv) >= 2 and sys.argv[1] == "convert" and len(sys.argv) == 5:
        return do_convert(sys.argv[2], sys.argv[3], sys.argv[4])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
