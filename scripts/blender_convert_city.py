#!/usr/bin/env python3
"""Convert a textureless Manhattan FBX into a chunked runtime city GLB.

The source package uploaded to Model Inbox contains 11 merged photogrammetry
sections but none of its external PNG textures.  At the owner's request this
converter intentionally ignores those textures and creates a readable,
mobile-oriented fallback city from geometry alone:

* source geometry is converted from miniature/kilometre-like units to metres;
* street-level vertices are flattened to a single city plate;
* original source parts are decimated before splitting;
* faces are split into 250 m spatial chunk objects in one GLB;
* roofs, facades and ground receive deterministic vertex colours;
* a 4 m occupancy raster is merged into city-local rectangle colliders.

The generated JS data module keeps colliders in city-local Three.js coords
(X east, Y up, Z south), so runtime placement can be changed without another
Blender conversion.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np


WATER_NAMES = {"water", "watter"}


# --------------------------------------------------------------------------- #
# Small utilities
# --------------------------------------------------------------------------- #

def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Convert a Model Inbox city FBX to a chunked GLB")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-glb", type=Path, required=True)
    parser.add_argument("--output-data-js", type=Path, required=True)
    parser.add_argument("--report-json", type=Path, required=True)
    parser.add_argument("--report-md", type=Path, required=True)
    parser.add_argument("--output-svg", type=Path, required=True)
    parser.add_argument("--asset-key", default="kingsford-manhattan-city")
    parser.add_argument("--display-name", default="New York City - Manhattan")
    parser.add_argument("--root-name", default="KingsfordManhattanCity")
    parser.add_argument("--scale-xy", type=float, default=250.0)
    parser.add_argument("--scale-z", type=float, default=230.0)
    parser.add_argument("--ground-source-z", type=float, default=0.008)
    parser.add_argument("--target-triangles", type=int, default=340000)
    parser.add_argument("--chunk-size", type=float, default=250.0)
    parser.add_argument("--collider-cell-size", type=float, default=4.0)
    parser.add_argument("--obstacle-height-m", type=float, default=2.0)
    return parser.parse_args(argv)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, float(value)))


def rounded(values, digits: int = 4) -> list[float]:
    return [round(float(v), digits) for v in values]


def json_round(value, digits: int = 4):
    if isinstance(value, dict):
        return {k: json_round(v, digits) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_round(v, digits) for v in value]
    if isinstance(value, (np.floating, float)):
        return round(float(value), digits)
    if isinstance(value, (np.integer,)):
        return int(value)
    return value


def hash01(*values: int) -> float:
    """Deterministic small integer hash used for fallback colour variation."""
    n = 2166136261
    for value in values:
        n ^= int(value) & 0xFFFFFFFF
        n = (n * 16777619) & 0xFFFFFFFF
        n ^= n >> 13
        n = (n * 0x5BD1E995) & 0xFFFFFFFF
        n ^= n >> 15
    return n / 4294967295.0


def shade(color: tuple[float, float, float], multiplier: float) -> tuple[float, float, float]:
    return tuple(clamp(float(c) * multiplier, 0.0, 1.0) for c in color)


# --------------------------------------------------------------------------- #
# Blender import / extraction
# --------------------------------------------------------------------------- #

def import_fbx(path: Path) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"


def is_water_object(obj) -> bool:
    names = [obj.name]
    names.extend(slot.material.name for slot in obj.material_slots if slot.material)
    return any(name.strip().lower() in WATER_NAMES for name in names)


def extract_mesh(obj, depsgraph) -> dict | None:
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    if not mesh or not mesh.vertices:
        if mesh:
            evaluated.to_mesh_clear()
        return None
    try:
        mesh.calc_loop_triangles()
        verts = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", verts)
        verts = verts.reshape((-1, 3)).astype(np.float64, copy=False)

        tris = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int32)
        if len(mesh.loop_triangles):
            mesh.loop_triangles.foreach_get("vertices", tris)
        tris = tris.reshape((-1, 3)).astype(np.int64, copy=False)

        matrix = np.array(evaluated.matrix_world, dtype=np.float64)
        world = verts @ matrix[:3, :3].T + matrix[:3, 3]
        return {
            "object": obj,
            "name": obj.name,
            "vertices": world,
            "triangles": tris,
        }
    finally:
        evaluated.to_mesh_clear()


def extract_all(objects) -> list[dict]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    out = []
    for obj in objects:
        item = extract_mesh(obj, depsgraph)
        if item and len(item["triangles"]):
            out.append(item)
    return out


def tri_count(items: list[dict]) -> int:
    return int(sum(len(item["triangles"]) for item in items))


def apply_decimation(objects, ratio: float) -> None:
    ratio = clamp(ratio, 0.02, 1.0)
    if ratio >= 0.999:
        return
    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        modifier = obj.modifiers.new(name="NitchesCityDecimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        try:
            modifier.use_collapse_triangulate = True
        except Exception:
            pass
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = obj.evaluated_get(depsgraph)
        new_mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        old_mesh = obj.data
        try:
            obj.modifiers.remove(modifier)
        except Exception:
            pass
        obj.data = new_mesh
        if old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)
    bpy.context.view_layer.update()


# --------------------------------------------------------------------------- #
# Transform / colours
# --------------------------------------------------------------------------- #

class CityTransform:
    def __init__(self, source_min: np.ndarray, source_max: np.ndarray, args: argparse.Namespace):
        self.source_min = source_min
        self.source_max = source_max
        self.source_center = (source_min + source_max) * 0.5
        self.scale_xy = float(args.scale_xy)
        self.scale_z = float(args.scale_z)
        self.ground_source_z = float(args.ground_source_z)
        self.width_m = float(source_max[0] - source_min[0]) * self.scale_xy
        self.depth_m = float(source_max[1] - source_min[1]) * self.scale_xy
        self.min_x = -self.width_m * 0.5
        self.max_x = self.width_m * 0.5
        # Three.js local Z is -Blender Y, but the extent is symmetric.
        self.min_z = -self.depth_m * 0.5
        self.max_z = self.depth_m * 0.5

    def to_blender_local(self, vertices: np.ndarray) -> np.ndarray:
        out = np.empty_like(vertices, dtype=np.float64)
        out[:, 0] = (vertices[:, 0] - self.source_center[0]) * self.scale_xy
        out[:, 1] = (vertices[:, 1] - self.source_center[1]) * self.scale_xy
        dz = vertices[:, 2] - self.ground_source_z
        out[:, 2] = np.maximum(dz, 0.0) * self.scale_z
        return out

    def to_three_local(self, vertices: np.ndarray) -> np.ndarray:
        blender = self.to_blender_local(vertices)
        out = np.empty_like(blender)
        out[:, 0] = blender[:, 0]
        out[:, 1] = -blender[:, 1]  # Three Z
        out[:, 2] = blender[:, 2]  # Three Y/up
        return out


GROUND_COLORS = [
    (0.13, 0.14, 0.15),
    (0.19, 0.20, 0.21),
    (0.30, 0.31, 0.30),
    (0.16, 0.23, 0.12),
]
ROOF_COLORS = [
    (0.42, 0.40, 0.36),
    (0.28, 0.29, 0.31),
    (0.52, 0.43, 0.34),
    (0.36, 0.42, 0.48),
    (0.48, 0.45, 0.40),
    (0.24, 0.25, 0.27),
]
FACADE_COLORS = [
    (0.48, 0.39, 0.30),
    (0.42, 0.43, 0.46),
    (0.52, 0.46, 0.38),
    (0.24, 0.34, 0.45),
    (0.55, 0.38, 0.27),
    (0.38, 0.36, 0.34),
]


def face_color(points: np.ndarray, up_ratio: float, part_index: int) -> tuple[float, float, float]:
    centroid = points.mean(axis=0)
    h = float(centroid[2])
    block_x = math.floor(float(centroid[0]) / 12.0)
    block_y = math.floor(float(centroid[1]) / 12.0)
    fine_x = math.floor(float(centroid[0]) / 4.0)
    fine_y = math.floor(float(centroid[1]) / 4.0)
    block_hash = hash01(block_x, block_y, part_index * 131)
    fine_hash = hash01(fine_x, fine_y, part_index * 17 + 7)

    if up_ratio > 0.68 and h < 0.9:
        if fine_hash < 0.65:
            color = GROUND_COLORS[0] if block_hash < 0.5 else GROUND_COLORS[1]
        elif fine_hash < 0.88:
            color = GROUND_COLORS[2]
        else:
            color = GROUND_COLORS[3]
        return shade(color, 0.88 + fine_hash * 0.24)

    if up_ratio > 0.68:
        color = ROOF_COLORS[int(block_hash * len(ROOF_COLORS)) % len(ROOF_COLORS)]
        return shade(color, 0.88 + fine_hash * 0.22)

    if up_ratio < 0.48 and h > 1.2:
        base = FACADE_COLORS[int(block_hash * len(FACADE_COLORS)) % len(FACADE_COLORS)]
        floor_index = int(h // 3.0)
        window_hash = hash01(fine_x, fine_y, floor_index, part_index * 31)
        if window_hash < 0.16:
            return (0.035, 0.07, 0.11)
        return shade(base, 0.80 + window_hash * 0.34)

    # Slopes, bridges, embankments and irregular photogrammetry transitions.
    concrete = (0.30, 0.30, 0.27)
    olive = (0.24, 0.27, 0.17)
    color = olive if h < 3.0 and block_hash < 0.25 else concrete
    return shade(color, 0.85 + fine_hash * 0.25)


# --------------------------------------------------------------------------- #
# Collider raster
# --------------------------------------------------------------------------- #

def build_colliders(meshes: list[dict], transform: CityTransform, args: argparse.Namespace):
    cell = float(args.collider_cell_size)
    obstacle_y = float(args.obstacle_height_m)
    cols = max(1, int(math.ceil((transform.max_x - transform.min_x) / cell)))
    rows = max(1, int(math.ceil((transform.max_z - transform.min_z) / cell)))
    occ = np.zeros((rows, cols), dtype=bool)

    min_x = transform.min_x
    min_z = transform.min_z

    def mark_point(x: float, z: float) -> None:
        cx = int(math.floor((x - min_x) / cell))
        cz = int(math.floor((z - min_z) / cell))
        if 0 <= cx < cols and 0 <= cz < rows:
            occ[cz, cx] = True

    def mark_segment(ax: float, az: float, bx: float, bz: float) -> None:
        length = math.hypot(bx - ax, bz - az)
        steps = max(1, int(math.ceil(length / max(cell * 0.5, 0.1))))
        for i in range(steps + 1):
            t = i / steps
            mark_point(ax + (bx - ax) * t, az + (bz - az) * t)

    for item in meshes:
        pts = transform.to_three_local(item["vertices"])  # columns: x, gameZ, heightY
        for ia, ib, ic in item["triangles"]:
            ax, az, ay = [float(v) for v in pts[int(ia)]]
            bx, bz, by = [float(v) for v in pts[int(ib)]]
            cxp, czp, cy = [float(v) for v in pts[int(ic)]]
            max_y = max(ay, by, cy)
            if max_y < obstacle_y:
                continue

            # Vertices and centroid catch narrow/vertical faces whose 2D
            # projection is a line rather than a usable triangle.
            centroid_y = (ay + by + cy) / 3.0
            if centroid_y >= obstacle_y * 0.75:
                mark_point((ax + bx + cxp) / 3.0, (az + bz + czp) / 3.0)
            for px, pz, py in ((ax, az, ay), (bx, bz, by), (cxp, czp, cy)):
                if py >= obstacle_y:
                    mark_point(px, pz)

            points_by_height = sorted(((ax, az, ay), (bx, bz, by), (cxp, czp, cy)), key=lambda p: p[2])
            mark_segment(points_by_height[0][0], points_by_height[0][1], points_by_height[1][0], points_by_height[1][1])

            denom = (bz - czp) * (ax - cxp) + (cxp - bx) * (az - czp)
            if abs(denom) < 1e-9:
                continue
            cell_x0 = int(math.floor((min(ax, bx, cxp) - min_x) / cell))
            cell_x1 = int(math.floor((max(ax, bx, cxp) - min_x) / cell))
            cell_z0 = int(math.floor((min(az, bz, czp) - min_z) / cell))
            cell_z1 = int(math.floor((max(az, bz, czp) - min_z) / cell))
            cell_x0 = max(0, min(cols - 1, cell_x0))
            cell_x1 = max(0, min(cols - 1, cell_x1))
            cell_z0 = max(0, min(rows - 1, cell_z0))
            cell_z1 = max(0, min(rows - 1, cell_z1))
            for grid_z in range(cell_z0, cell_z1 + 1):
                pz = min_z + (grid_z + 0.5) * cell
                for grid_x in range(cell_x0, cell_x1 + 1):
                    px = min_x + (grid_x + 0.5) * cell
                    w0 = ((bz - czp) * (px - cxp) + (cxp - bx) * (pz - czp)) / denom
                    w1 = ((czp - az) * (px - cxp) + (ax - cxp) * (pz - czp)) / denom
                    w2 = 1.0 - w0 - w1
                    if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                        continue
                    y = w0 * ay + w1 * by + w2 * cy
                    if y >= obstacle_y:
                        occ[grid_z, grid_x] = True

    def neighbour_count(grid: np.ndarray) -> np.ndarray:
        count = np.zeros_like(grid, dtype=np.int32)
        count[1:, :] += grid[:-1, :]
        count[:-1, :] += grid[1:, :]
        count[:, 1:] += grid[:, :-1]
        count[:, :-1] += grid[:, 1:]
        return count

    # Remove single-cell noise, then fill one-cell holes inside roofs/blocks.
    occ = occ & (neighbour_count(occ) > 0)
    occ = occ | ((~occ) & (neighbour_count(occ) == 4))

    active: dict[tuple[int, int], int] = {}
    rectangles: list[list[float]] = []

    def finish_run(key: tuple[int, int], start_row: int, end_row_exclusive: int) -> None:
        c0, c1 = key
        x0 = min_x + c0 * cell
        x1 = min_x + (c1 + 1) * cell
        z0 = min_z + start_row * cell
        z1 = min_z + end_row_exclusive * cell
        rectangles.append([
            round((x0 + x1) * 0.5, 2),
            round((z0 + z1) * 0.5, 2),
            round((x1 - x0) * 0.5, 2),
            round((z1 - z0) * 0.5, 2),
        ])

    for row in range(rows):
        runs: list[tuple[int, int]] = []
        start = None
        for col in range(cols + 1):
            occupied = col < cols and bool(occ[row, col])
            if occupied and start is None:
                start = col
            if not occupied and start is not None:
                runs.append((start, col - 1))
                start = None
        run_set = set(runs)
        for key, start_row in list(active.items()):
            if key not in run_set:
                finish_run(key, start_row, row)
                del active[key]
        for key in runs:
            active.setdefault(key, row)
    for key, start_row in active.items():
        finish_run(key, start_row, rows)

    rectangles.sort(key=lambda r: (r[1], r[0], r[2], r[3]))
    return occ, rectangles, {"rows": rows, "cols": cols, "occupiedCells": int(np.count_nonzero(occ))}


def write_occupancy_svg(path: Path, rectangles: list[list[float]], transform: CityTransform, chunk_size: float) -> None:
    width = 1200
    height = 1000
    pad = 30
    span_x = transform.max_x - transform.min_x
    span_z = transform.max_z - transform.min_z
    scale = min((width - pad * 2) / span_x, (height - pad * 2) / span_z)
    off_x = (width - span_x * scale) / 2
    off_y = (height - span_z * scale) / 2

    def sx(x: float) -> float:
        return off_x + (x - transform.min_x) * scale

    def sy(z: float) -> float:
        return off_y + (z - transform.min_z) * scale

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#17212b"/>',
        '<text x="24" y="28" fill="#ffffff" font-family="sans-serif" font-size="20" font-weight="700">Manhattan city occupancy / colliders</text>',
        '<text x="24" y="52" fill="#bfd4e2" font-family="sans-serif" font-size="13">City-local coordinates: X east, Z south (north is up). Red rectangles are merged 4 m obstacle cells.</text>',
        f'<rect x="{sx(transform.min_x):.2f}" y="{sy(transform.min_z):.2f}" width="{span_x * scale:.2f}" height="{span_z * scale:.2f}" fill="#2d3a33" stroke="#ffffff" stroke-opacity="0.5"/>',
    ]
    x = transform.min_x
    while x <= transform.max_x + 0.01:
        lines.append(f'<line x1="{sx(x):.2f}" y1="{sy(transform.min_z):.2f}" x2="{sx(x):.2f}" y2="{sy(transform.max_z):.2f}" stroke="#ffffff" stroke-opacity="0.16"/>')
        x += chunk_size
    z = transform.min_z
    while z <= transform.max_z + 0.01:
        lines.append(f'<line x1="{sx(transform.min_x):.2f}" y1="{sy(z):.2f}" x2="{sx(transform.max_x):.2f}" y2="{sy(z):.2f}" stroke="#ffffff" stroke-opacity="0.16"/>')
        z += chunk_size
    for cx, cz, hw, hd in rectangles:
        lines.append(
            f'<rect x="{sx(cx - hw):.2f}" y="{sy(cz - hd):.2f}" width="{max(1.0, hw * 2 * scale):.2f}" '
            f'height="{max(1.0, hd * 2 * scale):.2f}" fill="#d95d4e" fill-opacity="0.78">'
            f'<title>{html.escape(f"collider {cx:.1f},{cz:.1f} {hw*2:.1f}×{hd*2:.1f} m")}</title></rect>'
        )
    lines.append("</svg>")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# Output scene construction / export
# --------------------------------------------------------------------------- #

def build_material() -> bpy.types.Material:
    mat = bpy.data.materials.new(name="ManhattanVertexColor")
    mat.use_nodes = True
    mat.use_backface_culling = False
    tree = mat.node_tree
    tree.nodes.clear()
    output = tree.nodes.new(type="ShaderNodeOutputMaterial")
    output.location = (360, 0)
    bsdf = tree.nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (130, 0)
    bsdf.inputs["Roughness"].default_value = 0.94
    bsdf.inputs["Metallic"].default_value = 0.0
    color_node = tree.nodes.new(type="ShaderNodeVertexColor")
    color_node.location = (-150, 0)
    color_node.layer_name = "Color"
    tree.links.new(color_node.outputs["Color"], bsdf.inputs["Base Color"])
    tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return mat


def build_chunk_objects(meshes: list[dict], transform: CityTransform, args: argparse.Namespace, material):
    transformed_parts = []
    offsets = []
    all_vertices = []
    offset = 0
    for item in meshes:
        transformed = transform.to_blender_local(item["vertices"])
        transformed_parts.append(transformed)
        all_vertices.append(transformed)
        offsets.append(offset)
        offset += len(transformed)
    global_vertices = np.vstack(all_vertices) if all_vertices else np.empty((0, 3))

    chunk_size = float(args.chunk_size)
    bins: dict[tuple[int, int], dict] = {}
    for part_index, item in enumerate(meshes):
        tris = item["triangles"] + offsets[part_index]
        for tri in tris:
            indices = [int(tri[0]), int(tri[1]), int(tri[2])]
            points = global_vertices[indices]
            if not np.all(np.isfinite(points)):
                continue
            normal = np.cross(points[1] - points[0], points[2] - points[0])
            norm = float(np.linalg.norm(normal))
            if norm <= 1e-12:
                continue
            up_ratio = abs(float(normal[2])) / norm
            centroid = points.mean(axis=0)
            game_x = float(centroid[0])
            game_z = -float(centroid[1])
            ix = int(math.floor((game_x - transform.min_x) / chunk_size))
            iz = int(math.floor((game_z - transform.min_z) / chunk_size))
            max_ix = max(0, int(math.ceil(transform.width_m / chunk_size)) - 1)
            max_iz = max(0, int(math.ceil(transform.depth_m / chunk_size)) - 1)
            ix = max(0, min(max_ix, ix))
            iz = max(0, min(max_iz, iz))
            key = (ix, iz)
            bucket = bins.setdefault(key, {"faces": [], "colors": []})
            bucket["faces"].append(tuple(indices))
            bucket["colors"].append(face_color(points, up_ratio, part_index))

    collection = bpy.data.collections.new("KingsfordManhattanCityOutput")
    bpy.context.scene.collection.children.link(collection)
    root = bpy.data.objects.new(args.root_name, None)
    collection.objects.link(root)
    root.location = (0.0, 0.0, 0.0)

    chunk_infos = []
    output_objects = []
    total_output_vertices = 0
    for (ix, iz), bucket in sorted(bins.items()):
        faces_global = bucket["faces"]
        if not faces_global:
            continue
        center_x = transform.min_x + (ix + 0.5) * chunk_size
        center_z = transform.min_z + (iz + 0.5) * chunk_size
        blender_center = np.array([center_x, -center_z, 0.0], dtype=np.float64)

        mapping: dict[int, int] = {}
        local_vertices: list[tuple[float, float, float]] = []
        local_faces: list[tuple[int, int, int]] = []
        game_points: list[np.ndarray] = []
        for face in faces_global:
            mapped = []
            for gid in face:
                if gid not in mapping:
                    point = global_vertices[gid]
                    rel = point - blender_center
                    mapping[gid] = len(local_vertices)
                    local_vertices.append((float(rel[0]), float(rel[1]), float(rel[2])))
                    game_points.append(np.array([point[0], -point[1], point[2]], dtype=np.float64))
                mapped.append(mapping[gid])
            local_faces.append((mapped[0], mapped[1], mapped[2]))

        mesh_name = f"manhattan_{ix:02d}_{iz:02d}"
        mesh = bpy.data.meshes.new(mesh_name)
        mesh.from_pydata(local_vertices, [], local_faces)
        mesh.update(calc_edges=True)
        color_attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        flat_colors: list[float] = []
        for color in bucket["colors"]:
            for _ in range(3):
                flat_colors.extend([float(color[0]), float(color[1]), float(color[2]), 1.0])
        if flat_colors:
            color_attr.data.foreach_set("color", flat_colors)
        try:
            mesh.color_attributes.active = color_attr
        except Exception:
            pass
        mesh.materials.append(material)

        obj = bpy.data.objects.new(mesh_name, mesh)
        collection.objects.link(obj)
        obj.parent = root
        obj.location = (float(blender_center[0]), float(blender_center[1]), 0.0)
        output_objects.append(obj)
        total_output_vertices += len(local_vertices)

        if game_points:
            arr = np.vstack(game_points)
            bounds = {
                "minX": round(float(arr[:, 0].min()), 3),
                "maxX": round(float(arr[:, 0].max()), 3),
                "minZ": round(float(arr[:, 1].min()), 3),
                "maxZ": round(float(arr[:, 1].max()), 3),
                "minY": round(float(arr[:, 2].min()), 3),
                "maxY": round(float(arr[:, 2].max()), 3),
            }
        else:
            bounds = {"minX": center_x, "maxX": center_x, "minZ": center_z, "maxZ": center_z, "minY": 0, "maxY": 0}
        chunk_infos.append({
            "key": f"{ix}_{iz}",
            "ix": ix,
            "iz": iz,
            "meshName": mesh_name,
            "centerX": round(center_x, 3),
            "centerZ": round(center_z, 3),
            "bounds": bounds,
            "triangles": len(local_faces),
            "vertices": len(local_vertices),
        })

    bpy.context.view_layer.update()
    return root, output_objects, chunk_infos, total_output_vertices


def export_glb(path: Path, root, objects) -> list[str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    kwargs = {
        "filepath": str(path),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
        "export_materials": "EXPORT",
    }
    used = list(kwargs.keys())
    try:
        props = bpy.ops.export_scene.gltf.get_rna_type().properties
        prop_names = set(props.keys())
    except Exception:
        prop_names = set()
        props = {}
    optional = {
        "export_texcoords": False,
        "export_normals": True,
        "export_cameras": False,
        "export_lights": False,
        "export_animations": False,
        "export_image_format": "NONE",
        "export_colors": True,
        "export_attributes": True,
    }
    for key, value in optional.items():
        if key in prop_names:
            kwargs[key] = value
            used.append(key)
    if "export_vertex_color" in prop_names:
        prop = props["export_vertex_color"]
        enum_items = getattr(prop, "enum_items", None)
        if enum_items:
            identifiers = [item.identifier for item in enum_items]
            kwargs["export_vertex_color"] = "MATERIAL" if "MATERIAL" in identifiers else identifiers[0]
        else:
            kwargs["export_vertex_color"] = True
        used.append("export_vertex_color")

    bpy.ops.export_scene.gltf(**kwargs)
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"GLB export did not create {path}")
    return sorted(set(used))


# --------------------------------------------------------------------------- #
# Reports
# --------------------------------------------------------------------------- #

def build_markdown(report: dict) -> str:
    source = report["source"]
    stats = report["stats"]
    bounds = report["transform"]["localBounds"]
    lines = [
        f"# City conversion — {report['displayName']}",
        "",
        f"- Source: `{source['name']}` ({source['size']:,} bytes)",
        f"- Source SHA-256: `{source['sha256']}`",
        f"- Blender: {report['blenderVersion']}",
        "- External textures: **missing and intentionally ignored**; deterministic vertex colours are used instead.",
        "",
        "## Transform",
        "",
        f"- Horizontal scale: {report['transform']['scaleXYMPerUnit']} m/unit",
        f"- Vertical scale: {report['transform']['scaleZMPerUnit']} m/unit above source Z {report['transform']['sourceGroundZ']}",
        f"- Local footprint: **{bounds['widthM']:.1f} × {bounds['depthM']:.1f} m**",
        f"- Local height: {bounds['minY']:.1f}…{bounds['maxY']:.1f} m",
        "- Local coordinates: X east, Y up, Z south (Blender north maps to negative Z).",
        "",
        "## Output",
        "",
        f"- Original: {stats['originalTriangles']:,} triangles / {stats['originalVertices']:,} vertices",
        f"- After decimation: {stats['decimatedTriangles']:,} triangles",
        f"- Exported chunks: {len(report['chunks'])} objects, {stats['outputTriangles']:,} triangles",
        f"- GLB: {stats['glbBytes']:,} bytes, SHA-256 `{stats['glbSha256']}`",
        f"- Colliders: {len(report['colliders']['rectangles']):,} merged rectangles from {report['colliders']['occupiedCells']:,} occupied 4 m cells",
        "",
        "## Heaviest chunks",
        "",
        "| Chunk | Triangles | Max height |",
        "|---|---:|---:|",
    ]
    for chunk in sorted(report["chunks"], key=lambda c: c["triangles"], reverse=True)[:20]:
        lines.append(f"| `{chunk['meshName']}` | {chunk['triangles']:,} | {chunk['bounds']['maxY']:.1f} m |")
    if report["warnings"]:
        lines += ["", "## Warnings", ""]
        lines.extend(f"- {warning}" for warning in report["warnings"])
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main() -> int:
    args = parse_args()
    input_path = args.input.resolve()
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 2
    if args.scale_xy <= 0 or args.scale_z <= 0 or args.chunk_size <= 0 or args.collider_cell_size <= 0:
        print("Scales and cell sizes must be positive", file=sys.stderr)
        return 2

    source_size = input_path.stat().st_size
    source_sha = sha256_file(input_path)
    import_fbx(input_path)

    city_objects = [obj for obj in bpy.data.objects if obj.type == "MESH" and not is_water_object(obj)]
    if not city_objects:
        print("No city mesh objects found after FBX import", file=sys.stderr)
        return 2

    original = extract_all(city_objects)
    if not original:
        print("Could not extract city geometry", file=sys.stderr)
        return 2
    original_triangles = tri_count(original)
    original_vertices = int(sum(len(item["vertices"]) for item in original))
    all_source_vertices = np.vstack([item["vertices"] for item in original])
    source_min = all_source_vertices.min(axis=0)
    source_max = all_source_vertices.max(axis=0)
    transform = CityTransform(source_min, source_max, args)

    transformed_original_heights = np.concatenate([
        transform.to_blender_local(item["vertices"])[:, 2] for item in original
    ])
    height_percentiles = {
        str(int(p)): round(float(np.percentile(transformed_original_heights, p)), 3)
        for p in (0, 25, 50, 75, 90, 95, 99, 100)
    }

    _, collider_rectangles, collider_grid = build_colliders(original, transform, args)
    write_occupancy_svg(args.output_svg, collider_rectangles, transform, float(args.chunk_size))

    decimation_ratio = clamp(float(args.target_triangles) / max(original_triangles, 1), 0.02, 1.0)
    apply_decimation(city_objects, decimation_ratio)
    decimated = extract_all(city_objects)
    decimated_triangles = tri_count(decimated)
    if decimated_triangles > int(args.target_triangles * 1.12):
        second_ratio = clamp(float(args.target_triangles) / max(decimated_triangles, 1), 0.02, 1.0)
        apply_decimation(city_objects, second_ratio)
        decimated = extract_all(city_objects)
        decimated_triangles = tri_count(decimated)
        decimation_ratio *= second_ratio

    material = build_material()
    root, output_objects, chunk_infos, output_vertices = build_chunk_objects(decimated, transform, args, material)
    output_triangles = int(sum(chunk["triangles"] for chunk in chunk_infos))
    export_options = export_glb(args.output_glb, root, output_objects)
    glb_bytes = args.output_glb.stat().st_size
    glb_sha = sha256_file(args.output_glb)

    local_bounds = {
        "minX": round(transform.min_x, 3),
        "maxX": round(transform.max_x, 3),
        "minZ": round(transform.min_z, 3),
        "maxZ": round(transform.max_z, 3),
        "minY": round(float(transformed_original_heights.min()), 3),
        "maxY": round(float(transformed_original_heights.max()), 3),
        "widthM": round(transform.width_m, 3),
        "depthM": round(transform.depth_m, 3),
    }

    warnings = [
        "The FBX references 13 external PNG textures that are not present in Model Inbox; they were deliberately ignored and replaced with vertex colours.",
        "Source scale is interpreted as miniature/kilometre-like units; conversion uses 250 m/unit horizontally so the footprint fits Kingsford district.",
        "Street-level source vertices at or below the configured ground Z are flattened to the city plate; bridges and elevated terrain remain approximate.",
        "Colliders are an occupancy-raster approximation of merged photogrammetry geometry, not hand-authored building footprints.",
        "Chunk splitting assigns triangles by centroid; hairline seams can occur where a source triangle crosses a 250 m boundary.",
    ]
    if output_triangles > int(args.target_triangles * 1.15):
        warnings.append(
            f"Output triangle count {output_triangles:,} exceeds the target {args.target_triangles:,} by more than 15% after Blender decimation."
        )

    per_source = []
    decimated_by_name = {item["name"]: item for item in decimated}
    for item in original:
        dec = decimated_by_name.get(item["name"])
        per_source.append({
            "name": item["name"],
            "originalVertices": int(len(item["vertices"])),
            "originalTriangles": int(len(item["triangles"])),
            "decimatedVertices": int(len(dec["vertices"])) if dec else 0,
            "decimatedTriangles": int(len(dec["triangles"])) if dec else 0,
        })

    city_data = {
        "schemaVersion": 1,
        "assetKey": args.asset_key,
        "displayName": args.display_name,
        "generatedBy": "scripts/blender_convert_city.py",
        "source": {
            "name": input_path.name,
            "size": source_size,
            "sha256": source_sha,
            "blenderVersion": bpy.app.version_string,
            "missingTexturesIgnored": True,
        },
        "transform": {
            "sourceBoundsBlender": {
                "min": rounded(source_min, 6),
                "max": rounded(source_max, 6),
                "center": rounded(transform.source_center, 6),
            },
            "sourceGroundZ": float(args.ground_source_z),
            "scaleXYMPerUnit": float(args.scale_xy),
            "scaleZMPerUnit": float(args.scale_z),
            "localBounds": local_bounds,
            "note": "City-local Three.js coordinates: X east, Y up, Z=-Blender Y (south positive).",
        },
        "layout": {
            "chunkSizeM": float(args.chunk_size),
            "chunks": chunk_infos,
        },
        "colliders": {
            "space": "city-local",
            "format": "[centerX, centerZ, halfWidthM, halfDepthM]",
            "cellSizeM": float(args.collider_cell_size),
            "obstacleHeightM": float(args.obstacle_height_m),
            "grid": collider_grid,
            "occupiedCells": collider_grid["occupiedCells"],
            "rectangles": collider_rectangles,
        },
        "stats": {
            "originalVertices": original_vertices,
            "originalTriangles": original_triangles,
            "decimatedTriangles": decimated_triangles,
            "outputVertices": int(output_vertices),
            "outputTriangles": output_triangles,
            "decimationRatio": round(float(decimation_ratio), 6),
            "glbBytes": int(glb_bytes),
            "glbSha256": glb_sha,
        },
    }

    report = {
        **json_round(city_data["source"], 6),
        "assetKey": args.asset_key,
        "displayName": args.display_name,
        "blenderVersion": bpy.app.version_string,
        "source": city_data["source"],
        "transform": city_data["transform"],
        "heightPercentilesM": height_percentiles,
        "perSourceObject": per_source,
        "chunks": chunk_infos,
        "colliders": {
            "grid": collider_grid,
            "occupiedCells": collider_grid["occupiedCells"],
            "rectangles": collider_rectangles,
        },
        "stats": city_data["stats"],
        "exportOptions": export_options,
        "warnings": warnings,
    }

    args.output_data_js.parent.mkdir(parents=True, exist_ok=True)
    args.report_json.parent.mkdir(parents=True, exist_ok=True)
    args.report_md.parent.mkdir(parents=True, exist_ok=True)
    js_payload = json.dumps(json_round(city_data, 4), ensure_ascii=False, indent=2)
    args.output_data_js.write_text(
        "// Generated by scripts/blender_convert_city.py from the Model Inbox FBX.\n"
        "// Do not edit by hand; regenerate through the city conversion workflow.\n"
        f"export const MANHATTAN_CITY_DATA = {js_payload};\n\n"
        "export default MANHATTAN_CITY_DATA;\n",
        encoding="utf-8",
    )
    args.report_json.write_text(json.dumps(json_round(report, 4), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.report_md.write_text(build_markdown(report), encoding="utf-8")

    print(json.dumps({
        "source": city_data["source"],
        "localBounds": local_bounds,
        "chunks": len(chunk_infos),
        "colliders": len(collider_rectangles),
        "stats": city_data["stats"],
        "warnings": warnings,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
