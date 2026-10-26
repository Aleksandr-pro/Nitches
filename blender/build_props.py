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
  * traffic_signal_short.glb / traffic_signal_long.glb
                      detailed mast-arm signals, static red aspect only
  * hero_building.glb five-storey residential block with balconies
  * townhouse.glb     two-storey suburban house with garage and gable roof
  * villa.glb         Building Model No.1: detailed fixed-scale modern villa
  * glass_tower.glb   podium tower with finned glass curtain wall
"""
import math
import os
import sys

import bpy
from mathutils import Vector

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
    # Building Model No.1 (villa) uses a richer, physically separated
    # material set instead of painting every architectural surface with
    # the three generic facade colours.
    mat("FacadeStone", (0.62, 0.57, 0.48), roughness=0.92)
    mat("FacadeWoodSlat", (0.38, 0.22, 0.11), roughness=0.78)
    mat("WindowFrame", (0.08, 0.09, 0.10), roughness=0.48, metallic=0.55)
    mat("WindowGlassDark", (0.05, 0.13, 0.18), roughness=0.06, metallic=0.25)
    mat("ConcreteLight", (0.72, 0.71, 0.68), roughness=0.94)
    mat("RoofGravel", (0.28, 0.27, 0.25), roughness=1.0)
    mat("SolarCell", (0.02, 0.08, 0.18), roughness=0.18, metallic=0.35)
    # 0.2.8 second pass on Building Model No.1. These names are reserved
    # for the villa so its world-scale plaster/stone/glass treatment does
    # not accidentally restyle the older hero/townhouse/tower props.
    mat("VillaPlaster", (0.86, 0.81, 0.72), roughness=0.94)
    mat("VillaStone", (0.72, 0.64, 0.52), roughness=0.88)
    mat("VillaLimestone", (0.76, 0.67, 0.54), roughness=0.90)
    mat("VillaGranite", (0.05, 0.055, 0.06), roughness=0.50, metallic=0.08)
    mat("VillaWood", (0.30, 0.18, 0.09), roughness=0.76)
    mat("VillaGlass", (0.10, 0.24, 0.31), roughness=0.06, metallic=0.10)
    mat("VillaInterior", (0.035, 0.030, 0.028), roughness=0.96)
    mat("VillaCurtain", (0.72, 0.66, 0.56), roughness=1.0)
    mat("VillaPavement", (0.67, 0.61, 0.51), roughness=0.90)
    mat("VillaDeck", (0.45, 0.32, 0.19), roughness=0.84)
    mat("VillaMulch", (0.12, 0.075, 0.045), roughness=1.0)
    mat("VillaLawn", (0.18, 0.36, 0.12), roughness=1.0)
    mat("VillaHedge", (0.08, 0.25, 0.07), roughness=1.0)
    # The traffic signals are deliberately NOT an animated system yet.
    # Only the red lens material emits; amber and green remain dark.
    mat("SignalMetal", (0.36, 0.39, 0.42), roughness=0.34, metallic=0.9)
    mat("SignalHousing", (0.025, 0.028, 0.03), roughness=0.58, metallic=0.05)
    mat("SignalRedOn", (0.45, 0.015, 0.01), roughness=0.25, emission=(1.0, 0.02, 0.01))
    mat("SignalAmberOff", (0.22, 0.09, 0.005), roughness=0.2)
    mat("SignalGreenOff", (0.005, 0.13, 0.045), roughness=0.2)
    mat("SignalReflector", (0.85, 0.62, 0.05), roughness=0.42)
    mat("SignalCable", (0.01, 0.01, 0.012), roughness=0.72)


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


def sphere(name, x, y, z, dx, dy, dz, material):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.5, segments=24, ring_count=16, location=(x, y, z),
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (dx, dy, dz)
    return finish(obj, material, smooth=True)


def tube_between(name, start, end, radius_start, radius_end, material, vertices=16):
    """A tapered tube whose local +Z axis is aimed from start to end."""
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    length = direction.length
    if length <= 0.0001:
        return None
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cone_add(
        radius1=radius_start,
        radius2=radius_end,
        depth=length,
        vertices=vertices,
        location=midpoint,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(
        direction.normalized()
    )
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
# detailed mast-arm traffic signals. Blender local convention:
#   * origin at the pole base, Z up;
#   * mast arm reaches along +X;
#   * signal lenses face +Y in Blender, which becomes -Z after Y-up glTF
#     export. NativeWorldBuilder's yaw table is built around that axis.
# The model is intentionally static: red is lit, amber/green are dark.
# --------------------------------------------------------------------------- #
def _signal_head(cx, cz, prefix):
    housing = MATS["SignalHousing"]
    metal = MATS["SignalMetal"]
    reflector = MATS["SignalReflector"]

    # Backplate and its reflective perimeter sit behind the deeper main
    # housing; the border remains visible as a clean frame from the road.
    box(f"{prefix}_backplate", cx, -0.205, cz, 0.52, 0.055, 1.30, housing, bevel=0.025)
    box(f"{prefix}_reflector_top", cx, -0.166, cz + 0.625, 0.54, 0.028, 0.05, reflector)
    box(f"{prefix}_reflector_bottom", cx, -0.166, cz - 0.625, 0.54, 0.028, 0.05, reflector)
    box(f"{prefix}_reflector_left", cx - 0.257, -0.166, cz, 0.05, 0.028, 1.20, reflector)
    box(f"{prefix}_reflector_right", cx + 0.257, -0.166, cz, 0.05, 0.028, 1.20, reflector)

    box(f"{prefix}_housing", cx, 0.0, cz, 0.38, 0.34, 1.12, housing, bevel=0.035)
    box(f"{prefix}_housing_top", cx, -0.01, cz + 0.585, 0.42, 0.36, 0.07, housing, bevel=0.02)
    box(f"{prefix}_housing_bottom", cx, -0.01, cz - 0.585, 0.42, 0.36, 0.07, housing, bevel=0.02)

    lamp_materials = (
        MATS["SignalRedOn"],
        MATS["SignalAmberOff"],
        MATS["SignalGreenOff"],
    )
    for index, lamp_z in enumerate((cz + 0.37, cz, cz - 0.37)):
        # A full tunnel visor: the capped cylinder forms the side wall and
        # front bezel annulus, while the convex lens sits in its mouth.
        cyl(
            f"{prefix}_visor_{index}", cx, 0.185, lamp_z,
            0.168, 0.23, housing, vertices=28,
            rotation=(math.pi / 2.0, 0.0, 0.0),
        )
        cyl(
            f"{prefix}_bezel_{index}", cx, 0.285, lamp_z,
            0.149, 0.032, housing, vertices=28,
            rotation=(math.pi / 2.0, 0.0, 0.0),
        )
        sphere(
            f"{prefix}_lens_{index}", cx, 0.292, lamp_z,
            0.25, 0.075, 0.25, lamp_materials[index],
        )
        # Door hinge and latch blocks break up the otherwise plain side.
        box(f"{prefix}_hinge_{index}", cx + 0.205, 0.02, lamp_z + 0.10, 0.035, 0.20, 0.055, metal)
        box(f"{prefix}_latch_{index}", cx - 0.205, 0.02, lamp_z, 0.035, 0.16, 0.07, metal)

    # Twin hanger cheeks and a through-bolt connect the head to the drop
    # tube instead of leaving the housing floating below the mast arm.
    for sx in (-0.105, 0.105):
        box(f"{prefix}_hanger_cheek", cx + sx, -0.03, cz + 0.72, 0.045, 0.20, 0.34, metal)
    cyl(
        f"{prefix}_hanger_bolt", cx, -0.03, cz + 0.82,
        0.030, 0.30, metal, vertices=12,
        rotation=(0.0, math.pi / 2.0, 0.0),
    )


def _build_traffic_signal_variant(reach, head_positions):
    metal = MATS["SignalMetal"]
    housing = MATS["SignalHousing"]
    cable = MATS["SignalCable"]

    # Foundation plate, flange, four hex anchor bolts and a tapered
    # decorative base cover with an access door.
    box("signal_base_plate", 0.0, 0.0, 0.035, 0.62, 0.62, 0.07, metal, bevel=0.015)
    cyl("signal_base_flange", 0.0, 0.0, 0.115, 0.275, 0.10, metal, vertices=28)
    cone("signal_base_cover", 0.0, 0.0, 0.43, 0.235, 0.155, 0.58, metal, vertices=28)
    for sx in (-0.225, 0.225):
        for sy in (-0.225, 0.225):
            cyl("signal_anchor_bolt", sx, sy, 0.105, 0.035, 0.07, housing, vertices=6)
    box("signal_base_access_door", 0.0, -0.205, 0.43, 0.22, 0.025, 0.34, housing)
    sphere("signal_base_access_knob", 0.07, -0.225, 0.43, 0.045, 0.045, 0.045, metal)

    # Main tapered pole and cap.
    cone("signal_pole", 0.0, 0.0, 3.08, 0.145, 0.082, 5.95, metal, vertices=28)
    cyl("signal_pole_collar", 0.0, 0.0, 5.52, 0.105, 0.16, metal, vertices=24)
    sphere("signal_pole_cap", 0.0, 0.0, 6.08, 0.17, 0.17, 0.10, metal)

    # The arm is five tapered segments on a shallow rising curve, rather
    # than one perfectly horizontal cylinder intersecting the pole.
    arm_points = (
        (0.0, 0.0, 5.56),
        (reach * 0.20, 0.0, 5.79),
        (reach * 0.45, 0.0, 5.94),
        (reach * 0.72, 0.0, 6.015),
        (reach * 0.90, 0.0, 6.04),
        (reach, 0.0, 6.04),
    )
    arm_radii = (0.108, 0.096, 0.082, 0.068, 0.058, 0.050)
    box("signal_arm_mount", 0.02, 0.0, 5.56, 0.30, 0.24, 0.42, metal, bevel=0.025)
    rbox(
        "signal_arm_gusset", 0.34, 0.0, 5.32,
        0.72, 0.055, 0.16, metal,
        rotation=(0.0, -0.52, 0.0), bevel=0.01,
    )
    for index in range(len(arm_points) - 1):
        tube_between(
            f"signal_arm_{index}",
            arm_points[index],
            arm_points[index + 1],
            arm_radii[index],
            arm_radii[index + 1],
            metal,
            vertices=24,
        )
    sphere("signal_arm_end_cap", reach, 0.0, 6.04, 0.11, 0.11, 0.11, metal)

    # Signal heads hang from short drop tubes. A gently sagging cable is
    # routed under the arm to every head.
    for head_index, head_x in enumerate(head_positions):
        head_z = 4.78
        tube_between(
            f"signal_drop_tube_{head_index}",
            (head_x, -0.03, 6.00),
            (head_x, -0.03, 5.58),
            0.036,
            0.036,
            metal,
            vertices=14,
        )
        _signal_head(head_x, head_z, f"signal_head_{head_index}")
        cable_points = (
            (0.07, -0.055, 5.43),
            (head_x * 0.34, -0.070, 5.67),
            (head_x * 0.68, -0.070, 5.83),
            (head_x, -0.060, 5.70),
        )
        for cable_index in range(len(cable_points) - 1):
            tube_between(
                f"signal_cable_{head_index}_{cable_index}",
                cable_points[cable_index],
                cable_points[cable_index + 1],
                0.016,
                0.016,
                cable,
                vertices=8,
            )

    # Static pedestrian aspect on the pole: upper red symbol lit, lower
    # indication dark. It is geometry only, with no switching logic.
    box("ped_signal_bracket", 0.0, 0.17, 2.68, 0.10, 0.16, 0.12, metal)
    box("ped_signal_housing", 0.0, 0.29, 2.68, 0.34, 0.20, 0.58, housing, bevel=0.025)
    box("ped_signal_red", 0.0, 0.405, 2.83, 0.19, 0.025, 0.19, MATS["SignalRedOn"])
    box("ped_signal_off", 0.0, 0.405, 2.53, 0.19, 0.025, 0.19, MATS["SignalGreenOff"])

    # Ground controller cabinet behind the pole (local -X is away from
    # the travelled lanes in every runtime approach orientation).
    cabinet_x = -0.68
    box("signal_cabinet_plinth", cabinet_x, -0.16, 0.07, 0.82, 0.52, 0.14, MATS["ConcreteLight"])
    box("signal_cabinet", cabinet_x, -0.16, 0.67, 0.72, 0.40, 1.06, metal, bevel=0.025)
    box("signal_cabinet_door", cabinet_x, -0.375, 0.67, 0.62, 0.025, 0.94, housing)
    box("signal_cabinet_handle", cabinet_x + 0.22, -0.405, 0.67, 0.045, 0.035, 0.20, metal)
    for vent_index in range(4):
        box(
            f"signal_cabinet_vent_{vent_index}",
            cabinet_x - 0.15,
            -0.392,
            0.34 + vent_index * 0.075,
            0.28,
            0.018,
            0.028,
            housing,
        )


def build_traffic_signal_short():
    _build_traffic_signal_variant(4.35, (4.18,))


def build_traffic_signal_long():
    _build_traffic_signal_variant(6.85, (4.00, 6.68))


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
# Building Model No.1 — detailed modern villa.
# Fixed real-metre envelope: 19.15 x 15.14 m, 8.84 m high. The runtime no
# longer stretches this asset to unrelated JSON footprints: window, door
# and floor dimensions remain architectural at every placement.
# --------------------------------------------------------------------------- #
def build_villa():
    main = MATS["VillaPlaster"]
    accent = MATS["VillaStone"]
    stone = MATS["VillaLimestone"]
    granite = MATS["VillaGranite"]
    wood = MATS["VillaWood"]
    frame = MATS["WindowFrame"]
    glass = MATS["VillaGlass"]
    interior = MATS["VillaInterior"]
    curtain = MATS["VillaCurtain"]
    pavement = MATS["VillaPavement"]
    deck = MATS["VillaDeck"]
    mulch = MATS["VillaMulch"]
    lawn = MATS["VillaLawn"]
    hedge = MATS["VillaHedge"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    gravel = MATS["RoofGravel"]
    solar = MATS["SolarCell"]
    glow = MATS["LampGlow"]

    # Site slab and the three interlocking house volumes. A polished dark
    # granite plinth now separates the warm plaster/stone walls from the
    # ground instead of leaving the whole parcel as one pale slab.
    box("villa_plinth", 0.0, 0.0, 0.14, 19.15, 15.14, 0.28, granite, bevel=0.02)
    box("villa_west_volume", -3.6, -0.7, 3.315, 10.8, 11.6, 6.07, main, bevel=0.045)
    box("villa_east_volume", 4.7, -0.4, 3.64, 7.4, 10.8, 6.72, accent, bevel=0.045)
    box("villa_link_volume", 0.3, 0.6, 1.81, 2.8, 8.6, 3.06, main, bevel=0.03)

    # Expressed floor slabs and a continuous granite base course stop the
    # large walls reading as unbroken coloured boxes. The base wraps all
    # four elevations; it is no longer a single dressed strip at the front.
    box("villa_west_floor_band", -3.6, -0.7, 3.42, 10.96, 11.76, 0.18, granite)
    box("villa_east_floor_band", 4.7, -0.4, 3.48, 7.56, 10.96, 0.18, granite)
    box("villa_west_base_front", -3.6, -6.55, 0.72, 10.88, 0.16, 0.88, granite)
    box("villa_west_base_rear", -3.6, 5.15, 0.72, 10.88, 0.16, 0.88, granite)
    box("villa_east_base_front", 4.7, -5.85, 0.72, 7.48, 0.16, 0.88, granite)
    box("villa_east_base_rear", 4.7, 5.05, 0.72, 7.48, 0.16, 0.88, granite)
    box("villa_west_base_side", -9.05, -0.7, 0.72, 0.16, 11.68, 0.88, granite)
    box("villa_east_base_side", 8.45, -0.4, 0.72, 0.16, 10.88, 0.88, granite)

    def reveal_v(cx, cy, cz, height, face):
        if face in ("front", "back"):
            box("villa_facade_reveal_v", cx, cy, cz, 0.055, 0.045, height, frame)
        else:
            box("villa_facade_reveal_v", cx, cy, cz, 0.045, 0.055, height, frame)

    def reveal_h(cx, cy, cz, length, face):
        if face in ("front", "back"):
            box("villa_facade_reveal_h", cx, cy, cz, length, 0.045, 0.055, frame)
        else:
            box("villa_facade_reveal_h", cx, cy, cz, 0.045, length, 0.055, frame)

    def facade_pier(cx, cy, cz, width, height, face, material=None):
        pier_material = stone if material is None else material
        if face in ("front", "back"):
            box("villa_facade_pier", cx, cy, cz, width, 0.15, height, pier_material, bevel=0.012)
        else:
            box("villa_facade_pier", cx, cy, cz, 0.15, width, height, pier_material, bevel=0.012)

    # Panel joints on every elevation. Window frames are deeper than
    # these 45 mm shadow gaps, so aligned joints pass behind the glazing
    # and reappear in the solid wall exactly as a panelised facade would.
    for seam_x in (-8.35, -4.70, -1.05, 1.45):
        reveal_v(seam_x, -6.515, 3.35, 5.75, "front")
        reveal_v(seam_x, 5.115, 3.35, 5.75, "back")
    for seam_z in (1.12, 5.92):
        reveal_h(-3.6, -6.515, seam_z, 10.55, "front")
        reveal_h(-3.6, 5.115, seam_z, 10.55, "back")
    for seam_y in (-5.85, -0.80, 4.45):
        reveal_v(-9.015, seam_y, 3.35, 5.75, "left")
    for seam_z in (1.12, 5.92):
        reveal_h(-9.015, -0.7, seam_z, 11.35, "left")
    for seam_y in (-5.15, -0.45, 4.35):
        reveal_v(8.415, seam_y, 3.65, 6.35, "right")
    for seam_z in (1.12, 6.55):
        reveal_h(8.415, -0.4, seam_z, 10.55, "right")
    for seam_x in (1.25, 4.70, 8.15):
        reveal_v(seam_x, 5.015, 3.65, 6.35, "back")
    for seam_z in (1.12, 6.55):
        reveal_h(4.7, 5.015, seam_z, 7.15, "back")

    # Projecting limestone piers give the two-storey walls a real bay
    # rhythm and cast narrow shadows at phone distance.
    for pier_x in (-8.78, -4.70, 1.58):
        facade_pier(pier_x, -6.545, 3.35, 0.34, 5.85, "front")
        facade_pier(pier_x, 5.145, 3.35, 0.34, 5.85, "back")
    for pier_y in (-5.90, -0.80, 4.55):
        facade_pier(-9.045, pier_y, 3.35, 0.34, 5.85, "left")
    for pier_y in (-5.20, -0.45, 4.45):
        facade_pier(8.445, pier_y, 3.65, 0.34, 6.35, "right")
    for pier_x in (1.22, 8.18):
        facade_pier(pier_x, 5.045, 3.65, 0.34, 6.35, "back")
    facade_pier(1.02, -5.875, 3.65, 0.30, 6.35, "front", granite)
    facade_pier(4.98, -5.875, 3.65, 0.30, 6.35, "front", granite)

    def roof(cx, cy, wall_top, width, depth, name, parapet_material):
        box(f"{name}_slab", cx, cy, wall_top + 0.15, width + 0.55, depth + 0.55, 0.30, dark, bevel=0.025)
        box(f"{name}_gravel", cx, cy, wall_top + 0.335, width - 0.35, depth - 0.35, 0.07, gravel)
        # Parapet ring in the same finish as its own volume, finished by
        # segmented black-granite coping rather than a bright metal strip.
        for sy, sign in ((cy - depth / 2 + 0.12, -1), (cy + depth / 2 - 0.12, 1)):
            box(f"{name}_parapet", cx, sy, wall_top + 0.56, width - 0.20, 0.24, 0.48, parapet_material)
            box(f"{name}_coping", cx, sy, wall_top + 0.84, width - 0.08, 0.34, 0.08, granite)
            segment_count = max(2, int(width // 2.7))
            for segment in range(1, segment_count):
                joint_x = cx - width / 2.0 + width * segment / segment_count
                box(f"{name}_coping_joint", joint_x, sy + sign * 0.185, wall_top + 0.84, 0.035, 0.025, 0.085, frame)
        for sx in (cx - width / 2 + 0.12, cx + width / 2 - 0.12):
            box(f"{name}_parapet", sx, cy, wall_top + 0.56, 0.24, depth - 0.20, 0.48, parapet_material)
            box(f"{name}_coping", sx, cy, wall_top + 0.84, 0.34, depth - 0.08, 0.08, granite)

    roof(-3.6, -0.7, 6.35, 10.8, 11.6, "villa_west_roof", main)
    roof(4.7, -0.4, 7.00, 7.4, 10.8, "villa_east_roof", accent)
    box("villa_link_roof", 0.3, 0.6, 3.46, 3.25, 9.05, 0.24, dark, bevel=0.02)

    def face_window(cx, cy, cz, width, height, face):
        sign = -1.0 if face in ("front", "left") else 1.0
        divisions = max(1, int(width // 1.05))
        variant = int(abs(cx * 3.7 + cy * 5.3 + cz * 7.1)) % 4
        blind_fraction = (0.24, 0.38, 0.0, 0.52)[variant]
        blind_drop = height * blind_fraction
        if face in ("front", "back"):
            # A dark granite reveal, a separate interior backing and then
            # the reflective pane give each opening physical depth. In
            # 0.2.7 the transparent pane sat almost directly on the solid
            # wall box, which is why it read as flat black paint.
            box("villa_window_reveal", cx, cy + sign * 0.018, cz, width + 0.38, 0.085, height + 0.38, granite)
            box("villa_window_interior", cx, cy + sign * 0.038, cz, width - 0.03, 0.040, height - 0.03, interior)
            if variant != 1:
                for curtain_side in (-1.0, 1.0):
                    curtain_x = cx + curtain_side * (width / 2.0 - 0.17)
                    box("villa_window_curtain", curtain_x, cy + sign * 0.064, cz, 0.24, 0.034, height - 0.14, curtain)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.035
                box("villa_window_blind", cx, cy + sign * 0.066, blind_z, width - 0.12, 0.032, blind_drop, curtain)
                box("villa_window_blind_rail", cx, cy + sign * 0.070, blind_z - blind_drop / 2.0, width - 0.10, 0.038, 0.045, frame)
            box("villa_window_interior_light", cx - width * 0.18, cy + sign * 0.068, cz + height * 0.34, width * 0.38, 0.026, 0.040, glow)
            box("villa_window_frame", cx, cy + sign * 0.028, cz, width + 0.19, 0.17, height + 0.19, frame)
            box("villa_window_glass", cx, cy + sign * 0.098, cz, width, 0.045, height, glass)
            for division in range(1, divisions):
                mx = cx - width / 2.0 + width * division / divisions
                box("villa_window_mullion", mx, cy + sign * 0.112, cz, 0.055, 0.055, height, frame)
            box("villa_window_transom", cx, cy + sign * 0.112, cz + height * 0.24, width, 0.055, 0.055, frame)
            box("villa_window_handle", cx + width * 0.22, cy + sign * 0.128, cz - 0.05, 0.045, 0.035, 0.34, metal)
            box("villa_window_sill", cx, cy + sign * 0.110, cz - height / 2.0 - 0.085, width + 0.42, 0.30, 0.10, granite)
            box("villa_window_drip_groove", cx, cy + sign * 0.205, cz - height / 2.0 - 0.155, width + 0.30, 0.045, 0.028, frame)
            box("villa_window_header", cx, cy + sign * 0.065, cz + height / 2.0 + 0.095, width + 0.28, 0.16, 0.11, frame)
            if cz > 3.8:
                for shade_index in range(3):
                    shade_z = cz + height / 2.0 + 0.28 + shade_index * 0.11
                    box("villa_window_shade_louvre", cx, cy + sign * 0.30, shade_z, width + 0.24, 0.50, 0.035, frame)
                for bracket_side in (-1.0, 1.0):
                    bracket_x = cx + bracket_side * (width / 2.0 - 0.08)
                    box("villa_window_shade_bracket", bracket_x, cy + sign * 0.24, cz + height / 2.0 + 0.30, 0.055, 0.42, 0.28, metal)
        else:
            box("villa_window_reveal", cx + sign * 0.018, cy, cz, 0.085, width + 0.38, height + 0.38, granite)
            box("villa_window_interior", cx + sign * 0.038, cy, cz, 0.040, width - 0.03, height - 0.03, interior)
            if variant != 1:
                for curtain_side in (-1.0, 1.0):
                    curtain_y = cy + curtain_side * (width / 2.0 - 0.17)
                    box("villa_window_curtain", cx + sign * 0.064, curtain_y, cz, 0.034, 0.24, height - 0.14, curtain)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.035
                box("villa_window_blind", cx + sign * 0.066, cy, blind_z, 0.032, width - 0.12, blind_drop, curtain)
                box("villa_window_blind_rail", cx + sign * 0.070, cy, blind_z - blind_drop / 2.0, 0.038, width - 0.10, 0.045, frame)
            box("villa_window_interior_light", cx + sign * 0.068, cy - width * 0.18, cz + height * 0.34, 0.026, width * 0.38, 0.040, glow)
            box("villa_window_frame", cx + sign * 0.028, cy, cz, 0.17, width + 0.19, height + 0.19, frame)
            box("villa_window_glass", cx + sign * 0.098, cy, cz, 0.045, width, height, glass)
            for division in range(1, divisions):
                my = cy - width / 2.0 + width * division / divisions
                box("villa_window_mullion", cx + sign * 0.112, my, cz, 0.055, 0.055, height, frame)
            box("villa_window_transom", cx + sign * 0.112, cy, cz + height * 0.24, 0.055, width, 0.055, frame)
            box("villa_window_handle", cx + sign * 0.128, cy + width * 0.22, cz - 0.05, 0.035, 0.045, 0.34, metal)
            box("villa_window_sill", cx + sign * 0.110, cy, cz - height / 2.0 - 0.085, 0.30, width + 0.42, 0.10, granite)
            box("villa_window_drip_groove", cx + sign * 0.205, cy, cz - height / 2.0 - 0.155, 0.045, width + 0.30, 0.028, frame)
            box("villa_window_header", cx + sign * 0.065, cy, cz + height / 2.0 + 0.095, 0.16, width + 0.28, 0.11, frame)
            if cz > 3.8:
                for shade_index in range(3):
                    shade_z = cz + height / 2.0 + 0.28 + shade_index * 0.11
                    box("villa_window_shade_louvre", cx + sign * 0.30, cy, shade_z, 0.50, width + 0.24, 0.035, frame)
                for bracket_side in (-1.0, 1.0):
                    bracket_y = cy + bracket_side * (width / 2.0 - 0.08)
                    box("villa_window_shade_bracket", cx + sign * 0.24, bracket_y, cz + height / 2.0 + 0.30, 0.42, 0.055, 0.28, metal)

    # Front (Blender -Y) glazing. Upper west/east openings are full-height
    # balcony doors, not floating picture windows.
    face_window(-6.6, -6.50, 1.62, 3.5, 2.50, "front")
    face_window(-2.8, -6.50, 1.62, 3.5, 2.50, "front")
    face_window(-6.6, -6.50, 4.80, 3.2, 2.45, "front")
    face_window(-2.8, -6.50, 4.80, 3.2, 2.45, "front")
    face_window(3.0, -5.80, 1.72, 2.8, 2.30, "front")
    face_window(3.0, -5.80, 5.18, 3.0, 1.90, "front")
    face_window(5.9, -5.80, 4.87, 2.6, 2.50, "front")

    # Rear and side elevations receive the same construction; the model
    # is not a single dressed facade with blank backs.
    face_window(-6.4, 5.10, 1.62, 3.4, 2.50, "back")
    face_window(-2.6, 5.10, 1.62, 3.4, 2.50, "back")
    face_window(-6.4, 5.10, 4.90, 3.0, 1.90, "back")
    face_window(-2.6, 5.10, 4.90, 3.0, 1.90, "back")
    face_window(4.6, 5.00, 1.72, 3.2, 2.35, "back")
    face_window(4.6, 5.00, 5.05, 3.2, 1.95, "back")
    face_window(-9.00, -3.0, 1.75, 2.4, 1.75, "left")
    face_window(-9.00, 1.4, 1.75, 2.4, 1.75, "left")
    face_window(-9.00, -3.0, 4.95, 2.4, 1.75, "left")
    face_window(-9.00, 1.4, 4.95, 2.4, 1.75, "left")
    face_window(8.40, -2.7, 1.85, 2.3, 1.80, "right")
    face_window(8.40, 1.8, 1.85, 2.3, 1.80, "right")
    face_window(8.40, -2.7, 5.10, 2.3, 1.80, "right")
    face_window(8.40, 1.8, 5.10, 2.3, 1.80, "right")

    # Stone feature wall with a separated timber privacy screen. The
    # 0.2.7 panel joints were accidentally buried inside this overlay;
    # they now sit on its face and remain visible between the fins, and
    # the screen itself stands a real 105 mm clear of the stone.
    box("villa_feature_stone", 3.0, -5.88, 3.58, 3.6, 0.17, 6.55, stone, bevel=0.02)
    for seam_z in (1.55, 3.15, 4.75, 6.35):
        box("villa_stone_joint", 3.0, -5.985, seam_z, 3.58, 0.035, 0.045, frame)
    for seam_x in (2.10, 3.00, 3.90):
        box("villa_stone_joint_v", seam_x, -5.985, 3.58, 0.040, 0.035, 6.45, frame)
    for fin_index in range(9):
        fin_x = 1.62 + fin_index * 0.345
        box("villa_timber_fin", fin_x, -6.16, 3.52, 0.15, 0.18, 5.85, wood)
        for spacer_z in (1.05, 3.52, 5.95):
            box("villa_timber_fin_spacer", fin_x, -6.035, spacer_z, 0.055, 0.09, 0.055, frame)
    box("villa_fin_rail_top", 3.0, -6.16, 6.50, 3.55, 0.14, 0.10, frame)
    box("villa_fin_rail_bottom", 3.0, -6.16, 0.57, 3.55, 0.14, 0.10, frame)

    def balcony(cx, face_y, sign, floor_z, width):
        slab_y = face_y + sign * 0.58
        box("villa_balcony_slab", cx, slab_y, floor_z + 0.09, width, 1.18, 0.18, granite)
        box("villa_balcony_beam", cx, slab_y, floor_z - 0.05, width - 0.25, 0.22, 0.12, frame)
        # Warm timber soffit boards are visible from the street below and
        # keep the balcony edge from reading as a plain concrete tray.
        soffit_count = max(4, int(width // 0.82))
        for soffit_index in range(soffit_count):
            soffit_x = cx - width / 2.0 + width * (soffit_index + 0.5) / soffit_count
            box("villa_balcony_soffit", soffit_x, slab_y, floor_z - 0.018, width / soffit_count - 0.055, 1.04, 0.035, deck)
        rail_y = face_y + sign * 1.12
        planter_y = rail_y - sign * 0.17
        box("villa_balcony_planter", cx, planter_y, floor_z + 0.30, width - 0.55, 0.20, 0.24, granite)
        box("villa_balcony_hedge", cx, planter_y, floor_z + 0.50, width - 0.70, 0.15, 0.22, hedge, bevel=0.045)
        panel_count = 3
        panel_width = width / panel_count
        for panel in range(panel_count):
            px = cx - width / 2.0 + panel_width * (panel + 0.5)
            box("villa_balcony_glass", px, rail_y, floor_z + 0.55, panel_width - 0.09, 0.045, 0.74, glass)
        for px in (cx - width / 2.0, cx - width / 6.0, cx + width / 6.0, cx + width / 2.0):
            box("villa_balcony_post", px, rail_y, floor_z + 0.55, 0.055, 0.07, 0.82, metal)
        box("villa_balcony_top_rail", cx, rail_y, floor_z + 0.99, width, 0.09, 0.07, metal)
        for px in (cx - width / 2.0, cx + width / 2.0):
            side_y = face_y + sign * 0.58
            box("villa_balcony_side_glass", px, side_y, floor_z + 0.55, 0.045, 1.08, 0.74, glass)
            box("villa_balcony_side_rail", px, side_y, floor_z + 0.99, 0.08, 1.12, 0.07, metal)
            bracket_y = face_y + sign * 0.52
            rbox(
                "villa_balcony_bracket", px * 0.96, bracket_y, floor_z - 0.38,
                0.09, 1.05, 0.09, metal,
                rotation=(sign * 0.62, 0.0, 0.0),
            )

    balcony(-4.7, -6.50, -1.0, 3.49, 6.4)
    balcony(5.9, -5.80, -1.0, 3.55, 4.2)
    balcony(-4.5, 5.10, 1.0, 3.49, 6.0)

    # Recessed entrance in the link volume, with canopy, tie rods, pivot
    # door, sidelight, steps and wall lights.
    box("villa_entry_canopy", 0.3, -5.25, 3.16, 4.6, 3.30, 0.18, frame, bevel=0.02)
    box("villa_entry_canopy_fascia", 0.3, -6.88, 3.08, 4.65, 0.10, 0.30, metal)
    for column_x in (-1.7, 2.3):
        cyl("villa_entry_column", column_x, -6.62, 1.72, 0.075, 2.95, metal, vertices=16)
        tube_between(
            "villa_entry_tie_rod",
            (column_x, -6.62, 3.05),
            (column_x, -3.78, 3.28),
            0.018,
            0.018,
            metal,
            vertices=8,
        )
    box("villa_entry_door", 0.25, -3.78, 1.62, 1.32, 0.10, 2.52, wood, bevel=0.015)
    box("villa_entry_door_glass", 0.03, -3.845, 1.78, 0.42, 0.035, 1.55, glass)
    cyl("villa_entry_handle", 0.78, -3.88, 1.62, 0.025, 1.08, metal, vertices=10)
    face_window(1.45, -3.70, 1.66, 0.75, 2.20, "front")
    # Granite portal, grooved pivot door, canopy soffit and house
    # furniture turn the recess into an unmistakable residential entry.
    box("villa_entry_portal_left", -0.78, -3.82, 1.62, 0.28, 0.18, 2.75, granite)
    box("villa_entry_portal_right", 2.10, -3.82, 1.62, 0.28, 0.18, 2.75, granite)
    box("villa_entry_portal_header", 0.66, -3.82, 3.00, 3.05, 0.18, 0.28, granite)
    for groove_x in (-0.18, 0.18, 0.54):
        box("villa_entry_door_groove", groove_x, -3.842, 1.62, 0.025, 0.025, 2.35, frame)
    for soffit_x in (-1.65, -1.26, -0.87, -0.48, -0.09, 0.30, 0.69, 1.08, 1.47, 1.86, 2.25):
        box("villa_entry_canopy_soffit", soffit_x, -5.25, 3.045, 0.22, 3.00, 0.045, deck)
    for downlight_x in (-1.05, 0.30, 1.65):
        cyl("villa_entry_downlight", downlight_x, -5.25, 3.008, 0.055, 0.025, glow, vertices=14)
    box("villa_entry_threshold", 0.3, -4.02, 0.34, 2.80, 0.55, 0.12, granite)
    box("villa_house_number_plaque", -1.28, -3.84, 1.78, 0.42, 0.06, 0.55, granite)
    box("villa_house_number_inset", -1.28, -3.88, 1.78, 0.28, 0.025, 0.36, metal)
    box("villa_intercom", 2.02, -3.88, 1.34, 0.15, 0.055, 0.24, frame)
    box("villa_intercom_lens", 2.02, -3.915, 1.42, 0.07, 0.025, 0.07, glass)
    box("villa_intercom_call_light", 2.02, -3.915, 1.27, 0.07, 0.025, 0.045, glow)
    for step_index, (step_y, step_top) in enumerate(((-4.25, 0.42), (-4.72, 0.32), (-5.19, 0.22))):
        box(f"villa_entry_step_{step_index}", 0.3, step_y, step_top / 2.0 + 0.14, 2.60, 0.47, step_top, pavement)
    for path_y in (-5.72, -6.32, -6.92):
        box("villa_entry_path_paver", 0.3, path_y, 0.315, 2.30, 0.48, 0.05, pavement)
    for planter_x in (-1.55, 2.15):
        box("villa_entry_planter", planter_x, -5.35, 0.50, 0.72, 0.56, 0.42, granite)
        box("villa_entry_planter_hedge", planter_x, -5.35, 0.79, 0.62, 0.46, 0.28, hedge, bevel=0.055)
    for light_x in (-0.95, 1.95):
        box("villa_entry_light_body", light_x, -3.80, 2.45, 0.16, 0.10, 0.28, frame)
        box("villa_entry_light", light_x, -3.86, 2.45, 0.10, 0.035, 0.18, glow)

    # Flush timber sectional garage door in a granite portal: panel
    # seams, top lights, hardware, threshold drainage and a keypad post.
    box("villa_garage_frame", 6.15, -5.84, 1.58, 4.72, 0.14, 2.58, frame)
    box("villa_garage_door", 6.15, -5.92, 1.58, 4.45, 0.08, 2.32, wood, bevel=0.012)
    box("villa_garage_portal_left", 3.66, -5.90, 1.58, 0.30, 0.24, 2.86, granite)
    box("villa_garage_portal_right", 8.64, -5.90, 1.58, 0.30, 0.24, 2.86, granite)
    box("villa_garage_portal_header", 6.15, -5.90, 3.02, 5.28, 0.24, 0.28, granite)
    box("villa_garage_light_bar", 6.15, -6.035, 2.82, 1.35, 0.035, 0.07, glow)
    for seam_z in (0.95, 1.48, 2.01):
        box("villa_garage_seam_h", 6.15, -5.97, seam_z, 4.40, 0.025, 0.045, frame)
    for seam_x in (5.05, 6.15, 7.25):
        box("villa_garage_seam_v", seam_x, -5.97, 1.58, 0.035, 0.025, 2.26, frame)
    for window_x in (4.95, 5.75, 6.55, 7.35):
        box("villa_garage_window", window_x, -5.975, 2.38, 0.58, 0.03, 0.34, glass)
    box("villa_garage_handle", 6.15, -5.99, 1.18, 0.42, 0.035, 0.07, frame)
    box("villa_garage_bottom_seal", 6.15, -5.975, 0.46, 4.42, 0.035, 0.09, frame)
    box("villa_driveway_apron", 6.15, -6.70, 0.295, 4.85, 1.65, 0.035, granite)
    for paver_x in (4.15, 5.35, 6.55, 7.75):
        for paver_y in (-6.35, -7.08):
            box("villa_driveway_paver", paver_x, paver_y, 0.325, 1.08, 0.62, 0.045, pavement)
    box("villa_garage_drainage_channel", 6.15, -6.03, 0.335, 4.60, 0.16, 0.035, frame)
    for drain_x in (4.25, 4.85, 5.45, 6.05, 6.65, 7.25, 7.85):
        box("villa_garage_drainage_slot", drain_x, -6.03, 0.356, 0.28, 0.055, 0.012, metal)
    cyl("villa_garage_keypad_post", 3.55, -6.72, 0.62, 0.045, 0.68, frame, vertices=10)
    box("villa_garage_keypad", 3.55, -6.74, 1.03, 0.16, 0.07, 0.24, granite)
    box("villa_garage_keypad_light", 3.55, -6.785, 1.08, 0.08, 0.025, 0.08, glow)
    # The sliding vehicle gate is parked fully open inside the east
    # boundary so the house reads as a secured villa without blocking
    # the player's driveway sightline.
    box("villa_vehicle_gate_panel", 9.08, -5.35, 0.98, 0.07, 3.15, 1.28, wood)
    box("villa_vehicle_gate_rail_top", 9.08, -5.35, 1.66, 0.10, 3.25, 0.08, frame)
    box("villa_vehicle_gate_rail_bottom", 9.08, -5.35, 0.36, 0.10, 3.25, 0.08, frame)
    box("villa_vehicle_gate_track", 9.08, -5.35, 0.315, 0.16, 3.45, 0.035, metal)

    # Roof terrace over the ground-floor link and a rear garden pergola.
    for px in (-0.95, 1.55):
        for py in (-3.2, 4.2):
            box("villa_link_pergola_post", px, py, 4.65, 0.16, 0.16, 2.15, wood)
    for slat_index in range(13):
        slat_y = -3.2 + slat_index * 0.62
        box("villa_link_pergola_slat", 0.3, slat_y, 5.78, 2.95, 0.14, 0.13, wood)
    box("villa_link_pergola_beam", -0.95, 0.5, 5.68, 0.16, 7.70, 0.18, wood)
    box("villa_link_pergola_beam", 1.55, 0.5, 5.68, 0.16, 7.70, 0.18, wood)
    for px in (-7.4, -2.2):
        for py in (5.35, 7.05):
            box("villa_garden_pergola_post", px, py, 1.68, 0.17, 0.17, 2.80, wood)
    for slat_index in range(9):
        slat_x = -7.4 + slat_index * 0.65
        box("villa_garden_pergola_slat", slat_x, 6.20, 3.16, 0.14, 2.15, 0.14, wood)
    box("villa_garden_pergola_beam", -4.8, 5.32, 3.05, 5.55, 0.16, 0.18, wood)
    box("villa_garden_pergola_beam", -4.8, 7.08, 3.05, 5.55, 0.16, 0.18, wood)

    # Solar array with individual framed modules, cell busbars, support
    # rails and a cable tray; the modules are not eight blank blue slabs.
    for panel_x in (-7.3, -5.9, -4.5, -3.1):
        for panel_y in (-2.4, -0.2):
            rbox("villa_solar_frame", panel_x, panel_y, 7.02, 1.18, 1.85, 0.065, metal, rotation=(0.22, 0.0, 0.0), bevel=0.008)
            rbox("villa_solar_cell", panel_x, panel_y - 0.012, 7.065, 1.05, 1.68, 0.028, solar, rotation=(0.22, 0.0, 0.0))
            for busbar_offset in (-0.26, 0.0, 0.26):
                rbox("villa_solar_busbar", panel_x + busbar_offset, panel_y - 0.018, 7.084, 0.018, 1.62, 0.007, metal, rotation=(0.22, 0.0, 0.0))
            box("villa_solar_leg", panel_x - 0.42, panel_y + 0.68, 6.76, 0.07, 0.07, 0.22, metal)
            box("villa_solar_leg", panel_x + 0.42, panel_y + 0.68, 6.76, 0.07, 0.07, 0.22, metal)
    box("villa_solar_cable_tray", -5.2, 0.78, 6.78, 5.55, 0.18, 0.08, frame)
    box("villa_solar_inverter", -2.05, 0.78, 6.98, 0.58, 0.28, 0.42, metal, bevel=0.015)

    def roof_hvac(cx, cy, base_z):
        box("villa_roof_hvac", cx, cy, base_z + 0.42, 1.65, 1.05, 0.84, metal, bevel=0.025)
        cyl("villa_roof_hvac_fan", cx, cy, base_z + 0.87, 0.34, 0.05, frame, vertices=24)
        cyl("villa_roof_hvac_ring", cx, cy, base_z + 0.90, 0.22, 0.055, metal, vertices=24)
        for grille_offset in (-0.22, 0.0, 0.22):
            box("villa_roof_hvac_grille", cx + grille_offset, cy - 0.545, base_z + 0.42, 0.055, 0.025, 0.55, frame)

    roof_hvac(-6.4, 3.2, 6.69)
    roof_hvac(5.8, 2.7, 7.34)
    box("villa_skylight_frame", -1.6, 2.8, 6.80, 1.55, 1.05, 0.20, frame)
    box("villa_skylight_glass", -1.6, 2.8, 6.92, 1.38, 0.88, 0.06, glass)
    box("villa_lift_overrun", 6.7, -3.2, 8.05, 2.2, 1.8, 1.35, accent, bevel=0.025)
    box("villa_lift_overrun_cap", 6.7, -3.2, 8.78, 2.4, 2.0, 0.12, dark)
    cyl("villa_roof_vent", 2.8, -3.5, 7.85, 0.13, 1.05, metal, vertices=16)
    cone("villa_roof_vent_cap", 2.8, -3.5, 8.48, 0.24, 0.05, 0.28, metal, vertices=16)
    cyl("villa_chimney", -8.1, 3.9, 7.55, 0.20, 1.55, stone, vertices=16)
    cyl("villa_chimney_cap", -8.1, 3.9, 8.38, 0.28, 0.12, frame, vertices=16)

    # Corner downspouts with lower shoes, plus side service hardware.
    for dx, dy, top_z in ((-8.88, -6.34, 6.35), (8.28, -5.64, 7.0), (-8.88, 4.94, 6.35), (8.28, 4.84, 7.0)):
        pipe_height = top_z - 0.35
        cyl("villa_downspout", dx, dy, 0.35 + pipe_height / 2.0, 0.055, pipe_height, metal, vertices=10)
        tube_between("villa_downspout_shoe", (dx, dy, 0.42), (dx, dy - 0.28 if dy < 0 else dy + 0.28, 0.18), 0.055, 0.055, metal, vertices=10)
        for bracket_z in (1.15, 3.35, 5.45):
            if bracket_z < top_z:
                box("villa_downspout_bracket", dx, dy, bracket_z, 0.15, 0.15, 0.055, frame)

    box("villa_side_ac", 8.62, 2.85, 0.72, 0.38, 1.02, 0.82, metal, bevel=0.02)
    cyl("villa_side_ac_fan", 8.83, 2.85, 0.72, 0.29, 0.045, frame, vertices=24, rotation=(0.0, math.pi / 2.0, 0.0))
    for grille_y in (2.60, 2.85, 3.10):
        box("villa_side_ac_grille", 8.855, grille_y, 0.72, 0.025, 0.045, 0.56, metal)
    box("villa_meter_cabinet", -9.18, -0.7, 1.05, 0.16, 0.72, 1.05, metal, bevel=0.015)
    box("villa_meter_window", -9.28, -0.7, 1.22, 0.025, 0.34, 0.34, glass)

    # Finished grounds inside the unchanged architectural footprint:
    # planting beds, a rear lawn/deck, side service strips and clipped
    # hedges replace the exposed pale site slab seen in the 0.2.7 shots.
    box("villa_front_planting_bed_west", -5.0, -7.00, 0.305, 7.80, 0.62, 0.055, mulch)
    box("villa_front_planting_bed_east", 2.75, -6.82, 0.305, 2.55, 0.78, 0.055, mulch)
    box("villa_front_bed_edging_west", -5.0, -6.67, 0.335, 7.90, 0.07, 0.09, granite)
    box("villa_front_bed_edging_east", 2.75, -6.40, 0.335, 2.65, 0.07, 0.09, granite)
    box("villa_rear_lawn", -4.8, 6.28, 0.300, 6.20, 1.85, 0.050, lawn)
    box("villa_rear_deck", -4.8, 6.20, 0.345, 4.85, 1.45, 0.060, deck)
    box("villa_rear_planting_bed_west", -4.5, 5.45, 0.305, 8.50, 0.55, 0.055, mulch)
    box("villa_rear_planting_bed_east", 4.7, 5.35, 0.305, 6.80, 0.55, 0.055, mulch)
    box("villa_side_planting_west", -9.23, -0.7, 0.305, 0.32, 10.80, 0.055, mulch)
    box("villa_side_planting_east", 8.92, -0.4, 0.305, 0.78, 9.80, 0.055, mulch)
    for stepper_y in (-4.2, -2.4, -0.6, 1.2, 3.0):
        box("villa_side_stepping_paver", 8.92, stepper_y, 0.345, 0.58, 0.92, 0.045, pavement)
    for hedge_x in (-7.35, -4.05, -0.75, 2.55, 5.85):
        box("villa_rear_hedge", hedge_x, 6.98, 0.58, 2.85, 0.34, 0.52, hedge, bevel=0.055)
    box("villa_rear_outdoor_table", -4.8, 6.20, 0.78, 1.65, 0.82, 0.08, stone)
    box("villa_rear_outdoor_table_leg", -4.8, 6.20, 0.55, 0.18, 0.58, 0.38, granite)
    for bench_y in (5.68, 6.72):
        box("villa_rear_outdoor_bench", -4.8, bench_y, 0.55, 1.45, 0.32, 0.09, deck)
        box("villa_rear_outdoor_bench_leg", -5.35, bench_y, 0.40, 0.10, 0.26, 0.22, frame)
        box("villa_rear_outdoor_bench_leg", -4.25, bench_y, 0.40, 0.10, 0.26, 0.22, frame)

    # Low garden walls, coping, an open pedestrian gate, planters and a
    # mailbox complete the street edge.
    def garden_wall(cx, cy, dx, dy):
        box("villa_garden_wall", cx, cy, 0.67, dx, dy, 0.78, stone)
        box("villa_garden_wall_coping", cx, cy, 1.10, dx + 0.08, dy + 0.08, 0.09, granite)

    garden_wall(-6.75, -7.35, 5.55, 0.22)
    garden_wall(3.05, -7.35, 2.15, 0.22)
    garden_wall(-9.45, 0.0, 0.22, 14.45)
    garden_wall(9.45, 0.0, 0.22, 14.45)
    garden_wall(0.0, 7.35, 18.70, 0.22)
    for pillar_x in (-3.92, 2.02):
        box("villa_gate_pillar", pillar_x, -7.35, 0.78, 0.40, 0.40, 1.08, granite)
        box("villa_gate_pillar_cap", pillar_x, -7.35, 1.38, 0.50, 0.50, 0.10, stone)
        box("villa_gate_pillar_light", pillar_x, -7.58, 1.08, 0.18, 0.035, 0.24, glow)
    rbox("villa_pedestrian_gate", -3.55, -6.88, 0.86, 1.55, 0.06, 1.08, wood, rotation=(0.0, 0.0, 0.52))
    box("villa_mailbox", -3.82, -7.20, 1.02, 0.48, 0.22, 0.34, frame, bevel=0.015)
    box("villa_mailbox_slot", -3.82, -7.325, 1.08, 0.30, 0.025, 0.045, metal)
    for planter_x in (-7.6, -5.2, 2.2, 8.1):
        box("villa_planter", planter_x, -6.95, 0.48, 1.25, 0.48, 0.42, granite, bevel=0.015)
        box("villa_planter_soil", planter_x, -6.95, 0.70, 1.12, 0.36, 0.045, mulch)
        box("villa_planter_hedge", planter_x, -6.95, 0.84, 1.05, 0.34, 0.28, hedge, bevel=0.055)
    for light_x in (-2.1, 3.9, 8.3):
        box("villa_path_light_post", light_x, -7.02, 0.48, 0.09, 0.09, 0.42, frame)
        box("villa_path_light", light_x, -7.02, 0.72, 0.15, 0.15, 0.10, glow)


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
        (build_traffic_signal_short, "traffic_signal_short.glb"),
        (build_traffic_signal_long, "traffic_signal_long.glb"),
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
