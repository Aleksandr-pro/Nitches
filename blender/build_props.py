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
  * hero_building.glb Building Model No.3: fixed-scale podium residential/hotel block
  * townhouse.glb     Building Model No.2: fixed-scale semi-detached townhouse pair
  * villa.glb         Building Model No.1: detailed fixed-scale modern villa
  * glass_tower.glb   Building Model No.4: fixed-scale glass district tower
  * main_tower.glb    legacy 148 m landmark massing pending its own pass
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
    # Building Model No.2 has its own plaster/stone/terracotta set so the
    # fixed-scale townhouse does not inherit the villa's modern roof and
    # facade treatment merely by sharing a model category.
    mat("TownPlaster", (0.84, 0.76, 0.64), roughness=0.92)
    mat("TownStone", (0.66, 0.58, 0.47), roughness=0.94)
    mat("TownTrim", (0.88, 0.84, 0.76), roughness=0.86)
    mat("TownRoof", (0.55, 0.25, 0.14), roughness=0.95)
    mat("TownGarage", (0.18, 0.22, 0.22), roughness=0.55, metallic=0.25)
    mat("TownDoor", (0.28, 0.12, 0.07), roughness=0.72)
    mat("TownDoorAccent", (0.08, 0.25, 0.28), roughness=0.50)
    # Building Model No.3 uses a stone-podium / warm-plaster tower /
    # timber-screen palette distinct from both earlier premium models.
    mat("HeroPlaster", (0.83, 0.78, 0.68), roughness=0.92)
    mat("HeroStone", (0.48, 0.44, 0.38), roughness=0.92)
    mat("HeroTrim", (0.82, 0.78, 0.69), roughness=0.84)
    mat("HeroWood", (0.42, 0.25, 0.12), roughness=0.78)
    mat("HeroMetal", (0.16, 0.18, 0.20), roughness=0.46, metallic=0.55)
    mat("TowerGlass", (0.10, 0.26, 0.34), roughness=0.08, metallic=0.15)
    mat("TowerSpandrel", (0.05, 0.11, 0.16), roughness=0.28, metallic=0.55)
    mat("TowerStone", (0.52, 0.49, 0.43), roughness=0.92, metallic=0.0)
    mat("TowerTrim", (0.78, 0.76, 0.70), roughness=0.55, metallic=0.25)
    mat("TowerMetal", (0.10, 0.12, 0.14), roughness=0.42, metallic=0.70)
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
# Building Model No.3 — detailed fixed-scale mid-rise residential/hotel block.
# Measured envelope: 32.40 x 24.60 m, 28.56 m high. A two-storey
# stone podium carries six residential floors and a set-back penthouse;
# the runtime places the finished design at scale 1.0 and only reuses it
# on infill parcels where the real footprint physically fits.
# --------------------------------------------------------------------------- #
def build_hero():
    plaster = MATS["HeroPlaster"]
    stone = MATS["HeroStone"]
    trim = MATS["HeroTrim"]
    wood = MATS["HeroWood"]
    hero_metal = MATS["HeroMetal"]
    granite = MATS["VillaGranite"]
    glass = MATS["VillaGlass"]
    interior = MATS["VillaInterior"]
    curtain = MATS["VillaCurtain"]
    frame = MATS["WindowFrame"]
    pavement = MATS["VillaPavement"]
    lawn = MATS["VillaLawn"]
    hedge = MATS["VillaHedge"]
    mulch = MATS["VillaMulch"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    solar = MATS["SolarCell"]
    glow = MATS["LampGlow"]

    def face_window(cx, cy, cz, width, height, face):
        sign = -1.0 if face in ("front", "left") else 1.0
        variant = int(abs(cx * 3.7 + cy * 5.3 + cz * 6.9)) % 4
        if face in ("front", "back"):
            box("hero_window_reveal", cx, cy + sign * 0.015, cz, width + 0.28, 0.075, height + 0.28, trim)
            box("hero_window_interior", cx, cy + sign * 0.032, cz, width - 0.02, 0.034, height - 0.02, interior)
            if variant == 0:
                for side in (-1.0, 1.0):
                    box("hero_window_curtain", cx + side * (width / 2.0 - 0.15), cy + sign * 0.052, cz, 0.20, 0.028, height - 0.12, curtain)
            elif variant == 1:
                blind_h = height * 0.38
                box("hero_window_blind", cx, cy + sign * 0.054, cz + height / 2.0 - blind_h / 2.0 - 0.03, width - 0.10, 0.028, blind_h, curtain)
                box("hero_window_blind_rail", cx, cy + sign * 0.058, cz + height / 2.0 - blind_h - 0.04, width - 0.08, 0.032, 0.038, frame)
            elif variant == 2:
                box("hero_window_light", cx - width * 0.16, cy + sign * 0.055, cz + height * 0.30, width * 0.36, 0.022, 0.034, glow)
            box("hero_window_frame", cx, cy + sign * 0.024, cz, width + 0.15, 0.135, height + 0.15, frame)
            box("hero_window_glass", cx, cy + sign * 0.078, cz, width, 0.038, height, glass)
            divisions = max(1, int(width // 1.15))
            for division in range(1, divisions):
                mx = cx - width / 2.0 + width * division / divisions
                box("hero_window_mullion", mx, cy + sign * 0.090, cz, 0.046, 0.046, height, frame)
            box("hero_window_transom", cx, cy + sign * 0.090, cz + height * 0.24, width, 0.046, 0.046, frame)
            box("hero_window_sill", cx, cy + sign * 0.090, cz - height / 2.0 - 0.070, width + 0.34, 0.25, 0.085, trim)
        else:
            box("hero_window_reveal", cx + sign * 0.015, cy, cz, 0.075, width + 0.28, height + 0.28, trim)
            box("hero_window_interior", cx + sign * 0.032, cy, cz, 0.034, width - 0.02, height - 0.02, interior)
            if variant == 0:
                for side in (-1.0, 1.0):
                    box("hero_window_curtain", cx + sign * 0.052, cy + side * (width / 2.0 - 0.15), cz, 0.028, 0.20, height - 0.12, curtain)
            elif variant == 1:
                blind_h = height * 0.38
                box("hero_window_blind", cx + sign * 0.054, cy, cz + height / 2.0 - blind_h / 2.0 - 0.03, 0.028, width - 0.10, blind_h, curtain)
                box("hero_window_blind_rail", cx + sign * 0.058, cy, cz + height / 2.0 - blind_h - 0.04, 0.032, width - 0.08, 0.038, frame)
            elif variant == 2:
                box("hero_window_light", cx + sign * 0.055, cy - width * 0.16, cz + height * 0.30, 0.022, width * 0.36, 0.034, glow)
            box("hero_window_frame", cx + sign * 0.024, cy, cz, 0.135, width + 0.15, height + 0.15, frame)
            box("hero_window_glass", cx + sign * 0.078, cy, cz, 0.038, width, height, glass)
            divisions = max(1, int(width // 1.15))
            for division in range(1, divisions):
                my = cy - width / 2.0 + width * division / divisions
                box("hero_window_mullion", cx + sign * 0.090, my, cz, 0.046, 0.046, height, frame)
            box("hero_window_transom", cx + sign * 0.090, cy, cz + height * 0.24, 0.046, width, 0.046, frame)
            box("hero_window_sill", cx + sign * 0.090, cy, cz - height / 2.0 - 0.070, 0.25, width + 0.34, 0.085, trim)

    def balcony(cx, face_y, sign, floor_z, screen_side):
        slab_y = face_y + sign * 0.85
        rail_y = face_y + sign * 1.62
        box("hero_balcony_slab", cx, slab_y, floor_z + 0.12, 4.90, 1.72, 0.18, trim)
        box("hero_balcony_soffit", cx, slab_y, floor_z + 0.015, 4.78, 1.60, 0.045, wood)
        box("hero_balcony_glass_rail", cx, rail_y, floor_z + 0.72, 4.72, 0.055, 0.82, glass)
        box("hero_balcony_top_rail", cx, rail_y, floor_z + 1.16, 4.86, 0.075, 0.065, frame)
        for post_offset in (-2.32, 0.0, 2.32):
            box("hero_balcony_post", cx + post_offset, rail_y, floor_z + 0.68, 0.042, 0.05, 0.96, frame)
        for side in (-1.0, 1.0):
            box("hero_balcony_side_rail", cx + side * 2.40, slab_y, floor_z + 1.16, 0.06, 1.62, 0.06, frame)
        box("hero_balcony_screen", cx + screen_side * 2.34, slab_y, floor_z + 1.02, 0.075, 1.56, 1.72, wood)
        planter_x = cx - screen_side * 1.78
        box("hero_balcony_planter", planter_x, rail_y - sign * 0.16, floor_z + 0.34, 1.05, 0.28, 0.28, granite)
        box("hero_balcony_hedge", planter_x, rail_y - sign * 0.16, floor_z + 0.56, 0.94, 0.20, 0.24, hedge, bevel=0.035)

    # Urban parcel, two-storey stone podium and set-back residential tower.
    box("hero_lot_plinth", 0.0, 0.0, 0.15, 32.40, 24.60, 0.30, granite, bevel=0.015)
    box("hero_podium", 0.0, 0.0, 3.00, 30.00, 20.40, 5.40, stone, bevel=0.025)
    box("hero_podium_cornice", 0.0, 0.0, 5.82, 30.55, 20.95, 0.24, trim)
    box("hero_tower", 0.0, 0.20, 15.30, 28.00, 18.40, 19.20, plaster, bevel=0.035)
    for pier_side in (-1.0, 1.0):
        box("hero_tower_end_pier", pier_side * 12.90, 0.20, 15.40, 3.40, 19.00, 19.60, stone, bevel=0.018)
        box("hero_penthouse_pier", pier_side * 10.20, 0.50, 26.55, 1.40, 15.00, 2.90, stone)
    box("hero_tower_cornice", 0.0, 0.20, 25.05, 29.00, 19.40, 0.35, trim)
    box("hero_tower_roof", 0.0, 0.20, 25.02, 27.40, 17.80, 0.18, dark)
    box("hero_penthouse", 0.0, 0.50, 26.55, 21.60, 14.60, 2.80, plaster, bevel=0.020)
    box("hero_penthouse_roof", 0.0, 0.50, 28.05, 22.60, 15.60, 0.30, trim)

    # Dark granite base and stone piers articulate the podium street wall.
    box("hero_podium_base_front", 0.0, -10.27, 0.85, 30.20, 0.15, 1.10, granite)
    box("hero_podium_base_rear", 0.0, 10.27, 0.85, 30.20, 0.15, 1.10, granite)
    for base_side in (-1.0, 1.0):
        box("hero_podium_base_side", base_side * 15.07, 0.0, 0.85, 0.15, 20.60, 1.10, granite)
    for pier_x in (-13.5, -9.0, -4.5, 4.5, 9.0, 13.5):
        box("hero_podium_front_pier", pier_x, -10.29, 2.95, 1.00, 0.34, 4.90, trim)
        box("hero_podium_rear_pier", pier_x, 10.29, 2.95, 1.00, 0.34, 4.90, trim)

    # Floor bands, central fins and panel seams keep the long elevations
    # from reading as one flat textured slab at street distance.
    for band_index in range(7):
        band_z = 5.75 + band_index * 3.20
        if band_z > 24.95:
            continue
        box("hero_floor_band_front", 0.0, -9.13, band_z, 28.35, 0.28, 0.22, trim)
        box("hero_floor_band_rear", 0.0, 9.53, band_z, 28.35, 0.28, 0.22, trim)
        for band_side in (-1.0, 1.0):
            box("hero_floor_band_side", band_side * 14.68, 0.20, band_z, 0.18, 19.10, 0.22, trim)
    for fin_x in (-3.90, 3.90):
        box("hero_front_fin", fin_x, -9.23, 15.30, 0.55, 0.46, 19.20, stone)
        box("hero_rear_fin", fin_x, 9.63, 15.30, 0.55, 0.46, 19.20, stone)
    for seam_x in (-9.75, -3.25, 3.25, 9.75):
        box("hero_facade_seam_front", seam_x, -9.025, 15.30, 0.070, 0.045, 19.00, frame)
        box("hero_facade_seam_rear", seam_x, 9.425, 15.30, 0.070, 0.045, 19.00, frame)

    # Six residential floors: deep windows, balcony doors and real
    # projecting balconies with glass rails, timber screens and planters.
    for floor_index in range(6):
        floor_z = 5.70 + floor_index * 3.20
        window_z = floor_z + 1.72
        door_z = floor_z + 1.42
        for face_y, pier_face_y, face_name, sign in ((-9.00, -9.30, "front", -1.0), (9.40, 9.70, "back", 1.0)):
            for bay_x in (-12.90, 12.90):
                face_window(bay_x, pier_face_y, window_z, 1.80, 1.72, face_name)
            for bay_x in (-6.50, 6.50):
                face_window(bay_x, face_y, door_z, 2.35, 2.28, face_name)
            face_window(0.0, face_y, door_z, 3.05, 2.28, face_name)
            for balcony_index, bay_x in enumerate((-6.50, 0.0, 6.50)):
                screen_side = 1.0 if (floor_index + balcony_index) % 2 == 0 else -1.0
                balcony(bay_x, face_y, sign, floor_z, screen_side)
        for side_sign, side_name in ((-1.0, "left"), (1.0, "right")):
            for bay_y in (-5.80, 0.20, 6.20):
                face_window(side_sign * 14.60, bay_y, window_z, 1.90, 1.72, side_name)

    # Penthouse glazing on all four sides.
    for bay_x in (-7.0, 0.0, 7.0):
        face_window(bay_x, -6.80, 26.62, 3.00, 1.90, "front")
        face_window(bay_x, 7.80, 26.62, 3.00, 1.90, "back")
    for side_sign, side_name in ((-1.0, "left"), (1.0, "right")):
        for bay_y in (-2.0, 3.0):
            face_window(side_sign * 10.90, bay_y, 26.62, 2.20, 1.90, side_name)

    # Street-level lobby and retail. The lobby is a recessed interior
    # volume behind a stone portal, not a glass sticker on the podium.
    box("hero_lobby_interior", 0.0, -10.02, 2.45, 5.60, 0.48, 4.20, interior)
    for portal_side in (-1.0, 1.0):
        box("hero_lobby_portal_column", portal_side * 2.88, -10.34, 2.55, 0.55, 0.30, 4.55, trim)
    box("hero_lobby_portal_header", 0.0, -10.34, 4.92, 6.30, 0.30, 0.55, trim)
    face_window(0.0, -10.20, 2.40, 4.45, 3.75, "front")
    for shop_x in (-11.25, -6.75, 6.75, 11.25):
        face_window(shop_x, -10.20, 2.20, 3.20, 3.20, "front")
        face_window(shop_x, -10.20, 4.95, 2.55, 0.88, "front")
        rbox("hero_shop_awning", shop_x, -10.78, 4.08, 3.45, 1.12, 0.08, wood, rotation=(-0.16, 0.0, 0.0), bevel=0.010)
        tube_between("hero_awning_rod_l", (shop_x - 1.45, -11.28, 4.16), (shop_x - 1.45, -10.25, 4.85), 0.022, 0.022, hero_metal, vertices=8)
        tube_between("hero_awning_rod_r", (shop_x + 1.45, -11.28, 4.16), (shop_x + 1.45, -10.25, 4.85), 0.022, 0.022, hero_metal, vertices=8)
    for side_sign, side_name in ((-1.0, "left"), (1.0, "right")):
        for shop_y in (-6.0, 0.0, 6.0):
            face_window(side_sign * 15.00, shop_y, 2.75, 2.65, 2.55, side_name)

    # Entrance canopy on columns and tie rods, steps, ramp, blade sign.
    box("hero_entry_canopy", 0.0, -11.15, 4.58, 7.20, 2.00, 0.22, granite, bevel=0.020)
    box("hero_entry_canopy_soffit", 0.0, -11.15, 4.44, 6.80, 1.80, 0.055, wood)
    for column_side in (-1.0, 1.0):
        column_x = column_side * 3.20
        box("hero_entry_column_base", column_x, -11.85, 0.48, 0.36, 0.36, 0.36, granite)
        cyl("hero_entry_column", column_x, -11.85, 2.42, 0.115, 3.85, hero_metal, vertices=14)
        tube_between("hero_entry_tie_rod", (column_x, -11.85, 4.42), (column_x, -10.24, 5.35), 0.025, 0.025, hero_metal, vertices=8)
        box("hero_entry_lantern_body", column_side * 2.72, -10.42, 3.55, 0.17, 0.11, 0.34, frame)
        box("hero_entry_lantern", column_side * 2.72, -10.49, 3.55, 0.10, 0.035, 0.22, glow)
    for step_index, (step_y, step_top) in enumerate(((-10.62, 0.52), (-11.12, 0.40), (-11.62, 0.28))):
        box("hero_entry_step", 0.0, step_y, step_top / 2.0 + 0.15, 6.20 - step_index * 0.35, 0.52, step_top - 0.15, pavement)
    rbox("hero_entry_ramp", 5.15, -11.20, 0.42, 2.20, 2.05, 0.12, pavement, rotation=(0.10, 0.0, 0.0))
    box("hero_blade_sign", 4.15, -10.62, 5.05, 0.18, 0.92, 2.45, hero_metal, bevel=0.015)
    box("hero_blade_sign_glow", 4.15, -11.10, 5.05, 0.10, 0.035, 2.05, glow)
    box("hero_address_plaque", -3.35, -10.38, 1.75, 0.55, 0.06, 0.75, granite)
    box("hero_address_inset", -3.35, -10.42, 1.75, 0.36, 0.025, 0.50, metal)

    # Rear service elevation: parking/loading door, dock, staff entry,
    # bins and bicycle parking keep the back from being an empty wall.
    box("hero_service_portal", 7.50, 10.28, 1.95, 4.15, 0.18, 3.35, trim)
    box("hero_service_door", 7.50, 10.36, 1.90, 3.65, 0.10, 3.00, hero_metal, bevel=0.010)
    for seam_z in (1.05, 1.85, 2.65):
        box("hero_service_door_seam", 7.50, 10.42, seam_z, 3.55, 0.025, 0.045, frame)
    box("hero_loading_dock", 7.50, 11.15, 0.52, 5.20, 1.55, 0.45, pavement)
    for bollard_x in (4.85, 10.15):
        cyl("hero_dock_bollard", bollard_x, 11.85, 0.68, 0.09, 0.76, hero_metal, vertices=12)
    box("hero_staff_door_frame", -7.00, 10.29, 1.62, 1.35, 0.16, 2.55, trim)
    box("hero_staff_door", -7.00, 10.37, 1.58, 1.05, 0.09, 2.30, hero_metal)
    box("hero_staff_canopy", -7.00, 10.78, 3.05, 2.10, 1.05, 0.14, granite)
    for service_x in (-11.0, -3.0, 1.5, 12.2):
        face_window(service_x, 10.20, 3.55, 2.15, 1.65, "back")
    for bin_x in (-11.4, -9.2):
        box("hero_waste_bin", bin_x, 11.35, 0.82, 1.85, 1.05, 1.08, dark, bevel=0.025)
        box("hero_waste_bin_lid", bin_x, 11.35, 1.40, 1.92, 1.10, 0.09, hero_metal)
    for rack_index in range(5):
        rack_x = 12.2 + rack_index * 0.72
        tube_between("hero_bike_rack", (rack_x, 11.15, 0.30), (rack_x, 11.15, 1.05), 0.035, 0.035, metal, vertices=8)
        tube_between("hero_bike_rack_top", (rack_x, 11.15, 1.05), (rack_x + 0.42, 11.15, 1.05), 0.035, 0.035, metal, vertices=8)
        tube_between("hero_bike_rack_leg", (rack_x + 0.42, 11.15, 1.05), (rack_x + 0.42, 11.15, 0.30), 0.035, 0.035, metal, vertices=8)

    # Downspouts, meters and podium-roof condensers.
    for pipe_side in (-1.0, 1.0):
        for pipe_y in (-8.45, 8.85):
            cyl("hero_downspout", pipe_side * 14.85, pipe_y, 15.35, 0.065, 19.30, frame, vertices=10)
            for bracket_z in (7.20, 12.20, 17.20, 22.20):
                box("hero_downspout_bracket", pipe_side * 14.78, pipe_y, bracket_z, 0.20, 0.16, 0.055, metal)
        meter_x = pipe_side * 15.12
        box("hero_meter_cabinet", meter_x, -4.35, 1.35, 0.17, 0.85, 1.20, metal, bevel=0.012)
        box("hero_meter_window", meter_x + pipe_side * 0.095, -4.35, 1.55, 0.025, 0.40, 0.40, glass)
        for vent_offset in (-0.24, 0.0, 0.24):
            box("hero_podium_vent", meter_x, 3.40 + vent_offset, 4.55, 0.10, 0.16, 0.65, frame)
    for ac_x in (-11.0, 11.0):
        for ac_y in (-9.65, 9.95):
            box("hero_podium_ac", ac_x, ac_y, 6.18, 1.45, 0.78, 0.72, metal, bevel=0.018)
            cyl("hero_podium_ac_fan", ac_x, ac_y, 6.57, 0.24, 0.045, frame, vertices=16)

    # Podium-roof terraces at the tower setback.
    for terrace_side in (-1.0, 1.0):
        terrace_x = terrace_side * 11.20
        for post_x in (terrace_x - 1.65, terrace_x + 1.65):
            for post_y in (-10.05, -9.15):
                box("hero_podium_pergola_post", post_x, post_y, 6.82, 0.14, 0.14, 1.95, wood)
        for beam_y in (-10.08, -9.12):
            box("hero_podium_pergola_beam", terrace_x, beam_y, 7.86, 3.75, 0.15, 0.16, wood)
        for slat_index in range(5):
            box("hero_podium_pergola_slat", terrace_x - 1.55 + slat_index * 0.78, -9.60, 8.00, 0.13, 1.16, 0.11, wood)
    for planter_x in (-13.8, -7.2, 7.2, 13.8):
        box("hero_podium_roof_planter", planter_x, -9.72, 6.13, 1.75, 0.55, 0.42, granite)
        box("hero_podium_roof_hedge", planter_x, -9.72, 6.43, 1.55, 0.38, 0.28, hedge, bevel=0.040)

    # Tower-roof parapet, penthouse terrace pergola and roof plant.
    box("hero_roof_parapet_front", 0.0, -8.95, 25.58, 27.80, 0.18, 0.90, trim)
    box("hero_roof_parapet_rear", 0.0, 9.35, 25.58, 27.80, 0.18, 0.90, trim)
    for parapet_side in (-1.0, 1.0):
        box("hero_roof_parapet_side", parapet_side * 13.90, 0.20, 25.58, 0.18, 18.30, 0.90, trim)
    for post_x in (-8.0, 0.0, 8.0):
        box("hero_roof_pergola_post", post_x, -8.20, 26.25, 0.15, 0.15, 2.05, wood)
    box("hero_roof_pergola_beam", 0.0, -8.20, 27.38, 17.20, 0.17, 0.18, wood)
    for slat_index in range(9):
        box("hero_roof_pergola_slat", -7.6 + slat_index * 1.90, -7.72, 27.52, 0.14, 1.10, 0.12, wood)
    box("hero_lift_overrun", 12.15, 4.00, 26.30, 2.55, 3.10, 2.30, stone, bevel=0.018)
    box("hero_lift_overrun_cap", 12.15, 4.00, 27.52, 2.80, 3.35, 0.16, granite)
    cyl("hero_roof_tank", -12.00, 4.20, 26.20, 0.95, 2.05, metal, vertices=18)
    cone("hero_roof_tank_cap", -12.00, 4.20, 27.48, 1.08, 0.18, 0.48, hero_metal, vertices=18)
    for hvac_x in (-8.0, 0.0, 8.0):
        for hvac_y in (-7.50, 8.55):
            box("hero_roof_hvac", hvac_x, hvac_y, 25.62, 2.25, 1.35, 0.88, metal, bevel=0.020)
            cyl("hero_roof_hvac_fan", hvac_x, hvac_y, 26.09, 0.34, 0.05, frame, vertices=18)
    for vent_x in (-4.5, 4.5):
        cyl("hero_roof_vent", vent_x, 8.20, 25.72, 0.12, 1.05, metal, vertices=12)
        cone("hero_roof_vent_cap", vent_x, 8.20, 26.34, 0.22, 0.05, 0.24, metal, vertices=12)
    for panel_x in (-6.8, -3.4, 0.0, 3.4, 6.8):
        rbox("hero_solar_frame", panel_x, 0.50, 28.38, 2.85, 2.15, 0.08, metal, rotation=(-0.12, 0.0, 0.0), bevel=0.008)
        rbox("hero_solar_cell", panel_x, 0.53, 28.42, 2.68, 1.98, 0.028, solar, rotation=(-0.12, 0.0, 0.0))
        for busbar_offset in (-0.68, 0.68):
            rbox("hero_solar_busbar", panel_x + busbar_offset, 0.535, 28.44, 0.020, 1.90, 0.008, metal, rotation=(-0.12, 0.0, 0.0))

    # Forecourt, side landscape strips, bollards and rear planting.
    box("hero_forecourt_paving", 0.0, -11.28, 0.345, 25.00, 1.95, 0.07, pavement)
    box("hero_dropoff_strip", 0.0, -12.08, 0.335, 18.50, 0.42, 0.05, granite)
    box("hero_rear_paving", 0.0, 11.35, 0.345, 24.00, 1.75, 0.07, pavement)
    for landscape_side in (-1.0, 1.0):
        box("hero_side_lawn", landscape_side * 15.55, 0.0, 0.345, 1.20, 18.50, 0.06, lawn)
        for hedge_y in (-7.5, -2.5, 2.5, 7.5):
            box("hero_side_hedge", landscape_side * 15.55, hedge_y, 0.62, 0.82, 2.55, 0.48, hedge, bevel=0.055)
    for planter_x in (-13.0, -9.0, 9.0, 13.0):
        box("hero_front_planter", planter_x, -11.45, 0.58, 1.85, 0.78, 0.52, granite)
        box("hero_front_planter_soil", planter_x, -11.45, 0.86, 1.68, 0.60, 0.045, mulch)
        box("hero_front_planter_hedge", planter_x, -11.45, 1.02, 1.58, 0.50, 0.32, hedge, bevel=0.045)
    for bollard_x in (-9.0, -6.0, -3.0, 3.0, 6.0, 9.0):
        cyl("hero_front_bollard", bollard_x, -12.02, 0.68, 0.085, 0.76, hero_metal, vertices=12)
        box("hero_front_bollard_light", bollard_x, -12.02, 1.08, 0.10, 0.10, 0.045, glow)
    for bench_x in (-11.8, 11.8):
        box("hero_front_bench", bench_x, -11.02, 0.58, 2.15, 0.48, 0.10, wood)
        box("hero_front_bench_base", bench_x, -11.02, 0.42, 1.75, 0.34, 0.24, granite)
    for rear_hedge_x in (-14.0, -5.0, 0.5, 13.5):
        box("hero_rear_hedge", rear_hedge_x, 11.85, 0.60, 2.60, 0.55, 0.52, hedge, bevel=0.055)


# --------------------------------------------------------------------------- #
# Building Model No.2 — detailed semi-detached townhouse pair.
# Fixed real-metre envelope: 18.87 x 16.37 m, 11.05 m high. Two mirrored
# 9.4 m homes share a party wall; the runtime places the complete design
# at scale 1.0 rather than stretching one small house over every parcel.
# --------------------------------------------------------------------------- #
def build_townhouse():
    plaster = MATS["TownPlaster"]
    stone = MATS["TownStone"]
    trim = MATS["TownTrim"]
    roof_tile = MATS["TownRoof"]
    garage_mat = MATS["TownGarage"]
    door_mat = MATS["TownDoor"]
    door_accent = MATS["TownDoorAccent"]
    granite = MATS["VillaGranite"]
    wood = MATS["VillaWood"]
    deck = MATS["VillaDeck"]
    frame = MATS["WindowFrame"]
    glass = MATS["VillaGlass"]
    interior = MATS["VillaInterior"]
    curtain = MATS["VillaCurtain"]
    pavement = MATS["VillaPavement"]
    mulch = MATS["VillaMulch"]
    lawn = MATS["VillaLawn"]
    hedge = MATS["VillaHedge"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    solar = MATS["SolarCell"]
    glow = MATS["LampGlow"]

    # Shared lot slab. The finished landscaping below covers most of it;
    # the dark stone edge separates the parcel from the city terrain.
    box("townhouse_lot_plinth", 0.0, 0.0, 0.09, 18.80, 16.20, 0.18, granite, bevel=0.015)

    def face_window(cx, cy, cz, width, height, face, shutters=False):
        sign = -1.0 if face in ("front", "left") else 1.0
        variant = int(abs(cx * 4.3 + cy * 6.1 + cz * 7.7)) % 4
        blind_drop = height * (0.28, 0.44, 0.0, 0.58)[variant]
        if face in ("front", "back"):
            box("town_window_reveal", cx, cy + sign * 0.016, cz, width + 0.34, 0.080, height + 0.34, trim)
            box("town_window_interior", cx, cy + sign * 0.036, cz, width - 0.03, 0.038, height - 0.03, interior)
            if variant != 1:
                for side in (-1.0, 1.0):
                    box("town_window_curtain", cx + side * (width / 2.0 - 0.16), cy + sign * 0.060, cz, 0.22, 0.032, height - 0.13, curtain)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.03
                box("town_window_blind", cx, cy + sign * 0.062, blind_z, width - 0.10, 0.030, blind_drop, curtain)
                box("town_window_blind_rail", cx, cy + sign * 0.066, blind_z - blind_drop / 2.0, width - 0.08, 0.036, 0.040, frame)
            box("town_window_light", cx - width * 0.17, cy + sign * 0.064, cz + height * 0.33, width * 0.34, 0.024, 0.035, glow)
            box("town_window_frame", cx, cy + sign * 0.026, cz, width + 0.18, 0.155, height + 0.18, frame)
            box("town_window_glass", cx, cy + sign * 0.090, cz, width, 0.042, height, glass)
            divisions = max(1, int(width // 0.95))
            for division in range(1, divisions):
                mx = cx - width / 2.0 + width * division / divisions
                box("town_window_mullion", mx, cy + sign * 0.103, cz, 0.050, 0.052, height, frame)
            box("town_window_transom", cx, cy + sign * 0.103, cz + height * 0.22, width, 0.052, 0.050, frame)
            box("town_window_handle", cx + width * 0.21, cy + sign * 0.118, cz - 0.04, 0.040, 0.032, 0.28, metal)
            box("town_window_sill", cx, cy + sign * 0.100, cz - height / 2.0 - 0.075, width + 0.40, 0.28, 0.095, trim)
            box("town_window_header", cx, cy + sign * 0.060, cz + height / 2.0 + 0.085, width + 0.30, 0.15, 0.10, trim)
            if shutters:
                for side in (-1.0, 1.0):
                    sx = cx + side * (width / 2.0 + 0.28)
                    box("town_window_shutter", sx, cy + sign * 0.045, cz, 0.38, 0.055, height + 0.08, wood)
                    for groove in (-0.30, 0.0, 0.30):
                        box("town_window_shutter_groove", sx, cy + sign * 0.078, cz + groove * height, 0.32, 0.020, 0.035, frame)
            if cz < 3.0 and variant in (0, 3):
                box("town_window_flower_box", cx, cy + sign * 0.18, cz - height / 2.0 - 0.24, width * 0.72, 0.22, 0.20, granite)
                box("town_window_flower_hedge", cx, cy + sign * 0.18, cz - height / 2.0 - 0.10, width * 0.64, 0.16, 0.16, hedge, bevel=0.035)
        else:
            box("town_window_reveal", cx + sign * 0.016, cy, cz, 0.080, width + 0.34, height + 0.34, trim)
            box("town_window_interior", cx + sign * 0.036, cy, cz, 0.038, width - 0.03, height - 0.03, interior)
            if variant != 1:
                for side in (-1.0, 1.0):
                    box("town_window_curtain", cx + sign * 0.060, cy + side * (width / 2.0 - 0.16), cz, 0.032, 0.22, height - 0.13, curtain)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.03
                box("town_window_blind", cx + sign * 0.062, cy, blind_z, 0.030, width - 0.10, blind_drop, curtain)
                box("town_window_blind_rail", cx + sign * 0.066, cy, blind_z - blind_drop / 2.0, 0.036, width - 0.08, 0.040, frame)
            box("town_window_light", cx + sign * 0.064, cy - width * 0.17, cz + height * 0.33, 0.024, width * 0.34, 0.035, glow)
            box("town_window_frame", cx + sign * 0.026, cy, cz, 0.155, width + 0.18, height + 0.18, frame)
            box("town_window_glass", cx + sign * 0.090, cy, cz, 0.042, width, height, glass)
            divisions = max(1, int(width // 0.95))
            for division in range(1, divisions):
                my = cy - width / 2.0 + width * division / divisions
                box("town_window_mullion", cx + sign * 0.103, my, cz, 0.052, 0.050, height, frame)
            box("town_window_transom", cx + sign * 0.103, cy, cz + height * 0.22, 0.052, width, 0.050, frame)
            box("town_window_handle", cx + sign * 0.118, cy + width * 0.21, cz - 0.04, 0.032, 0.040, 0.28, metal)
            box("town_window_sill", cx + sign * 0.100, cy, cz - height / 2.0 - 0.075, 0.28, width + 0.40, 0.095, trim)
            box("town_window_header", cx + sign * 0.060, cy, cz + height / 2.0 + 0.085, 0.15, width + 0.30, 0.10, trim)
            if shutters:
                for side in (-1.0, 1.0):
                    sy = cy + side * (width / 2.0 + 0.28)
                    box("town_window_shutter", cx + sign * 0.045, sy, cz, 0.055, 0.38, height + 0.08, wood)
                    for groove in (-0.30, 0.0, 0.30):
                        box("town_window_shutter_groove", cx + sign * 0.078, sy, cz + groove * height, 0.020, 0.32, 0.035, frame)

    def juliet_balcony(cx, face_y, sign):
        slab_y = face_y + sign * 0.30
        rail_y = face_y + sign * 0.54
        box("town_juliet_slab", cx, slab_y, 3.68, 1.95, 0.58, 0.14, granite)
        for bracket_x in (cx - 0.72, cx + 0.72):
            rbox("town_juliet_bracket", bracket_x, slab_y, 3.42, 0.08, 0.48, 0.08, metal, rotation=(sign * 0.62, 0.0, 0.0))
        for post_offset in (-0.88, -0.44, 0.0, 0.44, 0.88):
            box("town_juliet_post", cx + post_offset, rail_y, 4.18, 0.038, 0.045, 0.86, frame)
        box("town_juliet_top_rail", cx, rail_y, 4.64, 1.92, 0.07, 0.06, frame)
        box("town_juliet_mid_rail", cx, rail_y, 4.18, 1.92, 0.045, 0.04, frame)
        for side in (-1.0, 1.0):
            box("town_juliet_side_rail", cx + side * 0.92, face_y + sign * 0.30, 4.64, 0.06, 0.52, 0.06, frame)

    def roof_dormer(cx, unit_material):
        box("town_dormer_body", cx, -3.55, 7.88, 1.35, 1.28, 1.60, unit_material, bevel=0.015)
        for cheek_side in (-1.0, 1.0):
            box("town_dormer_cheek", cx + cheek_side * 0.72, -3.55, 7.88, 0.09, 1.34, 1.62, trim)
        gable_roof("town_dormer_roof", cx, -3.55, 8.98, 1.62, 1.52, 0.66, roof_tile, ridge_axis="y")
        box("town_dormer_ridge", cx, -3.55, 9.34, 0.20, 1.58, 0.09, granite)
        face_window(cx, -4.20, 7.95, 0.86, 1.02, "front")

    # Party wall between the two homes, carried up both roof slopes as a
    # raised granite flashing line so the pair reads as two dwellings
    # under one continuous semi-detached roof.
    box("town_party_wall", 0.0, 0.55, 3.45, 0.30, 10.10, 6.30, trim)
    tube_between("town_party_flashing_front", (0.0, -4.88, 6.72), (0.0, 0.55, 10.20), 0.10, 0.10, granite, vertices=10)
    tube_between("town_party_flashing_rear", (0.0, 5.98, 6.72), (0.0, 0.55, 10.20), 0.10, 0.10, granite, vertices=10)

    # One continuous main roof over the pair: tile ridge, fascia boards,
    # gutters and gable-end rake trim (per-home dormers sit on it below).
    gable_roof("town_main_roof", 0.0, 0.55, 8.35, 18.72, 10.90, 3.50, roof_tile, ridge_axis="x")
    box("town_main_ridge", 0.0, 0.55, 10.16, 18.78, 0.34, 0.15, granite)
    for eave_y in (-4.95, 6.05):
        box("town_roof_fascia", 0.0, eave_y, 6.52, 18.78, 0.18, 0.25, trim)
        tube_between("town_roof_gutter", (-9.30, eave_y, 6.34), (9.30, eave_y, 6.34), 0.065, 0.065, frame, vertices=10)
    for rake_x in (-9.34, 9.34):
        tube_between("town_roof_rake_front", (rake_x, -4.92, 6.62), (rake_x, 0.55, 10.12), 0.055, 0.055, trim, vertices=8)
        tube_between("town_roof_rake_rear", (rake_x, 6.02, 6.62), (rake_x, 0.55, 10.12), 0.055, 0.055, trim, vertices=8)

    for unit_side in (-1.0, 1.0):
        unit_x = unit_side * 4.60
        garage_x = unit_side * 7.00
        door_x = unit_side * 4.30
        bay_x = unit_side * 1.95
        body_material = plaster if unit_side < 0 else stone
        accent_material = stone if unit_side < 0 else plaster
        front_door_material = door_mat if unit_side < 0 else door_accent

        # Main two-storey volume, stone foundation and string course.
        box("town_foundation", unit_x, 0.55, 0.28, 9.30, 10.20, 0.56, stone, bevel=0.02)
        box("town_main_body", unit_x, 0.55, 3.45, 9.00, 9.90, 6.30, body_material, bevel=0.035)
        box("town_base_front", unit_x, -4.46, 0.72, 9.08, 0.14, 0.88, stone)
        box("town_base_rear", unit_x, 5.56, 0.72, 9.08, 0.14, 0.88, stone)
        box("town_base_outer", unit_x + unit_side * 4.54, 0.55, 0.72, 0.14, 9.98, 0.88, stone)
        box("town_string_front", unit_x, -4.47, 3.42, 9.10, 0.15, 0.20, trim)
        box("town_string_rear", unit_x, 5.57, 3.42, 9.10, 0.15, 0.20, trim)
        box("town_string_outer", unit_x + unit_side * 4.55, 0.55, 3.42, 0.15, 10.00, 0.20, trim)
        for quoin_z in (1.25, 2.55, 4.65, 5.95):
            box("town_corner_quoin", unit_x + unit_side * 4.38, -4.42, quoin_z, 0.42, 0.16, 0.62, trim)
            box("town_corner_quoin", unit_x + unit_side * 4.38, 5.52, quoin_z, 0.42, 0.16, 0.62, trim)

        # Attached garage: projecting volume, front gable, sectional
        # timber-look door, windows, lights and a real paved driveway.
        box("town_garage_body", garage_x, -2.25, 1.72, 3.70, 5.90, 2.92, accent_material, bevel=0.025)
        gable_roof("town_garage_roof", garage_x, -2.25, 3.68, 4.15, 6.35, 1.05, roof_tile, ridge_axis="y")
        box("town_garage_ridge", garage_x, -2.25, 4.25, 0.22, 6.45, 0.10, granite)
        box("town_garage_portal", garage_x, -5.25, 1.50, 3.25, 0.16, 2.62, trim)
        box("town_garage_door", garage_x, -5.35, 1.48, 2.78, 0.09, 2.24, garage_mat, bevel=0.010)
        for seam_z in (0.83, 1.38, 1.93):
            box("town_garage_seam_h", garage_x, -5.405, seam_z, 2.70, 0.025, 0.045, frame)
        for seam_offset in (-0.70, 0.0, 0.70):
            box("town_garage_seam_v", garage_x + seam_offset, -5.405, 1.48, 0.035, 0.025, 2.16, frame)
        for window_offset in (-0.82, 0.0, 0.82):
            box("town_garage_window", garage_x + window_offset, -5.415, 2.28, 0.56, 0.030, 0.32, glass)
        box("town_garage_handle", garage_x, -5.425, 1.08, 0.42, 0.035, 0.07, frame)
        box("town_garage_bottom_seal", garage_x, -5.41, 0.42, 2.74, 0.035, 0.09, frame)
        for light_offset in (-1.70, 1.70):
            box("town_garage_light_body", garage_x + light_offset, -5.27, 2.55, 0.16, 0.10, 0.28, frame)
            box("town_garage_light", garage_x + light_offset, -5.335, 2.55, 0.10, 0.035, 0.18, glow)
        box("town_driveway_bed", garage_x, -6.68, 0.205, 3.45, 2.75, 0.045, granite)
        for paver_dx in (-1.12, 0.0, 1.12):
            for paver_y in (-5.83, -6.68, -7.53):
                box("town_driveway_paver", garage_x + paver_dx, paver_y, 0.245, 1.00, 0.72, 0.045, pavement)
        box("town_driveway_drain", garage_x, -5.50, 0.255, 2.90, 0.16, 0.030, frame)

        # Two-storey front bay. The angled side panes are separate
        # framed/interior/glass layers, not a texture wrapped round a box.
        box("town_bay_ground", bay_x, -4.72, 1.62, 3.15, 0.78, 2.72, accent_material, bevel=0.018)
        box("town_bay_upper", bay_x, -4.62, 4.82, 2.75, 0.50, 2.28, accent_material, bevel=0.015)
        box("town_bay_roof", bay_x, -4.82, 3.08, 3.48, 1.05, 0.18, roof_tile)
        box("town_bay_cornice", bay_x, -4.88, 6.02, 3.05, 0.72, 0.16, trim)
        for corbel_offset in (-1.05, 0.0, 1.05):
            box("town_bay_corbel", bay_x + corbel_offset, -4.62, 3.48, 0.18, 0.28, 0.34, trim)
        face_window(bay_x, -5.11, 1.72, 2.20, 1.92, "front", shutters=False)
        face_window(bay_x, -4.87, 4.86, 2.05, 1.78, "front", shutters=True)
        for pane_side in (-1.0, 1.0):
            pane_x = bay_x + pane_side * 1.43
            rotation = (0.0, 0.0, pane_side * 0.62)
            rbox("town_bay_side_interior", pane_x, -4.86, 1.72, 0.78, 0.045, 1.78, interior, rotation=rotation)
            rbox("town_bay_side_glass", pane_x, -4.92, 1.72, 0.82, 0.055, 1.82, glass, rotation=rotation)
            rbox("town_bay_side_frame", pane_x, -4.96, 1.72, 0.90, 0.045, 0.12, frame, rotation=rotation)

        # Porch and entrance. Each home has its own door colour,
        # sidelight, lanterns, number plaque, mailbox and paved path.
        box("town_porch_slab", door_x, -5.18, 0.32, 2.35, 1.70, 0.22, pavement)
        box("town_porch_step", door_x, -6.12, 0.20, 1.75, 0.55, 0.18, trim)
        gable_roof("town_porch_roof", door_x, -5.05, 3.24, 2.95, 1.78, 0.78, roof_tile, ridge_axis="y")
        box("town_porch_ridge", door_x, -5.05, 3.67, 0.20, 1.86, 0.09, granite)
        for column_offset in (-1.18, 1.18):
            column_x = door_x + column_offset
            box("town_porch_column_base", column_x, -5.78, 0.50, 0.28, 0.28, 0.36, stone)
            cyl("town_porch_column", column_x, -5.78, 1.78, 0.075, 2.55, trim, vertices=12)
            box("town_porch_column_cap", column_x, -5.78, 3.02, 0.25, 0.25, 0.14, trim)
        box("town_entry_frame", door_x, -4.46, 1.58, 1.42, 0.16, 2.62, trim)
        box("town_entry_door", door_x, -4.53, 1.56, 1.12, 0.10, 2.34, front_door_material, bevel=0.012)
        box("town_entry_door_glass", door_x - 0.20, -4.60, 1.82, 0.38, 0.035, 1.28, glass)
        for groove_offset in (-0.28, 0.08, 0.38):
            box("town_entry_door_groove", door_x + groove_offset, -4.592, 1.56, 0.025, 0.022, 2.18, frame)
        cyl("town_entry_handle", door_x + 0.43, -4.63, 1.55, 0.022, 0.72, metal, vertices=10)
        for lantern_offset in (-1.18, 1.18):
            lantern_x = door_x + lantern_offset
            box("town_entry_lantern_body", lantern_x, -5.90, 2.30, 0.15, 0.12, 0.28, frame)
            box("town_entry_lantern", lantern_x, -5.97, 2.30, 0.09, 0.035, 0.18, glow)
        plaque_x = door_x - unit_side * 1.18
        box("town_house_number", plaque_x, -5.89, 1.85, 0.34, 0.05, 0.44, granite)
        box("town_house_number_inset", plaque_x, -5.92, 1.85, 0.22, 0.02, 0.28, metal)
        mailbox_x = door_x - unit_side * 1.05
        box("town_mailbox_post", mailbox_x, -7.30, 0.62, 0.09, 0.09, 0.85, frame)
        box("town_mailbox", mailbox_x, -7.30, 1.12, 0.30, 0.58, 0.28, frame, bevel=0.02)
        box("town_mailbox_slot", mailbox_x, -7.60, 1.16, 0.18, 0.025, 0.04, metal)
        box("town_mailbox_flag", mailbox_x + 0.18, -7.45, 1.28, 0.03, 0.20, 0.16, door_mat)
        for path_y in (-6.55, -7.22, -7.82):
            box("town_entry_path_paver", door_x, path_y, 0.235, 1.28, 0.52, 0.045, pavement)

        # Remaining front windows and a Juliet balcony over the porch.
        face_window(garage_x, -4.40, 5.18, 1.65, 1.62, "front", shutters=True)
        face_window(door_x, -4.40, 4.92, 1.42, 2.22, "front", shutters=False)
        juliet_balcony(door_x, -4.40, -1.0)

        # Rear elevation: sliding doors, kitchen window and bedrooms.
        face_window(unit_x - unit_side * 1.55, 5.50, 1.62, 2.65, 2.34, "back")
        face_window(garage_x, 5.50, 1.92, 1.75, 1.42, "back", shutters=True)
        face_window(garage_x, 5.50, 5.02, 1.65, 1.70, "back", shutters=True)
        face_window(door_x, 5.50, 5.02, 1.45, 1.70, "back", shutters=True)
        face_window(bay_x, 5.50, 5.02, 1.85, 1.70, "back", shutters=False)
        face_window(unit_x - unit_side * 3.55, 5.50, 1.95, 0.82, 1.15, "back")

        # Outer side elevation; the party-wall side remains blank.
        side_x = unit_x + unit_side * 4.50
        side_face = "right" if unit_side > 0 else "left"
        face_window(garage_x + unit_side * 1.85, -2.20, 1.95, 1.70, 1.05, side_face)
        face_window(side_x, -1.75, 1.88, 1.55, 1.42, side_face, shutters=True)
        face_window(side_x, 2.65, 1.88, 1.55, 1.42, side_face, shutters=True)
        face_window(side_x, -1.75, 5.02, 1.55, 1.68, side_face, shutters=True)
        face_window(side_x, 2.65, 5.02, 1.55, 1.68, side_face, shutters=False)

        # Two dormers per home on the shared main roof.
        roof_dormer(garage_x, body_material)
        roof_dormer(bay_x, body_material)

        # Stone chimney, flashing, twin flues and rear roof vent.
        chimney_x = unit_side * 8.25
        box("town_chimney", chimney_x, 2.20, 9.025, 0.86, 0.86, 3.65, stone, bevel=0.015)
        rbox("town_chimney_flashing", chimney_x, 2.20, 9.02, 1.08, 1.18, 0.14, frame, rotation=(-0.57, 0.0, 0.0))
        box("town_chimney_cap", chimney_x, 2.20, 10.94, 1.06, 1.06, 0.18, granite)
        for flue_offset in (-0.22, 0.22):
            box("town_chimney_flue", chimney_x + flue_offset, 2.20, 11.00, 0.28, 0.28, 0.10, dark)
        cyl("town_roof_vent", unit_x - unit_side * 2.5, 3.25, 8.72, 0.11, 0.62, metal, vertices=12)
        cone("town_roof_vent_cap", unit_x - unit_side * 2.5, 3.25, 9.08, 0.20, 0.045, 0.22, metal, vertices=12)

        # Solar panels on the rear slope of the right-hand home only;
        # identical equipment on both roofs looked stamped rather than lived in.
        if unit_side > 0:
            for panel_x in (2.55, 3.85, 5.15, 6.45):
                rbox("town_solar_frame", panel_x, 3.28, 8.43, 1.12, 1.72, 0.07, metal, rotation=(-0.57, 0.0, 0.0), bevel=0.008)
                rbox("town_solar_cell", panel_x, 3.31, 8.47, 1.00, 1.58, 0.028, solar, rotation=(-0.57, 0.0, 0.0))
                for busbar_offset in (-0.25, 0.25):
                    rbox("town_solar_busbar", panel_x + busbar_offset, 3.32, 8.48, 0.018, 1.52, 0.007, metal, rotation=(-0.57, 0.0, 0.0))

        # Downspouts, side meter and rear condenser with a fan grille.
        for pipe_y, pipe_x in ((-4.80, unit_x - unit_side * 4.32), (5.90, unit_x + unit_side * 4.25)):
            cyl("town_downspout", pipe_x, pipe_y, 3.45, 0.055, 5.85, frame, vertices=10)
            tube_between("town_downspout_shoe", (pipe_x, pipe_y, 0.58), (pipe_x, pipe_y - 0.28 if pipe_y < 0 else pipe_y + 0.28, 0.24), 0.055, 0.055, frame, vertices=8)
            bracket_y = pipe_y + 0.20 if pipe_y < 0 else pipe_y - 0.20
            for bracket_z in (1.25, 3.40, 5.55):
                box("town_downspout_bracket", pipe_x, bracket_y, bracket_z, 0.16, 0.52, 0.05, metal)
        meter_x = garage_x + unit_side * 1.94
        box("town_meter_cabinet", meter_x, -4.20, 1.25, 0.16, 0.72, 1.05, metal, bevel=0.012)
        box("town_meter_window", meter_x + unit_side * 0.09, -4.20, 1.42, 0.025, 0.34, 0.34, glass)
        ac_x = unit_side * 8.15
        box("town_ac_unit", ac_x, 6.05, 0.68, 1.00, 0.42, 0.78, metal, bevel=0.018)
        cyl("town_ac_fan", ac_x, 6.285, 0.68, 0.27, 0.045, frame, vertices=20, rotation=(math.pi / 2.0, 0.0, 0.0))
        for grille_offset in (-0.18, 0.0, 0.18):
            box("town_ac_grille", ac_x + grille_offset, 6.315, 0.68, 0.040, 0.025, 0.52, metal)

        # Rear patio with pergola, outdoor counter and garden furniture.
        box("town_rear_patio", unit_x, 6.50, 0.27, 7.80, 2.25, 0.12, pavement)
        for post_x in (unit_x - 3.35, unit_x + 3.35):
            for post_y in (5.78, 7.32):
                box("town_pergola_post", post_x, post_y, 1.48, 0.16, 0.16, 2.55, wood)
        for beam_y in (5.74, 7.36):
            box("town_pergola_beam", unit_x, beam_y, 2.80, 7.15, 0.17, 0.18, wood)
        for slat_index in range(11):
            slat_x = unit_x - 3.3 + slat_index * 0.66
            box("town_pergola_slat", slat_x, 6.55, 2.94, 0.14, 1.95, 0.13, wood)
        counter_x = unit_x + unit_side * 2.55
        box("town_outdoor_counter", counter_x, 6.55, 0.72, 0.72, 1.85, 0.86, stone)
        box("town_outdoor_grill", counter_x, 6.35, 1.22, 0.58, 0.72, 0.18, dark)
        box("town_outdoor_table", unit_x - unit_side * 0.65, 6.55, 0.78, 1.55, 0.82, 0.08, deck)
        box("town_outdoor_table_leg", unit_x - unit_side * 0.65, 6.55, 0.52, 0.16, 0.58, 0.42, granite)
        for bench_y in (6.02, 7.08):
            box("town_outdoor_bench", unit_x - unit_side * 0.65, bench_y, 0.54, 1.35, 0.30, 0.09, deck)

        # Finished front/rear planting and lawn areas per home.
        box("town_front_lawn", unit_side * 2.60, -7.05, 0.215, 4.90, 1.75, 0.05, lawn)
        bed_x = bay_x - unit_side * 0.25
        box("town_bay_planting_bed", bed_x, -5.48, 0.225, 2.90, 0.58, 0.055, mulch)
        for bed_hedge_offset in (-0.95, 0.0, 0.95):
            box("town_bay_bed_hedge", bed_x + bed_hedge_offset, -5.48, 0.42, 0.72, 0.36, 0.34, hedge, bevel=0.05)
        box("town_rear_lawn_strip", unit_x, 7.78, 0.215, 8.65, 0.58, 0.05, lawn)
        for planter_x in (door_x - 0.82, door_x + 0.82):
            box("town_porch_planter", planter_x, -5.75, 0.56, 0.50, 0.42, 0.28, granite)
            box("town_porch_planter_soil", planter_x, -5.75, 0.71, 0.42, 0.34, 0.040, mulch)
            box("town_porch_planter_hedge", planter_x, -5.75, 0.83, 0.40, 0.28, 0.22, hedge, bevel=0.040)
        for hedge_x in (unit_side * 1.35, unit_side * 3.05):
            box("town_front_hedge", hedge_x, -7.55, 0.52, 1.35, 0.34, 0.50, hedge, bevel=0.05)

    # Boundary walls and gates. Driveways and both pedestrian paths are
    # left open; the timber pedestrian gates are parked ajar.
    def boundary_wall(cx, cy, dx, dy):
        box("town_boundary_wall", cx, cy, 0.58, dx, dy, 0.72, stone)
        box("town_boundary_coping", cx, cy, 0.99, dx + 0.07, dy + 0.07, 0.09, granite)

    boundary_wall(0.0, -8.00, 7.20, 0.20)
    boundary_wall(-5.12, -8.00, 0.38, 0.20)
    boundary_wall(5.12, -8.00, 0.38, 0.20)
    boundary_wall(-9.05, -8.00, 0.70, 0.20)
    boundary_wall(9.05, -8.00, 0.70, 0.20)
    boundary_wall(-9.30, 0.0, 0.20, 16.20)
    boundary_wall(9.30, 0.0, 0.20, 16.20)
    boundary_wall(0.0, 8.00, 18.80, 0.20)
    boundary_wall(0.0, 6.78, 0.16, 2.45)
    for pillar_x in (-8.68, -5.32, -3.62, 3.62, 5.32, 8.68):
        box("town_gate_pillar", pillar_x, -8.00, 0.72, 0.36, 0.36, 1.02, granite)
        box("town_gate_pillar_cap", pillar_x, -8.00, 1.29, 0.46, 0.46, 0.10, trim)
        box("town_gate_pillar_light", pillar_x, -8.20, 1.00, 0.16, 0.035, 0.22, glow)
    for gate_side in (-1.0, 1.0):
        rbox("town_pedestrian_gate", gate_side * 3.86, -7.58, 0.82, 1.08, 0.06, 1.02, wood, rotation=(0.0, 0.0, gate_side * 0.48))
        box("town_driveway_gate_track", gate_side * 8.92, -6.70, 0.25, 0.15, 2.55, 0.035, metal)
        box("town_driveway_gate_panel", gate_side * 9.02, -6.70, 0.92, 0.07, 2.45, 1.22, wood)
        box("town_driveway_gate_rail", gate_side * 9.02, -6.70, 1.58, 0.10, 2.55, 0.08, frame)


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
# Building Model No.4 — detailed fixed-scale glass district tower.
# Planned envelope: 34.00 x 34.00 m, 72.90 m high. A two-storey stone
# podium carries two set-back curtain-wall shaft tiers and a mechanical
# crown; the runtime places the finished design at scale 1.0. The old
# finned-glass proxy is preserved below only for the separate 148 m
# landmark, whose own detailed pass remains a future building.
# --------------------------------------------------------------------------- #
def build_glass_tower():
    glass = MATS["TowerGlass"]
    spandrel = MATS["TowerSpandrel"]
    stone = MATS["TowerStone"]
    trim = MATS["TowerTrim"]
    tower_metal = MATS["TowerMetal"]
    core = MATS["VillaInterior"]
    curtain = MATS["VillaCurtain"]
    granite = MATS["VillaGranite"]
    frame = MATS["WindowFrame"]
    pavement = MATS["VillaPavement"]
    lawn = MATS["VillaLawn"]
    hedge = MATS["VillaHedge"]
    mulch = MATS["VillaMulch"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    glow = MATS["LampGlow"]
    wood = MATS["VillaWood"]

    def curtain_tier(half, z_bottom, z_top, floors, seed):
        height = z_top - z_bottom
        centre_z = (z_bottom + z_top) * 0.5
        floor_h = height / float(floors)
        box("tower_shaft_core", 0.0, 0.0, centre_z, half * 2.0 - 0.30, half * 2.0 - 0.30, height, core, bevel=0.035)
        # Four continuous glass skins over a dark occupied core. Floor
        # slabs, continuous mullions, feature fins and varied interior
        # blind/lit panels give the curtain wall its scale without a
        # separate deep window assembly for every office pane.
        for axis in ("y", "x"):
            for sign in (-1.0, 1.0):
                if axis == "y":
                    box("tower_curtain_glass", 0.0, sign * (half + 0.020), centre_z, half * 2.0, 0.080, height, glass)
                else:
                    box("tower_curtain_glass", sign * (half + 0.020), 0.0, centre_z, 0.080, half * 2.0, height, glass)
                for offset_ratio in (-0.75, -0.50, -0.25, 0.0, 0.25, 0.50, 0.75):
                    offset = offset_ratio * half
                    if axis == "y":
                        box("tower_curtain_mullion", offset, sign * (half + 0.085), centre_z, 0.110, 0.150, height, frame)
                    else:
                        box("tower_curtain_mullion", sign * (half + 0.085), offset, centre_z, 0.150, 0.110, height, frame)
                for fin_ratio in (-0.50, 0.0, 0.50):
                    fin_offset = fin_ratio * half
                    if axis == "y":
                        box("tower_feature_fin", fin_offset, sign * (half + 0.270), centre_z, 0.300, 0.500, height, tower_metal)
                        if fin_ratio == 0.0:
                            box("tower_feature_light", fin_offset, sign * (half + 0.535), centre_z, 0.075, 0.035, height * 0.94, glow)
                    else:
                        box("tower_feature_fin", sign * (half + 0.270), fin_offset, centre_z, 0.500, 0.300, height, tower_metal)
                        if fin_ratio == 0.0:
                            box("tower_feature_light", sign * (half + 0.535), fin_offset, centre_z, 0.035, 0.075, height * 0.94, glow)
        for slab_index in range(floors + 1):
            slab_z = z_bottom + slab_index * floor_h
            box("tower_floor_spandrel", 0.0, 0.0, slab_z, half * 2.0 + 0.35, half * 2.0 + 0.35, 0.270, spandrel)
        for corner_x in (-1.0, 1.0):
            for corner_y in (-1.0, 1.0):
                box("tower_corner_pier", corner_x * (half - 0.050), corner_y * (half - 0.050), centre_z, 0.850, 0.850, height, trim)
        for floor_index in range(floors):
            panel_z = z_bottom + (floor_index + 0.52) * floor_h
            for face_index, (axis, sign) in enumerate((("y", -1.0), ("y", 1.0), ("x", -1.0), ("x", 1.0))):
                pattern = (floor_index * 3 + face_index * 2 + seed) % 5
                panel_specs = ((-0.46, 0.48), (0.34, 0.36)) if pattern in (0, 1) else ((-0.18, 0.72),)
                for panel_ratio, panel_width_ratio in panel_specs:
                    panel_offset = panel_ratio * half
                    panel_width = panel_width_ratio * half
                    panel_material = glow if pattern == 0 else (curtain if pattern in (1, 2) else spandrel)
                    if axis == "y":
                        box("tower_interior_panel", panel_offset, sign * (half - 0.085), panel_z, panel_width, 0.030, 1.12, panel_material)
                    else:
                        box("tower_interior_panel", sign * (half - 0.085), panel_offset, panel_z, 0.030, panel_width, 1.12, panel_material)

    def podium_bay(face, offset):
        sign = -1.0 if face in ("front", "left") else 1.0
        if face in ("front", "back"):
            box("tower_podium_bay_interior", offset, sign * 15.540, 3.15, 3.55, 0.040, 4.65, core)
            box("tower_podium_bay_glass", offset, sign * 15.600, 3.15, 3.55, 0.060, 4.65, glass)
            box("tower_podium_bay_mullion", offset, sign * 15.645, 3.15, 0.065, 0.055, 4.65, frame)
            box("tower_podium_bay_transom", offset, sign * 15.645, 4.55, 3.55, 0.055, 0.065, frame)
            box("tower_podium_bay_sill", offset, sign * 15.610, 0.78, 3.75, 0.18, 0.10, trim)
        else:
            box("tower_podium_bay_interior", sign * 15.540, offset, 3.15, 0.040, 3.55, 4.65, core)
            box("tower_podium_bay_glass", sign * 15.600, offset, 3.15, 0.060, 3.55, 4.65, glass)
            box("tower_podium_bay_mullion", sign * 15.645, offset, 3.15, 0.055, 0.065, 4.65, frame)
            box("tower_podium_bay_transom", sign * 15.645, offset, 4.55, 0.055, 3.55, 0.065, frame)
            box("tower_podium_bay_sill", sign * 15.610, offset, 0.78, 0.18, 3.75, 0.10, trim)

    # Plaza parcel and two-storey stone podium.
    box("tower_lot_plinth", 0.0, 0.0, 0.15, 34.00, 34.00, 0.30, granite, bevel=0.015)
    box("tower_podium", 0.0, 0.0, 3.75, 31.00, 31.00, 6.90, stone, bevel=0.030)
    box("tower_podium_cornice", 0.0, 0.0, 7.32, 31.70, 31.70, 0.28, trim)
    box("tower_podium_base_front", 0.0, -15.57, 0.52, 31.20, 0.15, 0.45, granite)
    box("tower_podium_base_rear", 0.0, 15.57, 0.52, 31.20, 0.15, 0.45, granite)
    for base_side in (-1.0, 1.0):
        box("tower_podium_base_side", base_side * 15.57, 0.0, 0.52, 0.15, 31.20, 0.45, granite)
    for column_offset in (-13.0, -8.67, -4.33, 4.33, 8.67, 13.0):
        box("tower_podium_column_front", column_offset, -15.62, 3.65, 0.95, 0.30, 5.70, trim)
        box("tower_podium_column_rear", column_offset, 15.62, 3.65, 0.95, 0.30, 5.70, trim)
        box("tower_podium_column_left", -15.62, column_offset, 3.65, 0.30, 0.95, 5.70, trim)
        box("tower_podium_column_right", 15.62, column_offset, 3.65, 0.30, 0.95, 5.70, trim)
    for bay_offset in (-10.83, -6.50, -2.17, 2.17, 6.50, 10.83):
        podium_bay("front", bay_offset)
        podium_bay("left", bay_offset)
        podium_bay("right", bay_offset)
    for bay_offset in (-10.83, -6.50, -2.17, 2.17):
        podium_bay("back", bay_offset)
    for strip_sign in (-1.0, 1.0):
        box("tower_podium_clerestory", 0.0, strip_sign * 15.575, 6.35, 27.00, 0.060, 0.75, glass)
        box("tower_podium_clerestory_side", strip_sign * 15.575, 0.0, 6.35, 0.060, 27.00, 0.75, glass)
    box("tower_sign_band", 0.0, -15.700, 5.78, 10.20, 0.180, 0.78, tower_metal)
    box("tower_sign_glow", 0.0, -15.800, 5.78, 9.55, 0.035, 0.28, glow)
    for banner_side in (-1.0, 1.0):
        box("tower_entry_banner", banner_side * 5.85, -15.720, 5.20, 0.78, 0.055, 2.15, spandrel)
        box("tower_entry_banner_stripe", banner_side * 5.85, -15.755, 5.20, 0.14, 0.025, 1.85, glow)

    # Main entrance: stone header, canopy on columns/tie rods, steps,
    # ramp and paired lobby-door handles behind the podium glazing.
    box("tower_entry_header", 0.0, -15.700, 5.12, 9.60, 0.35, 0.58, trim)
    box("tower_entry_canopy", 0.0, -16.150, 4.66, 9.80, 1.35, 0.22, granite, bevel=0.020)
    box("tower_entry_canopy_soffit", 0.0, -16.150, 4.52, 9.35, 1.18, 0.055, wood)
    for column_side in (-1.0, 1.0):
        column_x = column_side * 4.40
        box("tower_entry_column_base", column_x, -16.55, 0.48, 0.38, 0.38, 0.36, granite)
        cyl("tower_entry_column", column_x, -16.55, 2.50, 0.120, 3.95, tower_metal, vertices=14)
        tube_between("tower_entry_tie_rod", (column_x, -16.55, 4.50), (column_x, -15.55, 5.55), 0.025, 0.025, tower_metal, vertices=8)
        cyl("tower_lobby_door_handle", column_side * 0.35, -15.700, 1.55, 0.024, 0.92, metal, vertices=10)
    for step_index, (step_y, step_top) in enumerate(((-15.85, 0.75), (-16.30, 0.60), (-16.72, 0.45))):
        box("tower_entry_step", 0.0, step_y, (0.30 + step_top) / 2.0, 7.40 - step_index * 0.40, 0.48, step_top - 0.30, pavement)
    box("tower_address_plaque", -4.95, -15.720, 1.75, 0.62, 0.060, 0.85, granite)
    box("tower_address_inset", -4.95, -15.760, 1.75, 0.40, 0.025, 0.56, metal)

    # Rear service door, loading dock and side parking-garage portal.
    box("tower_service_portal", 8.70, 15.600, 2.05, 4.35, 0.18, 3.45, trim)
    box("tower_service_door", 8.70, 15.680, 1.98, 3.85, 0.10, 3.10, tower_metal, bevel=0.010)
    for seam_z in (1.10, 1.95, 2.80):
        box("tower_service_door_seam", 8.70, 15.740, seam_z, 3.75, 0.025, 0.045, frame)
    box("tower_loading_dock", 8.70, 16.15, 0.50, 5.40, 1.30, 0.42, pavement)
    box("tower_service_canopy", 8.70, 16.05, 3.95, 5.20, 1.05, 0.15, granite)
    box("tower_garage_portal", 15.600, 8.00, 2.00, 0.18, 5.00, 3.40, trim)
    box("tower_garage_door", 15.680, 8.00, 1.95, 0.10, 4.45, 3.05, tower_metal, bevel=0.010)
    for seam_y in (6.85, 8.00, 9.15):
        box("tower_garage_door_seam", 15.740, seam_y, 1.95, 0.025, 0.045, 2.95, frame)
    rbox("tower_garage_ramp", 16.25, 8.00, 0.38, 1.35, 5.30, 0.12, pavement, rotation=(0.0, 0.11, 0.0))
    for bin_x in (-12.20, -10.00):
        box("tower_waste_bin", bin_x, 16.15, 0.82, 1.85, 1.00, 1.08, dark, bevel=0.025)
        box("tower_waste_bin_lid", bin_x, 16.15, 1.40, 1.92, 1.05, 0.09, tower_metal)

    # Two shaft tiers and the setback between them.
    curtain_tier(13.00, 7.35, 41.85, 10, 1)
    box("tower_setback_slab", 0.0, 0.0, 42.05, 27.40, 27.40, 0.45, trim)
    curtain_tier(11.00, 42.30, 66.45, 7, 3)

    # Podium and setback roof terraces: glass rails, planters and plant.
    for rail_sign in (-1.0, 1.0):
        box("tower_podium_roof_rail", 0.0, rail_sign * 15.25, 7.82, 29.40, 0.055, 0.78, glass)
        box("tower_podium_roof_rail_side", rail_sign * 15.25, 0.0, 7.82, 0.055, 29.40, 0.78, glass)
        box("tower_podium_roof_toprail", 0.0, rail_sign * 15.25, 8.25, 29.55, 0.075, 0.065, frame)
        box("tower_podium_roof_toprail_side", rail_sign * 15.25, 0.0, 8.25, 0.075, 29.55, 0.065, frame)
        box("tower_setback_rail", 0.0, rail_sign * 13.35, 42.75, 25.80, 0.055, 0.78, glass)
        box("tower_setback_rail_side", rail_sign * 13.35, 0.0, 42.75, 0.055, 25.80, 0.78, glass)
        box("tower_setback_toprail", 0.0, rail_sign * 13.35, 43.18, 25.95, 0.075, 0.065, frame)
        box("tower_setback_toprail_side", rail_sign * 13.35, 0.0, 43.18, 0.075, 25.95, 0.065, frame)
    for planter_x in (-10.0, -5.0, 5.0, 10.0):
        for planter_y in (-14.25, 14.25):
            box("tower_podium_roof_planter", planter_x, planter_y, 7.62, 1.90, 0.72, 0.48, granite)
            box("tower_podium_roof_hedge", planter_x, planter_y, 7.96, 1.66, 0.50, 0.30, hedge, bevel=0.040)
        for planter_y in (-12.25, 12.25):
            box("tower_setback_planter", planter_x, planter_y, 42.55, 1.75, 0.68, 0.45, granite)
            box("tower_setback_hedge", planter_x, planter_y, 42.87, 1.52, 0.48, 0.28, hedge, bevel=0.038)
    for hvac_x, hvac_y in ((-14.30, -8.00), (-14.30, 8.00), (14.30, -8.00), (14.30, 8.00)):
        box("tower_podium_hvac", hvac_x, hvac_y, 7.78, 1.60, 1.45, 0.92, metal, bevel=0.018)
        cyl("tower_podium_hvac_fan", hvac_x, hvac_y, 8.27, 0.32, 0.045, frame, vertices=16)
    for post_x in (-7.0, 7.0):
        for post_y in (-12.85, -11.55):
            box("tower_setback_pergola_post", post_x, post_y, 43.35, 0.15, 0.15, 2.05, wood)
    for beam_y in (-12.88, -11.52):
        box("tower_setback_pergola_beam", 0.0, beam_y, 44.45, 15.20, 0.16, 0.17, wood)
    for slat_index in range(8):
        box("tower_setback_pergola_slat", -6.65 + slat_index * 1.90, -12.20, 44.60, 0.14, 1.58, 0.12, wood)

    # Mechanical crown, corner fins, cooling towers, helipad and mast.
    box("tower_crown_frame", 0.0, 0.0, 66.65, 19.40, 19.40, 0.40, trim)
    box("tower_mechanical_penthouse", 0.0, 0.0, 68.65, 14.50, 14.50, 3.60, spandrel, bevel=0.020)
    box("tower_mechanical_roof", 0.0, 0.0, 70.60, 15.30, 15.30, 0.30, trim)
    for louvre_z in (67.85, 68.45, 69.05, 69.65):
        box("tower_crown_louvre_front", 0.0, -7.30, louvre_z, 11.80, 0.10, 0.16, frame)
        box("tower_crown_louvre_rear", 0.0, 7.30, louvre_z, 11.80, 0.10, 0.16, frame)
        box("tower_crown_louvre_left", -7.30, 0.0, louvre_z, 0.10, 11.80, 0.16, frame)
        box("tower_crown_louvre_right", 7.30, 0.0, louvre_z, 0.10, 11.80, 0.16, frame)
    for fin_x in (-9.35, 9.35):
        for fin_y in (-9.35, 9.35):
            box("tower_crown_fin", fin_x, fin_y, 68.98, 0.55, 0.55, 5.15, tower_metal)
            box("tower_crown_fin_light", fin_x, fin_y, 71.62, 0.34, 0.34, 0.14, glow)
    for rail_sign in (-1.0, 1.0):
        box("tower_crown_rail", 0.0, rail_sign * 9.45, 67.30, 18.20, 0.050, 0.72, glass)
        box("tower_crown_rail_side", rail_sign * 9.45, 0.0, 67.30, 0.050, 18.20, 0.72, glass)
    for tower_x, tower_y in ((8.45, -4.00), (-8.45, 4.00)):
        cyl("tower_cooling_tower", tower_x, tower_y, 67.82, 0.86, 1.92, metal, vertices=18)
        cyl("tower_cooling_fan", tower_x, tower_y, 68.82, 0.55, 0.06, frame, vertices=18)
    cyl("tower_helipad", 0.0, 0.0, 70.82, 5.35, 0.12, dark, vertices=36)
    cyl("tower_helipad_ring", 0.0, 0.0, 70.90, 4.35, 0.035, trim, vertices=36)
    cyl("tower_helipad_centre", 0.0, 0.0, 70.925, 3.95, 0.030, dark, vertices=36)
    for h_side in (-0.85, 0.85):
        box("tower_helipad_h_leg", h_side, 0.0, 70.95, 0.45, 3.10, 0.035, glow)
    box("tower_helipad_h_cross", 0.0, 0.0, 70.95, 2.10, 0.45, 0.035, glow)
    cyl("tower_mast", 8.85, 8.85, 69.72, 0.075, 5.75, tower_metal, vertices=10)
    box("tower_beacon", 8.85, 8.85, 72.75, 0.30, 0.30, 0.30, glow)

    # Forecourt, lit bollards, benches and narrow landscape strips.
    box("tower_forecourt_paving", 0.0, -16.15, 0.345, 24.00, 1.55, 0.07, pavement)
    box("tower_dropoff_strip", 0.0, -16.88, 0.335, 18.00, 0.22, 0.05, granite)
    box("tower_rear_paving", 0.0, 16.20, 0.345, 23.00, 1.45, 0.07, pavement)
    for landscape_side in (-1.0, 1.0):
        box("tower_side_lawn", landscape_side * 16.25, 0.0, 0.345, 1.30, 24.00, 0.06, lawn)
        for hedge_y in (-9.0, -3.0, 3.0, 9.0):
            if landscape_side > 0.0 and hedge_y == 9.0:
                continue
            box("tower_side_hedge", landscape_side * 16.25, hedge_y, 0.62, 0.82, 3.10, 0.48, hedge, bevel=0.055)
    for planter_x in (-11.0, -7.0, 7.0, 11.0):
        box("tower_front_planter", planter_x, -16.25, 0.58, 1.90, 0.80, 0.52, granite)
        box("tower_front_planter_soil", planter_x, -16.25, 0.86, 1.72, 0.62, 0.045, mulch)
        box("tower_front_planter_hedge", planter_x, -16.25, 1.02, 1.60, 0.52, 0.32, hedge, bevel=0.045)
    for bollard_x in (-9.0, -6.0, -3.0, 3.0, 6.0, 9.0):
        cyl("tower_front_bollard", bollard_x, -16.78, 0.68, 0.085, 0.76, tower_metal, vertices=12)
        box("tower_front_bollard_light", bollard_x, -16.78, 1.08, 0.10, 0.10, 0.045, glow)
    for bench_x in (-12.20, 12.20):
        box("tower_front_bench", bench_x, -16.05, 0.58, 2.20, 0.50, 0.10, wood)
        box("tower_front_bench_base", bench_x, -16.05, 0.42, 1.80, 0.36, 0.24, granite)
    for rear_hedge_x in (-14.0, -4.5, 0.5, 13.5):
        box("tower_rear_hedge", rear_hedge_x, 16.35, 0.60, 2.60, 0.55, 0.52, hedge, bevel=0.055)

# --------------------------------------------------------------------------- #
# Legacy 148 m landmark massing, preserved until its own detailed pass.
# It is deliberately separate so Building Model No.4 is never stretched
# vertically into the main tower; only the landmark transform scales it.
# --------------------------------------------------------------------------- #
def build_main_tower_legacy():
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
        (build_main_tower_legacy, "main_tower.glb"),
    ):
        reset_scene()
        standard_mats()
        build()
        export(out_dir, filename)
    print("[props] done ->", out_dir)


main()
