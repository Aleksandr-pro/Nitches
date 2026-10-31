#!/usr/bin/env python3
"""Model weight / draw-budget audit for Nitches (0.3.4; runtime estimate 0.3.5).

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
import math
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



# --- 0.3.5 runtime estimate -------------------------------------------------
# The shipped JSON still carries ~300 buildings with model="generic":
# the world builder classifies them into premium fixed-scale GLBs by
# kind/size at load time.  Counting only direct `model` stems therefore
# understates the heavy repeats (262 premium townhouses).  The tables
# below mirror native/scripts/world_builder.gd (_build_buildings
# classification, _batched_model_chunk_size, _add_building_far_proxy
# cells) so this audit reports what the phone actually submits.

CITY_STEMS_035 = {
    "office_tower_low", "office_tower_mid", "office_tower_high",
    "midrise_a", "midrise_b", "warehouse_large", "warehouse_small",
    "container_red", "container_blue", "villa_b", "townhouse_b",
    "barn", "greenhouse", "shopping_mall",
    "turbine_hall_long", "turbine_hall_short",
}
DETAIL_CHUNK_035 = {"townhouse": 360.0, "villa": 460.0, "hero_building": 460.0,
                    "glass_tower": 520.0, "grand_hotel": 520.0}
PROXY_CHUNK_035 = {"townhouse": 560.0, "villa": 560.0, "hero_building": 700.0,
                   "glass_tower": 700.0, "grand_hotel": 700.0}
PROXY_BOXES_035 = {
    "villa": 2, "townhouse": 2, "hero_building": 2, "glass_tower": 2,
    "grand_hotel": 3, "office_tower_low": 3, "office_tower_mid": 4,
    "office_tower_high": 4, "midrise_a": 2, "midrise_b": 2,
    "warehouse_large": 2, "warehouse_small": 2, "container_red": 1,
    "container_blue": 1, "villa_b": 2, "townhouse_b": 2, "barn": 2,
    "greenhouse": 2, "shopping_mall": 2, "turbine_hall_long": 2,
    "turbine_hall_short": 2,
}
# Gate for the classified city+premium detail layer.  0.3.4 shipped
# 6 398 of these nodes (premium models still at 180 m cells); the
# 0.3.5 wide-cell pass measures 4 031.  Keep regressions visible.
DETAIL_NODE_BUDGET_035 = 4400


def classify_building(building: dict) -> str:
    model = str(building.get("model", "generic"))
    kind = str(building.get("kind", ""))
    w = float(building.get("w", 20.0))
    d = float(building.get("d", 16.0))
    h = float(building.get("h", 10.0))
    total = max(h + float(building.get("roofH", 0.0)), 5.0)
    if model.startswith("cottage_"):
        return model
    if model in ("villa", "glass_tower"):
        return model
    if model in CITY_STEMS_035:
        return model
    if kind == "rt-villa" and w <= 29.0 and d <= 22.0 and total <= 13.0:
        return "townhouse"
    if kind == "rt-hotel" and h > 38.0 and 33.0 <= w <= 36.0 and 25.0 <= d <= 28.0:
        return "grand_hotel"
    if kind == "rt-hotel" and 15.0 <= h <= 38.0 and w <= 55.0 and d <= 38.0:
        return "hero_building"
    return "GENERIC"


def _cell_count(points: list, chunk_m: float) -> int:
    return len({(math.floor((x + 3500.0) / chunk_m), math.floor((z + 3500.0) / chunk_m))
                for x, z in points})


def runtime_building_audit(world: dict, by_stem: dict, top: int) -> dict:
    positions: dict = collections.defaultdict(list)
    instances: dict = collections.Counter()
    generic = 0
    for building in world.get("buildings", []):
        stem = classify_building(building)
        if stem == "GENERIC":
            generic += 1
            continue
        if stem not in by_stem:
            continue
        positions[stem].append((float(building.get("x", 0.0)), float(building.get("z", 0.0))))
        instances[stem] += 1
        if stem.startswith("container") and float(building.get("h", 0.0)) > 4.0:
            instances[stem] += 1  # stacked second box (same cell)
    rows = []
    detail_nodes = 0
    proxy_nodes = 0
    worst_tris = 0
    for stem, points in positions.items():
        parts = by_stem[stem]["primitives"]
        chunk = 620.0 if stem in CITY_STEMS_035 else DETAIL_CHUNK_035.get(stem, 180.0)
        d_nodes = _cell_count(points, chunk) * parts
        p_chunk = 820.0 if stem in CITY_STEMS_035 else PROXY_CHUNK_035.get(stem, 260.0)
        p_nodes = _cell_count(points, p_chunk) * PROXY_BOXES_035.get(stem, 0)
        tris = by_stem[stem]["unique_tris"] * instances[stem]
        detail_nodes += d_nodes
        proxy_nodes += p_nodes
        worst_tris += tris
        rows.append((d_nodes, stem, instances[stem], parts, p_nodes, tris))
    print("\nRichTown runtime estimate (builder classification, chunked MultiMesh nodes):")
    for d_nodes, stem, count, parts, p_nodes, tris in sorted(rows, reverse=True)[:top]:
        print(f"  {stem:24s} x{count:4d}  parts={parts:2d}  detail_nodes={d_nodes:5d}  "
              f"proxy_nodes={p_nodes:4d}  worst_tris={fmt(tris):>9s}")
    print(f"  TOTAL detail_nodes={fmt(detail_nodes)}  proxy_nodes={fmt(proxy_nodes)}  "
          f"worst_tris={fmt(worst_tris)}  generic_boxes={generic}")
    return {"generic": generic, "detail_nodes": detail_nodes,
            "proxy_nodes": proxy_nodes, "worst_tris": worst_tris}


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

    runtime = {"generic": 0, "detail_nodes": 0, "proxy_nodes": 0}
    if world_path.exists():
        runtime = runtime_building_audit(
            json.loads(world_path.read_text(encoding="utf-8")), by_stem, args.top)

    problems = []
    if runtime["generic"]:
        problems.append(
            f"{runtime['generic']} RichTown buildings still render as generic "
            "massing boxes (0.3.5 target: 0)")
    if runtime["detail_nodes"] > DETAIL_NODE_BUDGET_035:
        problems.append(
            f"runtime detail layer needs {runtime['detail_nodes']} MultiMesh "
            f"nodes (0.3.5 budget: {DETAIL_NODE_BUDGET_035})")
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
