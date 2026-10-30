#!/usr/bin/env python3
"""Model weight / draw-budget audit for Nitches (0.3.4).

Reads every committed GLB directly (glTF JSON chunk only, stdlib only)
and reports the numbers that decide whether a phone keeps frame:

  * file bytes (download / import weight),
  * node and mesh-object counts (scene traversal + import cost),
  * material/primitive counts (MultiMesh part count after merging),
  * unique triangles per model and per placed instance
    (RichTown building data -> worst-case submitted triangles if the
    HLOD layer ever failed open).

Usage:
    python3 scripts/audit-model-performance.py [--top 20] [--strict]

--strict exits 1 when a prop GLB still carries >250 mesh objects
(unmerged Blender output) so the check can gate releases once the
0.3.4 merged exports have landed.
"""

import argparse
import collections
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_glb(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError(f"not a GLB: {path}")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:  # 'JSON'
        raise ValueError(f"first GLB chunk is not JSON: {path}")
    return json.loads(data[20:20 + json_length])


def primitive_triangles(primitive: dict, accessors: list) -> int:
    mode = primitive.get("mode", 4)
    if "indices" in primitive:
        count = int(accessors[primitive["indices"]].get("count", 0))
    else:
        position = primitive.get("attributes", {}).get("POSITION")
        count = int(accessors[position].get("count", 0)) if position is not None else 0
    if mode == 4:  # TRIANGLES
        return count // 3
    if mode in (5, 6):  # STRIP / FAN (not produced by our exporter)
        return max(count - 2, 0)
    return 0


def audit_glb(path: Path) -> dict:
    gltf = read_glb(path)
    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])
    mesh_tris = []
    primitives = 0
    for mesh in meshes:
        tris = 0
        for primitive in mesh.get("primitives", []):
            primitives += 1
            tris += primitive_triangles(primitive, accessors)
        mesh_tris.append(tris)
    placed_tris = 0
    mesh_nodes = 0
    for node in gltf.get("nodes", []):
        if "mesh" in node:
            mesh_nodes += 1
            placed_tris += mesh_tris[node["mesh"]]
    materials = [m.get("name", "") for m in gltf.get("materials", [])]
    return {
        "stem": path.stem,
        "bytes": path.stat().st_size,
        "nodes": len(gltf.get("nodes", [])),
        "mesh_nodes": mesh_nodes,
        "meshes": len(meshes),
        "primitives": primitives,
        "materials": materials,
        "unique_tris": sum(mesh_tris),
        "placed_tris": placed_tris,
        "images": len(gltf.get("images", [])),
        "extensions": sorted(gltf.get("extensionsUsed", [])),
    }


def fmt(n: int) -> str:
    return f"{n:,}".replace(",", " ")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    prop_files = sorted((ROOT / "src/assets/models/props").glob("*.glb"))
    car_files = sorted((ROOT / "src/assets/models/cars").glob("*.glb"))
    props = [audit_glb(p) for p in prop_files]
    cars = [audit_glb(p) for p in car_files]
    by_stem = {row["stem"]: row for row in props}

    print(f"Props: {len(props)} GLBs, {fmt(sum(r['bytes'] for r in props))} bytes, "
          f"{fmt(sum(r['unique_tris'] for r in props))} unique tris, "
          f"{fmt(sum(r['meshes'] for r in props))} mesh objects, "
          f"{fmt(sum(r['primitives'] for r in props))} primitives")
    print(f"Cars:  {len(cars)} GLBs, {fmt(sum(r['bytes'] for r in cars))} bytes, "
          f"{fmt(sum(r['unique_tris'] for r in cars))} unique tris, "
          f"{fmt(sum(r['meshes'] for r in cars))} mesh objects")

    def table(title, rows, key):
        print(f"\nTop {args.top} props by {title}:")
        for row in sorted(rows, key=lambda r: r[key], reverse=True)[:args.top]:
            print(f"  {row['stem']:24s} bytes={row['bytes'] // 1024:6d} KB  meshes={row['meshes']:5d}  "
                  f"prims={row['primitives']:4d}  mats={len(row['materials']):2d}  tris={fmt(row['unique_tris']):>8s}")

    table("mesh objects (unmerged export weight)", props, "meshes")
    table("triangles", props, "unique_tris")
    table("file bytes", props, "bytes")

    # RichTown placement estimate from the shipped world data.
    world_path = ROOT / "native/data/richtown_native.json"
    counts = collections.Counter()
    stack_extra = collections.Counter()
    if world_path.exists():
        world = json.loads(world_path.read_text(encoding="utf-8"))
        for building in world.get("buildings", []):
            model = building.get("model")
            if model in by_stem:
                counts[model] += 1
                if model.startswith("container") and float(building.get("h", 0)) > 4:
                    stack_extra[model] += 1
    if counts:
        print("\nRichTown placed-building worst case (all detailed LOD0 submitted):")
        total = 0
        worst = []
        for stem, count in counts.most_common():
            tris = by_stem[stem]["unique_tris"] * (count + stack_extra[stem])
            total += tris
            worst.append((tris, stem, count + stack_extra[stem], by_stem[stem]["unique_tris"]))
        for tris, stem, count, each in sorted(worst, reverse=True)[:args.top]:
            print(f"  {stem:24s} x{count:4d}  @ {fmt(each):>7s} tris = {fmt(tris):>9s}")
        print(f"  TOTAL placed buildings: {fmt(total)} tris "
              "(HLOD/visibility ranges cut this by an order of magnitude in play)")

    problems = []
    for row in props:
        if row["meshes"] > 250:
            problems.append(f"{row['stem']}: {row['meshes']} mesh objects (unmerged Blender export)")
        if counts.get(row["stem"], 0) >= 50 and row["unique_tris"] > 6000:
            problems.append(f"{row['stem']}: repeated x{counts[row['stem']]} but {row['unique_tris']} tris each")
    if problems:
        print("\nBottlenecks:")
        for problem in problems:
            print(f"  - {problem}")
    if args.strict and problems:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
