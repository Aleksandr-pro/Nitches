#!/usr/bin/env python3
"""Inspect a large scene/model in headless Blender without converting it.

Designed for Model Inbox world/city assets. The report is intentionally
measurement-first: world bounds, likely scale, object/material/texture
inventory, triangle load, category guesses from names, and a top-down SVG
footprint. No source geometry is changed or exported by this script.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


CATEGORY_KEYWORDS = [
    ("water", ("water", "river", "ocean", "sea", "hudson", "harbor", "harbour")),
    ("roads", ("road", "street", "avenue", "ave_", "highway", "asphalt", "crosswalk", "sidewalk", "pavement", "curb", "lane")),
    ("ground", ("ground", "terrain", "landscape", "island", "baseplate", "base_plate", "park", "grass", "plaza")),
    ("bridges", ("bridge",)),
    ("buildings", ("building", "house", "tower", "skyscraper", "apartment", "office", "block", "warehouse", "church", "school", "hospital")),
    ("vegetation", ("tree", "bush", "shrub", "plant", "foliage", "hedge")),
    ("props", ("lamp", "light", "sign", "traffic", "bench", "hydrant", "pole", "fence", "railing", "car", "vehicle", "bus", "truck")),
]

CATEGORY_COLORS = {
    "water": "#276f9f",
    "roads": "#252a30",
    "ground": "#4d7c4f",
    "bridges": "#b47b3a",
    "buildings": "#c9c2b4",
    "vegetation": "#4da65a",
    "props": "#d8b84a",
    "uncategorized": "#9b93a6",
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Inspect a scene in Blender")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-md", type=Path, required=True)
    parser.add_argument("--output-svg", type=Path, required=True)
    parser.add_argument("--asset-key", default="")
    parser.add_argument("--display-name", default="")
    return parser.parse_args(argv)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_scene(path: Path) -> dict:
    before_objects = set(bpy.data.objects)
    suffix = path.suffix.lower()
    if suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path))
        method = "open_mainfile"
    elif suffix == ".fbx":
        clear_scene()
        bpy.ops.import_scene.fbx(filepath=str(path))
        method = "import_scene.fbx"
    elif suffix in {".glb", ".gltf"}:
        clear_scene()
        bpy.ops.import_scene.gltf(filepath=str(path))
        method = "import_scene.gltf"
    elif suffix == ".obj":
        clear_scene()
        if hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=str(path))
            method = "wm.obj_import"
        else:
            bpy.ops.import_scene.obj(filepath=str(path))
            method = "import_scene.obj"
    else:
        raise ValueError(f"Unsupported inspection input extension: {suffix}")
    after_objects = set(bpy.data.objects)
    return {
        "method": method,
        "newObjectCountHint": len(after_objects - before_objects) if suffix != ".blend" else len(after_objects),
    }


def categorize(*names: str) -> str:
    haystack = " ".join(name.lower() for name in names if name)
    for category, keywords in CATEGORY_KEYWORDS:
        if any(keyword in haystack for keyword in keywords):
            return category
    return "uncategorized"


def safe_list(values, limit: int = 5000) -> list:
    values = list(values)
    return values[:limit]


def rounded(values, digits: int = 4) -> list[float]:
    return [round(float(v), digits) for v in values]


def material_image_names(material) -> list[str]:
    names = []
    if not material or not material.use_nodes or not material.node_tree:
        return names
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and getattr(node, "image", None):
            names.append(node.image.name)
    return sorted(set(names))


def world_aabb(obj) -> tuple[list[float], list[float]] | None:
    if not getattr(obj, "bound_box", None):
        return None
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    if not corners:
        return None
    mins = [min(v[i] for v in corners) for i in range(3)]
    maxs = [max(v[i] for v in corners) for i in range(3)]
    if not all(math.isfinite(v) for v in mins + maxs):
        return None
    return mins, maxs


def collection_summary() -> list[dict]:
    out = []

    def visit(collection, depth=0):
        out.append({
            "name": collection.name,
            "depth": depth,
            "directObjects": len(collection.objects),
            "children": len(collection.children),
        })
        for child in collection.children:
            visit(child, depth + 1)

    if bpy.context.scene and bpy.context.scene.collection:
        visit(bpy.context.scene.collection)
    return out[:1000]


def image_summary(input_path: Path) -> list[dict]:
    result = []
    for image in bpy.data.images:
        raw_path = image.filepath or ""
        absolute = ""
        exists = None
        if raw_path:
            try:
                absolute = bpy.path.abspath(raw_path)
            except Exception:
                absolute = raw_path
            exists = os.path.exists(absolute)
            # FBX embedded media is usually extracted beside the FBX as
            # <name>.fbm/... while an unsaved Blender scene may resolve //
            # paths against cwd. Try the source directory too.
            if exists is False and raw_path.startswith("//"):
                candidate = input_path.parent / raw_path[2:]
                absolute = str(candidate)
                exists = candidate.exists()
        result.append({
            "name": image.name,
            "source": image.source,
            "filepath": raw_path,
            "absolutePath": absolute,
            "exists": exists,
            "packed": bool(image.packed_file),
            "packedBytes": int(image.packed_file.size) if image.packed_file else None,
            "size": [int(image.size[0]), int(image.size[1])] if len(image.size) >= 2 else None,
            "alphaMode": getattr(image, "alpha_mode", None),
            "colorspace": getattr(image.colorspace_settings, "name", None) if image.colorspace_settings else None,
        })
    return result


def material_summary() -> list[dict]:
    result = []
    for material in bpy.data.materials:
        result.append({
            "name": material.name,
            "users": int(material.users),
            "useNodes": bool(material.use_nodes),
            "diffuseColor": rounded(material.diffuse_color, 4) if material.diffuse_color else None,
            "images": material_image_names(material),
        })
    return result


def build_svg(path: Path, footprints: list[dict], global_min: list[float], global_max: list[float], title: str) -> None:
    width = 1200
    height = 1200
    pad = 36
    span_x = max(global_max[0] - global_min[0], 1e-9)
    span_y = max(global_max[1] - global_min[1], 1e-9)
    scale = min((width - pad * 2) / span_x, (height - pad * 2) / span_y)
    drawn_w = span_x * scale
    drawn_h = span_y * scale
    off_x = (width - drawn_w) / 2
    off_y = (height - drawn_h) / 2

    order = {"water": 0, "ground": 1, "roads": 2, "bridges": 3, "buildings": 4, "vegetation": 5, "props": 6, "uncategorized": 2}
    items = sorted(footprints, key=lambda item: (order.get(item["category"], 2), -item["footprintAreaM2"]))[:4000]

    def sx(x: float) -> float:
        return off_x + (x - global_min[0]) * scale

    def sy(y: float) -> float:
        return off_y + (global_max[1] - y) * scale

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#10222e"/>',
        f'<text x="24" y="28" fill="#ffffff" font-family="sans-serif" font-size="20" font-weight="700">{html.escape(title)} — top-down footprint</text>',
        f'<text x="24" y="52" fill="#bfd4e2" font-family="sans-serif" font-size="13">Blender X/Y footprint; boxes are object AABBs, capped at 4000 largest footprints.</text>',
    ]
    for item in items:
        mins = item["worldMin"]
        maxs = item["worldMax"]
        x = sx(mins[0])
        y = sy(maxs[1])
        w = max(1.0, (maxs[0] - mins[0]) * scale)
        h = max(1.0, (maxs[1] - mins[1]) * scale)
        color = CATEGORY_COLORS.get(item["category"], CATEGORY_COLORS["uncategorized"])
        label = html.escape(f"{item['name']} [{item['category']}] {item['dimensions'][0]:.1f}×{item['dimensions'][1]:.1f}×{item['dimensions'][2]:.1f}")
        lines.append(
            f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" '
            f'fill="{color}" fill-opacity="0.78" stroke="#0b1116" stroke-opacity="0.28" stroke-width="0.4">'
            f'<title>{label}</title></rect>'
        )
    legend_y = height - 26
    x = 24
    for category in ["water", "ground", "roads", "buildings", "vegetation", "props", "bridges", "uncategorized"]:
        lines.append(f'<rect x="{x}" y="{legend_y - 11}" width="12" height="12" fill="{CATEGORY_COLORS[category]}"/>')
        lines.append(f'<text x="{x + 17}" y="{legend_y}" fill="#ffffff" font-family="sans-serif" font-size="12">{category}</text>')
        x += 28 + len(category) * 8
    lines.append("</svg>")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def human_bytes(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.2f} {unit}" if unit != "B" else f"{size} B"
        value /= 1024
    return f"{value:.2f} GiB"


def build_markdown(data: dict) -> str:
    s = data["summary"]
    b = data["worldBounds"]
    lines = [
        f"# Scene inspection — {data.get('displayName') or data['input']['name']}",
        "",
        f"- Input: `{data['input']['name']}` ({human_bytes(data['input']['size'])})",
        f"- SHA-256: `{data['input']['sha256']}`",
        f"- Blender: {data['blenderVersion']}; import: `{data['import']['method']}`",
        f"- Scene units: system `{data['sceneUnits']['system']}`, scale_length `{data['sceneUnits']['scaleLength']}`, length unit `{data['sceneUnits']['lengthUnit']}`",
        "",
        "## Scale and bounds",
        "",
    ]
    if b:
        lines += [
            f"- World size (Blender X × Y × Z): **{b['sizeXYZ'][0]:.3f} × {b['sizeXYZ'][1]:.3f} × {b['sizeXYZ'][2]:.3f}**",
            f"- Centre: ({b['centerXYZ'][0]:.3f}, {b['centerXYZ'][1]:.3f}, {b['centerXYZ'][2]:.3f})",
            f"- Min: ({b['min'][0]:.3f}, {b['min'][1]:.3f}, {b['min'][2]:.3f})",
            f"- Max: ({b['max'][0]:.3f}, {b['max'][1]:.3f}, {b['max'][2]:.3f})",
        ]
    else:
        lines.append("- No mesh world bounds were found.")
    lines += [
        "",
        "## Geometry and scene contents",
        "",
        f"- Objects: {s['objects']} ({s['meshObjects']} meshes)",
        f"- Evaluated vertices: {s['evaluatedVertices']:,}",
        f"- Evaluated triangulated faces: **{s['evaluatedTriangles']:,}**",
        f"- Materials: {s['materials']}; images: {s['images']} (packed {s['packedImages']}, external existing {s['existingExternalImages']}, external missing {s['missingExternalImages']})",
        f"- Collections: {s['collections']}",
        "",
        "### Objects by type",
        "",
    ]
    for name, count in sorted(s["objectsByType"].items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"- `{name}`: {count:,}")
    lines += ["", "### Mesh footprints by guessed category", ""]
    for name, count in sorted(s["meshFootprintsByCategory"].items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"- `{name}`: {count:,}")
    lines += ["", "## Largest footprints", "", "| Object | Category | X × Y × Z | Triangles |", "|---|---:|---:|---:|"]
    for item in data["largestFootprints"][:25]:
        d = item["dimensions"]
        lines.append(f"| `{item['name']}` | {item['category']} | {d[0]:.1f} × {d[1]:.1f} × {d[2]:.1f} | {item['triangles']:,} |")
    lines += ["", "## Heaviest meshes", "", "| Object | Category | Triangles | Vertices |", "|---|---:|---:|---:|"]
    for item in data["heaviestMeshes"][:25]:
        lines.append(f"| `{item['name']}` | {item['category']} | {item['triangles']:,} | {item['vertices']:,} |")
    lines += ["", "## Images and textures", ""]
    if data["images"]:
        for image in data["images"][:80]:
            size = "×".join(str(v) for v in image["size"]) if image.get("size") else "unknown"
            status = "packed" if image["packed"] else ("exists" if image["exists"] else "missing/unknown" if image["filepath"] else "generated/no file")
            lines.append(f"- `{image['name']}` — {size}, {status}; path `{image['filepath'] or '—'}`")
    else:
        lines.append("- No Blender images were registered after import.")
    if data["warnings"]:
        lines += ["", "## Warnings", ""]
        for warning in data["warnings"]:
            lines.append(f"- {warning}")
    lines += [
        "",
        "## Interpretation notes",
        "",
        "- Blender dimensions are reported exactly as imported. Whether one Blender unit equals one game metre must be decided from recognizable objects/heights before conversion.",
        "- Category labels are keyword guesses from object/material names only; unnamed city meshes need spatial or visual classification later.",
        "- A single city mesh still needs spatial splitting/chunking and collider generation before it should replace a playable district.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    input_path = args.input.resolve()
    if not input_path.is_file():
        print(f"Input not found: {input_path}", file=sys.stderr)
        return 2

    input_size = input_path.stat().st_size
    input_sha = sha256_file(input_path)
    import_info = import_scene(input_path)

    scene = bpy.context.scene
    unit = scene.unit_settings if scene else None
    depsgraph = bpy.context.evaluated_depsgraph_get()

    counts_by_type = Counter(obj.type for obj in bpy.data.objects)
    footprints: list[dict] = []
    detailed: list[dict] = []
    category_counts = Counter()
    total_vertices = 0
    total_triangles = 0
    mesh_objects = 0
    global_min = [math.inf, math.inf, math.inf]
    global_max = [-math.inf, -math.inf, -math.inf]
    errors: list[dict] = []

    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh_objects += 1
        evaluated = obj.evaluated_get(depsgraph)
        mesh = None
        verts = 0
        tris = 0
        try:
            mesh = evaluated.to_mesh()
            if mesh:
                verts = len(mesh.vertices)
                tris = sum(max(0, len(poly.vertices) - 2) for poly in mesh.polygons)
        except Exception as exc:  # Blender object conversion can fail on exotic data.
            errors.append({"object": obj.name, "error": str(exc)})
        finally:
            if mesh:
                evaluated.to_mesh_clear()
        total_vertices += verts
        total_triangles += tris

        material_names = [slot.material.name for slot in obj.material_slots if slot.material]
        category = categorize(obj.name, *material_names)
        category_counts[category] += 1
        aabb = world_aabb(evaluated)
        if not aabb:
            continue
        mins, maxs = aabb
        dims = [maxs[i] - mins[i] for i in range(3)]
        for i in range(3):
            global_min[i] = min(global_min[i], mins[i])
            global_max[i] = max(global_max[i], maxs[i])
        item = {
            "name": obj.name,
            "category": category,
            "worldMin": rounded(mins),
            "worldMax": rounded(maxs),
            "dimensions": rounded(dims),
            "footprintAreaM2": round(max(dims[0], 0) * max(dims[1], 0), 4),
            "vertices": verts,
            "triangles": tris,
            "materials": material_names,
            "parent": obj.parent.name if obj.parent else None,
            "collections": [c.name for c in obj.users_collection],
        }
        footprints.append(item)
        detailed.append(item)

    if global_min[0] == math.inf:
        world_bounds = None
    else:
        dimensions = [global_max[i] - global_min[i] for i in range(3)]
        center = [(global_max[i] + global_min[i]) / 2 for i in range(3)]
        world_bounds = {
            "min": rounded(global_min),
            "max": rounded(global_max),
            "sizeXYZ": rounded(dimensions),
            "centerXYZ": rounded(center),
            "note": "Blender world axes: X width, Y depth, Z height. Bounds are from evaluated object AABBs.",
        }

    images = image_summary(input_path)
    materials = material_summary()
    warnings: list[str] = []
    if errors:
        warnings.append(f"{len(errors)} mesh objects could not be evaluated; first examples are in evaluationErrors.")
    missing_images = [img for img in images if img["filepath"] and not img["packed"] and img["exists"] is False]
    if missing_images:
        warnings.append(f"{len(missing_images)} external image paths do not exist beside the imported file; original texture files or an archive may be required.")
    if total_triangles > 2_000_000:
        warnings.append("Evaluated triangle count is above 2M; mobile conversion needs aggressive LOD/decimation and spatial chunking.")
    elif total_triangles > 750_000:
        warnings.append("Evaluated triangle count is above 750k; mobile conversion needs LOD/decimation and spatial chunking.")
    if mesh_objects > 5_000:
        warnings.append("Mesh object count is above 5000; merging/instancing by material and chunk will be required to control draw calls.")
    if world_bounds and max(world_bounds["sizeXYZ"][:2]) > 10_000:
        warnings.append("Footprint exceeds 10k Blender units on an axis; source may use centimetres or a non-metre scale.")
    if world_bounds and max(world_bounds["sizeXYZ"][:2]) < 20:
        warnings.append("Footprint is under 20 Blender units; source may be a miniature/scaled scene rather than metres.")

    footprints_sorted = sorted(footprints, key=lambda item: item["footprintAreaM2"], reverse=True)
    heaviest_sorted = sorted(detailed, key=lambda item: item["triangles"], reverse=True)

    data = {
        "assetKey": args.asset_key,
        "displayName": args.display_name,
        "input": {
            "name": input_path.name,
            "size": input_size,
            "sha256": input_sha,
        },
        "blenderVersion": bpy.app.version_string,
        "import": import_info,
        "sceneUnits": {
            "system": getattr(unit, "system", None) if unit else None,
            "scaleLength": float(getattr(unit, "scale_length", 1.0)) if unit else 1.0,
            "lengthUnit": getattr(unit, "length_unit", None) if unit else None,
        },
        "worldBounds": world_bounds,
        "summary": {
            "objects": len(bpy.data.objects),
            "meshObjects": mesh_objects,
            "objectsByType": dict(counts_by_type),
            "evaluatedVertices": total_vertices,
            "evaluatedTriangles": total_triangles,
            "materials": len(materials),
            "images": len(images),
            "packedImages": sum(1 for img in images if img["packed"]),
            "existingExternalImages": sum(1 for img in images if img["filepath"] and not img["packed"] and img["exists"] is True),
            "missingExternalImages": len(missing_images),
            "collections": len(bpy.data.collections),
            "meshFootprintsByCategory": dict(category_counts),
        },
        "collections": collection_summary(),
        "materials": materials[:2000],
        "images": images[:2000],
        "largestFootprints": footprints_sorted[:100],
        "heaviestMeshes": heaviest_sorted[:100],
        "footprints": footprints_sorted[:5000],
        "footprintsTruncated": len(footprints_sorted) > 5000,
        "evaluationErrors": errors[:100],
        "warnings": warnings,
    }

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_md.parent.mkdir(parents=True, exist_ok=True)
    args.output_svg.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.output_md.write_text(build_markdown(data), encoding="utf-8")
    if world_bounds:
        build_svg(args.output_svg, footprints, global_min, global_max, args.display_name or input_path.name)
    else:
        args.output_svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="800" height="200"><text x="20" y="40">No mesh footprints found.</text></svg>\n', encoding="utf-8")

    print(json.dumps({
        "input": data["input"],
        "worldBounds": world_bounds,
        "summary": data["summary"],
        "warnings": warnings,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
