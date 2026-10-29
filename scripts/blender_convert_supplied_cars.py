#!/usr/bin/env python3
"""Convert the three owner-supplied cars into game-ready GLBs.

The converter is deliberately narrow and auditable.  It bakes the evaluated
source meshes (including Geometry Nodes), normalises every car to metres
with the axle midpoint at the origin, assigns the semantic material names
understood by ``vehicle_controller.gd``, joins the body, and creates
``Wheel_FL/FR/RL/RR`` pivots with ``*_Spin`` children.

Blender convention on output: nose = -Y, up = +Z.  Blender's glTF exporter
maps that to the game's GLB contract (+Z nose, +Y up); the Godot visual
root turns the model to -Z forward once at runtime.

Examples (run with Blender or with the ``bpy`` Python module)::

    blender -b --python scripts/blender_convert_supplied_cars.py -- \
        --car audi --input r8_objects.obj --output audi_r8.glb \
        --report audi_r8.json

Camaro additionally accepts ``--overlay-image``: a copy of its atlas whose
blue painted areas are transparent.  The converter keeps a repaintable
``Paint`` underlay and a 4 mm offset ``LiveryTexture`` shell above it.
"""

from __future__ import annotations

import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


CAR_CONFIG = {
    "audi": {
        "root_name": "AudiR8V10Plus",
        "target_length_m": 4.426,
    },
    "camaro": {
        "root_name": "ChevroletCamaroSS",
        "target_length_m": 4.783,
    },
    "mercedes": {
        "root_name": "MercedesBenz560SEL",
        "target_length_m": 5.160,
    },
}

# name -> (linear-ish RGBA, metallic, roughness, emission RGB, emission strength)
SEMANTIC_MATERIALS = {
    "Paint": ((0.34, 0.018, 0.026, 1.0), 0.68, 0.28, (0, 0, 0), 0.0),
    "PaintSecondary": ((0.055, 0.058, 0.064, 1.0), 0.55, 0.36, (0, 0, 0), 0.0),
    "GlassWindow": ((0.018, 0.040, 0.058, 0.72), 0.08, 0.08, (0, 0, 0), 0.0),
    "TireRubber": ((0.010, 0.010, 0.011, 1.0), 0.0, 0.95, (0, 0, 0), 0.0),
    "RimMetal": ((0.52, 0.55, 0.58, 1.0), 1.0, 0.24, (0, 0, 0), 0.0),
    "Chrome": ((0.62, 0.65, 0.68, 1.0), 1.0, 0.16, (0, 0, 0), 0.0),
    "CarbonTrim": ((0.018, 0.020, 0.023, 1.0), 0.32, 0.38, (0, 0, 0), 0.0),
    "BlackTrim": ((0.014, 0.015, 0.017, 1.0), 0.05, 0.78, (0, 0, 0), 0.0),
    "BlackGloss": ((0.012, 0.013, 0.016, 1.0), 0.22, 0.22, (0, 0, 0), 0.0),
    "GreyTrim": ((0.16, 0.165, 0.17, 1.0), 0.05, 0.82, (0, 0, 0), 0.0),
    "InteriorDark": ((0.022, 0.021, 0.020, 1.0), 0.0, 0.92, (0, 0, 0), 0.0),
    "InteriorCloth": ((0.48, 0.40, 0.31, 1.0), 0.0, 1.0, (0, 0, 0), 0.0),
    "RedTrim": ((0.48, 0.012, 0.018, 1.0), 0.10, 0.34, (0, 0, 0), 0.0),
    "BrakeDisc": ((0.36, 0.38, 0.40, 1.0), 0.92, 0.38, (0, 0, 0), 0.0),
    "BrakeCaliper": ((0.55, 0.016, 0.020, 1.0), 0.25, 0.30, (0, 0, 0), 0.0),
    "Headlight": ((0.64, 0.74, 0.82, 1.0), 0.08, 0.10, (0.9, 0.95, 1.0), 0.12),
    "TailLight": ((0.42, 0.012, 0.018, 1.0), 0.06, 0.22, (1.0, 0.02, 0.03), 0.45),
    "WhiteTrim": ((0.84, 0.85, 0.86, 1.0), 0.05, 0.48, (0, 0, 0), 0.0),
}

MERCEDES_PRESERVED_MATERIALS = {
    "chassis.1": "ChassisTexture",
    "chassis.5": "EngineTextureA",
    "chassis.7": "LeatherTextureA",
    "chassis.8": "VelvetTextureA",
    "chassis.9": "InteriorTextureA",
    "chassis.10": "InteriorTextureB",
    "chassis.11": "PlasticTexture",
    "chassis.12": "VelvetTextureB",
    "chassis.13": "VelvetTextureA",
    "chassis.14": "EngineTextureB",
    "chassis.21": "LeatherTextureB",
    "Covers": "CoverTexture",
    "Tire_0": "TireSidewallTexture",
    "Tire_1": "TireTreadTexture",
    "Lights": "LightTexture",
    "Lights_Body": "LightTexture",
}

ORIGINAL_MATERIAL_NAMES: dict[int, str] = {}


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


def base_name(name: str) -> str:
    return re.sub(r"\.\d+$", "", name)


def object_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, point.x)
            mins.y = min(mins.y, point.y)
            mins.z = min(mins.z, point.z)
            maxs.x = max(maxs.x, point.x)
            maxs.y = max(maxs.y, point.y)
            maxs.z = max(maxs.z, point.z)
            found = True
    if not found:
        raise RuntimeError("No mesh bounds found")
    return mins, maxs


def object_center(obj: bpy.types.Object) -> Vector:
    mins, maxs = object_bounds([obj])
    return (mins + maxs) * 0.5


def object_size(obj: bpy.types.Object) -> Vector:
    mins, maxs = object_bounds([obj])
    return maxs - mins


def triangle_count(objects: list[bpy.types.Object]) -> int:
    total = 0
    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def load_source(car: str, input_path: Path) -> None:
    suffix = input_path.suffix.lower()
    if suffix == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(input_path))
    elif suffix == ".obj":
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.wm.obj_import(filepath=str(input_path))
    elif suffix == ".fbx":
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(input_path), use_anim=False)
    else:
        raise RuntimeError(f"Unsupported source format: {input_path}")
    bpy.context.view_layer.update()


def source_car_meshes(car: str) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.data:
            continue
        if car == "mercedes" and obj.name == "Plane":
            continue  # the authored studio ground, not part of the car
        result.append(obj)
    if not result:
        raise RuntimeError("Source contains no car meshes")
    return result


def is_tire_object(car: str, obj: bpy.types.Object) -> bool:
    name = obj.name
    clean = base_name(name).removeprefix("BAKED__")
    if car == "audi":
        return clean == "tyre"
    if car == "camaro":
        return clean.startswith("Wheel_")
    if car == "mercedes":
        return clean in {"FL", "FR", "BL", "BR"}
    return False


def bake_objects(car: str, sources: list[bpy.types.Object]) -> list[bpy.types.Object]:
    """Flatten evaluated source meshes into identity-transform copies."""
    mins, maxs = object_bounds(sources)
    raw_length = float(maxs.y - mins.y)
    if raw_length <= 0.0:
        raise RuntimeError("Source length is zero")
    scale = float(CAR_CONFIG[car]["target_length_m"]) / raw_length

    tire_sources = [obj for obj in sources if is_tire_object(car, obj)]
    if len(tire_sources) != 4:
        raise RuntimeError(f"Expected 4 tire/wheel sources, got {len(tire_sources)}: {[o.name for o in tire_sources]}")
    tire_centers = [object_center(obj) for obj in tire_sources]
    axle_mid = sum(tire_centers, Vector((0.0, 0.0, 0.0))) / 4.0
    tire_mins, _ = object_bounds(tire_sources)
    normalize = (
        Matrix.Translation((-axle_mid.x * scale, -axle_mid.y * scale, -tire_mins.z * scale))
        @ Matrix.Diagonal((scale, scale, scale, 1.0))
    )

    depsgraph = bpy.context.evaluated_depsgraph_get()
    collection = bpy.data.collections.new("GameCarBaked")
    bpy.context.scene.collection.children.link(collection)
    baked: list[bpy.types.Object] = []
    for obj in sources:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.transform(normalize @ obj.matrix_world)
        # new_from_object normally carries data-linked slots; copy any
        # object-linked slots explicitly so semantic mapping sees them all.
        for index, slot in enumerate(obj.material_slots):
            if slot.material is None:
                continue
            while len(mesh.materials) <= index:
                mesh.materials.append(None)
            mesh.materials[index] = slot.material
        copy = bpy.data.objects.new(f"BAKED__{obj.name}", mesh)
        collection.objects.link(copy)
        baked.append(copy)

    baked_ids = {obj.as_pointer() for obj in baked}
    for obj in list(bpy.data.objects):
        if obj.as_pointer() not in baked_ids:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in baked:
        obj.name = obj.name.removeprefix("BAKED__")
        if obj.data:
            obj.data.name = f"{obj.name}Mesh"
    bpy.context.view_layer.update()
    print(f"BAKE car={car} rawLength={raw_length:.6f} scale={scale:.8f} objects={len(baked)}")
    return baked


def semantic_material(name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    color, metallic, roughness, emission, strength = SEMANTIC_MATERIALS[name]
    mat = bpy.data.materials.new(name=name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Alpha"].default_value = color[3]
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    if color[3] < 0.999:
        # Blender 4.2+/5 spelling of alpha-blended viewport rendering.
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    return mat


def preserved_material(material: bpy.types.Material, target_name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(target_name)
    if existing:
        return existing
    material.name = target_name
    return material


def image_material(
    name: str,
    image: bpy.types.Image,
    *,
    metallic: float,
    roughness: float,
    use_alpha: bool,
) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    mat = bpy.data.materials.new(name=name)
    mat.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    if bsdf:
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if use_alpha:
            links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    if use_alpha:
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    return mat


def find_material_image(material: bpy.types.Material | None) -> bpy.types.Image | None:
    if material is None or not material.use_nodes or not material.node_tree:
        return None
    for node in material.node_tree.nodes:
        if node.bl_idname == "ShaderNodeTexImage" and node.image and node.image.size[0] > 0:
            return node.image
    return None


def wheel_code_for_center(center: Vector) -> str:
    # Blender -Y is the nose; +X becomes the car's left after the
    # glTF/Godot axis conversion and the runtime PI visual turn.
    if center.y < 0.0:
        return "FL" if center.x > 0.0 else "FR"
    return "RL" if center.x > 0.0 else "RR"


def assign_wheel_groups(
    car: str, objects: list[bpy.types.Object]
) -> tuple[dict[int, str], dict[str, Vector], dict[str, Vector]]:
    tires = [obj for obj in objects if is_tire_object(car, obj)]
    if len(tires) != 4:
        raise RuntimeError(f"After bake expected 4 tires, got {len(tires)}")
    hubs: dict[str, Vector] = {}
    tire_sizes: dict[str, Vector] = {}
    groups: dict[int, str] = {}
    for tire in tires:
        center = object_center(tire)
        code = wheel_code_for_center(center)
        hubs[code] = center
        tire_sizes[code] = object_size(tire)
        groups[tire.as_pointer()] = code

    if car == "audi":
        # Rims, brake discs/calipers and centre-cap details are separate
        # split-OBJ objects clustered tightly around each tyre centre.
        for obj in objects:
            if obj.as_pointer() in groups:
                continue
            clean = base_name(obj.name)
            center = object_center(obj)
            size = object_size(obj)
            nearest_code = min(hubs, key=lambda code: (center - hubs[code]).length)
            distance = (center - hubs[nearest_code]).length
            if clean == "rims 1" or (distance < 0.18 and max(size.x, size.y, size.z) < 0.36):
                groups[obj.as_pointer()] = nearest_code
    return groups, hubs, tire_sizes


def fix_audi_rim_orientation(obj: bpy.types.Object) -> None:
    """Flip the two mirrored R8 rim shells whose spoke faces point inboard.

    The split OBJ mirrors rim *positions* to all four corners, but for the
    front-right and rear-left shells it keeps winding whose large outer
    spoke faces point toward the car centre.  Those two wheels render as
    black discs.  Measure the area-weighted X normal on the outer third of
    each rim and flip only a shell that demonstrably faces inboard.
    """
    if obj.type != "MESH" or not obj.data or base_name(obj.name) != "rims 1":
        return
    center = object_center(obj)
    size = object_size(obj)
    outward = 1.0 if center.x > 0.0 else -1.0
    score = 0.0
    for polygon in obj.data.polygons:
        if (polygon.center.x - center.x) * outward > size.x * 0.25:
            score += float(polygon.area) * float(polygon.normal.x)
    if score * outward < 0.0:
        obj.data.flip_normals()
        obj.data.update()
        print(f"Flipped inboard-facing Audi rim shell: {obj.name}")


def audi_semantic(obj: bpy.types.Object, in_wheel: bool) -> bpy.types.Material:
    clean = base_name(obj.name)
    size = object_size(obj)
    center = object_center(obj)
    if clean == "body color":
        return semantic_material("Paint")
    if clean == "tyre":
        return semantic_material("TireRubber")
    if clean == "rims 1":
        return semantic_material("RimMetal")
    if clean == "chrome":
        return semantic_material("Chrome")
    if clean == "metal 1":
        return semantic_material("BrakeCaliper" if in_wheel else "RedTrim")
    if clean == "metal 2":
        if in_wheel and max(size.y, size.z) > 0.28:
            return semantic_material("BrakeDisc")
        if in_wheel and size.x < 0.006:
            return semantic_material("RimMetal")
        return semantic_material("BlackTrim")
    if clean in {"black gloss", "trim"}:
        return semantic_material("BlackGloss")
    if clean == "black matt":
        return semantic_material("CarbonTrim")
    if clean in {"Aluminium 1", "Aluminum 2"}:
        return semantic_material("Chrome")
    if clean == "grille":
        return semantic_material("BlackTrim")
    if clean == "glass window":
        return semantic_material("GlassWindow")
    if clean in {"glass lamp", "glass projector"}:
        return semantic_material("Headlight" if center.y < 0.0 else "TailLight")
    if clean.startswith("tail light"):
        return semantic_material("TailLight")
    if clean == "light":
        return semantic_material("Headlight" if center.y < 0.0 else "TailLight")
    if clean == "interior 1" or clean == "interior roof":
        return semantic_material("InteriorDark")
    if clean == "interior 2":
        return semantic_material("InteriorCloth")
    if clean == "logo red":
        return semantic_material("RedTrim")
    return semantic_material("BlackTrim")


def mercedes_semantic(material: bpy.types.Material | None) -> bpy.types.Material:
    if material is None:
        return semantic_material("BlackTrim")
    original = ORIGINAL_MATERIAL_NAMES.get(material.as_pointer(), material.name)
    if original in MERCEDES_PRESERVED_MATERIALS:
        return preserved_material(material, MERCEDES_PRESERVED_MATERIALS[original])
    mapping = {
        "primary": "Paint",
        "secondary": "PaintSecondary",
        "primary_2": "BlackTrim",
        "chassis.0": "Chrome",
        "chassis.3": "BlackTrim",
        "chassis.4": "GreyTrim",
        "Glass": "GlassWindow",
        "Rim": "RimMetal",
        "Mirror": "Chrome",
        "Plate.001": "WhiteTrim",
        "Object267.3": "BlackTrim",
        "Object273.3": "WhiteTrim",
    }
    return semantic_material(mapping.get(original, "BlackTrim"))


def assign_semantics(
    car: str,
    objects: list[bpy.types.Object],
    wheel_groups: dict[int, str],
    overlay_image_path: str,
) -> list[bpy.types.Object]:
    global ORIGINAL_MATERIAL_NAMES
    ORIGINAL_MATERIAL_NAMES = {
        mat.as_pointer(): mat.name for mat in bpy.data.materials
    }
    extra_objects: list[bpy.types.Object] = []

    # Build the rebuilt Camaro atlas materials before any slot is replaced.
    camaro_wheel_material: bpy.types.Material | None = None
    camaro_livery_material: bpy.types.Material | None = None
    if car == "camaro":
        atlas_image: bpy.types.Image | None = None
        for mat in bpy.data.materials:
            if ORIGINAL_MATERIAL_NAMES.get(mat.as_pointer()) == "lambert2":
                atlas_image = find_material_image(mat)
                break
        if atlas_image is None:
            raise RuntimeError("Camaro lambert2 atlas image was not found")
        camaro_wheel_material = image_material(
            "TireRimTexture", atlas_image, metallic=0.28, roughness=0.52, use_alpha=False
        )
        if overlay_image_path:
            overlay = bpy.data.images.load(str(Path(overlay_image_path).resolve()))
            overlay.alpha_mode = "STRAIGHT"
            camaro_livery_material = image_material(
                "LiveryTexture", overlay, metallic=0.34, roughness=0.34, use_alpha=True
            )

    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        in_wheel = obj.as_pointer() in wheel_groups
        current_materials = list(obj.data.materials)
        if not current_materials:
            current_materials = [None]
            obj.data.materials.append(None)
        for index, material in enumerate(current_materials):
            if car == "audi":
                replacement = audi_semantic(obj, in_wheel)
            elif car == "mercedes":
                replacement = mercedes_semantic(material)
            elif car == "camaro":
                original = (
                    ORIGINAL_MATERIAL_NAMES.get(material.as_pointer(), material.name)
                    if material
                    else ""
                )
                if obj.name.startswith("Wheel_"):
                    replacement = camaro_wheel_material
                elif original == "Glass" or obj.name.startswith("Body_Glass"):
                    replacement = semantic_material("GlassWindow")
                else:
                    replacement = semantic_material("Paint")
            else:
                replacement = semantic_material("BlackTrim")
            obj.data.materials[index] = replacement

    if car == "camaro" and camaro_livery_material is not None:
        body = next((obj for obj in objects if obj.name.startswith("Body_Textures")), None)
        if body is None:
            raise RuntimeError("Camaro body object was not found for the livery shell")
        shell_mesh = body.data.copy()
        shell_mesh.materials.clear()
        shell_mesh.materials.append(camaro_livery_material)
        # Push the shell 4 mm along averaged face normals so the graphics
        # sit above the repaintable paint without z-fighting.
        bm = bmesh.new()
        bm.from_mesh(shell_mesh)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        for vert in bm.verts:
            normal = Vector((0.0, 0.0, 0.0))
            for face in vert.link_faces:
                normal += face.normal
            if normal.length_squared > 0.000001:
                vert.co += normal.normalized() * 0.004
        bm.to_mesh(shell_mesh)
        bm.free()
        shell = bpy.data.objects.new("BodyLiveryOverlay", shell_mesh)
        body.users_collection[0].objects.link(shell)
        extra_objects.append(shell)

    if car == "mercedes":
        split_mercedes_light_faces(objects)
        shrink_mercedes_images()

    return extra_objects


def split_mercedes_light_faces(objects: list[bpy.types.Object]) -> None:
    """Turn the front/rear ends of the textured light meshes into the
    flat Headlight/TailLight materials the runtime can switch/brake-glow,
    while indicator/reflector detail in between keeps its texture."""
    body_objects = [obj for obj in objects if obj.name not in {"FL", "FR", "BL", "BR"}]
    mins, maxs = object_bounds(body_objects)
    length = maxs.y - mins.y
    front_limit = mins.y + length * 0.16
    rear_limit = maxs.y - length * 0.16
    headlight = semantic_material("Headlight")
    taillight = semantic_material("TailLight")
    for obj in body_objects:
        if obj.type != "MESH" or not obj.data:
            continue
        light_slots = {
            index
            for index, mat in enumerate(obj.data.materials)
            if mat and mat.name == "LightTexture"
        }
        if not light_slots:
            continue
        slot_by_name = {mat.name: i for i, mat in enumerate(obj.data.materials) if mat}
        if "Headlight" not in slot_by_name:
            obj.data.materials.append(headlight)
            slot_by_name["Headlight"] = len(obj.data.materials) - 1
        if "TailLight" not in slot_by_name:
            obj.data.materials.append(taillight)
            slot_by_name["TailLight"] = len(obj.data.materials) - 1
        for polygon in obj.data.polygons:
            if polygon.material_index not in light_slots:
                continue
            if polygon.center.y < front_limit:
                polygon.material_index = slot_by_name["Headlight"]
            elif polygon.center.y > rear_limit:
                polygon.material_index = slot_by_name["TailLight"]


def shrink_mercedes_images() -> None:
    # Thirteen 2048px PNGs are authoring resolution, not phone resolution.
    # 1024px JPEG export keeps the W126 interior/lights readable while
    # cutting the GLB by well over half.
    for image in bpy.data.images:
        width, height = int(image.size[0]), int(image.size[1])
        if width <= 0 or height <= 0 or max(width, height) <= 1024:
            continue
        ratio = 1024.0 / float(max(width, height))
        image.scale(max(1, round(width * ratio)), max(1, round(height * ratio)))


def join_objects(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    if not objects:
        raise RuntimeError(f"No objects to join for {name}")
    if len(objects) == 1:
        only = objects[0]
        only.name = name
        if only.data:
            only.data.name = f"{name}Mesh"
        return only
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    if joined.data:
        joined.data.name = f"{name}Mesh"
    return joined


def build_hierarchy(
    objects: list[bpy.types.Object],
    wheel_groups: dict[int, str],
    hubs: dict[str, Vector],
    root_name: str,
) -> tuple[bpy.types.Object, bpy.types.Object, dict[str, bpy.types.Object]]:
    by_code: dict[str, list[bpy.types.Object]] = defaultdict(list)
    body_objects: list[bpy.types.Object] = []
    for obj in objects:
        code = wheel_groups.get(obj.as_pointer())
        if code:
            by_code[code].append(obj)
        else:
            body_objects.append(obj)

    spins: dict[str, bpy.types.Object] = {}
    pivots: dict[str, bpy.types.Object] = {}
    for code in ("FL", "FR", "RL", "RR"):
        group = by_code.get(code, [])
        if not group:
            raise RuntimeError(f"Wheel group {code} is empty")
        hub = hubs[code]
        spin = join_objects(group, f"Wheel_{code}_Spin")
        spin.data.transform(Matrix.Translation(-hub))
        spin.location = hub
        spin.rotation_euler = (0.0, 0.0, 0.0)
        spin.scale = (1.0, 1.0, 1.0)
        pivot = bpy.data.objects.new(f"Wheel_{code}", None)
        pivot.empty_display_type = "PLAIN_AXES"
        pivot.empty_display_size = 0.12
        pivot.location = hub
        spin.users_collection[0].objects.link(pivot)
        spin.parent = pivot
        spin.matrix_parent_inverse = Matrix.Identity(4)
        spin.location = (0.0, 0.0, 0.0)
        spins[code] = spin
        pivots[code] = pivot

    body = join_objects(body_objects, "Body")
    root = bpy.data.objects.new(root_name, None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.25
    body.users_collection[0].objects.link(root)
    for child in [body, *pivots.values()]:
        child.parent = root
        child.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return root, body, spins


def purge_orphans() -> None:
    try:
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except Exception as exc:  # older/newer Blender spelling differences
        print(f"orphans_purge skipped: {exc}")


def main() -> None:
    args = parse_args()
    car = args.get("car", "").lower()
    if car not in CAR_CONFIG:
        raise RuntimeError(f"--car must be one of {sorted(CAR_CONFIG)}, got {car!r}")
    input_path = Path(args.get("input", "")).expanduser().resolve()
    output_path = Path(args.get("output", "")).expanduser().resolve()
    if not input_path.exists():
        raise RuntimeError(f"Input does not exist: {input_path}")
    if not str(output_path):
        raise RuntimeError("--output is required")

    load_source(car, input_path)
    sources = source_car_meshes(car)
    input_triangles = triangle_count(sources)
    baked = bake_objects(car, sources)
    wheel_groups, hubs, tire_sizes = assign_wheel_groups(car, baked)
    if car == "audi":
        for obj in baked:
            fix_audi_rim_orientation(obj)
    extras = assign_semantics(car, baked, wheel_groups, args.get("overlay-image", ""))
    all_objects = baked + extras
    root, body, spins = build_hierarchy(
        all_objects, wheel_groups, hubs, str(CAR_CONFIG[car]["root_name"])
    )
    purge_orphans()

    final_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    mins, maxs = object_bounds(final_meshes)
    size = maxs - mins
    final_triangles = triangle_count(final_meshes)

    if args.get("save-blend"):
        blend_path = Path(args["save-blend"]).expanduser().resolve()
        blend_path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    export_kwargs = {
        "filepath": str(output_path),
        "export_format": "GLB",
        "use_selection": False,
        "export_apply": True,
        "export_yup": True,
        "export_materials": "EXPORT",
    }
    if car == "mercedes":
        # No alpha textures are used by the preserved Mercedes materials.
        export_kwargs["export_image_format"] = "JPEG"
        export_kwargs["export_jpeg_quality"] = 82
    bpy.ops.export_scene.gltf(**export_kwargs)

    front_track = abs(float(hubs["FL"].x - hubs["FR"].x))
    rear_track = abs(float(hubs["RL"].x - hubs["RR"].x))
    wheelbase = abs(float((hubs["RL"].y + hubs["RR"].y - hubs["FL"].y - hubs["FR"].y) * 0.5))
    report = {
        "car": car,
        "input": input_path.name,
        "output": output_path.name,
        "outputBytes": output_path.stat().st_size,
        "inputTriangles": input_triangles,
        "finalTriangles": final_triangles,
        "finalMeshObjects": [obj.name for obj in final_meshes],
        "materials": sorted(mat.name for mat in bpy.data.materials if mat.users > 0),
        "boundsBlender": {
            "min": [round(float(v), 6) for v in mins],
            "max": [round(float(v), 6) for v in maxs],
            "sizeXYZ": [round(float(v), 6) for v in size],
        },
        "boundsGltfSizeXYZ": [
            round(float(size.x), 6),
            round(float(size.z), 6),
            round(float(size.y), 6),
        ],
        "wheelbaseM": round(wheelbase, 6),
        "frontTrackM": round(front_track, 6),
        "rearTrackM": round(rear_track, 6),
        "wheels": {
            code: {
                "blenderHub": [round(float(v), 6) for v in hubs[code]],
                "gltfHub": [
                    round(float(hubs[code].x), 6),
                    round(float(hubs[code].z), 6),
                    round(float(-hubs[code].y), 6),
                ],
                "tireSizeBlender": [round(float(v), 6) for v in tire_sizes[code]],
                "radiusM": round(float(max(tire_sizes[code].y, tire_sizes[code].z) * 0.5), 6),
                "spinTriangles": triangle_count([spins[code]]),
            }
            for code in ("FL", "FR", "RL", "RR")
        },
        "bodyTriangles": triangle_count([body]),
        "root": root.name,
    }
    if args.get("report"):
        report_path = Path(args["report"]).expanduser().resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
