#!/usr/bin/env python3
"""Convert an imported car OBJ into an optimized, game-ready GLB in Blender.

Run modes:
  blender -b car.blend --python scripts/blender_convert_car.py -- \
      --mode dump --output-json blend-materials.json

  blender -b --factory-startup --python scripts/blender_convert_car.py -- \
      --mode convert --input-obj car.obj --output-glb car.glb \
      --report-json conversion.json --blend-materials blend-materials.json

The converter is intentionally project-specific in its output contract:
metres, glTF +Z forward/+Y up, origin at the midpoint between axles on the
ground, and Wheel_FL/FR/RL/RR steering pivots with *_Spin children.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


WHEEL_RE = re.compile(r"Wheel(FL|FR|BL|BR|RL|RR)(Tire|Rim|Spoke|Axle|Brake)", re.IGNORECASE)
CORNER_MAP = {"FL": "FL", "FR": "FR", "BL": "RL", "BR": "RR", "RL": "RL", "RR": "RR"}


def parse_args() -> dict[str, str]:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out: dict[str, str] = {}
    i = 0
    while i < len(argv):
        item = argv[i]
        if item.startswith("--"):
            key = item[2:]
            value = "true"
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                value = argv[i + 1]
                i += 1
            out[key] = value
        i += 1
    return out


def srgb_hex_to_linear(value: str) -> tuple[float, float, float]:
    value = value.strip().lstrip("#")
    rgb = tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))

    def convert(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return tuple(convert(c) for c in rgb)  # type: ignore[return-value]


def write_json(path: str | None, data: dict) -> None:
    if not path:
        return
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def socket_default(socket):
    value = getattr(socket, "default_value", None)
    if value is None:
        return None
    try:
        return [float(v) for v in value]
    except Exception:
        try:
            return float(value)
        except Exception:
            return str(value)


def dump_blend(output_json: str | None) -> dict:
    materials = []
    for mat in bpy.data.materials:
        info: dict = {
            "name": mat.name,
            "diffuseColorLinear": [float(v) for v in mat.diffuse_color],
            "useNodes": bool(mat.use_nodes),
            "nodes": [],
            "baseColorLinear": None,
            "baseColorImage": None,
        }
        if mat.use_nodes and mat.node_tree:
            for node in mat.node_tree.nodes:
                node_info: dict = {"name": node.name, "type": node.bl_idname}
                if node.bl_idname == "ShaderNodeTexImage" and getattr(node, "image", None):
                    image = node.image
                    node_info["image"] = {
                        "name": image.name,
                        "filepath": bpy.path.abspath(image.filepath),
                        "size": [int(image.size[0]), int(image.size[1])],
                    }
                if node.bl_idname in {
                    "ShaderNodeBsdfPrincipled",
                    "ShaderNodeBsdfDiffuse",
                    "ShaderNodeBsdfGlossy",
                    "ShaderNodeEmission",
                }:
                    inputs = {}
                    for socket in node.inputs:
                        linked = []
                        for link in socket.links:
                            from_node = link.from_node
                            linked_item = {"node": from_node.name, "type": from_node.bl_idname}
                            if from_node.bl_idname == "ShaderNodeTexImage" and getattr(from_node, "image", None):
                                linked_item["image"] = from_node.image.name
                                linked_item["filepath"] = bpy.path.abspath(from_node.image.filepath)
                            linked.append(linked_item)
                        inputs[socket.name] = {"default": socket_default(socket), "linkedFrom": linked}
                    node_info["inputs"] = inputs
                    for candidate in ("Base Color", "Color"):
                        socket = node.inputs.get(candidate) if hasattr(node.inputs, "get") else None
                        if socket is not None and info["baseColorLinear"] is None:
                            info["baseColorLinear"] = socket_default(socket)
                            for link in socket.links:
                                if link.from_node.bl_idname == "ShaderNodeTexImage" and link.from_node.image:
                                    info["baseColorImage"] = {
                                        "name": link.from_node.image.name,
                                        "filepath": bpy.path.abspath(link.from_node.image.filepath),
                                        "size": [int(link.from_node.image.size[0]), int(link.from_node.image.size[1])],
                                    }
                info["nodes"].append(node_info)
        materials.append(info)

    objects = []
    for obj in bpy.context.scene.objects:
        objects.append({
            "name": obj.name,
            "type": obj.type,
            "materials": [slot.material.name if slot.material else None for slot in getattr(obj, "material_slots", [])],
            "dimensions": [float(v) for v in obj.dimensions],
            "location": [float(v) for v in obj.location],
        })

    data = {
        "blenderVersion": bpy.app.version_string,
        "sourceBlend": bpy.data.filepath,
        "materials": materials,
        "objects": objects,
    }
    write_json(output_json, data)
    print(json.dumps({"dumpedMaterials": len(materials), "dumpedObjects": len(objects)}, indent=2))
    return data


def mesh_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.data]


def tri_estimate(obj: bpy.types.Object) -> int:
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def object_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector] | None:
    bpy.context.view_layer.update()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, point.x)
            mins.y = min(mins.y, point.y)
            mins.z = min(mins.z, point.z)
            maxs.x = max(maxs.x, point.x)
            maxs.y = max(maxs.y, point.y)
            maxs.z = max(maxs.z, point.z)
            found = True
    return (mins, maxs) if found else None


def object_center(obj: bpy.types.Object) -> Vector:
    bounds = object_bounds([obj])
    assert bounds is not None
    return (bounds[0] + bounds[1]) * 0.5


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def import_obj(path: str) -> None:
    if hasattr(bpy.ops.wm, "obj_import"):
        bpy.ops.wm.obj_import(filepath=path)
    else:
        bpy.ops.import_scene.obj(filepath=path, axis_forward="-Z", axis_up="Y")
    bpy.context.view_layer.update()


def make_material(
    name: str,
    color_linear: tuple[float, float, float],
    metallic: float,
    roughness: float,
    alpha: float = 1.0,
    emission_linear: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.diffuse_color = (*color_linear, alpha)
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf:
        def set_input(names, value):
            for input_name in names:
                socket = bsdf.inputs.get(input_name) if hasattr(bsdf.inputs, "get") else None
                if socket is not None:
                    socket.default_value = value
                    return

        set_input(["Base Color"], (*color_linear, alpha))
        set_input(["Metallic"], metallic)
        set_input(["Roughness"], roughness)
        set_input(["Alpha"], alpha)
        if emission_linear is not None:
            set_input(["Emission Color", "Emission"], (*emission_linear, 1.0))
            set_input(["Emission Strength"], emission_strength)
    if alpha < 1.0:
        try:
            mat.blend_method = "BLEND"
        except Exception:
            pass
        try:
            mat.surface_render_method = "DITHERED"
        except Exception:
            pass
    return mat


def load_dump_material_colors(path: str | None) -> dict[str, dict]:
    if not path:
        return {}
    source = Path(path)
    if not source.is_file():
        print(f"Blend material dump not found, continuing without it: {path}")
        return {}
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"Cannot read blend material dump {path}: {exc}")
        return {}
    return {str(item.get("name", "")).lower(): item for item in data.get("materials", [])}


def dumped_color(material_name: str, dump_map: dict[str, dict]) -> tuple[float, float, float] | None:
    item = dump_map.get(material_name.lower())
    if not item:
        return None
    for key in ("baseColorLinear", "diffuseColorLinear"):
        value = item.get(key)
        if isinstance(value, list) and len(value) >= 3:
            rgb = tuple(max(0.0, min(1.0, float(v))) for v in value[:3])
            # Blender's generic exporter grey appears as 0.8 in older files;
            # treat a perfectly neutral, mid/high grey as "no useful color"
            # for paint so the caller can use its branded default instead.
            if max(rgb) - min(rgb) > 0.015 or rgb[0] < 0.35:
                return rgb  # type: ignore[return-value]
    return None


def semantic_material_name(original: str, primary_paint_original: str | None) -> str:
    lower = original.lower()
    if primary_paint_original and original == primary_paint_original:
        return "Paint"
    if "paint" in lower:
        return "PaintSecondary"
    if "windshield" in lower or "glass" in lower or "window" in lower:
        return "Glass"
    if "tire" in lower or "tyre" in lower:
        return "Tire"
    if "rim" in lower or "wheel" in lower:
        return "Rim"
    if "brake" in lower:
        return "Brake"
    if "headlight" in lower or "head_light" in lower or "frontlight" in lower or "front_light" in lower:
        return "Headlight"
    if "tail" in lower or "backlight" in lower or "back_light" in lower:
        return "Taillight"
    if "turn" in lower or "signal" in lower:
        return "TurnSignal"
    if "mirror" in lower:
        return "Mirror"
    if "exhaust" in lower:
        return "Exhaust"
    if "chrome" in lower:
        return "Chrome"
    if "black" in lower or "dark" in lower or "grill" in lower or "trim" in lower:
        return "BlackTrim"
    return "Trim"


def build_semantic_materials(
    primary_paint_original: str | None,
    secondary_paint_originals: list[str],
    dump_map: dict[str, dict],
    default_paint_hex: str,
) -> dict[str, bpy.types.Material]:
    paint_color = dumped_color(primary_paint_original or "", dump_map) or srgb_hex_to_linear(default_paint_hex)
    secondary_color = None
    for name in secondary_paint_originals:
        secondary_color = dumped_color(name, dump_map)
        if secondary_color:
            break
    if secondary_color is None:
        secondary_color = srgb_hex_to_linear("#e9edf0")

    return {
        "Paint": make_material("Paint", paint_color, 0.25, 0.32),
        "PaintSecondary": make_material("PaintSecondary", secondary_color, 0.2, 0.35),
        "Glass": make_material("Glass", srgb_hex_to_linear("#101d29"), 0.1, 0.08, alpha=0.74),
        "Chrome": make_material("Chrome", srgb_hex_to_linear("#d6dde3"), 1.0, 0.2),
        "Rim": make_material("Rim", srgb_hex_to_linear("#c2c8ce"), 1.0, 0.27),
        "BlackTrim": make_material("BlackTrim", srgb_hex_to_linear("#101114"), 0.25, 0.55),
        "Trim": make_material("Trim", srgb_hex_to_linear("#6d747c"), 0.35, 0.45),
        "Tire": make_material("Tire", srgb_hex_to_linear("#070707"), 0.0, 0.95),
        "Brake": make_material("Brake", srgb_hex_to_linear("#6b1d16"), 0.4, 0.42),
        "Exhaust": make_material("Exhaust", srgb_hex_to_linear("#969ea5"), 1.0, 0.34),
        "Mirror": make_material("Mirror", srgb_hex_to_linear("#e3edf3"), 1.0, 0.05),
        "Headlight": make_material(
            "Headlight", srgb_hex_to_linear("#fff1ba"), 0.1, 0.18,
            emission_linear=srgb_hex_to_linear("#ffe79a"), emission_strength=1.6,
        ),
        "Taillight": make_material(
            "Taillight", srgb_hex_to_linear("#650711"), 0.1, 0.25,
            emission_linear=srgb_hex_to_linear("#ff1622"), emission_strength=1.4,
        ),
        "TurnSignal": make_material(
            "TurnSignal", srgb_hex_to_linear("#713604"), 0.1, 0.25,
            emission_linear=srgb_hex_to_linear("#ff8a00"), emission_strength=1.2,
        ),
    }


def decimation_ratio(obj: bpy.types.Object) -> float:
    count = len(obj.data.polygons)
    if count < 250:
        return 1.0
    lower = obj.name.lower()
    if "tire" in lower or "tyre" in lower:
        return 0.16
    if "rim" in lower:
        return 0.12
    if "spoke" in lower:
        return 0.10
    if "brake" in lower or "axle" in lower:
        return 0.14
    if "wheel" in lower:
        return 0.18
    if "body_plane" in lower:
        return 0.52
    if "backpanel" in lower:
        return 0.45
    if "intake1" in lower or "intake2" in lower:
        return 0.35
    if "honeycomb" in lower or "grill" in lower:
        return 0.30
    if "logo" in lower or "text" in lower:
        return 0.30
    if "light" in lower or "bulb" in lower:
        return 0.30
    if "window" in lower or "windshield" in lower or "glass" in lower:
        return 0.65
    if "bumper" in lower or "spoiler" in lower:
        return 0.50
    if count > 10000:
        return 0.38
    if count > 4000:
        return 0.48
    if count > 1500:
        return 0.62
    if count > 600:
        return 0.75
    return 0.86


def apply_decimate(obj: bpy.types.Object, ratio: float) -> None:
    if ratio >= 0.999:
        return
    modifier = obj.modifiers.new(name="NitchesDecimate", type="DECIMATE")
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
    obj.modifiers.remove(modifier)
    obj.data = new_mesh
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)


def bake_matrix(objects: list[bpy.types.Object], matrix: Matrix) -> None:
    bpy.context.view_layer.update()
    for obj in objects:
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        obj.data.transform(matrix @ obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        obj.data.update()
    bpy.context.view_layer.update()


def weighted_center_x(objects: list[bpy.types.Object]) -> float | None:
    total = 0
    weighted = 0.0
    for obj in objects:
        weight = max(1, tri_estimate(obj))
        weighted += object_center(obj).x * weight
        total += weight
    return weighted / total if total else None


def wheel_code(obj_name: str) -> str | None:
    match = WHEEL_RE.search(obj_name)
    if not match:
        return None
    return CORNER_MAP.get(match.group(1).upper())


def join_objects(objects: list[bpy.types.Object], new_name: str) -> bpy.types.Object:
    if not objects:
        raise ValueError(f"No objects to join for {new_name}")
    if len(objects) == 1:
        joined = objects[0]
    else:
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        with bpy.context.temp_override(
            active_object=objects[0],
            selected_objects=objects,
            selected_editable_objects=objects,
        ):
            bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
    joined.name = new_name
    if joined.data:
        joined.data.name = f"{new_name}Mesh"
    return joined


def create_empty(name: str, location: Vector) -> bpy.types.Object:
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.25
    empty.location = location
    return empty


def convert(args: dict[str, str]) -> dict:
    input_obj = args.get("input-obj")
    output_glb = args.get("output-glb")
    if not input_obj or not output_glb:
        raise ValueError("--input-obj and --output-glb are required in convert mode")

    target_length = float(args.get("target-length", "4.66"))
    default_paint_hex = args.get("default-paint", "#9b1420")
    dump_map = load_dump_material_colors(args.get("blend-materials"))

    clear_scene()
    import_obj(input_obj)
    imported = mesh_objects()
    if not imported:
        raise RuntimeError("OBJ import produced no mesh objects")

    input_polygons = sum(len(obj.data.polygons) for obj in imported)
    input_triangles = sum(tri_estimate(obj) for obj in imported)

    # Choose the paint material that covers the most polygons. This avoids
    # guessing whether Paintjob1 or PaintJob2 is the body vs. a stripe.
    material_polygons: Counter[str] = Counter()
    for obj in imported:
        slot_names = [slot.material.name if slot.material else "" for slot in obj.material_slots]
        for poly in obj.data.polygons:
            if 0 <= poly.material_index < len(slot_names) and slot_names[poly.material_index]:
                material_polygons[slot_names[poly.material_index]] += 1
    paint_originals = [name for name in material_polygons if "paint" in name.lower()]
    paint_originals.sort(key=lambda name: material_polygons[name], reverse=True)
    primary_paint_original = paint_originals[0] if paint_originals else None
    secondary_paint_originals = paint_originals[1:]

    semantic_materials = build_semantic_materials(
        primary_paint_original,
        secondary_paint_originals,
        dump_map,
        default_paint_hex,
    )

    for obj in imported:
        if not obj.data.materials:
            semantic = semantic_material_name(obj.name, primary_paint_original)
            obj.data.materials.append(semantic_materials[semantic])
        else:
            for index, material in enumerate(list(obj.data.materials)):
                original_name = material.name if material else obj.name
                semantic = semantic_material_name(original_name, primary_paint_original)
                obj.data.materials[index] = semantic_materials[semantic]

    decimation: dict[str, float] = {}
    for obj in list(imported):
        ratio = decimation_ratio(obj)
        decimation[obj.name] = ratio
        apply_decimate(obj, ratio)
    imported = mesh_objects()
    decimated_triangles = sum(tri_estimate(obj) for obj in imported)

    # Decide nose direction on Blender X (length after the default OBJ import).
    def name_has(obj: bpy.types.Object, words: tuple[str, ...]) -> bool:
        lower = obj.name.lower()
        return any(word in lower for word in words)

    front_objects = [obj for obj in imported if name_has(obj, ("front", "grill", "headlight", "head_light", "hood"))]
    back_objects = [obj for obj in imported if name_has(obj, ("back", "tail", "trunk", "rear", "spoiler", "exhaust", "gascap"))]
    front_x = weighted_center_x(front_objects)
    back_x = weighted_center_x(back_objects)
    nose_positive_x = True if front_x is None or back_x is None else front_x >= back_x

    bounds = object_bounds(imported)
    assert bounds is not None
    raw_length = bounds[1].x - bounds[0].x
    if raw_length <= 0:
        raise RuntimeError("Imported model has zero length")
    scale = target_length / raw_length
    angle = -math.pi / 2 if nose_positive_x else math.pi / 2
    rotation_scale = Matrix.Diagonal((scale, scale, scale, 1.0)) @ Matrix.Rotation(angle, 4, "Z")
    bake_matrix(imported, rotation_scale)

    # After the rotation, forward is -Y in Blender, which glTF exports as +Z.
    wheel_groups: dict[str, list[bpy.types.Object]] = defaultdict(list)
    for obj in imported:
        code = wheel_code(obj.name)
        if code:
            wheel_groups[code].append(obj)

    tire_objects = [obj for group in wheel_groups.values() for obj in group if "tire" in obj.name.lower() or "tyre" in obj.name.lower()]
    if len(wheel_groups) < 4 or len(tire_objects) < 4:
        raise RuntimeError(f"Expected four wheel groups/tires, found groups={sorted(wheel_groups)} tires={len(tire_objects)}")

    tire_centers = [object_center(obj) for obj in tire_objects]
    axle_midpoint = sum(tire_centers, Vector((0, 0, 0))) / len(tire_centers)
    tire_bounds = object_bounds(tire_objects)
    assert tire_bounds is not None
    ground_z = tire_bounds[0].z
    bake_matrix(imported, Matrix.Translation((-axle_midpoint.x, -axle_midpoint.y, -ground_z)))

    # Recompute groups after baking (object references remain valid).
    wheel_groups = defaultdict(list)
    non_wheel: list[bpy.types.Object] = []
    for obj in mesh_objects():
        code = wheel_code(obj.name)
        if code:
            wheel_groups[code].append(obj)
        else:
            non_wheel.append(obj)

    wheel_report: dict[str, dict] = {}
    wheel_pivots: list[bpy.types.Object] = []
    for code in ("FL", "FR", "RL", "RR"):
        group = wheel_groups.get(code, [])
        if not group:
            raise RuntimeError(f"Missing wheel group {code}")
        tires = [obj for obj in group if "tire" in obj.name.lower() or "tyre" in obj.name.lower()]
        bounds_for_hub = object_bounds(tires or group)
        assert bounds_for_hub is not None
        hub = (bounds_for_hub[0] + bounds_for_hub[1]) * 0.5
        tire_size = bounds_for_hub[1] - bounds_for_hub[0]
        radius = max(tire_size.y, tire_size.z) * 0.5

        spin = join_objects(group, f"Wheel_{code}_Spin")
        spin.data.transform(Matrix.Translation(-hub))
        spin.location = hub
        spin.rotation_euler = (0.0, 0.0, 0.0)
        spin.scale = (1.0, 1.0, 1.0)

        pivot = create_empty(f"Wheel_{code}", hub)
        spin.parent = pivot
        spin.matrix_parent_inverse = Matrix.Identity(4)
        spin.location = (0.0, 0.0, 0.0)
        spin.rotation_euler = (0.0, 0.0, 0.0)
        spin.scale = (1.0, 1.0, 1.0)
        wheel_pivots.append(pivot)
        wheel_report[code] = {
            "blenderHub": [round(float(v), 6) for v in hub],
            "gltfHub": [round(float(hub.x), 6), round(float(hub.z), 6), round(float(-hub.y), 6)],
            "radius": round(float(radius), 6),
            "sourceObjectCount": len(group),
        }

    body = join_objects(non_wheel, "Body")
    root = create_empty(args.get("root-name", "Mustang"), Vector((0.0, 0.0, 0.0)))
    for child in [body, *wheel_pivots]:
        child.parent = root
        child.matrix_parent_inverse = Matrix.Identity(4)

    bpy.context.view_layer.update()
    final_meshes = mesh_objects()
    final_bounds = object_bounds(final_meshes)
    assert final_bounds is not None
    blender_size = final_bounds[1] - final_bounds[0]
    final_triangles = sum(tri_estimate(obj) for obj in final_meshes)

    output_path = Path(output_glb)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )

    report = {
        "blenderVersion": bpy.app.version_string,
        "inputObj": str(Path(input_obj).name),
        "outputGlb": str(output_path.name),
        "outputBytes": output_path.stat().st_size if output_path.exists() else 0,
        "input": {
            "objects": len(imported),
            "polygons": input_polygons,
            "estimatedTriangles": input_triangles,
            "materialPolygonCounts": dict(material_polygons.most_common()),
        },
        "afterDecimationEstimatedTriangles": decimated_triangles,
        "finalEstimatedTriangles": final_triangles,
        "primaryPaintOriginalMaterial": primary_paint_original,
        "secondaryPaintOriginalMaterials": secondary_paint_originals,
        "decimationRatios": decimation,
        "orientation": {
            "frontCenterBlenderX": front_x,
            "backCenterBlenderX": back_x,
            "nosePositiveXBeforeRotation": nose_positive_x,
            "rotationZDegrees": math.degrees(angle),
            "scale": scale,
            "rawLength": raw_length,
            "targetLength": target_length,
        },
        "boundsBlender": {
            "min": [round(float(v), 6) for v in final_bounds[0]],
            "max": [round(float(v), 6) for v in final_bounds[1]],
            "sizeXYZ": [round(float(v), 6) for v in blender_size],
        },
        "boundsGltf": {
            "sizeXYZ": [
                round(float(blender_size.x), 6),
                round(float(blender_size.z), 6),
                round(float(blender_size.y), 6),
            ],
            "note": "glTF dimensions are width X, height Y, length Z; origin is axle midpoint at ground level.",
        },
        "wheels": wheel_report,
        "materials": sorted(semantic_materials.keys()),
    }
    write_json(args.get("report-json"), report)
    print(json.dumps({
        "outputGlb": str(output_path),
        "outputBytes": report["outputBytes"],
        "inputTriangles": input_triangles,
        "finalTriangles": final_triangles,
        "boundsGltf": report["boundsGltf"],
        "wheels": wheel_report,
    }, ensure_ascii=False, indent=2))
    return report


def main() -> int:
    args = parse_args()
    mode = args.get("mode", "convert")
    if mode == "dump":
        dump_blend(args.get("output-json"))
        return 0
    if mode == "convert":
        convert(args)
        return 0
    raise ValueError(f"Unknown mode: {mode}")


if __name__ == "__main__":
    raise SystemExit(main())
