#!/usr/bin/env python3
"""Build original low-poly city props for Nitches Horizon in Blender.

Run headless:
    blender -b -noaudio --python blender/build_props.py -- <out_dir>

Designs are original (authored for this fan project) and modelled in real
metres, origin at ground centre, Blender Z-up; the glTF exporter converts
to Y-up for three.js. Materials carry semantic names (PropsMetal, ...) —
the game remaps them to the player's photo textures at load time, while
the plain colours below keep the raw GLBs presentable on their own.

Props:
  * bus_shelter.glb   enclosed air-conditioned stop (RichTown standard)
  * street_lamp.glb   tapered pole with two swept arms
  * hero_building.glb five-storey residential block with balconies
"""
import math
import os
import sys

import bpy

# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
MATS = {}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name, color, roughness=0.7, metallic=0.0, emission=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission is not None:
            for key in ("Emission Color", "Emission"):
                if key in bsdf.inputs:
                    bsdf.inputs[key].default_value = (*emission, 1.0)
                    break
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = 2.2
    MATS[name] = m
    return m


def standard_mats():
    mat("PropsMetal", (0.42, 0.45, 0.48), roughness=0.38, metallic=0.85)
    mat("PropsGlass", (0.16, 0.28, 0.36), roughness=0.08, metallic=0.9)
    mat("PropsWood", (0.45, 0.30, 0.16), roughness=0.82)
    mat("FacadeMain", (0.87, 0.83, 0.75), roughness=0.88)
    mat("FacadeAccent", (0.55, 0.50, 0.44), roughness=0.9)
    mat("RoofDark", (0.16, 0.16, 0.17), roughness=0.95)
    mat("LampGlow", (1.0, 0.94, 0.78), roughness=0.4, emission=(1.0, 0.9, 0.65))


def finish(obj, material, bevel=0.0, smooth=False):
    if material:
        obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    except RuntimeError:
        pass
    if bevel > 0:
        mod = obj.modifiers.new(name="bev", type="BEVEL")
        mod.width = bevel
        mod.segments = 2
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError:
            pass
    if smooth:
        try:
            bpy.ops.object.shade_smooth()
        except RuntimeError:
            pass
    obj.select_set(False)
    return obj


def box(name, x, y, z, dx, dy, dz, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=(x, y, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (dx, dy, dz)
    return finish(obj, material, bevel=bevel)


def cyl(name, x, y, z, radius, depth, material, vertices=14, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, vertices=vertices,
        location=(x, y, z), rotation=rotation,
    )
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, material, smooth=True)


def cone(name, x, y, z, r1, r2, depth, material, vertices=14):
    bpy.ops.mesh.primitive_cone_add(
        radius1=r1, radius2=r2, depth=depth, vertices=vertices, location=(x, y, z),
    )
    obj = bpy.context.active_object
    obj.name = name
    return finish(obj, material, smooth=True)


def export(out_dir, filename):
    path = os.path.join(out_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=True, export_apply=True,
    )
    tris = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[props] {filename}: {os.path.getsize(path)} bytes, ~{tris} tris")


# --------------------------------------------------------------------------- #
# enclosed air-conditioned bus shelter: 5.4 x 2.0 m, 2.75 m tall
# --------------------------------------------------------------------------- #
def build_shelter():
    metal = MATS["PropsMetal"]
    glass = MATS["PropsGlass"]
    wood = MATS["PropsWood"]
    dark = MATS["RoofDark"]

    box("base", 0, 0, 0.06, 5.4, 2.0, 0.12, dark)
    for sx in (-2.55, 2.55):
        for sy in (-0.88, 0.88):
            cyl("post", sx, sy, 1.32, 0.055, 2.4, metal)
    # roof slab + fascia + rooftop AC unit
    box("roof", 0, 0, 2.62, 5.75, 2.35, 0.13, metal, bevel=0.03)
    box("fascia", 0, 0, 2.5, 5.5, 2.1, 0.1, metal)
    box("ac", -1.7, 0, 2.86, 1.3, 0.8, 0.34, metal, bevel=0.02)
    cyl("ac_fan", -1.7, 0, 3.04, 0.26, 0.04, dark, vertices=18)
    # glazed long sides with a central door gap on BOTH faces (enclosed stop)
    for sy in (-0.9, 0.9):
        for sx in (-1.65, 1.65):
            box("glass_long", sx, sy, 1.28, 2.05, 0.05, 2.15, glass)
        for sx in (-0.62, 0.62):
            box("door_frame", sx, sy, 1.28, 0.07, 0.07, 2.15, metal)
        box("header", 0, sy, 2.4, 5.2, 0.06, 0.14, metal)
    # glazed short sides
    for sx in (-2.62, 2.62):
        box("glass_side", sx, 0, 1.28, 0.05, 1.72, 2.15, glass)
    # bench + info panel inside
    box("bench_seat", 0, -0.48, 0.62, 3.6, 0.45, 0.08, wood, bevel=0.015)
    box("bench_back", 0, -0.72, 0.98, 3.6, 0.06, 0.5, wood)
    for sx in (-1.5, 1.5):
        box("bench_leg", sx, -0.48, 0.31, 0.08, 0.42, 0.5, metal)
    box("info_panel", 2.28, 0.45, 1.35, 0.08, 0.9, 1.5, glass)


# --------------------------------------------------------------------------- #
# street lamp: tapered pole, two arms along the road axis, 6.55 m tall
# --------------------------------------------------------------------------- #
def build_lamp():
    metal = MATS["PropsMetal"]
    glow = MATS["LampGlow"]
    cyl("base", 0, 0, 0.3, 0.24, 0.6, metal, vertices=16)
    cone("pole", 0, 0, 3.35, 0.14, 0.075, 6.1, metal, vertices=14)
    cyl("collar", 0, 0, 6.15, 0.11, 0.16, metal)
    for s in (-1, 1):
        # swept arm along +/-Y (road axis after Y-up export), slight rise
        cyl("arm", 0, s * 1.0, 6.34, 0.045, 2.1, metal,
            rotation=(math.pi / 2 - s * 0.1, 0, 0))
        box("head", 0, s * 1.95, 6.5, 0.36, 1.0, 0.16, metal, bevel=0.045)
        box("glow", 0, s * 1.95, 6.41, 0.27, 0.82, 0.04, glow)
    cyl("finial", 0, 0, 6.52, 0.05, 0.22, metal)


# --------------------------------------------------------------------------- #
# hero residential block: 24 x 14 m footprint, 17 m, five floors
# --------------------------------------------------------------------------- #
def build_hero():
    main = MATS["FacadeMain"]
    accent = MATS["FacadeAccent"]
    glass = MATS["PropsGlass"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]

    W, D = 24.0, 14.0
    floor_h, floors = 3.1, 5
    top = 1.1 + floors * floor_h  # plinth + floors = 16.6

    box("plinth", 0, 0, 0.55, W + 0.4, D + 0.4, 1.1, accent, bevel=0.03)
    box("body", 0, 0, 1.1 + (top - 1.1) / 2, W, D, top - 1.1, main, bevel=0.05)
    box("cornice", 0, 0, top + 0.22, W + 0.5, D + 0.5, 0.44, accent, bevel=0.03)
    # parapet ring + roof furniture
    for sy in (-(D / 2 - 0.15), D / 2 - 0.15):
        box("parapet", 0, sy, top + 0.75, W - 0.3, 0.25, 0.65, main)
    for sx in (-(W / 2 - 0.15), W / 2 - 0.15):
        box("parapet", sx, 0, top + 0.75, 0.25, D - 0.3, 0.65, main)
    box("roof_slab", 0, 0, top + 0.46, W - 0.6, D - 0.6, 0.08, dark)
    for i, (ax, ay) in enumerate(((-7, 3), (2, -3.5), (8, 2.5))):
        box(f"roof_ac_{i}", ax, ay, top + 0.95, 1.8, 1.1, 0.9, metal, bevel=0.03)
    cyl("roof_tank", -3.5, -3, top + 1.15, 0.85, 1.3, metal, vertices=18)
    box("lift_house", 5.5, -1, top + 1.1, 3.2, 2.6, 1.3, accent, bevel=0.03)

    def window_row(face_y, sign, count_x, span, ry=False):
        for f in range(floors):
            z = 1.1 + f * floor_h + 1.75
            for i in range(count_x):
                t = -span / 2 + span * (i + 0.5) / count_x
                if ry:  # short faces: window plane in YZ
                    box("win_frame", face_y + sign * 0.02, t, z, 0.07, 1.7, 1.8, metal)
                    box("win_glass", face_y + sign * 0.06, t, z, 0.05, 1.5, 1.6, glass)
                else:
                    box("win_frame", t, face_y + sign * 0.02, z, 1.7, 0.07, 1.8, metal)
                    box("win_glass", t, face_y + sign * 0.06, z, 1.5, 0.05, 1.6, glass)

    window_row(D / 2, 1, 6, W - 3)
    window_row(-D / 2, -1, 6, W - 3)
    window_row(W / 2, 1, 3, D - 3, ry=True)
    window_row(-W / 2, -1, 3, D - 3, ry=True)

    # balconies on both long faces, floors 2..5, three bays
    for sy, sign in ((D / 2, 1), (-D / 2, -1)):
        for f in range(1, floors):
            z = 1.1 + f * floor_h
            for bx in (-7.5, 0, 7.5):
                cy = sy + sign * 0.55
                box("balc_slab", bx, cy, z + 0.06, 2.6, 1.1, 0.12, accent)
                box("balc_glass", bx, sy + sign * 1.05, z + 0.42, 2.6, 0.05, 0.6, glass)
                box("balc_rail", bx, sy + sign * 1.05, z + 0.75, 2.6, 0.07, 0.06, metal)
                box("balc_door", bx, sy + sign * 0.05, z + 1.15, 1.1, 0.06, 2.2, glass)

    # entrance canopies both faces
    for sy, sign in ((D / 2, 1), (-D / 2, -1)):
        box("canopy", 0, sy + sign * 1.05, 3.25, 5.2, 2.1, 0.16, metal, bevel=0.03)
        for cx in (-2.3, 2.3):
            cyl("canopy_col", cx, sy + sign * 1.85, 1.6, 0.07, 3.2, metal)
        box("door", 0, sy + sign * 0.05, 1.55, 2.4, 0.08, 2.5, glass)
        box("door_frame", 0, sy + sign * 0.02, 1.6, 2.7, 0.06, 2.7, metal)


# --------------------------------------------------------------------------- #
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.path.join(os.getcwd(), "props_out")
    os.makedirs(out_dir, exist_ok=True)

    for build, filename in (
        (build_shelter, "bus_shelter.glb"),
        (build_lamp, "street_lamp.glb"),
        (build_hero, "hero_building.glb"),
    ):
        reset_scene()
        standard_mats()
        build()
        export(out_dir, filename)
    print("[props] done ->", out_dir)


main()
