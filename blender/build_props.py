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
  * townhouse.glb     two-storey suburban house with garage and gable roof
  * villa.glb         modern two-storey villa with pergola and roof terrace
  * glass_tower.glb   podium tower with finned glass curtain wall
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
    mat("FacadeGlass", (0.22, 0.45, 0.58), roughness=0.18, metallic=0.55)
    mat("RoofTile", (0.48, 0.2, 0.12), roughness=0.9)


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


def rbox(name, x, y, z, dx, dy, dz, material, rotation=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=(x, y, z), rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (dx, dy, dz)
    return finish(obj, material, bevel=bevel)


def gable_roof(name, x, y, z, dx, dy, dz, material, ridge_axis="x"):
    """A UV-mapped cube collapsed along its top edge into a gable prism."""
    obj = box(name, x, y, z, dx, dy, dz, material)
    for v in obj.data.vertices:
        if v.co.z > 0:
            if ridge_axis == "x":
                v.co.y = 0
            else:
                v.co.x = 0
    obj.data.update()
    return obj


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
# suburban townhouse: 12.8 x 11 m, 9.45 m including roof
# --------------------------------------------------------------------------- #
def build_townhouse():
    main = MATS["FacadeMain"]
    accent = MATS["FacadeAccent"]
    glass = MATS["PropsGlass"]
    metal = MATS["PropsMetal"]
    wood = MATS["PropsWood"]
    roof = MATS["RoofTile"]
    dark = MATS["RoofDark"]

    box("foundation", 0, 0, 0.3, 12.8, 11.0, 0.6, accent, bevel=0.02)
    box("house", -1.6, 0, 3.65, 8.8, 10.0, 6.1, main, bevel=0.04)
    box("garage", 4.45, 0.65, 2.05, 3.7, 7.7, 3.5, accent, bevel=0.03)
    gable_roof("main_roof", -1.6, 0, 8.05, 9.7, 11.2, 2.8, roof, ridge_axis="x")
    rbox("garage_roof", 4.45, 0.65, 3.98, 4.3, 8.5, 0.22, dark,
         rotation=(0.16, 0, 0), bevel=0.02)
    box("ridge_cap", -1.6, 0, 9.48, 9.8, 0.32, 0.16, dark)
    box("chimney", -4.2, 1.9, 8.75, 0.75, 0.75, 2.2, accent, bevel=0.02)
    box("chimney_cap", -4.2, 1.9, 9.9, 0.95, 0.95, 0.18, dark)

    def window(x, y, z, w, h, side="front"):
        if side in ("front", "back"):
            box("win_frame", x, y, z, w + 0.18, 0.09, h + 0.18, metal)
            box("win_glass", x, y + (-0.03 if side == "front" else 0.03), z, w, 0.06, h, glass)
            box("win_sill", x, y + (-0.05 if side == "front" else 0.05), z - h / 2 - 0.08, w + 0.3, 0.16, 0.1, accent)
        else:
            sign = 1 if side == "right" else -1
            box("win_frame", x, y, z, 0.09, w + 0.18, h + 0.18, metal)
            box("win_glass", x + sign * 0.03, y, z, 0.06, w, h, glass)
            box("win_sill", x + sign * 0.05, y, z - h / 2 - 0.08, 0.16, w + 0.3, 0.1, accent)

    for z in (1.75, 4.75):
        for x in (-4.7, -2.2, 0.6):
            if z < 3 and x == -2.2:
                continue
            window(x, -5.03, z, 1.35, 1.45, "front")
            window(x, 5.03, z, 1.35, 1.45, "back")
    for z in (1.8, 4.8):
        window(-6.03, -1.6, z, 1.5, 1.35, "left")
        window(-6.03, 1.8, z, 1.5, 1.35, "left")
        window(2.83, 2.2, z, 1.35, 1.25, "right")

    # porch, entrance and shutters
    rbox("porch_roof", -2.2, -5.65, 3.12, 3.4, 1.45, 0.14, dark,
         rotation=(-0.08, 0, 0), bevel=0.02)
    for cx in (-3.65, -0.75):
        cyl("porch_col", cx, -6.15, 1.55, 0.07, 3.1, wood)
    box("front_door", -2.2, -5.06, 1.55, 1.05, 0.09, 2.25, wood)
    box("door_glass", -2.2, -5.12, 1.95, 0.55, 0.04, 0.9, glass)
    box("step", -2.2, -5.55, 0.22, 1.7, 0.9, 0.24, accent)
    for x in (-5.55, -3.85, -0.25, 1.45):
        box("shutter", x, -5.08, 4.75, 0.42, 0.05, 1.45, wood)

    # sectional garage door with seams and a window band
    box("garage_door", 4.45, -3.24, 1.55, 2.9, 0.09, 2.25, metal)
    for i in range(4):
        box("garage_seam", 4.45, -3.3, 0.78 + i * 0.52, 2.86, 0.03, 0.05, dark)
    for x in (3.55, 4.45, 5.35):
        box("garage_win", x, -3.31, 2.33, 0.62, 0.04, 0.34, glass)
    box("driveway", 4.45, -5.15, 0.12, 3.4, 2.5, 0.12, dark)

    # downspouts, external AC, path and a low front fence
    for x, y in ((-5.85, -4.85), (2.65, -4.85), (-5.85, 4.85)):
        cyl("downspout", x, y, 3.3, 0.055, 6.2, metal, vertices=8)
    box("ac_unit", 1.8, 5.35, 0.65, 1.0, 0.55, 0.75, metal, bevel=0.02)
    for i, y in enumerate((-5.9, -6.7, -7.5)):
        box(f"path_{i}", -2.2, y, 0.09, 1.25, 0.55, 0.1, accent)
    for x in range(-6, 7, 2):
        if -3 <= x <= -1:
            continue
        box("fence_post", x + 0.35, -7.15, 0.5, 0.11, 0.11, 1.0, wood)
    for z in (0.38, 0.78):
        box("fence_rail", -4.15, -7.15, z, 4.5, 0.05, 0.1, wood)
        box("fence_rail", 3.15, -7.15, z, 7.0, 0.05, 0.1, wood)


# --------------------------------------------------------------------------- #
# modern villa: 18.5 x 14.5 m, 7.6 m, two interlocking volumes
# --------------------------------------------------------------------------- #
def build_villa():
    main = MATS["FacadeMain"]
    accent = MATS["FacadeAccent"]
    glass = MATS["PropsGlass"]
    metal = MATS["PropsMetal"]
    wood = MATS["PropsWood"]
    dark = MATS["RoofDark"]

    box("plinth", 0, 0, 0.3, 18.5, 14.5, 0.6, dark, bevel=0.02)
    box("west_volume", -3.3, 0.4, 3.45, 10.8, 11.4, 5.7, main, bevel=0.04)
    box("east_volume", 4.8, -0.6, 3.75, 7.0, 9.4, 6.3, accent, bevel=0.04)
    box("link_volume", 0.7, 1.5, 2.15, 4.2, 7.2, 3.1, glass)
    box("west_roof", -3.3, 0.4, 6.48, 11.5, 12.1, 0.38, dark, bevel=0.03)
    box("east_roof", 4.8, -0.6, 7.08, 7.7, 10.1, 0.38, wood, bevel=0.03)
    box("roof_screen", -5.8, 3.2, 7.0, 3.2, 2.2, 0.75, metal, bevel=0.02)

    def glass_wall(x, y, z, w, h, ry=False):
        if ry:
            box("glass_frame", x, y, z, 0.1, w + 0.18, h + 0.18, metal)
            box("glass_pane", x, y, z, 0.06, w, h, glass)
            for k in (-0.25, 0.25):
                box("mullion", x, y + k * w, z, 0.11, 0.08, h, metal)
        else:
            box("glass_frame", x, y, z, w + 0.18, 0.1, h + 0.18, metal)
            box("glass_pane", x, y, z, w, 0.06, h, glass)
            for k in (-0.25, 0.25):
                box("mullion", x + k * w, y, z, 0.08, 0.11, h, metal)

    glass_wall(-5.4, -5.35, 2.1, 4.6, 2.8)
    glass_wall(-0.8, -5.35, 2.1, 3.8, 2.8)
    glass_wall(4.8, -5.35, 2.3, 4.8, 3.1)
    glass_wall(-4.6, 6.15, 4.9, 5.8, 2.0)
    glass_wall(4.8, 4.15, 5.0, 4.6, 2.0)
    glass_wall(-8.75, 0.2, 3.4, 6.4, 3.4, ry=True)
    glass_wall(8.35, -0.6, 3.7, 5.8, 3.6, ry=True)

    # upper balcony with glass railing, timber privacy fins and pergola
    box("balcony", -3.3, -6.15, 3.62, 9.5, 1.45, 0.2, accent)
    box("balcony_glass", -3.3, -6.82, 4.15, 9.5, 0.06, 0.82, glass)
    box("balcony_rail", -3.3, -6.82, 4.6, 9.5, 0.09, 0.07, metal)
    for cx in (-7.7, 1.1):
        cyl("balcony_col", cx, -6.55, 1.8, 0.07, 3.6, metal)
    for i in range(7):
        box("privacy_fin", 2.0 + i * 0.52, -5.48, 3.3, 0.16, 0.12, 5.4, wood)
    for x in (-7.6, -3.2):
        for y in (4.5, 7.0):
            box("pergola_post", x, y, 1.45, 0.16, 0.16, 2.9, wood)
    for i in range(6):
        box("pergola_beam", -7.45 + i * 0.85, 5.75, 3.0, 0.15, 3.2, 0.16, wood)
    box("pergola_side", -5.4, 4.45, 3.0, 4.8, 0.15, 0.16, wood)
    box("pergola_side", -5.4, 7.05, 3.0, 4.8, 0.15, 0.16, wood)

    # entrance, garage, stairs, solar panels, AC and garden walls
    box("entrance", 0.8, -5.42, 1.55, 1.35, 0.1, 2.5, wood)
    box("entrance_glass", 0.8, -5.49, 1.9, 0.6, 0.04, 1.2, glass)
    box("garage_door", 8.38, -0.6, 1.45, 0.09, 4.3, 2.3, metal)
    for i in range(4):
        box("garage_seam", 8.44, -2.35 + i * 1.15, 1.45, 0.04, 0.06, 2.26, dark)
    for i in range(4):
        box(f"stair_{i}", -1.2, -6.15 - i * 0.34, 0.28 + i * 0.16, 2.4, 0.34, 0.14, accent)
    for x in (-5.6, -3.3):
        rbox("solar_panel", x, 1.3, 6.85, 2.0, 3.3, 0.08, glass,
             rotation=(0.23, 0, 0), bevel=0.01)
    box("roof_ac", 5.8, 2.4, 7.55, 1.5, 1.0, 0.7, metal, bevel=0.02)
    box("garden_wall", -5.4, 7.65, 0.65, 9.0, 0.25, 1.3, accent)
    box("garden_wall", 6.8, 6.5, 0.65, 0.25, 2.6, 1.3, accent)
    box("gate", 6.8, 4.55, 0.8, 0.08, 1.4, 1.25, wood)


# --------------------------------------------------------------------------- #
# glass podium tower: 30 x 30 m podium footprint, 67 m with crown
# --------------------------------------------------------------------------- #
def build_glass_tower():
    accent = MATS["FacadeAccent"]
    glass = MATS["FacadeGlass"]
    pane = MATS["PropsGlass"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]

    box("plinth", 0, 0, 0.4, 30.0, 30.0, 0.8, dark, bevel=0.03)
    box("podium", 0, 0, 3.2, 29.0, 29.0, 4.8, accent, bevel=0.05)
    for sy in (-14.56, 14.56):
        box("podium_glass", 0, sy, 2.4, 25.0, 0.08, 3.2, pane)
        for x in (-9, -3, 3, 9):
            box("podium_mullion", x, sy, 2.4, 0.12, 0.12, 3.2, metal)
    for sx in (-14.56, 14.56):
        box("podium_glass", sx, 0, 2.4, 0.08, 25.0, 3.2, pane)

    # two shaft tiers with curtain-wall floor bands and vertical fins
    box("shaft_low", 0, 0, 24.1, 25.0, 25.0, 37.0, glass, bevel=0.05)
    box("shaft_high", 0, 0, 52.6, 20.5, 20.5, 20.0, glass, bevel=0.05)
    for z in range(9, 43, 3):
        box("floor_band", 0, 0, z, 25.25, 25.25, 0.17, metal)
    for z in range(46, 62, 3):
        box("floor_band", 0, 0, z, 20.75, 20.75, 0.17, metal)
    for face in range(4):
        for t in (-8.5, -4.25, 0, 4.25, 8.5):
            if face == 0:
                box("fin_low", t, -12.72, 24.1, 0.2, 0.42, 36.2, metal)
                box("fin_high", t * 0.8, -10.47, 52.6, 0.18, 0.38, 19.2, metal)
            elif face == 1:
                box("fin_low", t, 12.72, 24.1, 0.2, 0.42, 36.2, metal)
                box("fin_high", t * 0.8, 10.47, 52.6, 0.18, 0.38, 19.2, metal)
            elif face == 2:
                box("fin_low", -12.72, t, 24.1, 0.42, 0.2, 36.2, metal)
                box("fin_high", -10.47, t * 0.8, 52.6, 0.38, 0.18, 19.2, metal)
            else:
                box("fin_low", 12.72, t, 24.1, 0.42, 0.2, 36.2, metal)
                box("fin_high", 10.47, t * 0.8, 52.6, 0.38, 0.18, 19.2, metal)

    # setback terrace, crown, roof plant and helipad
    box("setback_slab", 0, 0, 42.85, 26.2, 26.2, 0.45, accent)
    box("crown_slab", 0, 0, 65.7, 22.2, 22.2, 0.55, metal, bevel=0.04)
    for x in (-10.3, 10.3):
        for y in (-10.3, 10.3):
            box("crown_post", x, y, 64.2, 0.45, 0.45, 2.7, metal)
    box("roof_plant", -4.5, 3.0, 66.65, 5.5, 3.6, 1.35, accent, bevel=0.03)
    cyl("helipad", 4.6, -3.2, 66.05, 3.3, 0.16, dark, vertices=28)
    cyl("helipad_ring", 4.6, -3.2, 66.15, 2.45, 0.05, metal, vertices=28)
    cyl("mast", 0, 7.5, 68.2, 0.09, 4.5, metal, vertices=10)
    box("beacon", 0, 7.5, 70.55, 0.32, 0.32, 0.32, MATS["LampGlow"])

    # four entrance canopies and podium roof boxes
    for sy, sign in ((-14.5, -1), (14.5, 1)):
        box("canopy", 0, sy + sign * 1.15, 4.35, 8.0, 2.3, 0.2, metal, bevel=0.03)
        for cx in (-3.6, 3.6):
            cyl("canopy_col", cx, sy + sign * 2.05, 2.15, 0.08, 4.3, metal)
    for sx, sign in ((-14.5, -1), (14.5, 1)):
        box("canopy", sx + sign * 1.15, 0, 4.35, 2.3, 8.0, 0.2, metal, bevel=0.03)
    for x, y in ((-9, 9), (8, -8), (10, 7)):
        box("podium_ac", x, y, 6.05, 2.0, 1.3, 0.85, metal, bevel=0.02)


# --------------------------------------------------------------------------- #
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.path.join(os.getcwd(), "props_out")
    os.makedirs(out_dir, exist_ok=True)

    for build, filename in (
        (build_shelter, "bus_shelter.glb"),
        (build_lamp, "street_lamp.glb"),
        (build_hero, "hero_building.glb"),
        (build_townhouse, "townhouse.glb"),
        (build_villa, "villa.glb"),
        (build_glass_tower, "glass_tower.glb"),
    ):
        reset_scene()
        standard_mats()
        build()
        export(out_dir, filename)
    print("[props] done ->", out_dir)


main()
