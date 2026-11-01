#!/usr/bin/env python3
"""Convert the owner-supplied Bugatti Chiron into a game-ready GLB.

The supplied source is a Blender "underground garage" diorama scene whose
hero car is a CSR2-style Chiron Super Sport model.  Only the car objects
(identified by their ``CSR2_*`` / light / glass materials) are taken; the
garage set dressing is dropped.  The output follows the same GLB contract
as ``blender_convert_supplied_cars.py``: metres with the axle midpoint at
the origin, semantic material names understood by
``vehicle_controller.gd``, one ``Body`` mesh and ``Wheel_FL/FR/RL/RR``
pivots with ``*_Spin`` children.  Blender convention: nose = -Y, up = +Z.

Textures come from ``scripts/prepare_bugatti_textures.py`` (CSR2
diff/ref/gloss/opac maps turned into glTF base-colour + metallic-roughness
+ normal maps).  The two single-side caliper objects in the scene are
duplicates of geometry already inside the spanning ``CaliperLF`` /
``CaliperLR`` objects (exactly half the triangles, same bounds), so they
are excluded and the spanning objects are split per corner by face.

Example (run with Blender or with the ``bpy`` Python module)::

    blender -b --python scripts/blender_convert_bugatti_chiron.py -- \
        --blend "uploads_files_4478463_Underground+Garage+Scene.blend" \
        --textures /tmp/bugatti_tex \
        --output src/assets/models/cars/bugatti_chiron_super_sport.glb \
        --report src/assets/models/cars/bugatti_chiron_super_sport_report.json
"""

from __future__ import annotations

import json
import math
import sys
from collections import defaultdict
from pathlib import Path

import bpy  # noqa: E402  (bpy must initialise before bmesh in module mode)
import bmesh
from mathutils import Matrix, Vector

TARGET_LENGTH_M = 4.794  # Chiron Super Sport longtail, supplied spec sheet
ROOT_NAME = "BugattiChironSuperSport"

# name -> (RGBA, metallic, roughness, emission RGB, emission strength)
# Mirrors SEMANTIC_MATERIALS in blender_convert_supplied_cars.py.
SEMANTIC_MATERIALS = {
    "Paint": ((0.012, 0.012, 0.014, 1.0), 0.68, 0.28, (0, 0, 0), 0.0),
    "PaintSecondary": ((0.965, 0.054, 0.008, 1.0), 0.55, 0.36, (0, 0, 0), 0.0),
    "GlassWindow": ((0.018, 0.040, 0.058, 0.72), 0.08, 0.08, (0, 0, 0), 0.0),
    "Chrome": ((0.62, 0.65, 0.68, 1.0), 1.0, 0.16, (0, 0, 0), 0.0),
    "BlackTrim": ((0.014, 0.015, 0.017, 1.0), 0.05, 0.78, (0, 0, 0), 0.0),
    "BrakeCaliper": ((0.030, 0.030, 0.032, 1.0), 0.25, 0.30, (0, 0, 0), 0.0),
    "TailLight": ((0.42, 0.012, 0.018, 1.0), 0.06, 0.22, (1.0, 0.02, 0.03), 0.45),
}

CAR_MATERIAL_NAMES = {
    "Window", "GlassClear", "GlassRed", "Mirrors", "Park light",
    "brake light", "brake park light", "headlight", "miter", "bottons",
}
EXCLUDE_OBJECTS = {"CaliperRF", "CaliperRR"}  # duplicates, see docstring


def parse_args() -> dict[str, str]:
    args: dict[str, str] = {}
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = argv[1:]
    i = 0
    while i < len(argv):
        token = argv[i]
        if token.startswith("--") and i + 1 < len(argv):
            args[token[2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return args


def object_bounds(objects):
    bpy.context.view_layer.update()
    mins = Vector((math.inf, math.inf, math.inf))
    maxs = Vector((-math.inf, -math.inf, -math.inf))
    found = False
    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            for axis in range(3):
                mins[axis] = min(mins[axis], point[axis])
                maxs[axis] = max(maxs[axis], point[axis])
            found = True
    if not found:
        raise RuntimeError("No mesh bounds found")
    return mins, maxs


def object_center(obj) -> Vector:
    mins, maxs = object_bounds([obj])
    return (mins + maxs) * 0.5


def object_size(obj) -> Vector:
    mins, maxs = object_bounds([obj])
    return maxs - mins


def triangle_count(objects) -> int:
    total = 0
    for obj in objects:
        if obj.type != "MESH" or not obj.data:
            continue
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


def is_car_object(obj) -> bool:
    if obj.type != "MESH" or not obj.data:
        return False
    if obj.name in EXCLUDE_OBJECTS:
        return False
    for slot in obj.material_slots:
        if slot.material is None:
            continue
        name = slot.material.name
        if name.startswith("CSR2_") or name in CAR_MATERIAL_NAMES:
            return True
    return False


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
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    return mat


_TEXTURE_DIR: Path | None = None
_IMAGE_CACHE: dict[str, bpy.types.Image] = {}


def load_image(filename: str, colorspace: str) -> bpy.types.Image:
    if filename in _IMAGE_CACHE:
        return _IMAGE_CACHE[filename]
    assert _TEXTURE_DIR is not None
    path = _TEXTURE_DIR / filename
    if not path.exists():
        raise RuntimeError(f"Prepared texture missing: {path}")
    image = bpy.data.images.load(str(path), check_existing=False)
    try:
        image.colorspace_settings.name = colorspace
    except Exception:
        pass
    _IMAGE_CACHE[filename] = image
    return image


def textured_material(
    name: str,
    diff: str,
    mr: str | None = None,
    normal: str | None = None,
    emissive: str | None = None,
    emissive_strength: float = 1.0,
    use_alpha: bool = False,
    alpha_cutout: bool = False,
    metallic: float = 1.0,
    roughness: float = 1.0,
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
    x = -900

    def tex_node(filename: str, colorspace: str, y: int):
        node = nodes.new("ShaderNodeTexImage")
        node.image = load_image(filename, colorspace)
        node.interpolation = "Linear"
        node.location = (x, y)
        return node

    base = tex_node(diff, "sRGB", 300)
    links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    if use_alpha:
        links.new(base.outputs["Alpha"], bsdf.inputs["Alpha"])
    if mr:
        mr_node = tex_node(mr, "Non-Color", 0)
        separate = nodes.new("ShaderNodeSeparateRGB")
        separate.location = (-520, 0)
        links.new(mr_node.outputs["Color"], separate.inputs["Image"])
        links.new(separate.outputs["G"], bsdf.inputs["Roughness"])
        links.new(separate.outputs["B"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    if normal:
        n_node = tex_node(normal, "Non-Color", -300)
        nmap = nodes.new("ShaderNodeNormalMap")
        nmap.location = (-520, -300)
        links.new(n_node.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if emissive:
        e_node = tex_node(emissive, "sRGB", -600)
        links.new(e_node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emissive_strength
    if use_alpha:
        try:
            mat.surface_render_method = "DITHERED" if alpha_cutout else "BLENDED"
        except Exception:
            pass
    return mat


def bake_objects(sources, wheels):
    """Flatten evaluated source meshes into identity-transform copies."""
    mins, maxs = object_bounds(sources)
    raw_length = float(maxs.y - mins.y)
    if raw_length <= 0.0:
        raise RuntimeError("Source length is zero")
    scale = TARGET_LENGTH_M / raw_length
    if len(wheels) != 4:
        raise RuntimeError(f"Expected 4 wheel sources, got {len(wheels)}")
    centers = [object_center(o) for o in wheels]
    axle_mid = sum(centers, Vector((0.0, 0.0, 0.0))) / 4.0
    tire_mins, _ = object_bounds(wheels)
    normalize = (
        Matrix.Translation((-axle_mid.x * scale, -axle_mid.y * scale,
                            -tire_mins.z * scale))
        @ Matrix.Diagonal((scale, scale, scale, 1.0))
    )
    depsgraph = bpy.context.evaluated_depsgraph_get()
    collection = bpy.data.collections.new("GameCarBaked")
    bpy.context.scene.collection.children.link(collection)
    baked = []
    for obj in sources:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.transform(normalize @ obj.matrix_world)
        for index, slot in enumerate(obj.material_slots):
            if slot.material is None:
                continue
            while len(mesh.materials) <= index:
                mesh.materials.append(None)
            mesh.materials[index] = slot.material
        copy = bpy.data.objects.new(f"BAKED__{obj.name}", mesh)
        collection.objects.link(copy)
        baked.append(copy)
    baked_ids = {o.as_pointer() for o in baked}
    for obj in list(bpy.data.objects):
        if obj.as_pointer() not in baked_ids:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in baked:
        obj.name = obj.name.removeprefix("BAKED__")
        if obj.data:
            obj.data.name = f"{obj.name}Mesh"
    bpy.context.view_layer.update()
    print(f"BAKE rawLength={raw_length:.6f} scale={scale:.8f} "
          f"objects={len(baked)}")
    return baked


def wheel_code_for_center(center: Vector) -> str:
    # Blender -Y is the nose; +X becomes the car's left after the
    # glTF/Godot axis conversion and the runtime PI visual turn.
    if center.y < 0.0:
        return "FL" if center.x > 0.0 else "FR"
    return "RL" if center.x > 0.0 else "RR"


def target_materials() -> dict[str, bpy.types.Material]:
    head = textured_material("HeadlightTexture", "light_diff.jpg",
                             mr="light_mr.jpg", emissive="light_emissive.jpg",
                             emissive_strength=1.0)
    tail = textured_material("TailLightTexture", "light_diff.jpg",
                             mr="light_mr.jpg", emissive="light_emissive.jpg",
                             emissive_strength=1.6)
    brake_disc = textured_material("BrakeDisc", "wheel_diff.jpg",
                                   mr="wheel_mr.jpg",
                                   normal="wheel_nrml.png")
    return {
        "CSR2_Coloured": semantic_material("Paint"),
        "CSR2_CarPaint": semantic_material("PaintSecondary"),
        "CSR2_Carbon1": textured_material("CarbonTrim", "carbon_base.jpg",
                                          mr="carbon_mr.jpg"),
        "CSR2_Base": semantic_material("BlackTrim"),
        "Window": semantic_material("GlassWindow"),
        "GlassClear": semantic_material("GlassWindow"),
        "GlassRed": semantic_material("TailLight"),
        "Mirrors": semantic_material("Chrome"),
        "headlight": head,
        "Park light": tail,
        "brake park light": tail,
        "brake light": tail,
        "CSR2_Badge": textured_material("BadgeTexture",
                                        "badge_diff_rgba.png",
                                        mr="badge_mr.jpg",
                                        normal="badge_nrml.png",
                                        use_alpha=True, alpha_cutout=True),
        "CSR2_Grille1": textured_material("GrilleTexture",
                                          "grille1_diff_rgba.png",
                                          mr="grille1_mr.jpg",
                                          normal="grille1_nrml.png",
                                          use_alpha=True, alpha_cutout=True),
        "CSR2_Grille2": textured_material("GrilleTexture2",
                                          "grille2_diff.jpg",
                                          mr="grille2_mr.jpg",
                                          normal="grille2_nrml.png"),
        "CSR2_Grille3": textured_material("GrilleTexture3",
                                          "grille3_diff_rgba.png",
                                          mr="grille3_mr.jpg",
                                          normal="grille3_nrml.png",
                                          use_alpha=True, alpha_cutout=True),
        "CSR2_Interior": textured_material("InteriorDark",
                                           "interior_diff_rgba.png",
                                           mr="interior_mr.jpg",
                                           normal="interior_nrml.png",
                                           use_alpha=True, alpha_cutout=True),
        "CSR2_InteriorZone2": textured_material("InteriorCloth",
                                                "interior_diff_rgba.png",
                                                mr="interior_mr.jpg",
                                                normal="interior_nrml.png"),
        "CSR2_InteriorZone2A": textured_material("InteriorCloth",
                                                 "interior_diff_rgba.png",
                                                 mr="interior_mr.jpg",
                                                 normal="interior_nrml.png"),
        "miter": textured_material("InteriorGlow",
                                   "interior_diff_rgba.png",
                                   mr="interior_mr.jpg",
                                   emissive="interior_emissive.jpg",
                                   emissive_strength=0.9),
        "bottons": textured_material("InteriorGlow",
                                     "interior_diff_rgba.png",
                                     mr="interior_mr.jpg",
                                     emissive="interior_emissive.jpg",
                                     emissive_strength=0.9),
        "CSR2_Wheel1A_Tire": textured_material("TireTreadTexture",
                                               "wheel_diff.jpg",
                                               mr="wheel_mr.jpg",
                                               normal="wheel_nrml.png"),
        "CSR2_Wheel1A_Rim": textured_material("RimMetal", "wheel_diff.jpg",
                                              mr="wheel_mr.jpg",
                                              normal="wheel_nrml.png"),
        "CSR2_Wheel1A_Rotor": brake_disc,
        "CSR2_CalliperZone": brake_disc,
        "CSR2_Calliper_Color": semantic_material("BrakeCaliper"),
        "CSR2_CalliperBadge": semantic_material("BrakeCaliper"),
        # "CSR2_Light" handled per-face (front vs rear) below.
    }


def assign_materials(baked) -> None:
    targets = target_materials()
    head = bpy.data.materials["HeadlightTexture"]
    tail = bpy.data.materials["TailLightTexture"]
    fallback = semantic_material("BlackTrim")
    unmapped: set[str] = set()
    for obj in baked:
        mesh = obj.data
        light_slots: list[int] = []
        for index, material in enumerate(list(mesh.materials)):
            if material is None:
                mesh.materials[index] = fallback
                continue
            name = material.name
            if name == "CSR2_Light":
                mesh.materials[index] = head
                light_slots.append(index)
                continue
            target = targets.get(name)
            if target is None:
                unmapped.add(name)
                target = fallback
            mesh.materials[index] = target
        if light_slots:
            mesh.materials.append(tail)
            tail_index = len(mesh.materials) - 1
            for polygon in mesh.polygons:
                if polygon.material_index in light_slots \
                        and polygon.center.y > 0.0:
                    polygon.material_index = tail_index
    if unmapped:
        print(f"UNMAPPED materials (fell back to BlackTrim): {sorted(unmapped)}")


def split_calipers(baked, hubs) -> list[bpy.types.Object]:
    """Split the spanning caliper objects into per-corner pieces."""
    pieces: list[bpy.types.Object] = []
    spanning = [o for o in baked if o.name in ("CaliperLF", "CaliperLR")]
    for obj in spanning:
        for code, hub in hubs.items():
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            doomed = []
            for face in bm.faces:
                centre = face.calc_center_median()
                nearest = min(hubs, key=lambda c: (centre - hubs[c]).length)
                if nearest != code:
                    doomed.append(face)
            bmesh.ops.delete(bm, geom=doomed, context="FACES")
            if not bm.faces:
                bm.free()
                continue
            mesh = bpy.data.meshes.new(f"{obj.name}_{code}Mesh")
            bm.to_mesh(mesh)
            bm.free()
            for material in obj.data.materials:
                mesh.materials.append(material)
            piece = bpy.data.objects.new(f"{obj.name}_{code}", mesh)
            obj.users_collection[0].objects.link(piece)
            pieces.append(piece)
    for obj in spanning:
        baked.remove(obj)
        bpy.data.objects.remove(obj, do_unlink=True)
    return pieces


def join_objects(objects, name):
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


def build_hierarchy(objects, wheel_groups, hubs, root_name):
    by_code: dict[str, list] = defaultdict(list)
    body_objects: list = []
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


# Alpha-tested (glTF MASK) materials: mesh/decals cut-outs must not go
# through the transparent sorting path on mobile.
_MASK_MATERIALS = {"BadgeTexture", "GrilleTexture", "GrilleTexture3",
                   "InteriorDark"}


def force_mask_alpha(glb_path: Path) -> None:
    """Rewrite alphaMode to MASK for cut-out materials in the GLB JSON.

    Blender 4.2's exporter emits BLEND for any alpha-textured material;
    patching the JSON chunk afterwards is deterministic across versions.
    """
    import struct

    data = bytearray(glb_path.read_bytes())
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(bytes(data[20:20 + json_len]))
    for material in gltf.get("materials", []):
        if material.get("name") in _MASK_MATERIALS:
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = 0.5
    payload = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    payload += b" " * (-len(payload) % 4)
    rest = bytes(data[20 + json_len:])
    out = bytearray()
    out += b"glTF" + struct.pack("<II", 2, 12 + 8 + len(payload) + len(rest))
    out += struct.pack("<I", len(payload)) + b"JSON" + payload + rest
    glb_path.write_bytes(bytes(out))


def purge_orphans() -> None:
    try:
        bpy.ops.outliner.orphans_purge(
            do_local_ids=True, do_linked_ids=True, do_recursive=True)
    except Exception as exc:
        print(f"orphans_purge skipped: {exc}")


def main() -> None:
    global _TEXTURE_DIR
    args = parse_args()
    blend_path = Path(args.get("blend", "")).expanduser().resolve()
    output_path = Path(args.get("output", "")).expanduser().resolve()
    _TEXTURE_DIR = Path(args.get("textures", "")).expanduser().resolve()
    if not blend_path.exists():
        raise RuntimeError(f"Blend input does not exist: {blend_path}")
    if not str(output_path):
        raise RuntimeError("--output is required")

    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    bpy.context.view_layer.update()
    sources = [o for o in bpy.context.scene.objects if is_car_object(o)]
    wheels = [o for o in sources if o.name.startswith("Wheel_01_")]
    print(f"SOURCE car objects={len(sources)} wheels="
          f"{[w.name for w in wheels]}")
    input_triangles = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in sources:
        mesh = obj.evaluated_get(deps).to_mesh()
        mesh.calc_loop_triangles()
        input_triangles += len(mesh.loop_triangles)
        obj.evaluated_get(deps).to_mesh_clear()

    baked = bake_objects(sources, wheels)
    assign_materials(baked)

    baked_wheels = [o for o in baked if o.name.startswith("Wheel_01_")]
    hubs: dict[str, Vector] = {}
    tire_sizes: dict[str, Vector] = {}
    wheel_groups: dict[int, str] = {}
    for wheel in baked_wheels:
        centre = object_center(wheel)
        code = wheel_code_for_center(centre)
        hubs[code] = centre
        tire_sizes[code] = object_size(wheel)
        wheel_groups[wheel.as_pointer()] = code
    if len(hubs) != 4:
        raise RuntimeError(f"Wheel hubs incomplete: {sorted(hubs)}")

    for piece in split_calipers(baked, hubs):
        code = min(hubs, key=lambda c: (object_center(piece)
                                        - hubs[c]).length)
        wheel_groups[piece.as_pointer()] = code
        baked.append(piece)

    root, body, spins = build_hierarchy(baked, wheel_groups, hubs, ROOT_NAME)
    purge_orphans()

    final_meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mins, maxs = object_bounds(final_meshes)
    size = maxs - mins
    final_triangles = triangle_count(final_meshes)

    if args.get("save-blend"):
        save_path = Path(args["save-blend"]).expanduser().resolve()
        save_path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(save_path))

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
    force_mask_alpha(output_path)

    front_track = abs(float(hubs["FL"].x - hubs["FR"].x))
    rear_track = abs(float(hubs["RL"].x - hubs["RR"].x))
    wheelbase = abs(float((hubs["RL"].y + hubs["RR"].y
                           - hubs["FL"].y - hubs["FR"].y) * 0.5))
    report = {
        "car": "bugatti_chiron_super_sport",
        "input": blend_path.name,
        "output": output_path.name,
        "outputBytes": output_path.stat().st_size,
        "inputTriangles": input_triangles,
        "finalTriangles": final_triangles,
        "finalMeshObjects": [o.name for o in final_meshes],
        "materials": sorted({
            slot.name
            for mesh_obj in final_meshes
            for slot in mesh_obj.data.materials
            if slot is not None
        }),
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
                "tireSizeBlender": [round(float(v), 6)
                                    for v in tire_sizes[code]],
                "radiusM": round(float(max(tire_sizes[code].y,
                                           tire_sizes[code].z) * 0.5), 6),
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
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
