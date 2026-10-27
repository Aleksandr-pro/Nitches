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
  * main_tower.glb    Building Model No.5: fixed-scale sculptural 148 m flagship tower
  * opera_house.glb   Building Model No.6: fixed-scale RichTown Opera
  * mosque.glb        Building Model No.7: fixed-scale RichTown Mosque
  * palm_date.glb / palm_royal.glb
                      botanically structured palms with curved segmented
                      trunks, individual pinnate leaflets and crown detail
  * grass_tuft.glb / flower_clump.glb / ornamental_shrub.glb
                      geometric ground-cover models (no flat alpha cards)
  * park_bench.glb / park_pergola.glb
                      cast-iron/timber bench and stone/timber park pergola
"""
import math
import os
import random
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
    mat("MainGlass", (0.09, 0.27, 0.34), roughness=0.07, metallic=0.18)
    mat("MainSpandrel", (0.06, 0.10, 0.15), roughness=0.30, metallic=0.55)
    mat("MainStone", (0.62, 0.58, 0.50), roughness=0.90, metallic=0.0)
    mat("MainTrim", (0.78, 0.68, 0.48), roughness=0.38, metallic=0.45)
    mat("MainMetal", (0.12, 0.14, 0.16), roughness=0.40, metallic=0.75)
    mat("MainWater", (0.05, 0.28, 0.36), roughness=0.05, metallic=0.10)
    # Building Model No.6 is a ceramic-shell opera house.  Its warm
    # white pleated vaults, travertine podium, bronze structure and
    # inhabited glass foyer remain physically separated in the GLB so
    # Godot can assign real-metre photographic PBR materials to each.
    mat("OperaShell", (0.88, 0.83, 0.74), roughness=0.42, metallic=0.05)
    mat("OperaStone", (0.72, 0.64, 0.50), roughness=0.88)
    mat("OperaBronze", (0.48, 0.29, 0.13), roughness=0.34, metallic=0.82)
    mat("OperaGlass", (0.12, 0.28, 0.34), roughness=0.06, metallic=0.12)
    mat("OperaInterior", (0.10, 0.07, 0.045), roughness=0.94)
    mat("OperaWood", (0.42, 0.22, 0.10), roughness=0.78)
    mat("OperaGranite", (0.055, 0.06, 0.065), roughness=0.42, metallic=0.10)
    mat("OperaCurtain", (0.34, 0.025, 0.04), roughness=0.98)
    mat("OperaWater", (0.05, 0.24, 0.32), roughness=0.06, metallic=0.08)
    mat("OperaLight", (1.0, 0.72, 0.38), roughness=0.32, emission=(1.0, 0.55, 0.20))
    # Building Model No.7 is an original contemporary RichTown mosque:
    # warm carved sandstone, pale limestone dressings, a patinated
    # turquoise ribbed dome, brass screens/finials, glazed turquoise
    # tile bands and dark cedar doors.  Semantic material separation
    # lets Godot assign world-scale photographic PBR surfaces rather
    # than one sand-coloured primitive material.
    mat("MosqueStone", (0.78, 0.68, 0.52), roughness=0.92)
    mat("MosqueLimestone", (0.86, 0.79, 0.65), roughness=0.88)
    mat("MosqueDome", (0.05, 0.42, 0.45), roughness=0.34, metallic=0.65)
    mat("MosqueBrass", (0.62, 0.39, 0.14), roughness=0.32, metallic=0.85)
    mat("MosqueGlass", (0.08, 0.25, 0.30), roughness=0.07, metallic=0.15)
    mat("MosqueInterior", (0.09, 0.065, 0.045), roughness=0.96)
    mat("MosqueWood", (0.32, 0.16, 0.07), roughness=0.78)
    mat("MosqueTile", (0.04, 0.48, 0.52), roughness=0.24, metallic=0.05)
    mat("MosqueGranite", (0.05, 0.055, 0.06), roughness=0.42, metallic=0.08)
    mat("MosqueLight", (1.0, 0.72, 0.38), roughness=0.32, emission=(1.0, 0.55, 0.20))
    # The traffic signals are deliberately NOT an animated system yet.
    # Only the red lens material emits; amber and green remain dark.
    mat("SignalMetal", (0.36, 0.39, 0.42), roughness=0.34, metallic=0.9)
    mat("SignalHousing", (0.025, 0.028, 0.03), roughness=0.58, metallic=0.05)
    mat("SignalRedOn", (0.45, 0.015, 0.01), roughness=0.25, emission=(1.0, 0.02, 0.01))
    mat("SignalAmberOff", (0.22, 0.09, 0.005), roughness=0.2)
    mat("SignalGreenOff", (0.005, 0.13, 0.045), roughness=0.2)
    mat("SignalReflector", (0.85, 0.62, 0.05), roughness=0.42)
    mat("SignalCable", (0.01, 0.01, 0.012), roughness=0.72)
    # 0.2.17 vegetation is real merged geometry, not alpha-card fans.
    # Semantic names let Godot assign bark/foliage/stem/flower PBR
    # materials without turning every leaflet into a Blender object.
    mat("PalmTrunk", (0.31, 0.21, 0.12), roughness=0.97)
    mat("PalmCrown", (0.25, 0.20, 0.11), roughness=0.96)
    mat("PalmCrownshaft", (0.20, 0.36, 0.15), roughness=0.78)
    mat("PalmLeaf", (0.06, 0.26, 0.06), roughness=0.92)
    mat("PalmLeafDry", (0.48, 0.34, 0.15), roughness=1.0)
    mat("PalmRachis", (0.20, 0.24, 0.09), roughness=0.90)
    mat("PalmFruit", (0.68, 0.27, 0.05), roughness=0.58)
    mat("GrassBlade", (0.07, 0.29, 0.06), roughness=1.0)
    mat("GrassBladeDry", (0.43, 0.37, 0.14), roughness=1.0)
    mat("OrnamentalLeaf", (0.05, 0.24, 0.07), roughness=0.95)
    mat("ShrubBranch", (0.17, 0.10, 0.05), roughness=1.0)
    mat("ShrubBerry", (0.50, 0.07, 0.16), roughness=0.52)
    mat("FlowerLeaf", (0.06, 0.26, 0.07), roughness=0.95)
    mat("FlowerCoral", (0.80, 0.17, 0.11), roughness=0.72)
    mat("FlowerWhite", (0.90, 0.83, 0.69), roughness=0.76)
    mat("FlowerYellow", (0.87, 0.58, 0.07), roughness=0.70)
    mat("FlowerCentre", (0.56, 0.27, 0.03), roughness=0.80)


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


class MeshBuilder:
    """Small merged-mesh builder for botanical geometry.

    Palms and ground cover need thousands of leaflets/blades.  Creating a
    Blender object for every leaflet made the old sources slow and
    difficult to inspect and produced enormous node lists.  This builder
    accumulates indexed faces and per-loop UVs, then emits one object
    per semantic material.
    """

    def __init__(self):
        self.vertices = []
        self.faces = []
        self.loop_uvs = []

    def add_vertex(self, point):
        self.vertices.append((float(point.x), float(point.y), float(point.z)))
        return len(self.vertices) - 1

    def add_face(self, indices, uvs):
        if len(indices) != len(uvs):
            raise ValueError("MeshBuilder face/UV count mismatch")
        self.faces.append(tuple(indices))
        self.loop_uvs.extend((float(uv[0]), float(uv[1])) for uv in uvs)

    def tri(self, a, b, c, uvs=((0.0, 0.0), (1.0, 0.0), (0.5, 1.0))):
        self.add_face((a, b, c), uvs)

    def quad(self, a, b, c, d, uvs=((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        self.add_face((a, b, c, d), uvs)

    def build(self, name, material, smooth=True):
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        uv_layer = mesh.uv_layers.new(name="UVMap")
        for index, uv_value in enumerate(self.loop_uvs):
            if index < len(uv_layer.data):
                uv_layer.data[index].uv = uv_value
        if material is not None:
            mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        if smooth:
            for polygon in mesh.polygons:
                polygon.use_smooth = True
        return obj


def _curve_frames(points):
    frames = []
    previous_normal = None
    for index in range(len(points)):
        before = points[max(index - 1, 0)]
        after = points[min(index + 1, len(points) - 1)]
        tangent = after - before
        if tangent.length <= 0.00001:
            tangent = Vector((0.0, 0.0, 1.0))
        tangent.normalize()
        if previous_normal is None:
            reference = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.85 else Vector((0.0, 1.0, 0.0))
            normal = reference - tangent * reference.dot(tangent)
        else:
            normal = previous_normal - tangent * previous_normal.dot(tangent)
            if normal.length <= 0.00001:
                reference = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.85 else Vector((0.0, 1.0, 0.0))
                normal = reference - tangent * reference.dot(tangent)
        if normal.length <= 0.00001:
            normal = Vector((1.0, 0.0, 0.0))
        normal.normalize()
        binormal = tangent.cross(normal)
        if binormal.length <= 0.00001:
            binormal = Vector((0.0, 1.0, 0.0))
        binormal.normalize()
        frames.append((tangent, normal, binormal))
        previous_normal = normal
    return frames


def builder_tube(builder, points, radii, sides=10, uv_u_repeat=1.0, uv_v_scale=1.0,
                 radius_variation=None, cap_start=True, cap_end=True):
    """Append a parallel-transport tube to a MeshBuilder."""
    if len(points) < 2:
        return []
    frames = _curve_frames(points)
    rings = []
    distances = [0.0]
    for index in range(1, len(points)):
        distances.append(distances[-1] + (points[index] - points[index - 1]).length)
    for point_index, point in enumerate(points):
        _, normal, binormal = frames[point_index]
        radius_value = radii[min(point_index, len(radii) - 1)]
        if isinstance(radius_value, (tuple, list)):
            radius_x, radius_y = float(radius_value[0]), float(radius_value[1])
        else:
            radius_x = radius_y = float(radius_value)
        t = point_index / float(max(len(points) - 1, 1))
        ring = []
        for side_index in range(sides):
            angle = math.tau * float(side_index) / float(sides)
            variation = 1.0
            if radius_variation is not None:
                variation = float(radius_variation(point_index, angle, t))
            offset = (normal * (math.cos(angle) * radius_x) +
                      binormal * (math.sin(angle) * radius_y)) * variation
            ring.append(builder.add_vertex(point + offset))
        rings.append(ring)
    for segment in range(len(points) - 1):
        v0 = distances[segment] * uv_v_scale
        v1 = distances[segment + 1] * uv_v_scale
        for side_index in range(sides):
            next_side = (side_index + 1) % sides
            u0 = float(side_index) / float(sides) * uv_u_repeat
            u1 = float(side_index + 1) / float(sides) * uv_u_repeat
            builder.quad(
                rings[segment][side_index], rings[segment][next_side],
                rings[segment + 1][next_side], rings[segment + 1][side_index],
                ((u0, v0), (u1, v0), (u1, v1), (u0, v1)),
            )
    if cap_start:
        centre = builder.add_vertex(points[0])
        for side_index in range(sides):
            next_side = (side_index + 1) % sides
            builder.tri(centre, rings[0][next_side], rings[0][side_index])
    if cap_end:
        centre = builder.add_vertex(points[-1])
        for side_index in range(sides):
            next_side = (side_index + 1) % sides
            builder.tri(centre, rings[-1][side_index], rings[-1][next_side])
    return rings


def cubic_point(p0, p1, p2, p3, t):
    mt = 1.0 - t
    return (p0 * (mt * mt * mt) + p1 * (3.0 * mt * mt * t) +
            p2 * (3.0 * mt * t * t) + p3 * (t * t * t))


def cubic_tangent(p0, p1, p2, p3, t):
    mt = 1.0 - t
    tangent = ((p1 - p0) * (3.0 * mt * mt) + (p2 - p1) * (6.0 * mt * t) +
               (p3 - p2) * (3.0 * t * t))
    if tangent.length <= 0.00001:
        return Vector((0.0, 0.0, 1.0))
    return tangent.normalized()


def cubic_points(p0, p1, p2, p3, count):
    return [cubic_point(p0, p1, p2, p3, index / float(max(count - 1, 1))) for index in range(count)]


def builder_folded_leaf(builder, centres, half_widths, width_hint,
                        fold_ratio=0.34, uv_v_offset=0.0):
    """Append a lengthwise-folded ribbon leaf/blade.

    The last centre can use zero half-width to terminate in a real
    pointed tip.  Three centre stations therefore make six triangles:
    two folded quads plus the two tip triangles.
    """
    if len(centres) < 2 or len(centres) != len(half_widths):
        return
    rows = []
    for index, centre in enumerate(centres):
        before = centres[max(index - 1, 0)]
        after = centres[min(index + 1, len(centres) - 1)]
        tangent = after - before
        if tangent.length <= 0.00001:
            tangent = Vector((0.0, 0.0, 1.0))
        tangent.normalize()
        width_dir = width_hint - tangent * width_hint.dot(tangent)
        if width_dir.length <= 0.00001:
            width_dir = Vector((1.0, 0.0, 0.0)) - tangent * tangent.x
        if width_dir.length <= 0.00001:
            width_dir = Vector((0.0, 1.0, 0.0))
        width_dir.normalize()
        fold_dir = tangent.cross(width_dir)
        if fold_dir.length <= 0.00001:
            fold_dir = Vector((0.0, 0.0, 1.0))
        fold_dir.normalize()
        half_width = float(half_widths[index])
        if half_width <= 0.0005:
            rows.append((builder.add_vertex(centre),))
        else:
            rows.append((
                builder.add_vertex(centre - width_dir * half_width),
                builder.add_vertex(centre + fold_dir * half_width * fold_ratio),
                builder.add_vertex(centre + width_dir * half_width),
            ))
    for index in range(len(rows) - 1):
        current = rows[index]
        following = rows[index + 1]
        v0 = uv_v_offset + float(index) / float(len(rows) - 1)
        v1 = uv_v_offset + float(index + 1) / float(len(rows) - 1)
        if len(current) == 3 and len(following) == 3:
            builder.quad(current[0], following[0], following[1], current[1],
                         ((0.0, v0), (0.0, v1), (0.5, v1), (0.5, v0)))
            builder.quad(current[1], following[1], following[2], current[2],
                         ((0.5, v0), (0.5, v1), (1.0, v1), (1.0, v0)))
        elif len(current) == 3 and len(following) == 1:
            tip = following[0]
            builder.tri(current[0], tip, current[1],
                        ((0.0, v0), (0.5, v1), (0.5, v0)))
            builder.tri(current[1], tip, current[2],
                        ((0.5, v0), (0.5, v1), (1.0, v0)))
        elif len(current) == 1 and len(following) == 3:
            base = current[0]
            builder.tri(base, following[0], following[1],
                        ((0.5, v0), (0.0, v1), (0.5, v1)))
            builder.tri(base, following[1], following[2],
                        ((0.5, v0), (0.5, v1), (1.0, v1)))


def builder_ellipsoid(builder, centre, radii, segments=6, yaw=0.0, pitch=0.0, rings=2):
    """Append a low-segment ellipsoid; rings=1 gives a pointed berry."""
    from mathutils import Euler
    rotation = Euler((pitch, 0.0, yaw), "XYZ").to_matrix()
    levels = [-0.5 * math.pi]
    if rings == 1:
        levels.append(0.0)
    else:
        levels.extend((-math.pi / 6.0, math.pi / 6.0))
    levels.append(0.5 * math.pi)
    vertex_rows = []
    for phi in levels:
        if abs(abs(phi) - math.pi * 0.5) < 0.0001:
            local = Vector((0.0, 0.0, radii[2] * (1.0 if phi > 0.0 else -1.0)))
            vertex_rows.append((builder.add_vertex(centre + rotation @ local),))
        else:
            row = []
            for side_index in range(segments):
                theta = math.tau * float(side_index) / float(segments)
                local = Vector((
                    radii[0] * math.cos(phi) * math.cos(theta),
                    radii[1] * math.cos(phi) * math.sin(theta),
                    radii[2] * math.sin(phi),
                ))
                row.append(builder.add_vertex(centre + rotation @ local))
            vertex_rows.append(tuple(row))
    for row_index in range(len(vertex_rows) - 1):
        current = vertex_rows[row_index]
        following = vertex_rows[row_index + 1]
        if len(current) == 1 and len(following) > 1:
            for side_index in range(segments):
                builder.tri(current[0], following[side_index], following[(side_index + 1) % segments])
        elif len(current) > 1 and len(following) == 1:
            for side_index in range(segments):
                builder.tri(current[side_index], following[0], current[(side_index + 1) % segments])
        elif len(current) > 1 and len(following) > 1:
            for side_index in range(segments):
                next_side = (side_index + 1) % segments
                builder.quad(current[side_index], current[next_side], following[next_side], following[side_index])


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
# enclosed air-conditioned bus shelter: 5.75 x 2.35 m, 3.06 m tall.
# 0.2.23 photoreal pass: the previous 816-triangle shell becomes a real
# framed glazing system -- segmented tempered panes with mullions and
# gaskets, two sliding glass doors per long face (tracks, pull handles,
# seals, motion sensors), a standing-seam roof with drip rails, a solar
# array with individual cells and bus bars, a louvred rooftop AC unit
# with a bladed fan, ceiling LED strips, interior vent slats, a slatted
# bench on three cast frames with visible fixings and a lit timetable
# case.  The exact outer envelope (5.75 x 2.35 x 3.06 m) is unchanged so
# the native colliders and placements from earlier releases stay exact.
# --------------------------------------------------------------------------- #
def build_shelter():
    metal = MATS["PropsMetal"]
    glass = MATS["PropsGlass"]
    wood = MATS["PropsWood"]
    dark = MATS["RoofDark"]
    glow = MATS["LampGlow"]
    solar = MATS["SolarCell"]

    # Raised platform with anti-slip nosings and a drainage slot each end.
    box("shelter_platform", 0, 0, 0.060, 5.45, 2.05, 0.12, dark, bevel=0.012)
    for strip_index in range(7):
        box("shelter_antislip", -2.10 + strip_index * 0.70, 0, 0.124,
            0.34, 1.86, 0.010, metal)
    for sx in (-2.62, 2.62):
        box("shelter_drain", sx, 0, 0.122, 0.10, 1.80, 0.008, dark)

    # Four square corner posts on base plates with anchor bolts.
    for sx in (-2.55, 2.55):
        for sy in (-0.88, 0.88):
            box("shelter_post", sx, sy, 1.340, 0.11, 0.11, 2.44, metal, bevel=0.014)
            box("shelter_post_plate", sx, sy, 0.135, 0.22, 0.22, 0.03, metal, bevel=0.008)
            for bx in (-0.07, 0.07):
                for by in (-0.07, 0.07):
                    cyl("shelter_post_bolt", sx + bx, sy + by, 0.16, 0.014, 0.025,
                        dark, vertices=6)

    # Roof build-up: soffit, main slab, drip rails and standing seams.
    box("shelter_soffit", 0, 0, 2.520, 5.55, 2.15, 0.08, metal, bevel=0.012)
    box("shelter_roof", 0, 0, 2.640, 5.75, 2.35, 0.12, metal, bevel=0.025)
    for sy in (-1.125, 1.125):
        box("shelter_drip_rail", 0, sy, 2.575, 5.62, 0.05, 0.045, dark)
    for seam_y in (-0.90, -0.45, 0.0, 0.45, 0.90):
        box("shelter_roof_seam", 0, seam_y, 2.712, 5.58, 0.035, 0.024, dark)

    # Rooftop solar array: framed panel, 18 individual cells, bus bars.
    box("shelter_solar_frame", 1.25, 0, 2.725, 2.45, 1.30, 0.045, dark, bevel=0.010)
    for cell_x in range(6):
        for cell_y in range(3):
            box("shelter_solar_cell", 0.27 + cell_x * 0.392, -0.405 + cell_y * 0.405,
                2.752, 0.35, 0.36, 0.012, solar)
    for bar_y in (-0.60, -0.20, 0.20, 0.60):
        box("shelter_solar_busbar", 1.25, bar_y, 2.756, 2.36, 0.018, 0.014, metal)

    # Rooftop AC unit with louvres, service panel and a bladed fan.
    box("shelter_ac_body", -1.70, 0, 2.860, 1.30, 0.80, 0.34, metal, bevel=0.020)
    box("shelter_ac_panel", -1.70, -0.412, 2.860, 1.05, 0.022, 0.26, dark)
    for louvre_index in range(6):
        box("shelter_ac_louvre", -1.70, -0.428, 2.755 + louvre_index * 0.042,
            0.95, 0.012, 0.020, metal)
    cyl("shelter_ac_fan_ring", -1.70, 0, 3.040, 0.27, 0.035, dark, vertices=24)
    cyl("shelter_ac_fan_hub", -1.70, 0, 3.047, 0.070, 0.022, metal, vertices=16)
    for blade_index in range(5):
        blade_angle = blade_index * math.tau / 5.0
        rbox("shelter_ac_fan_blade",
             -1.70 + math.cos(blade_angle) * 0.145,
             math.sin(blade_angle) * 0.145, 3.045,
             0.20, 0.075, 0.012, metal, rotation=(0.0, 0.0, blade_angle))

    # Long glazed faces: two framed panes per side bay, bottom and mid
    # rails, header and rubber gaskets, with a central sliding doorway.
    for sy in (-0.92, 0.92):
        outward = 1.0 if sy > 0.0 else -1.0
        box("shelter_bottom_rail", 0, sy, 0.235, 5.20, 0.085, 0.190, metal, bevel=0.010)
        box("shelter_header", 0, sy, 2.415, 5.20, 0.075, 0.150, metal, bevel=0.008)
        for bay_centre in (-1.67, 1.67):
            for pane_offset in (-0.495, 0.495):
                box("shelter_pane_long", bay_centre + pane_offset, sy, 1.310,
                    0.92, 0.035, 1.98, glass)
            box("shelter_midrail", bay_centre, sy, 1.120, 1.98, 0.055, 0.060, metal)
            for gasket_offset in (-0.995, 0.0, 0.995):
                box("shelter_gasket_long", bay_centre + gasket_offset, sy, 1.310,
                    0.028, 0.060, 2.02, dark)
        for mullion_x in (-2.62, -1.67, -0.68, 0.68, 1.67, 2.62):
            box("shelter_mullion_long", mullion_x, sy, 1.310, 0.070, 0.085, 2.10,
                metal, bevel=0.008)
        # Sliding door pair: glass leaves, seals, pulls, track and sensor.
        box("shelter_door_track", 0, sy, 2.360, 1.36, 0.100, 0.110, dark)
        box("shelter_door_guide", 0, sy, 0.130, 1.36, 0.070, 0.020, dark)
        for door_x in (-0.315, 0.315):
            box("shelter_door_leaf", door_x, sy, 1.250, 0.59, 0.040, 2.05, glass)
            box("shelter_door_seal_v", door_x * 2.0, sy, 1.250, 0.022, 0.055, 2.05, dark)
            box("shelter_door_seal_top", door_x, sy, 2.260, 0.59, 0.055, 0.030, dark)
            box("shelter_door_kick", door_x, sy + outward * 0.028, 0.330,
                0.50, 0.012, 0.16, metal)
            cyl("shelter_door_pull", door_x * 0.30, sy + outward * 0.075, 1.150,
                0.016, 0.78, metal, vertices=10)
            for mount_z in (0.820, 1.480):
                cyl("shelter_door_pull_mount", door_x * 0.30, sy + outward * 0.040,
                    mount_z, 0.012, 0.075, metal, vertices=8,
                    rotation=(math.pi / 2.0, 0.0, 0.0))
        box("shelter_door_sensor", 0, sy + outward * 0.055, 2.315,
            0.18, 0.045, 0.060, dark, bevel=0.008)
        box("shelter_door_sensor_eye", 0, sy + outward * 0.080, 2.300,
            0.07, 0.012, 0.025, glow)

    # Short glazed ends with a centre mullion and corner gaskets.
    for sx in (-2.62, 2.62):
        box("shelter_bottom_rail_end", sx, 0, 0.235, 0.085, 1.76, 0.190, metal, bevel=0.010)
        box("shelter_header_end", sx, 0, 2.415, 0.075, 1.76, 0.150, metal, bevel=0.008)
        box("shelter_midrail_end", sx, 0, 1.120, 0.055, 1.76, 0.060, metal)
        for pane_y in (-0.445, 0.445):
            box("shelter_pane_end", sx, pane_y, 1.310, 0.035, 0.82, 1.98, glass)
        for gasket_y in (-0.88, 0.0, 0.88):
            box("shelter_mullion_end", sx, gasket_y, 1.310, 0.070, 0.070, 2.10,
                metal, bevel=0.008)

    # Interior ceiling lights and the AC supply vent.
    for strip_y in (-0.52, 0.52):
        box("shelter_led_housing", 0, strip_y, 2.470, 4.70, 0.110, 0.030, dark)
        box("shelter_led_strip", 0, strip_y, 2.452, 4.55, 0.075, 0.012, glow)
    box("shelter_vent_body", -1.20, 0, 2.455, 1.15, 0.55, 0.045, metal)
    for vent_index in range(6):
        box("shelter_vent_slat", -1.20, -0.205 + vent_index * 0.082, 2.428,
            1.02, 0.028, 0.010, dark)

    # Slatted bench on three cast frames; every slat is bolted to a frame.
    seat_ys = (-0.700, -0.605, -0.510, -0.415, -0.320)
    for slat_y in seat_ys:
        box("shelter_bench_seat_slat", 0, slat_y, 0.615, 3.80, 0.075, 0.045,
            wood, bevel=0.008)
    for back_z in (0.840, 1.010, 1.180):
        box("shelter_bench_back_slat", 0, -0.745, back_z, 3.80, 0.045, 0.090,
            wood, bevel=0.008)
    for frame_x in (-1.65, 0.0, 1.65):
        box("shelter_bench_frame_front", frame_x, -0.335, 0.365, 0.070, 0.070, 0.47,
            metal, bevel=0.010)
        box("shelter_bench_frame_rear", frame_x, -0.715, 0.720, 0.070, 0.070, 1.18,
            metal, bevel=0.010)
        box("shelter_bench_frame_foot", frame_x, -0.510, 0.145, 0.090, 0.52, 0.035,
            metal, bevel=0.008)
        box("shelter_bench_frame_seatrail", frame_x, -0.510, 0.575, 0.060, 0.48, 0.045,
            metal, bevel=0.008)
        for slat_y in seat_ys:
            cyl("shelter_bench_bolt", frame_x, slat_y, 0.642, 0.011, 0.012,
                dark, vertices=6)

    # Lit timetable case with printed rows behind glass.
    box("shelter_info_frame", 2.30, 0.48, 1.350, 0.070, 0.95, 1.50, metal, bevel=0.012)
    box("shelter_info_back", 2.265, 0.48, 1.350, 0.020, 0.82, 1.36, dark)
    box("shelter_info_glass", 2.345, 0.48, 1.350, 0.015, 0.82, 1.36, glass)
    box("shelter_info_header", 2.282, 0.48, 1.940, 0.012, 0.66, 0.14, glow)
    for row_index in range(8):
        box("shelter_info_row", 2.280, 0.265, 1.760 - row_index * 0.115,
            0.010, 0.34, 0.035, glow)
        box("shelter_info_row_time", 2.280, 0.680, 1.760 - row_index * 0.115,
            0.010, 0.16, 0.035, glow)


# --------------------------------------------------------------------------- #
# street lamp: tapered fluted pole, two swept arms along the road axis,
# 6.63 m tall.  0.2.23 photoreal pass replaces the 560-triangle prop
# with a bolted flange base and anchor bolts, an access door with a
# handle and screws, sectional pole collars, multi-segment swept arms
# with drooping power cables and die-cast LED heads (cooling fins,
# reflector tray, lens, gasket, corner screws and a photocell).
# The outer envelope (0.48 x 4.90 m footprint, 6.63 m tall) is kept so
# the native placements/colliders remain exact.
# --------------------------------------------------------------------------- #
def build_lamp():
    metal = MATS["PropsMetal"]
    glow = MATS["LampGlow"]
    dark = MATS["RoofDark"]

    # Bolted flange base: chamfered plinth, flange disc, tapered door
    # housing, four hex anchor bolts and the collar into the pole.
    box("lamp_plinth", 0, 0, 0.040, 0.48, 0.48, 0.080, dark, bevel=0.015)
    cyl("lamp_flange", 0, 0, 0.130, 0.270, 0.100, metal, vertices=24)
    cone("lamp_base_body", 0, 0, 0.475, 0.240, 0.165, 0.550, metal, vertices=24)
    cyl("lamp_base_collar", 0, 0, 0.790, 0.180, 0.080, metal, vertices=24)
    for bx in (-0.185, 0.185):
        for by in (-0.185, 0.185):
            cyl("lamp_anchor_bolt", bx, by, 0.195, 0.026, 0.050, dark, vertices=6)
            cyl("lamp_anchor_washer", bx, by, 0.175, 0.040, 0.012, metal, vertices=12)

    # Access door on the +X face with handle, hinges and corner screws.
    box("lamp_access_door", 0.195, 0, 0.520, 0.030, 0.240, 0.420, metal, bevel=0.008)
    box("lamp_access_gasket", 0.182, 0, 0.520, 0.012, 0.262, 0.442, dark)
    box("lamp_access_handle", 0.225, -0.070, 0.520, 0.035, 0.030, 0.120, dark, bevel=0.006)
    for hinge_z in (0.380, 0.660):
        box("lamp_access_hinge", 0.205, 0.125, hinge_z, 0.025, 0.025, 0.080, dark)
    for screw_y in (-0.095, 0.095):
        for screw_z in (0.345, 0.695):
            cyl("lamp_access_screw", 0.214, screw_y, screw_z, 0.009, 0.012,
                dark, vertices=6, rotation=(0.0, math.pi / 2.0, 0.0))

    # Tapered sectional pole with slip-joint collars and a maker's plate.
    cone("lamp_pole", 0, 0, 3.660, 0.145, 0.072, 5.720, metal, vertices=24)
    for collar_z, collar_r in ((2.100, 0.126), (4.000, 0.101), (5.700, 0.082)):
        cyl("lamp_pole_collar", 0, 0, collar_z, collar_r, 0.090, metal, vertices=24)
        cyl("lamp_pole_groove", 0, 0, collar_z - 0.060, collar_r - 0.004, 0.020,
            dark, vertices=24)
    box("lamp_maker_plate", -0.118, 0, 2.450, 0.012, 0.120, 0.180, dark)
    cyl("lamp_top_cap", 0, 0, 6.555, 0.076, 0.070, metal, vertices=20)
    sphere("lamp_finial", 0, 0, 6.595, 0.070, 0.070, 0.070, metal)

    for s in (-1, 1):
        # Swept arm along +/-Y (road axis after Y-up export), built from
        # five tapered tube segments so the rise reads as a real curve.
        arm_points = (
            (0.0, s * 0.050, 6.280),
            (0.0, s * 0.550, 6.410),
            (0.0, s * 1.150, 6.480),
            (0.0, s * 1.700, 6.500),
            (0.0, s * 2.180, 6.480),
        )
        arm_radii = (0.064, 0.058, 0.052, 0.047, 0.042)
        for segment_index in range(len(arm_points) - 1):
            tube_between("lamp_arm", arm_points[segment_index],
                         arm_points[segment_index + 1],
                         arm_radii[segment_index], arm_radii[segment_index + 1],
                         metal, vertices=14)
        # Drooping power cable from the pole collar into the head.
        cable_points = (
            (0.055, s * 0.100, 6.360),
            (0.070, s * 0.750, 6.330),
            (0.060, s * 1.400, 6.380),
            (0.040, s * 1.850, 6.440),
        )
        for segment_index in range(len(cable_points) - 1):
            tube_between("lamp_cable", cable_points[segment_index],
                         cable_points[segment_index + 1], 0.011, 0.011,
                         dark, vertices=8)

        head_y = s * 1.920
        # Die-cast LED head: housing, bonnet, cooling fins, end caps.
        box("lamp_head", 0, head_y, 6.430, 0.380, 1.060, 0.165, metal, bevel=0.040)
        box("lamp_head_bonnet", 0, head_y, 6.535, 0.300, 0.900, 0.060, metal, bevel=0.022)
        for fin_index in range(7):
            box("lamp_head_fin", 0, head_y + s * (-0.360 + fin_index * 0.120), 6.560,
                0.340, 0.032, 0.070, metal, bevel=0.006)
        for cap_offset in (-0.545, 0.545):
            box("lamp_head_endcap", 0, head_y + s * cap_offset, 6.430,
                0.330, 0.045, 0.140, dark, bevel=0.012)
        # Underside reflector tray, gasket, lens and corner screws.
        box("lamp_head_reflector", 0, head_y, 6.340, 0.300, 0.900, 0.022, dark)
        box("lamp_head_gasket", 0, head_y, 6.326, 0.272, 0.842, 0.010, metal)
        box("lamp_head_lens", 0, head_y, 6.318, 0.240, 0.780, 0.018, glow)
        for screw_x in (-0.120, 0.120):
            for screw_offset in (-0.390, 0.390):
                cyl("lamp_head_screw", screw_x, head_y + s * screw_offset, 6.322,
                    0.011, 0.014, dark, vertices=6)
    # Photocell on the +Y head only, as on real twin-arm columns.
    cyl("lamp_photocell_base", 0, 1.660, 6.580, 0.038, 0.030, dark, vertices=14)
    cyl("lamp_photocell", 0, 1.660, 6.608, 0.032, 0.040, metal, vertices=14)


# --------------------------------------------------------------------------- #
# park bench (0.2.23): 2.40 m cast-iron and hardwood bench that replaces
# the flat stone slabs the 0.2.22 parks used.  Two cast side frames with
# feet, legs, reclined back posts and curved armrests carry five seat
# slats and four back slats; every slat-to-frame joint has a hex bolt.
# Origin at ground centre, seat length along Blender X.
# --------------------------------------------------------------------------- #
def build_park_bench():
    metal = MATS["PropsMetal"]
    wood = MATS["PropsWood"]
    dark = MATS["RoofDark"]

    seat_ys = (-0.215, -0.108, 0.000, 0.108, 0.215)
    for slat_y in seat_ys:
        box("park_bench_seat_slat", 0, slat_y, 0.455, 2.40, 0.088, 0.045,
            wood, bevel=0.009)
    # Reclined back: four slats tilted 12 degrees from vertical.
    back_tilt = 0.21
    for back_index in range(4):
        back_z = 0.615 + back_index * 0.115
        back_y = -0.300 - (back_z - 0.455) * math.tan(back_tilt)
        rbox("park_bench_back_slat", 0, back_y, back_z, 2.40, 0.045, 0.088,
             wood, rotation=(back_tilt, 0.0, 0.0), bevel=0.009)

    for frame_x in (-1.060, 1.060):
        # Feet with pads, front leg, back post continuing into the back
        # support, seat rail and a three-segment curved armrest.
        box("park_bench_foot", frame_x, -0.020, 0.035, 0.085, 0.720, 0.070,
            metal, bevel=0.012)
        for pad_y in (-0.300, 0.260):
            cyl("park_bench_foot_pad", frame_x, pad_y, 0.080, 0.034, 0.025,
                dark, vertices=12)
            cyl("park_bench_anchor", frame_x, pad_y, 0.078, 0.013, 0.022,
                metal, vertices=6)
        box("park_bench_leg_front", frame_x, 0.235, 0.260, 0.075, 0.085, 0.390,
            metal, bevel=0.012)
        rbox("park_bench_back_post", frame_x, -0.315, 0.540, 0.075, 0.085, 0.980,
             metal, rotation=(back_tilt, 0.0, 0.0), bevel=0.012)
        box("park_bench_seat_rail", frame_x, 0.000, 0.425, 0.065, 0.600, 0.045,
            metal, bevel=0.008)
        arm_points = (
            (frame_x, -0.300, 0.655),
            (frame_x, -0.100, 0.700),
            (frame_x, 0.120, 0.705),
            (frame_x, 0.285, 0.660),
        )
        for segment_index in range(len(arm_points) - 1):
            tube_between("park_bench_armrest", arm_points[segment_index],
                         arm_points[segment_index + 1], 0.030, 0.030,
                         metal, vertices=12)
        tube_between("park_bench_arm_support", (frame_x, 0.235, 0.455),
                     (frame_x, 0.265, 0.655), 0.022, 0.022, metal, vertices=10)
        sphere("park_bench_arm_knob", frame_x, 0.295, 0.655, 0.068, 0.068, 0.068, metal)
        # Rosette medallion bolted to the outer face of the front leg.
        outer_x = frame_x + (0.045 if frame_x > 0.0 else -0.045)
        cyl("park_bench_medallion", outer_x, 0.235, 0.260, 0.038, 0.018,
            dark, vertices=16, rotation=(0.0, math.pi / 2.0, 0.0))
        cyl("park_bench_medallion_boss", outer_x, 0.235, 0.260, 0.016, 0.028,
            metal, vertices=10, rotation=(0.0, math.pi / 2.0, 0.0))
        for slat_y in seat_ys:
            cyl("park_bench_seat_bolt", frame_x, slat_y, 0.482, 0.012, 0.012,
                dark, vertices=6)
        for back_index in range(4):
            back_z = 0.615 + back_index * 0.115
            back_y = -0.300 - (back_z - 0.455) * math.tan(back_tilt) + 0.030
            cyl("park_bench_back_bolt", frame_x, back_y, back_z, 0.012, 0.040,
                dark, vertices=6, rotation=(math.pi / 2.0 - back_tilt, 0.0, 0.0))

    # Centre stretcher ties the two frames together under the seat.
    cyl("park_bench_stretcher", 0, 0.235, 0.180, 0.026, 2.120, metal,
        vertices=12, rotation=(0.0, math.pi / 2.0, 0.0))


# --------------------------------------------------------------------------- #
# park pergola (0.2.23): hexagonal stone-and-timber pergola, 11.5 m
# across the rafter tails and 3.84 m tall, replacing the box-built museum
# pergola from 0.2.22.  Six tapered round columns on stepped plinths
# with collars and capitals carry a hexagonal ring of through-tenoned
# beams, six radial rafters and two hexagonal purlin rings around a
# central hub with a ball finial.  Column centres sit
# at r=5.2 m, angles 30deg + k*60deg, exactly where the 0.2.22 native
# colliders already are.
# --------------------------------------------------------------------------- #
def build_park_pergola():
    stone = MATS["VillaStone"]
    wood = MATS["PropsWood"]
    metal = MATS["PropsMetal"]

    column_radius = 5.2
    column_positions = []
    for column_index in range(6):
        angle = math.pi / 6.0 + column_index * math.tau / 6.0
        cx = math.cos(angle) * column_radius
        cy = math.sin(angle) * column_radius
        column_positions.append((cx, cy))
        # Stepped square plinth, round foot moulding, tapered shaft,
        # necking collar, capital block and a loose stone bench block
        # between each pair of feet comes from the native side; here we
        # keep the structure itself complete and self-supporting.
        box("pergola_plinth_low", cx, cy, 0.110, 0.860, 0.860, 0.220, stone, bevel=0.015)
        box("pergola_plinth_high", cx, cy, 0.300, 0.700, 0.700, 0.180, stone, bevel=0.012)
        cyl("pergola_foot_ring", cx, cy, 0.430, 0.340, 0.090, stone, vertices=24)
        cone("pergola_column", cx, cy, 1.720, 0.295, 0.245, 2.500, stone, vertices=24)
        cyl("pergola_necking", cx, cy, 3.000, 0.275, 0.070, stone, vertices=24)
        box("pergola_capital", cx, cy, 3.100, 0.680, 0.680, 0.150, stone, bevel=0.012)
        box("pergola_abacus", cx, cy, 3.205, 0.800, 0.800, 0.070, stone, bevel=0.010)

    # Hexagonal ring beams between neighbouring capitals, ends
    # projecting 0.35 m past each column centre with a chamfered tip.
    for beam_index in range(6):
        x1, y1 = column_positions[beam_index]
        x2, y2 = column_positions[(beam_index + 1) % 6]
        mx, my = (x1 + x2) * 0.5, (y1 + y2) * 0.5
        yaw = math.atan2(y2 - y1, x2 - x1)
        rbox("pergola_ring_beam", mx, my, 3.340, column_radius + 0.70, 0.160, 0.200,
             wood, rotation=(0.0, 0.0, yaw), bevel=0.012)
        rbox("pergola_ring_beam_lower", mx, my, 3.225, column_radius + 0.30, 0.120, 0.050,
             wood, rotation=(0.0, 0.0, yaw), bevel=0.008)

    # Six radial rafters run from the central hub to each column and
    # project 0.55 m past the ring as eaves tails -- the clean radial
    # geometry of a real hexagonal pergola.
    for rafter_index in range(6):
        angle = math.pi / 6.0 + rafter_index * math.tau / 6.0
        rbox("pergola_rafter", math.cos(angle) * 2.750, math.sin(angle) * 2.750, 3.500,
             6.00, 0.140, 0.170, wood, rotation=(0.0, 0.0, angle), bevel=0.010)

    # Two hexagonal purlin rings tie the radial rafters together and
    # throw the ring shadows that make the shade structure read.
    for ring_radius, ring_z in ((3.60, 3.610), (1.80, 3.610)):
        for side_index in range(6):
            angle1 = math.pi / 6.0 + side_index * math.tau / 6.0
            angle2 = math.pi / 6.0 + (side_index + 1) * math.tau / 6.0
            x1, y1 = math.cos(angle1) * ring_radius, math.sin(angle1) * ring_radius
            x2, y2 = math.cos(angle2) * ring_radius, math.sin(angle2) * ring_radius
            yaw = math.atan2(y2 - y1, x2 - x1)
            rbox("pergola_purlin", (x1 + x2) * 0.5, (y1 + y2) * 0.5, ring_z,
                 ring_radius + 0.10, 0.075, 0.055, wood,
                 rotation=(0.0, 0.0, yaw), bevel=0.006)

    # Central hub where the radial rafters meet, with a ball finial.
    cyl("pergola_hub", 0, 0, 3.560, 0.300, 0.180, wood, vertices=24)
    cyl("pergola_finial_stem", 0, 0, 3.680, 0.035, 0.090, metal, vertices=12)
    sphere("pergola_finial_ball", 0, 0, 3.760, 0.150, 0.150, 0.150, metal)


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
# Building Model No.5 — detailed fixed-scale 148 m main tower.
# Planned envelope: 50.00 x 42.00 m, exactly 148.00 m high. The old
# square finned proxy scaled from the district-tower file is replaced by
# an original tapered, gently twisting oval-blade shaft over a rotating
# three-tier landscaped podium. Real floor slabs, capsule curtain-wall
# segments, mullions, fins, sky gardens and an open crown carry the form;
# no baked-window facade texture is used on the new flagship.
# --------------------------------------------------------------------------- #
def build_main_tower():
    glass = MATS["MainGlass"]
    spandrel = MATS["MainSpandrel"]
    stone = MATS["MainStone"]
    trim = MATS["MainTrim"]
    main_metal = MATS["MainMetal"]
    water = MATS["MainWater"]
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

    def rotate_xy(cx, cy, lx, ly, yaw):
        c = math.cos(yaw)
        s = math.sin(yaw)
        return (cx + c * lx - s * ly, cy + s * lx + c * ly)

    def local_box(name, cx, cy, cz, lx, ly, dx, dy, dz, material, yaw=0.0, extra_yaw=0.0, bevel=0.0):
        x, y = rotate_xy(cx, cy, lx, ly, yaw)
        obj = box(name, x, y, cz, dx, dy, dz, material, bevel=bevel)
        obj.rotation_euler = (0.0, 0.0, yaw + extra_yaw)
        return obj

    def capsule_volume(name, cx, cy, cz, length, width, height, material, yaw=0.0, vertices=18):
        straight = max(length - width, 0.20)
        local_box(name + "_body", cx, cy, cz, 0.0, 0.0, straight, width, height, material, yaw=yaw)
        for side in (-1.0, 1.0):
            ex, ey = rotate_xy(cx, cy, side * straight * 0.5, 0.0, yaw)
            cyl(name + "_cap", ex, ey, cz, width * 0.5, height, material, vertices=vertices)

    def shaft_profile(t):
        # A smooth architectural taper: the oval blade loses roughly a
        # third of its plan while turning 30 degrees and drifting in a
        # shallow S-curve. Every real floor below samples this profile.
        taper = t ** 0.88
        length = 38.0 - 13.5 * taper
        width = 24.0 - 8.5 * (t ** 0.92)
        yaw = -0.21 + 0.53 * t
        cx = -1.6 + 4.2 * t + 0.55 * math.sin(math.pi * t)
        cy = 0.9 - 2.2 * t - 0.35 * math.sin(math.pi * t)
        return (cx, cy, length, width, yaw)

    def perimeter_mullions(cx, cy, length, width, yaw, z_center, height, long_offsets, material):
        straight = max(length - width, 0.20)
        for face_sign in (-1.0, 1.0):
            for ratio in long_offsets:
                local_box(
                    "main_podium_mullion", cx, cy, z_center,
                    ratio * straight, face_sign * (width * 0.5 + 0.055),
                    0.10, 0.15, height, material, yaw=yaw,
                )
        for end_sign in (-1.0, 1.0):
            cap_x = end_sign * straight * 0.5
            base_angle = 0.0 if end_sign > 0.0 else math.pi
            for angle_offset in (-0.95, -0.48, 0.0, 0.48, 0.95):
                angle = base_angle + angle_offset
                lx = cap_x + math.cos(angle) * (width * 0.5 + 0.055)
                ly = math.sin(angle) * (width * 0.5 + 0.055)
                local_box(
                    "main_podium_arc_mullion", cx, cy, z_center,
                    lx, ly, 0.15, 0.10, height, material,
                    yaw=yaw, extra_yaw=angle,
                )

    # Rounded plaza parcel. The architectural site itself is an oval
    # capsule rather than another square slab.
    capsule_volume("main_site_plinth", 0.0, 0.0, 0.18, 50.00, 42.00, 0.36, granite, vertices=28)
    capsule_volume("main_site_paving_inset", 0.0, 0.0, 0.385, 48.60, 40.60, 0.045, pavement, vertices=28)

    # Three rotating podium terraces. Their yaws lead into the shaft's
    # base angle, so the flagship grows out of the podium instead of
    # sitting on an unrelated rectangular block.
    podium_tiers = (
        (46.00, 36.00, 0.36, 4.55, 0.00, 1.00, 4.00),
        (43.00, 32.50, 2.40, 5.90, -0.10, 3.05, 5.35),
        (40.50, 29.00, 4.20, 9.00, -0.21, 5.15, 7.75),
    )
    for tier_index, (length, width, z_bottom, z_top, yaw, glass_bottom, glass_top) in enumerate(podium_tiers):
        z_center = (z_bottom + z_top) * 0.5
        capsule_volume(
            "main_podium_tier_%d" % tier_index, 0.0, 0.0, z_center,
            length, width, z_top - z_bottom, stone, yaw=yaw, vertices=24,
        )
        glass_center = (glass_bottom + glass_top) * 0.5
        glass_height = glass_top - glass_bottom
        capsule_volume(
            "main_podium_core_band_%d" % tier_index, 0.0, 0.0, glass_center,
            length + 0.08, width + 0.08, glass_height, core, yaw=yaw, vertices=24,
        )
        capsule_volume(
            "main_podium_glass_band_%d" % tier_index, 0.0, 0.0, glass_center,
            length + 0.17, width + 0.17, glass_height, glass, yaw=yaw, vertices=24,
        )
        perimeter_mullions(
            0.0, 0.0, length + 0.17, width + 0.17, yaw,
            glass_center, glass_height,
            (-0.44, -0.30, -0.15, 0.0, 0.15, 0.30, 0.44), frame,
        )
        capsule_volume(
            "main_podium_cornice_%d" % tier_index, 0.0, 0.0, z_top + 0.06,
            length + 0.70, width + 0.70, 0.24, trim, yaw=yaw, vertices=24,
        )

    # Landscaped podium roofs in the exposed corner/end rings.
    for planter_x, planter_y in ((-19.0, -13.0), (19.0, -13.0), (-19.0, 13.0), (19.0, 13.0)):
        box("main_podium_corner_planter", planter_x, planter_y, 4.86, 2.60, 1.15, 0.52, granite)
        box("main_podium_corner_soil", planter_x, planter_y, 5.14, 2.38, 0.94, 0.045, mulch)
        box("main_podium_corner_hedge", planter_x, planter_y, 5.34, 2.24, 0.82, 0.34, hedge, bevel=0.055)
    for end_sign in (-1.0, 1.0):
        local_box("main_mid_podium_planter", 0.0, 0.0, 6.22, end_sign * 18.1, 0.0, 2.45, 1.10, 0.50, granite, yaw=-0.10)
        local_box("main_mid_podium_hedge", 0.0, 0.0, 6.58, end_sign * 18.1, 0.0, 2.15, 0.82, 0.32, hedge, yaw=-0.10, bevel=0.050)

    # Grand south entrance on the flat central portion of the lower
    # capsule: portal fins, lobby glass, blade canopy, rods and steps.
    box("main_lobby_interior", 0.0, -18.10, 3.30, 8.80, 0.12, 5.30, core)
    box("main_lobby_glass", 0.0, -18.20, 3.30, 8.80, 0.07, 5.30, glass)
    for mullion_x in (-3.30, -1.10, 1.10, 3.30):
        box("main_lobby_mullion", mullion_x, -18.265, 3.30, 0.09, 0.07, 5.30, frame)
    box("main_lobby_transom", 0.0, -18.265, 4.72, 8.80, 0.07, 0.09, frame)
    for portal_side in (-1.0, 1.0):
        portal = box("main_entry_portal_fin", portal_side * 5.35, -18.05, 4.45, 0.82, 1.05, 8.10, trim, bevel=0.020)
        portal.rotation_euler = (0.0, 0.0, portal_side * -0.10)
        cyl("main_lobby_door_handle", portal_side * 0.38, -18.30, 1.55, 0.026, 1.00, metal, vertices=10)
    box("main_entry_header", 0.0, -18.24, 6.18, 11.40, 0.34, 0.62, trim)
    capsule_volume("main_entry_canopy", 0.0, -18.65, 5.78, 13.00, 3.20, 0.24, granite, vertices=18)
    capsule_volume("main_entry_canopy_soffit", 0.0, -18.65, 5.63, 12.45, 2.75, 0.055, wood, vertices=18)
    for column_side in (-1.0, 1.0):
        column_x = column_side * 5.20
        box("main_entry_column_base", column_x, -19.65, 0.58, 0.42, 0.42, 0.44, granite)
        cyl("main_entry_column", column_x, -19.65, 3.10, 0.125, 4.95, main_metal, vertices=14)
        tube_between("main_entry_tie_rod", (column_x, -19.65, 5.55), (column_side * 5.35, -18.05, 8.30), 0.026, 0.026, main_metal, vertices=8)
    for step_y, step_top, step_width in ((-18.55, 0.80, 8.20), (-19.15, 0.62, 7.70), (-19.72, 0.47, 7.20)):
        box("main_entry_step", 0.0, step_y, (0.36 + step_top) * 0.5, step_width, 0.58, step_top - 0.36, pavement)
    box("main_sign_band", 0.0, -18.31, 6.78, 8.60, 0.16, 0.72, main_metal)
    box("main_sign_glow", 0.0, -18.405, 6.78, 7.95, 0.035, 0.27, glow)
    box("main_address_monolith", -7.65, -18.75, 1.18, 0.62, 0.48, 1.58, granite, bevel=0.020)
    box("main_address_inset", -7.65, -19.015, 1.28, 0.38, 0.035, 0.92, metal)

    # Rear service entrance and an angled garage portal on the east cap.
    box("main_service_portal", 2.40, 18.10, 2.05, 4.60, 0.20, 3.35, trim)
    box("main_service_door", 2.40, 18.20, 1.98, 4.05, 0.10, 3.00, main_metal, bevel=0.010)
    for seam_z in (1.08, 1.94, 2.80):
        box("main_service_door_seam", 2.40, 18.265, seam_z, 3.92, 0.025, 0.045, frame)
    box("main_loading_dock", 2.40, 19.35, 0.58, 5.30, 2.05, 0.44, pavement)
    box("main_service_canopy", 2.40, 19.05, 3.96, 5.30, 1.45, 0.16, granite)
    garage_angle = 0.61
    garage_cap_x = 5.0
    for radius, dz, material, name in ((18.12, 3.30, trim, "main_garage_portal"), (18.22, 3.00, main_metal, "main_garage_door")):
        gx = garage_cap_x + math.cos(garage_angle) * radius
        gy = math.sin(garage_angle) * radius
        local_box(name, 0.0, 0.0, 1.95, gx, gy, 4.85, 0.16, dz, material, extra_yaw=garage_angle + math.pi * 0.5)
    for bin_x in (-5.80, -3.75):
        box("main_waste_bin", bin_x, 18.65, 0.92, 1.75, 0.95, 1.08, dark, bevel=0.025)
        box("main_waste_bin_lid", bin_x, 18.65, 1.50, 1.83, 1.00, 0.09, main_metal)

    shaft_bottom = 9.00
    floor_count = 40
    floor_h = 3.42
    shaft_top = shaft_bottom + floor_count * floor_h

    # Real floor plates first: every boundary samples the smooth oval
    # profile, with a champagne trim plate every five floors.
    for boundary_index in range(floor_count + 1):
        t = boundary_index / float(floor_count)
        cx, cy, length, width, yaw = shaft_profile(t)
        slab_z = shaft_bottom + boundary_index * floor_h
        capsule_volume(
            "main_floor_spandrel", cx, cy, slab_z,
            length + 0.45, width + 0.45, 0.26, spandrel,
            yaw=yaw, vertices=18,
        )
        if boundary_index % 5 == 0 and boundary_index not in (0, floor_count):
            capsule_volume(
                "main_five_floor_trim", cx, cy, slab_z + 0.20,
                length + 0.82, width + 0.82, 0.11, trim,
                yaw=yaw, vertices=18,
            )

    # Occupied core and glass skin are rebuilt for every floor so the
    # taper/twist is actual geometry, not a texture or a single scaled box.
    for floor_index in range(floor_count):
        t = (floor_index + 0.5) / float(floor_count)
        cx, cy, length, width, yaw = shaft_profile(t)
        floor_center = shaft_bottom + (floor_index + 0.5) * floor_h
        capsule_volume(
            "main_shaft_core", cx, cy, floor_center,
            length - 0.35, width - 0.35, floor_h, core,
            yaw=yaw, vertices=18,
        )
        capsule_volume(
            "main_shaft_glass", cx, cy, floor_center,
            length, width, floor_h - 0.18, glass,
            yaw=yaw, vertices=18,
        )

        straight = max(length - width, 0.20)
        for face_index, face_sign in enumerate((-1.0, 1.0)):
            pattern = (floor_index * 3 + face_index * 2 + 1) % 5
            panel_specs = ((-0.30, 0.34), (0.28, 0.30)) if pattern in (0, 1) else ((-0.08, 0.62),)
            for panel_ratio, panel_width_ratio in panel_specs:
                panel_material = glow if pattern == 0 else (curtain if pattern in (1, 2) else spandrel)
                local_box(
                    "main_interior_panel", cx, cy, floor_center + 0.10,
                    panel_ratio * straight, face_sign * (width * 0.5 - 0.095),
                    panel_width_ratio * straight, 0.032, 1.10,
                    panel_material, yaw=yaw,
                )
            # A stronger vertical blade at the centre of each long face.
            local_box(
                "main_long_face_fin", cx, cy, floor_center,
                0.0, face_sign * (width * 0.5 + 0.24),
                0.34, 0.52, floor_h, main_metal, yaw=yaw,
            )
        for end_sign in (-1.0, 1.0):
            local_box(
                "main_end_fin", cx, cy, floor_center,
                end_sign * (length * 0.5 + 0.18), 0.0,
                0.56, 0.34, floor_h, main_metal, yaw=yaw,
            )
            local_box(
                "main_end_light", cx, cy, floor_center,
                end_sign * (length * 0.5 + 0.49), 0.0,
                0.10, 0.10, floor_h * 0.94, glow, yaw=yaw,
            )
            if floor_index % 3 == 0:
                cap_x = end_sign * straight * 0.5
                base_angle = 0.0 if end_sign > 0.0 else math.pi
                angle = base_angle + (0.38 if (floor_index // 3) % 2 == 0 else -0.38)
                lx = cap_x + math.cos(angle) * (width * 0.5 - 0.095)
                ly = math.sin(angle) * (width * 0.5 - 0.095)
                local_box(
                    "main_curved_interior_panel", cx, cy, floor_center + 0.08,
                    lx, ly, 2.05, 0.032, 1.02,
                    curtain if floor_index % 6 == 0 else glow,
                    yaw=yaw, extra_yaw=angle + math.pi * 0.5,
                )

    # Two-floor mullion segments follow the same sampled profile without
    # turning every office bay into a separate full-height object.
    for segment_index in range(floor_count // 2):
        t = (segment_index + 0.5) / float(floor_count // 2)
        cx, cy, length, width, yaw = shaft_profile(t)
        segment_center = shaft_bottom + (segment_index + 0.5) * floor_h * 2.0
        perimeter_mullions(
            cx, cy, length, width, yaw, segment_center,
            floor_h * 2.0 - 0.22,
            (-0.44, -0.22, 0.0, 0.22, 0.44), frame,
        )

    # Two sky gardens interrupt the glass shaft with planted terraces.
    for boundary_index in (13, 26):
        t = boundary_index / float(floor_count)
        cx, cy, length, width, yaw = shaft_profile(t)
        terrace_z = shaft_bottom + boundary_index * floor_h
        capsule_volume(
            "main_sky_garden_slab", cx, cy, terrace_z,
            length + 2.55, width + 2.55, 0.34, trim,
            yaw=yaw, vertices=20,
        )
        straight = max(length - width, 0.20)
        for face_sign in (-1.0, 1.0):
            local_box(
                "main_sky_garden_rail", cx, cy, terrace_z + 0.58,
                0.0, face_sign * (width * 0.5 + 1.20),
                straight + 1.65, 0.055, 0.76, glass, yaw=yaw,
            )
            for planter_ratio in (-0.32, 0.0, 0.32):
                local_box(
                    "main_sky_garden_planter", cx, cy, terrace_z + 0.38,
                    planter_ratio * straight, face_sign * (width * 0.5 + 0.74),
                    1.70, 0.55, 0.44, granite, yaw=yaw,
                )
                local_box(
                    "main_sky_garden_hedge", cx, cy, terrace_z + 0.70,
                    planter_ratio * straight, face_sign * (width * 0.5 + 0.74),
                    1.48, 0.38, 0.28, hedge, yaw=yaw, bevel=0.040,
                )
        for end_sign in (-1.0, 1.0):
            cap_x = end_sign * straight * 0.5
            base_angle = 0.0 if end_sign > 0.0 else math.pi
            for angle_offset in (-0.62, 0.0, 0.62):
                angle = base_angle + angle_offset
                rail_radius = width * 0.5 + 1.20
                lx = cap_x + math.cos(angle) * rail_radius
                ly = math.sin(angle) * rail_radius
                local_box(
                    "main_sky_garden_arc_rail", cx, cy, terrace_z + 0.58,
                    lx, ly, 1.55, 0.055, 0.76, glass,
                    yaw=yaw, extra_yaw=angle + math.pi * 0.5,
                )

    # Open crown: observation capsule, eight converging braces, end fins
    # and a short spire. The beacon top is the exact 148.00 m datum.
    top_cx, top_cy, top_length, top_width, top_yaw = shaft_profile(1.0)
    capsule_volume(
        "main_crown_slab", top_cx, top_cy, shaft_top + 0.16,
        top_length + 2.05, top_width + 2.05, 0.34, trim,
        yaw=top_yaw, vertices=20,
    )
    capsule_volume(
        "main_crown_core", top_cx, top_cy, shaft_top + 0.95,
        top_length - 3.90, top_width - 2.65, 1.55, spandrel,
        yaw=top_yaw, vertices=20,
    )
    capsule_volume(
        "main_crown_observation_glass", top_cx, top_cy, shaft_top + 1.00,
        top_length - 3.55, top_width - 2.30, 0.92, glass,
        yaw=top_yaw, vertices=20,
    )
    top_straight = max(top_length - top_width, 0.20)
    crown_points = (
        (-top_length * 0.5, 0.0),
        (-top_straight * 0.5, -top_width * 0.5),
        (0.0, -top_width * 0.5),
        (top_straight * 0.5, -top_width * 0.5),
        (top_length * 0.5, 0.0),
        (top_straight * 0.5, top_width * 0.5),
        (0.0, top_width * 0.5),
        (-top_straight * 0.5, top_width * 0.5),
    )
    for lx, ly in crown_points:
        start_x, start_y = rotate_xy(top_cx, top_cy, lx, ly, top_yaw)
        end_x, end_y = rotate_xy(top_cx, top_cy, lx * 0.38, ly * 0.38, top_yaw)
        tube_between(
            "main_crown_brace",
            (start_x, start_y, shaft_top + 0.30),
            (end_x, end_y, shaft_top + 1.78),
            0.16, 0.085, main_metal, vertices=10,
        )
        box("main_crown_brace_light", end_x, end_y, shaft_top + 1.84, 0.20, 0.20, 0.10, glow)
    for end_sign in (-1.0, 1.0):
        local_box(
            "main_crown_end_fin", top_cx, top_cy, shaft_top + 1.05,
            end_sign * (top_length * 0.5 + 0.28), 0.0,
            0.52, 0.42, 1.95, main_metal, yaw=top_yaw,
        )
    capsule_volume(
        "main_crown_ring", top_cx, top_cy, shaft_top + 1.82,
        top_length * 0.52, top_width * 0.58, 0.20, trim,
        yaw=top_yaw, vertices=20,
    )
    cyl("main_spire", top_cx, top_cy, 147.18, 0.085, 1.48, main_metal, vertices=10)
    box("main_beacon", top_cx, top_cy, 147.96, 0.16, 0.16, 0.08, glow)

    # Forecourt water mirrors, sculpture, flags, planters and lighting.
    for water_side in (-1.0, 1.0):
        water_x = water_side * 8.55
        box("main_reflecting_pool_basin", water_x, -18.95, 0.43, 5.15, 1.25, 0.16, granite)
        box("main_reflecting_pool", water_x, -18.95, 0.53, 4.88, 1.02, 0.045, water)
        cyl("main_flag_pole", water_side * 12.35, -18.55, 3.45, 0.045, 6.30, metal, vertices=10)
        box("main_flag_banner", water_side * 12.35 + (0.42 if water_side < 0.0 else -0.42), -18.55, 5.85, 0.78, 0.035, 1.45, spandrel)
    cyl("main_sculpture_base", -17.00, -15.20, 0.78, 0.78, 0.82, granite, vertices=18)
    sphere("main_forecourt_sculpture", -17.00, -15.20, 2.05, 2.05, 2.05, 2.35, trim)
    for planter_x in (-13.0, 13.0):
        box("main_front_planter", planter_x, -17.65, 0.64, 2.35, 0.80, 0.56, granite)
        box("main_front_planter_soil", planter_x, -17.65, 0.94, 2.12, 0.60, 0.045, mulch)
        box("main_front_planter_hedge", planter_x, -17.65, 1.11, 1.98, 0.50, 0.34, hedge, bevel=0.045)
        bench_x = planter_x * 0.91
        box("main_front_bench", bench_x, -18.72, 0.62, 2.25, 0.48, 0.10, wood)
        box("main_front_bench_base", bench_x, -18.72, 0.46, 1.82, 0.34, 0.24, granite)
    for bollard_x in (-10.0, -7.0, -4.0, 4.0, 7.0, 10.0):
        cyl("main_front_bollard", bollard_x, -19.72, 0.72, 0.085, 0.72, main_metal, vertices=12)
        box("main_front_bollard_light", bollard_x, -19.72, 1.10, 0.10, 0.10, 0.045, glow)
    for lawn_side in (-1.0, 1.0):
        box("main_side_lawn", lawn_side * 24.00, 0.0, 0.43, 1.20, 7.00, 0.055, lawn)
        for hedge_y in (-2.40, 2.40):
            box("main_side_hedge", lawn_side * 24.00, hedge_y, 0.68, 0.72, 2.20, 0.48, hedge, bevel=0.055)
    for rear_planter_x in (-10.0, -5.0, 8.0, 11.0):
        box("main_rear_planter", rear_planter_x, 19.05, 0.62, 2.25, 0.70, 0.52, granite)
        box("main_rear_hedge", rear_planter_x, 19.05, 0.99, 1.95, 0.48, 0.32, hedge, bevel=0.045)

# --------------------------------------------------------------------------- #
# Building Model No.6: RichTown Opera.  The fixed parcel is 52 x 56 m and
# the finial is exactly 22.00 m above the lot.  Blender -Y is the public
# west front after the native landmark yaw: a curved, inhabited glass
# foyer sits below three pleated ceramic shell vaults, while the fly
# tower, loading dock and service yard occupy the rear (+Y).  The design
# is original: three interlocking dhow-sail shells stand on a tall
# travertine podium rather than copying an existing opera house.
# --------------------------------------------------------------------------- #
def build_opera():
    shell_mat = MATS["OperaShell"]
    stone = MATS["OperaStone"]
    limestone = MATS["VillaLimestone"]
    bronze = MATS["OperaBronze"]
    opera_glass = MATS["OperaGlass"]
    interior = MATS["OperaInterior"]
    opera_wood = MATS["OperaWood"]
    opera_granite = MATS["OperaGranite"]
    curtain = MATS["OperaCurtain"]
    opera_water = MATS["OperaWater"]
    opera_light = MATS["OperaLight"]
    pavement = MATS["VillaPavement"]
    lawn = MATS["VillaLawn"]
    hedge = MATS["VillaHedge"]
    mulch = MATS["VillaMulch"]
    frame = MATS["WindowFrame"]
    metal = MATS["PropsMetal"]
    roof_dark = MATS["RoofDark"]

    def side_window(face_x, centre_y, centre_z, depth=2.45, height=3.35):
        side_sign = 1.0 if face_x >= 0.0 else -1.0
        outer_x = face_x + side_sign * 0.055
        box("opera_side_window_frame", outer_x, centre_y, centre_z, 0.11, depth + 0.22, height + 0.22, bronze)
        box("opera_side_window_glass", outer_x + side_sign * 0.065, centre_y, centre_z, 0.055, depth, height, opera_glass)
        box("opera_side_window_mullion", outer_x + side_sign * 0.10, centre_y, centre_z, 0.045, 0.09, height, frame)
        box("opera_side_window_sill", outer_x + side_sign * 0.11, centre_y, centre_z - height * 0.5 - 0.16,
            0.20, depth + 0.38, 0.13, limestone)
        box("opera_side_window_light", outer_x + side_sign * 0.105, centre_y, centre_z + height * 0.5 + 0.20,
            0.05, depth * 0.72, 0.055, opera_light)

    def rear_window(centre_x, face_y, centre_z, width=2.60, height=3.10):
        side_sign = 1.0 if face_y >= 0.0 else -1.0
        outer_y = face_y + side_sign * 0.055
        box("opera_rear_window_frame", centre_x, outer_y, centre_z, width + 0.22, 0.11, height + 0.22, bronze)
        box("opera_rear_window_glass", centre_x, outer_y + side_sign * 0.065, centre_z, width, 0.055, height, opera_glass)
        box("opera_rear_window_mullion", centre_x, outer_y + side_sign * 0.10, centre_z, 0.09, 0.045, height, frame)
        box("opera_rear_window_sill", centre_x, outer_y + side_sign * 0.11, centre_z - height * 0.5 - 0.16,
            width + 0.38, 0.20, 0.13, limestone)

    # --- Civic stone parcel, ceremonial steps, ramps and inlay joints. ---
    box("opera_lot", 0.0, 0.0, 0.18, 52.0, 56.0, 0.36, pavement)
    box("opera_lot_front_border", 0.0, -27.72, 0.385, 52.0, 0.56, 0.05, opera_granite)
    box("opera_lot_rear_border", 0.0, 27.72, 0.385, 52.0, 0.56, 0.05, opera_granite)
    box("opera_lot_left_border", -25.72, 0.0, 0.385, 0.56, 56.0, 0.05, opera_granite)
    box("opera_lot_right_border", 25.72, 0.0, 0.385, 0.56, 56.0, 0.05, opera_granite)
    for joint_index in range(13):
        joint_x = -24.0 + joint_index * 4.0
        box("opera_forecourt_joint", joint_x, -22.4, 0.395, 0.075, 10.4, 0.018, opera_granite)
        box("opera_rear_yard_joint", joint_x, 24.0, 0.395, 0.075, 7.2, 0.018, opera_granite)
    for joint_y in (-25.2, -19.8, 22.2, 25.8):
        box("opera_lot_transverse_joint", 0.0, joint_y, 0.395, 50.8, 0.075, 0.018, opera_granite)
    for step_index in range(5):
        box("opera_grand_step", 0.0, -27.18 + step_index * 0.54, 0.055 + step_index * 0.055,
            35.0, 0.62, 0.11 + step_index * 0.055, limestone)
    for ramp_side in (-1.0, 1.0):
        rbox("opera_access_ramp", ramp_side * 20.35, -25.65, 0.237, 3.15, 4.65, 0.14, limestone,
             rotation=(0.072, 0.0, 0.0))
        box("opera_ramp_kerb", ramp_side * 21.98, -25.65, 0.46, 0.16, 4.65, 0.34, opera_granite)
        box("opera_ramp_light_strip", ramp_side * 18.78, -25.65, 0.43, 0.07, 4.25, 0.045, opera_light)

    # Reflecting basin and central processional bridge.  Fountain rings
    # are real low geometry and the water is a separate physical part.
    box("opera_reflecting_pool_basin", 0.0, -21.55, 0.47, 39.0, 3.55, 0.24, opera_granite)
    box("opera_reflecting_pool_water", 0.0, -21.55, 0.585, 38.15, 2.78, 0.045, opera_water)
    box("opera_reflecting_pool_bridge", 0.0, -21.55, 0.62, 6.4, 3.82, 0.16, limestone)
    box("opera_pool_bridge_light", 0.0, -21.55, 0.715, 0.12, 3.35, 0.025, opera_light)
    for fountain_x in (-17.5, -14.5, -11.5, -8.5, -5.5, 5.5, 8.5, 11.5, 14.5, 17.5):
        cyl("opera_fountain_nozzle", fountain_x, -21.55, 0.65, 0.075, 0.16, bronze, vertices=10)
        cyl("opera_fountain_ring_outer", fountain_x, -21.55, 0.615, 0.46, 0.018, opera_water, vertices=12)
        cyl("opera_fountain_ring_inner", fountain_x, -21.55, 0.622, 0.25, 0.018, opera_light, vertices=10)

    # --- Travertine podium, auditorium core and rear fly tower. ---
    box("opera_black_plinth", 0.0, 2.0, 0.58, 46.65, 36.65, 0.46, opera_granite)
    # The podium is composed around a real 5 m deep foyer cavity: the
    # rear volume starts at y=-11 and only two stone cheeks reach the
    # curved entrance wall, so the doors do not sit on a solid box.
    box("opera_podium_rear", 0.0, 4.5, 2.98, 46.0, 31.0, 5.24, stone)
    box("opera_podium_rear_cornice", 0.0, 4.5, 5.72, 46.55, 31.55, 0.28, limestone)
    for cheek_side in (-1.0, 1.0):
        box("opera_podium_front_cheek", cheek_side * 20.75, -13.5, 2.98, 4.5, 5.0, 5.24, stone)
        box("opera_podium_front_cheek_cornice", cheek_side * 20.75, -13.5, 5.72, 4.85, 5.35, 0.28, limestone)
        box("opera_foyer_side_wall", cheek_side * 20.35, -13.85, 3.05, 0.32, 4.55, 5.35, interior)
    box("opera_foyer_floor", 0.0, -14.05, 0.48, 41.5, 5.55, 0.24, opera_granite)
    box("opera_auditorium_core", 0.0, 3.0, 8.10, 42.0, 30.0, 5.05, stone)
    box("opera_auditorium_shadow_gap", 0.0, 3.0, 10.72, 42.35, 30.35, 0.18, bronze)

    # Cut-stone piers, horizontal reveals and slit windows make the long
    # podium read as masonry at road distance rather than a textured box.
    for side_sign in (-1.0, 1.0):
        face_x = side_sign * 23.0
        for pier_y in (-14.0, -9.5, -5.0, -0.5, 4.0, 8.5, 13.0, 17.5):
            box("opera_side_pier", face_x + side_sign * 0.17, pier_y, 2.98, 0.34, 0.78, 5.05, limestone)
        for seam_z in (1.55, 2.85, 4.15, 5.25):
            box("opera_side_stone_seam", face_x + side_sign * 0.055, 2.0, seam_z, 0.07, 35.3, 0.065, frame)
        for window_y in (-11.75, -2.75, 6.25, 15.25):
            side_window(face_x, window_y, 3.10, depth=2.55, height=3.35)
        for clerestory_y in (-8.0, 3.0, 14.0):
            box("opera_clerestory_frame", side_sign * 21.04, clerestory_y, 8.65, 0.10, 4.10, 1.25, bronze)
            box("opera_clerestory_glass", side_sign * 21.11, clerestory_y, 8.65, 0.055, 3.82, 1.02, opera_glass)
            box("opera_clerestory_fin", side_sign * 21.22, clerestory_y - 1.28, 8.65, 0.16, 0.10, 1.02, bronze)
            box("opera_clerestory_fin", side_sign * 21.22, clerestory_y + 1.28, 8.65, 0.16, 0.10, 1.02, bronze)
    for rear_pier_x in range(-20, 21, 5):
        box("opera_rear_pier", float(rear_pier_x), 20.17, 2.98, 0.78, 0.34, 5.05, limestone)
    for rear_seam_z in (1.55, 2.85, 4.15, 5.25):
        box("opera_rear_stone_seam", 0.0, 20.055, rear_seam_z, 45.3, 0.07, 0.065, frame)
    for rear_window_x in (-17.5, -12.5, 12.5, 17.5):
        rear_window(rear_window_x, 20.0, 3.15, width=2.70, height=3.30)

    # Fly tower: tall stone volume, bronze louvre field, coping, roof
    # plant, guard rails and a working rear elevation.
    box("opera_fly_tower", 0.0, 14.5, 10.14, 25.0, 10.0, 19.56, stone)
    box("opera_fly_tower_cornice", 0.0, 14.5, 19.98, 25.55, 10.55, 0.24, limestone)
    box("opera_fly_tower_roof", 0.0, 14.5, 20.18, 24.7, 9.7, 0.16, roof_dark)
    for tower_pier_x in range(-12, 13, 3):
        box("opera_fly_tower_rear_pier", float(tower_pier_x), 19.58, 10.35, 0.36, 0.16, 18.8, limestone)
    for tower_seam_z in (4.0, 7.2, 10.4, 13.6, 16.8):
        box("opera_fly_tower_rear_seam", 0.0, 19.575, tower_seam_z, 24.6, 0.065, 0.065, frame)
    box("opera_fly_tower_louvre_shadow", 0.0, 19.64, 14.35, 15.8, 0.10, 7.8, interior)
    for louvre_index in range(15):
        louvre_x = -7.0 + louvre_index * 1.0
        box("opera_fly_tower_louvre", louvre_x, 19.72, 14.35, 0.17, 0.10, 7.45, bronze)
    for louvre_z in (11.2, 12.8, 14.4, 16.0, 17.6):
        box("opera_fly_tower_louvre_rail", 0.0, 19.74, louvre_z, 15.3, 0.09, 0.12, frame)
    # The front and flanks of the fly tower remain visible in the gaps
    # between the shells; give them the same bronze louvre rhythm
    # instead of leaving three blank stone planes behind the vaults.
    box("opera_fly_tower_front_shadow", 0.0, 9.43, 14.35, 15.8, 0.10, 7.8, interior)
    for louvre_index in range(15):
        louvre_x = -7.0 + louvre_index * 1.0
        box("opera_fly_tower_front_louvre", louvre_x, 9.35, 14.35, 0.17, 0.10, 7.45, bronze)
    for louvre_z in (11.2, 12.8, 14.4, 16.0, 17.6):
        box("opera_fly_tower_front_louvre_rail", 0.0, 9.33, louvre_z, 15.3, 0.09, 0.12, frame)
    for tower_side in (-1.0, 1.0):
        for seam_y in (11.0, 14.5, 18.0):
            box("opera_fly_tower_side_seam", tower_side * 12.56, seam_y, 10.35, 0.075, 0.18, 18.8, limestone)
        for seam_z in (4.0, 7.2, 10.4, 13.6, 16.8):
            box("opera_fly_tower_side_horizontal_seam", tower_side * 12.55, 14.5, seam_z, 0.065, 9.6, 0.065, frame)
    for plant_x, plant_y, plant_w, plant_d in ((-8.2, 12.6, 4.2, 2.1), (-2.6, 16.6, 3.4, 1.8), (4.8, 12.4, 4.8, 2.2), (9.4, 16.2, 2.8, 1.7)):
        box("opera_fly_roof_plant", plant_x, plant_y, 20.78, plant_w, plant_d, 1.05, metal)
        box("opera_fly_roof_plant_lid", plant_x, plant_y, 21.36, plant_w - 0.24, plant_d - 0.24, 0.11, frame)
        cyl("opera_fly_roof_fan", plant_x - plant_w * 0.22, plant_y, 21.48, 0.42, 0.13, bronze, vertices=16)
        cyl("opera_fly_roof_fan_hub", plant_x - plant_w * 0.22, plant_y, 21.57, 0.11, 0.08, frame, vertices=10)
    for rail_y in (9.85, 19.15):
        box("opera_fly_roof_rail", 0.0, rail_y, 20.78, 24.2, 0.055, 0.055, bronze)
    for rail_x in (-12.1, 12.1):
        box("opera_fly_roof_side_rail", rail_x, 14.5, 20.78, 0.055, 9.3, 0.055, bronze)
    cyl("opera_lightning_mast", 11.2, 18.4, 20.98, 0.035, 1.45, bronze, vertices=8)
    sphere("opera_lightning_mast_tip", 11.2, 18.4, 21.74, 0.13, 0.13, 0.13, opera_light)

    # Rear stage door, dock, canopy and service yard.
    box("opera_stage_door_frame", 0.0, 19.66, 3.55, 7.55, 0.22, 6.15, bronze)
    for slat_index in range(8):
        box("opera_stage_door_slat", 0.0, 19.79, 0.95 + slat_index * 0.72, 7.05, 0.08, 0.62, metal)
    box("opera_stage_door_centre_rail", 0.0, 19.84, 3.55, 0.14, 0.07, 5.85, frame)
    box("opera_loading_dock", 0.0, 21.55, 0.68, 12.5, 3.55, 0.64, limestone)
    box("opera_loading_dock_edge", 0.0, 23.30, 0.98, 12.5, 0.16, 0.08, opera_light)
    for dock_side in (-1.0, 1.0):
        rbox("opera_loading_ramp", dock_side * 7.65, 21.55, 0.39, 2.8, 3.55, 0.16, limestone,
             rotation=(0.0, dock_side * 0.105, 0.0))
        cyl("opera_dock_bumper", dock_side * 4.6, 23.38, 0.72, 0.16, 0.55, roof_dark, vertices=12)
    rbox("opera_stage_canopy", 0.0, 20.85, 7.05, 10.8, 2.75, 0.18, bronze, rotation=(0.07, 0.0, 0.0), bevel=0.035)
    for tie_x in (-4.6, -2.3, 2.3, 4.6):
        tube_between("opera_stage_canopy_tie", (tie_x, 22.05, 7.12), (tie_x, 19.62, 10.65), 0.032, 0.032, metal, vertices=8)
    for service_line_x in (-18.0, -12.0, 12.0, 18.0):
        box("opera_service_yard_line", service_line_x, 24.0, 0.415, 0.13, 6.8, 0.018, opera_light)
    box("opera_service_yard_centre_line", 0.0, 25.45, 0.415, 35.0, 0.13, 0.018, opera_light)

    # --- Inhabited foyer behind the curved glass. ---
    box("opera_foyer_back_wall", 0.0, -11.95, 7.05, 40.5, 1.55, 13.4, interior)
    box("opera_foyer_ceiling", 0.0, -14.0, 13.55, 40.5, 5.6, 0.32, limestone)
    for slat_index in range(41):
        slat_x = -19.0 + slat_index * 0.95
        box("opera_foyer_timber_slat", slat_x, -12.82, 7.05, 0.18, 0.13, 11.7, opera_wood)
    for balcony_z in (4.95, 8.15, 11.35):
        box("opera_foyer_balcony", 0.0, -13.75, balcony_z, 36.5, 2.35, 0.26, limestone)
        box("opera_foyer_balcony_wood_front", 0.0, -14.98, balcony_z + 0.38, 36.5, 0.12, 0.55, opera_wood)
        box("opera_foyer_balcony_glass_rail", 0.0, -15.02, balcony_z + 0.82, 36.5, 0.045, 0.38, opera_glass)
        box("opera_foyer_balcony_light", 0.0, -15.04, balcony_z - 0.18, 35.8, 0.045, 0.045, opera_light)
    for column_x in (-16.5, -8.25, 8.25, 16.5):
        cyl("opera_foyer_column", column_x, -14.55, 6.85, 0.23, 12.95, bronze, vertices=16)
        cyl("opera_foyer_column_base", column_x, -14.55, 0.62, 0.42, 0.52, opera_granite, vertices=16)
    # A pleated crimson performance curtain is visible through the foyer.
    box("opera_curtain_backing", 0.0, -12.35, 5.55, 13.4, 0.22, 9.0, interior)
    for pleat_index in range(21):
        pleat_x = -5.5 + pleat_index * 0.55
        cyl("opera_curtain_pleat", pleat_x, -12.55, 5.30, 0.17, 8.45, curtain, vertices=10)
    box("opera_curtain_pelmet", 0.0, -12.57, 9.78, 12.6, 0.30, 0.48, bronze)
    box("opera_curtain_light_wash", 0.0, -12.78, 1.02, 11.8, 0.08, 0.14, opera_light)
    for stair_side in (-1.0, 1.0):
        for step_index in range(10):
            step_x = stair_side * (2.05 + step_index * 0.74)
            step_z = 0.74 + step_index * 0.42
            box("opera_grand_interior_stair", step_x, -13.95, step_z, 0.72, 2.15, 0.15, limestone)
        tube_between("opera_grand_stair_handrail", (stair_side * 1.75, -15.02, 1.45),
                     (stair_side * 9.15, -15.02, 5.42), 0.045, 0.045, bronze, vertices=10)
    for light_index in range(11):
        light_x = -15.0 + light_index * 3.0
        pendant_z = 9.35 + (0.75 if light_index % 2 else 0.0)
        cyl("opera_pendant_rod", light_x, -14.45, (13.38 + pendant_z) * 0.5, 0.018, 13.38 - pendant_z, frame, vertices=6)
        cyl("opera_pendant_lantern", light_x, -14.45, pendant_z, 0.17, 0.26, opera_light, vertices=12)

    # Curved eleven-bay foyer curtain wall, doors, rails and canopy.
    facade_xs = [-19.0 + bay_index * 3.8 for bay_index in range(11)]
    facade_points = []
    for facade_x in facade_xs:
        facade_y = -16.55 - 1.15 * (1.0 - (facade_x / 19.0) ** 2)
        facade_points.append((facade_x, facade_y))
    for bay_index in range(10):
        x0, y0 = facade_points[bay_index]
        x1, y1 = facade_points[bay_index + 1]
        mid_x = (x0 + x1) * 0.5
        mid_y = (y0 + y1) * 0.5
        bay_dx = x1 - x0
        bay_dy = y1 - y0
        bay_length = math.hypot(bay_dx, bay_dy)
        bay_yaw = math.atan2(bay_dy, bay_dx)
        rbox("opera_curved_glass_pane", mid_x, mid_y, 7.15, bay_length + 0.035, 0.065, 10.85, opera_glass,
             rotation=(0.0, 0.0, bay_yaw))
        rbox("opera_glass_kick_plate", mid_x, mid_y - 0.055, 0.98, bay_length, 0.13, 1.08, opera_granite,
             rotation=(0.0, 0.0, bay_yaw))
        for rail_z in (1.82, 5.45, 9.08, 12.62):
            rbox("opera_curved_glass_rail", mid_x, mid_y - 0.065, rail_z, bay_length + 0.04, 0.13, 0.16, bronze,
                 rotation=(0.0, 0.0, bay_yaw))
        if 3 <= bay_index <= 6:
            direction_x = bay_dx / bay_length
            direction_y = bay_dy / bay_length
            normal_x = direction_y
            normal_y = -direction_x
            for door_side in (-0.82, 0.82):
                door_x = mid_x + direction_x * door_side + normal_x * 0.10
                door_y = mid_y + direction_y * door_side + normal_y * 0.10
                rbox("opera_entrance_door", door_x, door_y, 2.02, 1.52, 0.055, 3.18, opera_glass,
                     rotation=(0.0, 0.0, bay_yaw))
                handle_offset = 0.58 if door_side < 0.0 else -0.58
                handle_x = door_x + direction_x * handle_offset + normal_x * 0.075
                handle_y = door_y + direction_y * handle_offset + normal_y * 0.075
                cyl("opera_door_handle", handle_x, handle_y, 1.62, 0.026, 0.84, bronze, vertices=8)
            rbox("opera_door_header", mid_x + normal_x * 0.12, mid_y + normal_y * 0.12, 3.82,
                 bay_length * 0.92, 0.11, 0.24, bronze, rotation=(0.0, 0.0, bay_yaw))
    for point_index, (point_x, point_y) in enumerate(facade_points):
        if point_index == 0:
            tangent_yaw = math.atan2(facade_points[1][1] - point_y, facade_points[1][0] - point_x)
        elif point_index == len(facade_points) - 1:
            tangent_yaw = math.atan2(point_y - facade_points[-2][1], point_x - facade_points[-2][0])
        else:
            tangent_yaw = math.atan2(facade_points[point_index + 1][1] - facade_points[point_index - 1][1],
                                     facade_points[point_index + 1][0] - facade_points[point_index - 1][0])
        rbox("opera_curved_glass_mullion", point_x, point_y - 0.03, 7.15, 0.20, 0.27, 11.35, bronze,
             rotation=(0.0, 0.0, tangent_yaw))

    # Nine public colonnade fins carry the shell springing beam.  A
    # segmented tied canopy turns the doors into a real entrance in
    # silhouette and close-up rather than a decal or colour change.
    colonnade_points = []
    for fin_index in range(9):
        fin_x = -20.0 + fin_index * 5.0
        fin_y = -18.20 - 0.90 * (1.0 - (fin_x / 20.0) ** 2)
        tangent_yaw = math.atan(0.0045 * fin_x)
        colonnade_points.append((fin_x, fin_y, tangent_yaw))
        rbox("opera_colonnade_fin", fin_x, fin_y, 6.76, 0.62, 1.05, 12.80, limestone,
             rotation=(0.0, 0.0, tangent_yaw), bevel=0.035)
        rbox("opera_colonnade_bronze_edge", fin_x, fin_y - 0.59, 6.76, 0.16, 0.10, 12.80, bronze,
             rotation=(0.0, 0.0, tangent_yaw))
        rbox("opera_colonnade_base", fin_x, fin_y, 0.58, 0.92, 1.28, 0.44, opera_granite,
             rotation=(0.0, 0.0, tangent_yaw))
        rbox("opera_colonnade_capital", fin_x, fin_y, 13.28, 1.02, 1.34, 0.34, bronze,
             rotation=(0.0, 0.0, tangent_yaw))
        box("opera_colonnade_uplight", fin_x, fin_y - 0.75, 0.46, 0.22, 0.22, 0.07, opera_light)
    for bay_index in range(8):
        x0, y0, _yaw0 = colonnade_points[bay_index]
        x1, y1, _yaw1 = colonnade_points[bay_index + 1]
        beam_length = math.hypot(x1 - x0, y1 - y0)
        beam_yaw = math.atan2(y1 - y0, x1 - x0)
        rbox("opera_shell_springing_beam", (x0 + x1) * 0.5, (y0 + y1) * 0.5 + 0.15, 13.62,
             beam_length + 0.08, 0.85, 0.42, bronze, rotation=(0.0, 0.0, beam_yaw))
    for bay_index in range(10):
        x0, y0 = facade_points[bay_index]
        x1, y1 = facade_points[bay_index + 1]
        bay_length = math.hypot(x1 - x0, y1 - y0)
        bay_yaw = math.atan2(y1 - y0, x1 - x0)
        rbox("opera_entrance_canopy", (x0 + x1) * 0.5, (y0 + y1) * 0.5 - 1.28, 4.72,
             bay_length + 0.06, 2.55, 0.17, bronze, rotation=(0.055, 0.0, bay_yaw), bevel=0.03)
        rbox("opera_canopy_light", (x0 + x1) * 0.5, (y0 + y1) * 0.5 - 1.28, 4.60,
             bay_length * 0.72, 0.09, 0.035, opera_light, rotation=(0.055, 0.0, bay_yaw))
    for tie_x in (-16.0, -10.5, -5.0, 5.0, 10.5, 16.0):
        tie_facade_y = -16.55 - 1.15 * (1.0 - (tie_x / 19.0) ** 2)
        tube_between("opera_canopy_tie", (tie_x, tie_facade_y - 2.35, 4.86),
                     (tie_x, tie_facade_y - 0.12, 10.95), 0.030, 0.030, metal, vertices=8)

    # --- Three pleated ceramic shell vaults. ---
    shell_builder = MeshBuilder()
    shell_seam_builder = MeshBuilder()
    shell_glass_builder = MeshBuilder()
    shell_light_builder = MeshBuilder()
    shell_specs = (
        (-16.0, 6.9, 17.55, -15.6, 16.8),
        (0.0, 8.6, 21.68, -17.2, 18.2),
        (16.0, 6.9, 18.85, -16.1, 17.4),
    )

    def shell_point(spec, u, t, drop=0.0, y_offset=0.0):
        centre_x, half_width, peak_z, y_front, y_rear = spec
        profile = 0.80 + 0.20 * math.sin(math.pi * min(max(t * 1.08, 0.0), 1.0))
        width_scale = 0.88 + 0.12 * math.sin(math.pi * t)
        arch = max(math.cos(u * math.pi * 0.5), 0.0) ** 0.66
        point_x = centre_x + u * half_width * width_scale
        point_y = y_front + (y_rear - y_front) * t + y_offset
        point_z = 5.0 + (peak_z - 5.0) * profile * arch
        point_z += 0.050 * math.sin(u * math.pi * 7.0) * arch - drop
        return Vector((point_x, point_y, point_z))

    def offset_shell_point(spec, u, t, outward=0.065, y_offset=0.0):
        point = shell_point(spec, u, t, y_offset=y_offset)
        arch = max(math.cos(u * math.pi * 0.5), 0.0) ** 0.66
        point.x += (1.0 if u >= 0.0 else -1.0) * outward * (1.0 - arch)
        point.z += outward * (0.35 + 0.65 * arch)
        return point

    cross_segments = 32
    length_segments = 18
    shell_rows_by_spec = []
    for spec in shell_specs:
        outer_rows = []
        inner_rows = []
        outer_uv_rows = []
        inner_uv_rows = []
        for length_index in range(length_segments + 1):
            t = length_index / float(length_segments)
            outer_row = []
            inner_row = []
            outer_uv_row = []
            inner_uv_row = []
            for cross_index in range(cross_segments + 1):
                u = -1.0 + 2.0 * cross_index / float(cross_segments)
                outer_point = shell_point(spec, u, t)
                inner_point = shell_point(spec, u, t, drop=0.34)
                inner_point.x = spec[0] + (inner_point.x - spec[0]) * 0.985
                outer_row.append(shell_builder.add_vertex(outer_point))
                inner_row.append(shell_builder.add_vertex(inner_point))
                outer_uv_row.append(((outer_point.x + 26.0) / 3.0, (outer_point.y + 28.0) / 3.0))
                inner_uv_row.append(((inner_point.x + 26.0) / 3.0, (inner_point.y + 28.0) / 3.0))
            outer_rows.append(outer_row)
            inner_rows.append(inner_row)
            outer_uv_rows.append(outer_uv_row)
            inner_uv_rows.append(inner_uv_row)
        shell_rows_by_spec.append((outer_rows, inner_rows, outer_uv_rows, inner_uv_rows))
        for length_index in range(length_segments):
            for cross_index in range(cross_segments):
                shell_builder.quad(
                    outer_rows[length_index][cross_index],
                    outer_rows[length_index][cross_index + 1],
                    outer_rows[length_index + 1][cross_index + 1],
                    outer_rows[length_index + 1][cross_index],
                    (
                        outer_uv_rows[length_index][cross_index],
                        outer_uv_rows[length_index][cross_index + 1],
                        outer_uv_rows[length_index + 1][cross_index + 1],
                        outer_uv_rows[length_index + 1][cross_index],
                    ),
                )
                shell_builder.quad(
                    inner_rows[length_index][cross_index],
                    inner_rows[length_index + 1][cross_index],
                    inner_rows[length_index + 1][cross_index + 1],
                    inner_rows[length_index][cross_index + 1],
                    (
                        inner_uv_rows[length_index][cross_index],
                        inner_uv_rows[length_index + 1][cross_index],
                        inner_uv_rows[length_index + 1][cross_index + 1],
                        inner_uv_rows[length_index][cross_index + 1],
                    ),
                )
        # Close the rear of every vault in ceramic.  Fronts remain glazed.
        outer_rows, _inner_rows, outer_uv_rows, _inner_uv_rows = shell_rows_by_spec[-1]
        centre_x, _half_width, _peak_z, _y_front, y_rear = spec
        rear_centre = shell_builder.add_vertex(Vector((centre_x, y_rear, 5.05)))
        rear_centre_uv = ((centre_x + 26.0) / 3.0, (y_rear + 28.0) / 3.0)
        rear_row = outer_rows[-1]
        rear_uv_row = outer_uv_rows[-1]
        for cross_index in range(cross_segments):
            shell_builder.tri(
                rear_centre,
                rear_row[cross_index],
                rear_row[cross_index + 1],
                (rear_centre_uv, rear_uv_row[cross_index], rear_uv_row[cross_index + 1]),
            )
        # Thick shell skirts tie the vault into the podium cornice.
        for side_sign in (-1.0, 1.0):
            box("opera_shell_skirt", centre_x + side_sign * spec[1] * 0.94, (spec[3] + spec[4]) * 0.5, 4.72,
                0.62, spec[4] - spec[3], 1.55, shell_mat)

    for spec in shell_specs:
        centre_x, _half_width, _peak_z, y_front, _y_rear = spec
        # Front glazed lunette for each shell.
        cap_centre_point = Vector((centre_x, y_front + 0.10, 5.08))
        cap_centre = shell_glass_builder.add_vertex(cap_centre_point)
        cap_centre_uv = (0.5, 0.0)
        cap_row = []
        cap_uv_row = []
        for cross_index in range(cross_segments + 1):
            u = -1.0 + 2.0 * cross_index / float(cross_segments)
            cap_point = shell_point(spec, u, 0.0, drop=0.12, y_offset=0.10)
            cap_row.append(shell_glass_builder.add_vertex(cap_point))
            cap_uv_row.append(((u + 1.0) * 0.5, max(0.0, (cap_point.z - 5.0) / 16.0)))
        for cross_index in range(cross_segments):
            shell_glass_builder.tri(
                cap_centre,
                cap_row[cross_index + 1],
                cap_row[cross_index],
                (cap_centre_uv, cap_uv_row[cross_index + 1], cap_uv_row[cross_index]),
            )
        # Radiating and concentric bronze mullions on the lunette.
        for radial_u in (-0.78, -0.52, -0.26, 0.0, 0.26, 0.52, 0.78):
            arch_point = shell_point(spec, radial_u, 0.0, drop=0.10, y_offset=0.015)
            builder_tube(shell_seam_builder, [cap_centre_point, arch_point], [0.045, 0.045],
                         sides=5, uv_v_scale=0.35)
        for arc_fraction in (0.34, 0.62, 0.84):
            arc_points = []
            for arc_index in range(19):
                arc_u = -1.0 + 2.0 * arc_index / 18.0
                arch_point = shell_point(spec, arc_u, 0.0, drop=0.10, y_offset=0.015)
                arc_points.append(cap_centre_point + (arch_point - cap_centre_point) * arc_fraction)
            builder_tube(shell_seam_builder, arc_points, [0.034] * len(arc_points),
                         sides=5, uv_v_scale=0.35)
        # Longitudinal ceramic-panel ribs and transverse movement joints.
        for rib_u in (-0.84, -0.63, -0.42, -0.21, 0.0, 0.21, 0.42, 0.63, 0.84):
            rib_points = [offset_shell_point(spec, rib_u, rib_index / 18.0) for rib_index in range(19)]
            builder_tube(shell_seam_builder, rib_points, [0.055] * len(rib_points),
                         sides=5, uv_v_scale=0.45)
        for seam_t in (0.16, 0.32, 0.48, 0.64, 0.80):
            seam_points = [offset_shell_point(spec, -1.0 + seam_index / 12.0, seam_t, outward=0.050)
                           for seam_index in range(25)]
            builder_tube(shell_seam_builder, seam_points, [0.040] * len(seam_points),
                         sides=5, uv_v_scale=0.45)
        # Heavy front/rear fasciae and side edge beams show shell depth.
        for fascia_t, fascia_radius in ((0.0, 0.165), (1.0, 0.135)):
            fascia_points = [offset_shell_point(spec, -1.0 + fascia_index / 12.0, fascia_t, outward=0.035)
                             for fascia_index in range(25)]
            builder_tube(shell_seam_builder, fascia_points, [fascia_radius] * len(fascia_points),
                         sides=7, uv_v_scale=0.45)
        for edge_u in (-1.0, 1.0):
            edge_points = [offset_shell_point(spec, edge_u, edge_index / 18.0, outward=0.045)
                           for edge_index in range(19)]
            builder_tube(shell_seam_builder, edge_points, [0.135] * len(edge_points),
                         sides=7, uv_v_scale=0.45)
        # Continuous warm cove light under each front fascia.
        cove_points = []
        for cove_index in range(25):
            cove_u = -1.0 + cove_index / 12.0
            cove_point = shell_point(spec, cove_u, 0.0, drop=0.24, y_offset=-0.10)
            cove_points.append(cove_point)
        builder_tube(shell_light_builder, cove_points, [0.035] * len(cove_points),
                     sides=5, uv_v_scale=0.35)
        # Central bronze-framed skylight spine follows the vault crown.
        spine_points = [offset_shell_point(spec, 0.0, spine_index / 18.0, outward=0.10)
                        for spine_index in range(19)]
        builder_tube(shell_glass_builder, spine_points, [0.20] * len(spine_points),
                     sides=7, uv_v_scale=0.45)
        # Tapered shell buttress columns create a convincing load path.
        for support_side in (-1.0, 1.0):
            front_top = shell_point(spec, support_side * 0.91, 0.015)
            rear_top = shell_point(spec, support_side * 0.91, 0.985)
            tube_between("opera_shell_front_buttress",
                         (centre_x + support_side * spec[1] * 0.94, y_front + 1.05, 0.36),
                         (front_top.x, front_top.y, front_top.z), 0.27, 0.17, bronze, vertices=12)
            tube_between("opera_shell_rear_buttress",
                         (centre_x + support_side * spec[1] * 0.94, spec[4] - 1.05, 0.36),
                         (rear_top.x, rear_top.y, rear_top.z), 0.24, 0.16, bronze, vertices=12)

    shell_builder.build("opera_pleated_shells", shell_mat, smooth=True)
    shell_seam_builder.build("opera_shell_bronze_seams", bronze, smooth=True)
    shell_glass_builder.build("opera_shell_glass_lunettes", opera_glass, smooth=True)
    shell_light_builder.build("opera_shell_cove_lights", opera_light, smooth=True)
    # The sole object allowed to touch 22.00 m: a thin bronze finial.
    box("opera_exact_22m_finial", 0.0, 0.35, 21.96, 0.48, 2.20, 0.08, bronze)

    # --- Side restaurant terrace and north artists' entrance. ---
    box("opera_restaurant_deck", 24.35, 0.0, 0.58, 2.55, 24.0, 0.16, opera_wood)
    for pergola_y in (-11.0, -5.5, 0.0, 5.5, 11.0):
        cyl("opera_pergola_post", 25.35, pergola_y, 1.85, 0.075, 2.65, bronze, vertices=10)
    box("opera_pergola_beam", 25.35, 0.0, 3.16, 0.14, 23.4, 0.16, bronze)
    for slat_index in range(13):
        slat_y = -11.4 + slat_index * 1.9
        box("opera_pergola_slat", 24.35, slat_y, 3.28, 2.55, 0.12, 0.09, opera_wood)
    for table_y in (-8.25, -2.75, 2.75, 8.25):
        cyl("opera_terrace_table_top", 24.25, table_y, 1.32, 0.58, 0.07, limestone, vertices=18)
        cyl("opera_terrace_table_leg", 24.25, table_y, 0.97, 0.055, 0.66, bronze, vertices=10)
        for chair_offset in (-0.82, 0.82):
            box("opera_terrace_chair_seat", 24.25, table_y + chair_offset, 1.03, 0.46, 0.42, 0.07, opera_wood)
            box("opera_terrace_chair_back", 24.25, table_y + chair_offset + (0.20 if chair_offset > 0.0 else -0.20),
                1.27, 0.46, 0.06, 0.48, opera_wood)
        box("opera_terrace_table_light", 24.25, table_y, 1.43, 0.12, 0.12, 0.12, opera_light)

    box("opera_artist_door_frame", -23.12, 0.0, 2.05, 0.18, 1.75, 3.35, bronze)
    box("opera_artist_door", -23.24, 0.0, 2.05, 0.08, 1.48, 3.05, opera_glass)
    box("opera_artist_canopy", -23.82, 0.0, 3.92, 1.55, 2.75, 0.15, bronze)
    box("opera_artist_entrance_light", -23.34, 0.0, 3.48, 0.06, 1.25, 0.08, opera_light)
    box("opera_artist_step", -23.75, 0.0, 0.48, 1.35, 2.55, 0.14, limestone)

    # Emergency stairs at the service corners, with landings and rails.
    for stair_side in (-1.0, 1.0):
        stair_x = stair_side * 21.65
        for flight_index in range(4):
            flight_base_z = 0.55 + flight_index * 1.28
            rbox("opera_emergency_flight", stair_x, 18.65, flight_base_z + 0.56, 1.05, 2.75, 0.12, metal,
                 rotation=(0.43 if flight_index % 2 == 0 else -0.43, 0.0, 0.0))
            box("opera_emergency_landing", stair_x, 19.95 if flight_index % 2 == 0 else 17.35,
                flight_base_z + 1.18, 1.15, 0.95, 0.11, metal)
        box("opera_emergency_rail", stair_x + stair_side * 0.55, 18.65, 3.15, 0.045, 3.65, 0.045, bronze)

    # --- Forecourt sculpture, banners, furniture and landscape. ---
    sculpture_builder = MeshBuilder()
    sculpture_base = Vector((-20.2, -22.4, 0.72))
    sculpture_curves = (
        (Vector((-21.2, -23.0, 0.72)), Vector((-22.0, -22.8, 2.5)), Vector((-20.4, -21.7, 4.1)), Vector((-18.7, -22.0, 4.65))),
        (Vector((-20.2, -22.4, 0.72)), Vector((-20.6, -21.4, 2.8)), Vector((-19.2, -21.8, 4.3)), Vector((-19.9, -20.7, 5.25))),
        (Vector((-19.2, -23.0, 0.72)), Vector((-18.7, -23.3, 2.4)), Vector((-19.8, -22.7, 3.7)), Vector((-21.0, -21.6, 3.95))),
    )
    for curve_points in sculpture_curves:
        sampled = cubic_points(curve_points[0], curve_points[1], curve_points[2], curve_points[3], 14)
        builder_tube(sculpture_builder, sampled, [0.14] * len(sampled), sides=8, uv_v_scale=0.35)
    box("opera_sculpture_plinth", sculpture_base.x, sculpture_base.y, 0.54, 2.55, 2.55, 0.38, opera_granite)
    sculpture_builder.build("opera_bronze_forecourt_sculpture", bronze, smooth=True)

    box("opera_forecourt_sign_wall", 0.0, -25.65, 0.91, 10.5, 0.48, 1.10, opera_granite)
    box("opera_forecourt_sign_band", 0.0, -25.96, 1.12, 8.9, 0.055, 0.28, bronze)
    for sign_light_x in (-3.6, -1.8, 0.0, 1.8, 3.6):
        box("opera_sign_light_slit", sign_light_x, -26.005, 0.78, 0.58, 0.025, 0.055, opera_light)
    for banner_x in (-19.0, -13.0, 13.0, 19.0):
        cyl("opera_banner_pole", banner_x, -24.35, 3.88, 0.045, 7.05, bronze, vertices=10)
        box("opera_banner", banner_x + (0.48 if banner_x < 0.0 else -0.48), -24.35, 5.45, 0.88, 0.045, 3.35,
            curtain if abs(banner_x) > 15.0 else bronze)
        box("opera_banner_light_bar", banner_x + (0.48 if banner_x < 0.0 else -0.48), -24.39, 3.72, 0.88, 0.06, 0.07, opera_light)
    for bollard_x in (-22.0, -18.0, -14.0, -10.0, 10.0, 14.0, 18.0, 22.0):
        cyl("opera_forecourt_bollard", bollard_x, -26.75, 0.72, 0.085, 0.72, bronze, vertices=12)
        box("opera_forecourt_bollard_light", bollard_x, -26.75, 1.10, 0.10, 0.10, 0.045, opera_light)
    for bench_x in (-16.5, -9.5, 9.5, 16.5):
        box("opera_forecourt_bench", bench_x, -19.75, 0.68, 2.45, 0.52, 0.11, opera_wood)
        box("opera_forecourt_bench_base", bench_x, -19.75, 0.50, 2.00, 0.36, 0.28, opera_granite)
    for mast_x in (-22.5, 22.5):
        cyl("opera_forecourt_light_mast", mast_x, -20.5, 3.10, 0.055, 5.55, bronze, vertices=10)
        for head_offset in (-0.38, 0.38):
            box("opera_forecourt_light_head", mast_x + head_offset, -20.5, 5.92, 0.52, 0.16, 0.09, opera_light)
    for planter_x in (-21.5, -17.5, 17.5, 21.5):
        box("opera_front_planter", planter_x, -18.55, 0.66, 2.65, 0.82, 0.58, opera_granite)
        box("opera_front_planter_soil", planter_x, -18.55, 0.97, 2.38, 0.58, 0.045, mulch)
        box("opera_front_planter_hedge", planter_x, -18.55, 1.16, 2.18, 0.46, 0.34, hedge, bevel=0.045)

    formal_tree_builder = MeshBuilder()
    for garden_side in (-1.0, 1.0):
        box("opera_side_lawn", garden_side * 24.55, 21.0, 0.43, 1.65, 12.5, 0.055, lawn)
        box("opera_side_garden_hedge", garden_side * 24.55, 17.2, 0.76, 1.05, 3.35, 0.58, hedge, bevel=0.055)
        box("opera_side_garden_hedge", garden_side * 24.55, 24.8, 0.76, 1.05, 3.35, 0.58, hedge, bevel=0.055)
        for tree_y in (-13.0, 20.9):
            cyl("opera_formal_tree_planter", garden_side * 24.55, tree_y, 0.62, 0.78, 0.52, opera_granite, vertices=18)
            cyl("opera_formal_tree_trunk", garden_side * 24.55, tree_y, 1.75, 0.09, 1.95, opera_wood, vertices=10)
            # Five overlapping irregular ellipsoids avoid the perfect
            # green lollipop silhouette of a single UV sphere.
            tree_x = garden_side * 24.55
            canopy_clusters = (
                (0.00, 0.00, 3.18, 1.16, 1.04, 0.92, 0.20),
                (-0.62, -0.18, 2.88, 0.78, 0.72, 0.66, 0.85),
                (0.58, 0.22, 2.94, 0.82, 0.76, 0.70, -0.55),
                (-0.16, 0.58, 3.38, 0.76, 0.82, 0.68, 0.42),
                (0.20, -0.52, 3.48, 0.72, 0.70, 0.74, -0.24),
            )
            for cluster_x, cluster_y, cluster_z, radius_x, radius_y, radius_z, cluster_yaw in canopy_clusters:
                builder_ellipsoid(
                    formal_tree_builder,
                    Vector((tree_x + cluster_x, tree_y + cluster_y, cluster_z)),
                    (radius_x, radius_y, radius_z),
                    segments=10,
                    yaw=cluster_yaw,
                    pitch=cluster_yaw * 0.35,
                    rings=2,
                )
            tube_between("opera_formal_tree_branch", (tree_x, tree_y, 2.35),
                         (tree_x - 0.42, tree_y - 0.10, 3.05), 0.055, 0.035, opera_wood, vertices=8)
            tube_between("opera_formal_tree_branch", (tree_x, tree_y, 2.35),
                         (tree_x + 0.42, tree_y + 0.14, 3.10), 0.055, 0.035, opera_wood, vertices=8)
    for rear_planter_x in (-19.0, -14.5, 14.5, 19.0):
        box("opera_rear_planter", rear_planter_x, 26.35, 0.62, 2.45, 0.72, 0.52, opera_granite)
        box("opera_rear_planter_hedge", rear_planter_x, 26.35, 1.00, 2.12, 0.48, 0.34, hedge, bevel=0.045)
    formal_tree_builder.build("opera_formal_tree_canopies", hedge, smooth=True)


# --------------------------------------------------------------------------- #
# 0.2.17 botanical models.  These are deliberately geometric: palm fronds
# have a curved rachis and individual folded leaflets, grass consists of
# curved tapered blades, and flowers/shrubs have stems, branches, petals
# and berries.  No flat 10-card palm crown remains in the native world.
# --------------------------------------------------------------------------- #
def _random_direction(rng, minimum_z=-0.2):
    azimuth = rng.random() * math.tau
    z = rng.uniform(minimum_z, 1.0)
    xy = math.sqrt(max(0.0, 1.0 - z * z))
    return Vector((math.cos(azimuth) * xy, math.sin(azimuth) * xy, z))


def _palm_frond(builders, base, azimuth, length, elevation, droop, rng,
                leaflet_pairs=17, leaflet_length=0.48, dry=False, spines=False):
    outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
    side = Vector((-math.sin(azimuth), math.cos(azimuth), 0.0))
    up = Vector((0.0, 0.0, 1.0))
    initial = outward * math.cos(elevation) + up * math.sin(elevation)
    p0 = base
    p1 = base + initial * (length * 0.38)
    p2 = base + outward * (length * 0.78) + up * (math.sin(elevation) * length * 0.62 - droop * length * 0.34)
    p3 = base + outward * length + up * (math.sin(elevation) * length * 0.74 - droop * length)
    points = cubic_points(p0, p1, p2, p3, 11)
    radii = []
    for index in range(len(points)):
        t = index / float(len(points) - 1)
        radii.append(0.050 * ((1.0 - t) ** 0.72) + 0.007)
    builder_tube(builders["rachis"], points, radii, sides=5, uv_v_scale=0.45,
                 cap_start=False, cap_end=True)

    leaf_builder = builders["dry"] if dry else builders["leaf"]
    for pair_index in range(leaflet_pairs):
        pair_t = pair_index / float(max(leaflet_pairs - 1, 1))
        t = 0.20 + 0.76 * pair_t
        attachment = cubic_point(p0, p1, p2, p3, t)
        tangent = cubic_tangent(p0, p1, p2, p3, t)
        top = tangent.cross(side)
        if top.length <= 0.00001:
            top = up
        top.normalize()
        profile = math.sin(math.pi * (0.16 + 0.72 * pair_t))
        for sign in (-1.0, 1.0):
            local_attachment = attachment + tangent * (sign * 0.014)
            this_length = leaflet_length * (0.52 + 0.58 * profile) * rng.uniform(0.88, 1.10)
            if dry:
                this_length *= 0.78
            direction = (side * (sign * rng.uniform(0.66, 0.78)) +
                         tangent * rng.uniform(0.42, 0.56) +
                         top * (0.10 if dry else rng.uniform(0.24, 0.40)))
            if direction.length <= 0.00001:
                direction = side * sign
            direction.normalize()
            midpoint = local_attachment + direction * (this_length * 0.52) + up * (this_length * 0.030)
            tip = (local_attachment + direction * this_length +
                   tangent * (this_length * 0.045) -
                   up * (this_length * rng.uniform(0.17, 0.31)))
            builder_folded_leaf(
                leaf_builder,
                [local_attachment, midpoint, tip],
                [0.010, 0.024 if not dry else 0.019, 0.0],
                tangent,
                fold_ratio=0.42,
                uv_v_offset=rng.uniform(0.0, 0.35),
            )
    if spines:
        spine_builder = builders["rachis"]
        for spine_index in range(9):
            t = 0.050 + 0.015 * float(spine_index)
            attachment = cubic_point(p0, p1, p2, p3, t)
            tangent = cubic_tangent(p0, p1, p2, p3, t)
            for sign in (-1.0, 1.0):
                direction = (side * sign + tangent * 0.18 - up * 0.10).normalized()
                width_dir = tangent
                left = spine_builder.add_vertex(attachment - width_dir * 0.006)
                right = spine_builder.add_vertex(attachment + width_dir * 0.006)
                tip = spine_builder.add_vertex(attachment + direction * rng.uniform(0.075, 0.115))
                spine_builder.tri(left, right, tip)


def _palm_fruit_cluster(builders, origin, azimuth, rng):
    outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
    side = Vector((-math.sin(azimuth), math.cos(azimuth), 0.0))
    up = Vector((0.0, 0.0, 1.0))
    main_end = origin + outward * 0.34 - up * 0.42
    builder_tube(builders["rachis"], [origin, origin + outward * 0.16 - up * 0.13, main_end],
                 [0.026, 0.021, 0.015], sides=5, cap_start=False)
    for branch_index in range(6):
        spread = (float(branch_index) - 2.5) * 0.14
        end = main_end + side * spread + outward * rng.uniform(0.02, 0.13) - up * rng.uniform(0.30, 0.46)
        points = [main_end, (main_end + end) * 0.5 + outward * 0.035, end]
        builder_tube(builders["rachis"], points, [0.010, 0.008, 0.005], sides=4,
                     cap_start=False)
        for fruit_index in range(8):
            t = 0.18 + 0.78 * (fruit_index / 7.0)
            centre = points[0].lerp(points[-1], t)
            centre += side * rng.uniform(-0.018, 0.018) + outward * rng.uniform(-0.014, 0.020)
            builder_ellipsoid(
                builders["fruit"], centre,
                (0.020, 0.019, 0.030), segments=6,
                yaw=rng.random() * math.tau, pitch=rng.uniform(-0.25, 0.25), rings=1,
            )


def _build_palm_variant(name, species):
    rng = random.Random(1701 if species == "date" else 1702)
    builders = {key: MeshBuilder() for key in ("trunk", "crown", "leaf", "dry", "rachis", "fruit")}
    is_date = species == "date"
    trunk_height = 6.90 if is_date else 7.80
    lean = 0.52 if is_date else 0.34
    crown_length = 0.58 if is_date else 0.98
    p0 = Vector((0.0, 0.0, 0.0))
    p1 = Vector((lean * 0.07, lean * 0.02, trunk_height * 0.35))
    p2 = Vector((lean * 0.42, lean * 0.10, trunk_height * 0.72))
    p3 = Vector((lean, lean * 0.18, trunk_height))
    trunk_points = cubic_points(p0, p1, p2, p3, 37)
    trunk_radii = []
    for index in range(len(trunk_points)):
        t = index / float(len(trunk_points) - 1)
        if t < 0.05:
            radius = 0.345 - 0.70 * t
        elif t < 0.55:
            radius = 0.310 - 0.155 * ((t - 0.05) / 0.50)
        elif t < 0.92:
            radius = 0.233 - 0.100 * ((t - 0.55) / 0.37)
        else:
            radius = 0.196 + 0.20 * ((t - 0.92) / 0.08)
        trunk_radii.append(radius * (1.0 if is_date else 0.92))

    def trunk_variation(_index, angle, t):
        height = t * trunk_height
        if is_date:
            boot_layer = math.floor(height / 0.34)
            boot = max(0.0, math.sin(angle * 3.0 + boot_layer * 1.71))
            rib = 0.5 + 0.5 * math.sin(angle * 9.0 + height * 2.15)
            return 1.0 + 0.052 * boot * (1.0 - 0.28 * t) + 0.020 * rib
        return 1.0 + 0.018 * math.sin(height * 21.0) + 0.006 * math.sin(angle * 10.0 + height)

    builder_tube(builders["trunk"], trunk_points, trunk_radii, sides=16,
                 uv_u_repeat=3.0, uv_v_scale=0.52, radius_variation=trunk_variation)
    crown_base = trunk_points[-1]
    crown_points = []
    crown_radii = []
    for index in range(8):
        t = index / 7.0
        crown_points.append(Vector((crown_base.x + 0.08 * t, crown_base.y + 0.015 * t,
                                    crown_base.z - 0.08 + crown_length * t)))
        crown_radii.append(0.295 - 0.105 * (t ** 1.25) if is_date else 0.275 - 0.090 * (t ** 1.15))

    def crown_variation(_index, angle, _t):
        return 1.0 + (0.030 * math.sin(angle * 15.0) if is_date else 0.008 * math.sin(angle * 9.0))

    builder_tube(builders["crown"], crown_points, crown_radii, sides=16,
                 uv_u_repeat=2.0, uv_v_scale=0.75, radius_variation=crown_variation,
                 cap_start=False)
    crown_centre = crown_points[-1] + Vector((0.0, 0.0, 0.06))
    frond_count = 32 if is_date else 29
    for frond_index in range(frond_count):
        tier = frond_index / float(max(frond_count - 1, 1))
        azimuth = frond_index * 2.399963 + rng.uniform(-0.055, 0.055)
        outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
        base = crown_centre + outward * 0.10 + Vector((0.0, 0.0, -0.16 + 0.30 * (1.0 - tier)))
        if tier < 0.18:
            elevation = rng.uniform(0.82, 1.14)
            length = (2.05 if is_date else 2.25) * rng.uniform(0.92, 1.05)
            droop = rng.uniform(0.08, 0.18)
        elif tier < 0.60:
            elevation = rng.uniform(0.38, 0.78)
            length = (3.65 if is_date else 3.55) * rng.uniform(0.94, 1.06)
            droop = rng.uniform(0.28, 0.52)
        else:
            elevation = rng.uniform(0.02, 0.34)
            length = (3.95 if is_date else 3.75) * rng.uniform(0.94, 1.05)
            droop = rng.uniform(0.60, 0.94)
        _palm_frond(builders, base, azimuth, length, elevation, droop, rng,
                    leaflet_pairs=21 if is_date else 24,
                    leaflet_length=0.48 if is_date else 0.54,
                    spines=is_date)
    if is_date:
        for dry_index in range(9):
            azimuth = dry_index * (math.tau / 9.0) + 0.33
            outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
            base = crown_centre + outward * 0.09 - Vector((0.0, 0.0, 0.24))
            _palm_frond(builders, base, azimuth, rng.uniform(2.0, 2.45),
                        rng.uniform(-0.18, 0.02), rng.uniform(0.92, 1.12), rng,
                        leaflet_pairs=12, leaflet_length=0.40, dry=True)
        for azimuth in (0.55, 2.45):
            outward = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
            _palm_fruit_cluster(builders, crown_centre + outward * 0.20 - Vector((0.0, 0.0, 0.28)), azimuth, rng)
    material_names = {
        "trunk": "PalmTrunk",
        "crown": "PalmCrown" if is_date else "PalmCrownshaft",
        "leaf": "PalmLeaf",
        "dry": "PalmLeafDry",
        "rachis": "PalmRachis",
        "fruit": "PalmFruit",
    }
    for key, builder in builders.items():
        if builder.faces:
            builder.build("%s_%s" % (name, key), MATS[material_names[key]], smooth=True)


def build_palm_date():
    _build_palm_variant("palm_date", "date")


def build_palm_royal():
    _build_palm_variant("palm_royal", "royal")


def build_grass_tuft():
    # 0.2.23: 88 four-station folded blades (was 54 three-station),
    # each leaning along its own quadratic arc, plus broad clover-like
    # basal leaves and seeded heads.  All geometry stays merged into
    # the same two semantic materials, so the native wind materials,
    # 52 m detail range and far proxies are unchanged.
    rng = random.Random(1717)
    builders = {"leaf": MeshBuilder(), "dry": MeshBuilder()}
    for blade_index in range(88):
        azimuth = rng.random() * math.tau
        radius = 0.27 * math.sqrt(rng.random())
        base = Vector((math.cos(azimuth) * radius, math.sin(azimuth) * radius, 0.008))
        height = 0.18 + 0.34 * (rng.random() ** 0.72)
        lean_angle = rng.random() * math.tau
        lean = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0)) * rng.uniform(0.035, 0.145)
        centres = [
            base,
            base + lean * 0.14 + Vector((0.0, 0.0, height * 0.30)),
            base + lean * 0.46 + Vector((0.0, 0.0, height * 0.62)),
            base + lean + Vector((0.0, 0.0, height)),
        ]
        builder = builders["dry"] if rng.random() < 0.13 else builders["leaf"]
        builder_folded_leaf(builder, centres, [0.0130, 0.0110, 0.0070, 0.0],
                            Vector((-lean.y, lean.x, 0.0)), fold_ratio=0.28,
                            uv_v_offset=rng.uniform(0.0, 0.4))
        if blade_index % 8 == 0:
            builder_ellipsoid(builders["dry"], centres[-1] + Vector((0.0, 0.0, 0.018)),
                              (0.008, 0.008, 0.036), segments=6,
                              yaw=lean_angle, pitch=rng.uniform(-0.18, 0.18), rings=1)
    # Low broad leaves break the silhouette at the tuft's base so a
    # lawn edge does not read as identical vertical spikes.
    for _ in range(10):
        azimuth = rng.random() * math.tau
        direction = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
        base = direction * (0.10 * rng.random()) + Vector((0.0, 0.0, 0.012))
        length = rng.uniform(0.09, 0.16)
        centres = [
            base,
            base + direction * (length * 0.42) + Vector((0.0, 0.0, 0.020)),
            base + direction * (length * 0.78) + Vector((0.0, 0.0, 0.026)),
            base + direction * length + Vector((0.0, 0.0, 0.014)),
        ]
        builder_folded_leaf(builders["leaf"], centres, [0.006, 0.024, 0.020, 0.0],
                            Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.20,
                            uv_v_offset=rng.uniform(0.0, 0.35))
    builders["leaf"].build("grass_tuft_blades", MATS["GrassBlade"], smooth=True)
    builders["dry"].build("grass_tuft_dry_blades", MATS["GrassBladeDry"], smooth=True)


def build_flower_clump():
    # 0.2.23: a real bedding plant instead of a sparse rosette -- 48
    # four-station basal leaves, 20 open flowers with 8 outer petals,
    # 5 inner petals, domed centres, sepals and stem leaves, plus 6
    # closed buds.  Parts stay merged into the existing six semantic
    # materials so native batching/ranges are untouched.
    rng = random.Random(1731)
    leaf_builder = MeshBuilder()
    stem_builder = MeshBuilder()
    centre_builder = MeshBuilder()
    petal_builders = [MeshBuilder(), MeshBuilder(), MeshBuilder()]
    for leaf_index in range(48):
        azimuth = rng.random() * math.tau
        direction = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
        base = direction * (0.06 * rng.random()) + Vector((0.0, 0.0, 0.018))
        length = rng.uniform(0.16, 0.32)
        centres = [
            base,
            base + direction * (length * 0.34) + Vector((0.0, 0.0, rng.uniform(0.014, 0.034))),
            base + direction * (length * 0.68) + Vector((0.0, 0.0, rng.uniform(0.020, 0.048))),
            base + direction * length + Vector((0.0, 0.0, rng.uniform(0.004, 0.026))),
        ]
        builder_folded_leaf(leaf_builder, centres, [0.010, 0.030, 0.037, 0.0],
                            Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.22)
    for flower_index in range(20):
        azimuth = rng.random() * math.tau
        radius = 0.30 * math.sqrt(rng.random())
        base = Vector((math.cos(azimuth) * radius * 0.45, math.sin(azimuth) * radius * 0.45, 0.015))
        head = Vector((math.cos(azimuth) * radius, math.sin(azimuth) * radius, rng.uniform(0.25, 0.52)))
        midpoint = base.lerp(head, 0.52) + Vector((rng.uniform(-0.025, 0.025), rng.uniform(-0.025, 0.025), 0.0))
        builder_tube(stem_builder, [base, midpoint, head], [0.009, 0.007, 0.005], sides=6,
                     cap_start=False)
        # One small stem leaf halfway up the pedicel.
        stem_leaf_angle = rng.random() * math.tau
        stem_leaf_dir = Vector((math.cos(stem_leaf_angle), math.sin(stem_leaf_angle), 0.0))
        builder_folded_leaf(
            leaf_builder,
            [midpoint, midpoint + stem_leaf_dir * 0.045 + Vector((0.0, 0.0, 0.016)),
             midpoint + stem_leaf_dir * 0.095 + Vector((0.0, 0.0, 0.006))],
            [0.005, 0.022, 0.0],
            Vector((-stem_leaf_dir.y, stem_leaf_dir.x, 0.0)), fold_ratio=0.20)
        builder_ellipsoid(centre_builder, head + Vector((0.0, 0.0, 0.010)),
                          (0.019, 0.019, 0.014), segments=8, rings=2)
        petal_builder = petal_builders[flower_index % len(petal_builders)]
        # Green sepals cup the flower from below before the petals open.
        for sepal_index in range(4):
            sepal_angle = sepal_index * math.tau / 4.0 + rng.uniform(-0.10, 0.10)
            direction = Vector((math.cos(sepal_angle), math.sin(sepal_angle), 0.0))
            builder_folded_leaf(
                leaf_builder,
                [head - Vector((0.0, 0.0, 0.006)),
                 head + direction * 0.028 - Vector((0.0, 0.0, 0.010)),
                 head + direction * 0.058 - Vector((0.0, 0.0, 0.004))],
                [0.004, 0.014, 0.0],
                Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.18)
        for petal_index in range(8):
            petal_angle = petal_index * math.tau / 8.0 + rng.uniform(-0.06, 0.06)
            direction = Vector((math.cos(petal_angle), math.sin(petal_angle), 0.0))
            centres = [head, head + direction * 0.038 + Vector((0.0, 0.0, 0.010)),
                       head + direction * 0.082 + Vector((0.0, 0.0, 0.003))]
            builder_folded_leaf(petal_builder, centres, [0.004, 0.018, 0.0],
                                Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.16)
        for petal_index in range(5):
            petal_angle = petal_index * math.tau / 5.0 + 0.31 + rng.uniform(-0.06, 0.06)
            direction = Vector((math.cos(petal_angle), math.sin(petal_angle), 0.0))
            centres = [head + Vector((0.0, 0.0, 0.006)),
                       head + direction * 0.024 + Vector((0.0, 0.0, 0.016)),
                       head + direction * 0.048 + Vector((0.0, 0.0, 0.012))]
            builder_folded_leaf(petal_builder, centres, [0.003, 0.013, 0.0],
                                Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.14)
    # Closed buds on shorter pedicels between the open flowers.
    for bud_index in range(6):
        azimuth = rng.random() * math.tau
        radius = 0.24 * math.sqrt(rng.random())
        base = Vector((math.cos(azimuth) * radius * 0.5, math.sin(azimuth) * radius * 0.5, 0.015))
        head = Vector((math.cos(azimuth) * radius, math.sin(azimuth) * radius, rng.uniform(0.20, 0.38)))
        midpoint = base.lerp(head, 0.5) + Vector((rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), 0.0))
        builder_tube(stem_builder, [base, midpoint, head], [0.008, 0.006, 0.004], sides=6,
                     cap_start=False)
        builder_ellipsoid(petal_builders[bud_index % len(petal_builders)],
                          head + Vector((0.0, 0.0, 0.026)), (0.017, 0.017, 0.032),
                          segments=7, rings=2, yaw=rng.random() * math.tau)
        for sepal_index in range(3):
            sepal_angle = sepal_index * math.tau / 3.0 + rng.uniform(-0.12, 0.12)
            direction = Vector((math.cos(sepal_angle), math.sin(sepal_angle), 0.0))
            builder_folded_leaf(
                leaf_builder,
                [head, head + direction * 0.020 + Vector((0.0, 0.0, 0.018)),
                 head + direction * 0.032 + Vector((0.0, 0.0, 0.042))],
                [0.004, 0.012, 0.0],
                Vector((-direction.y, direction.x, 0.0)), fold_ratio=0.16)
    leaf_builder.build("flower_clump_leaves", MATS["FlowerLeaf"], smooth=True)
    stem_builder.build("flower_clump_stems", MATS["FlowerLeaf"], smooth=True)
    centre_builder.build("flower_clump_centres", MATS["FlowerCentre"], smooth=True)
    for builder, material_name in zip(petal_builders, ("FlowerCoral", "FlowerWhite", "FlowerYellow")):
        builder.build("flower_clump_%s" % material_name.lower(), MATS[material_name], smooth=True)


def build_ornamental_shrub():
    rng = random.Random(1753)
    branch_builder = MeshBuilder()
    leaf_builder = MeshBuilder()
    berry_builder = MeshBuilder()
    leaf_points = []
    queue = []
    for primary_index in range(6):
        azimuth = primary_index * math.tau / 6.0 + 0.41
        direction = Vector((math.cos(azimuth) * 0.48, math.sin(azimuth) * 0.48, 1.0)).normalized()
        queue.append((Vector((0.0, 0.0, 0.025)), direction, rng.uniform(0.34, 0.46), 0.026, 0))
    while queue:
        start, direction, length, radius, depth = queue.pop(0)
        bend = _random_direction(rng, 0.15) * 0.055
        midpoint = start + direction * (length * 0.52) + bend
        end = start + direction * length + bend * 0.45
        end.z = max(end.z, 0.055)
        builder_tube(branch_builder, [start, midpoint, end],
                     [radius, radius * 0.74, radius * 0.46], sides=6, cap_start=False)
        for t in (0.30, 0.52, 0.74, 0.94):
            leaf_points.append(start.lerp(end, t))
        if depth < 2:
            for _ in range(2):
                child = direction + _random_direction(rng, -0.10) * rng.uniform(0.38, 0.62)
                child.z = abs(child.z) + 0.22
                queue.append((end, child.normalized(), length * rng.uniform(0.62, 0.78),
                              radius * 0.62, depth + 1))
    for point in leaf_points:
        for _ in range(3):
            direction = _random_direction(rng, -0.05)
            length = rng.uniform(0.105, 0.205)
            centres = [point, point + direction * (length * 0.52) + Vector((0.0, 0.0, 0.012)),
                       point + direction * length]
            width_hint = Vector((-direction.y, direction.x, 0.18))
            builder_folded_leaf(leaf_builder, centres, [0.008, rng.uniform(0.024, 0.040), 0.0],
                                width_hint, fold_ratio=0.30, uv_v_offset=rng.uniform(0.0, 0.45))
        if rng.random() < 0.16:
            berry_centre = point + _random_direction(rng, 0.0) * 0.055
            builder_ellipsoid(berry_builder, berry_centre, (0.018, 0.018, 0.021),
                              segments=7, rings=2)
            if rng.random() < 0.35:
                builder_ellipsoid(berry_builder,
                                  berry_centre + _random_direction(rng, 0.0) * 0.034,
                                  (0.015, 0.015, 0.018), segments=6, rings=2)
    branch_builder.build("ornamental_shrub_branches", MATS["ShrubBranch"], smooth=True)
    leaf_builder.build("ornamental_shrub_leaves", MATS["OrnamentalLeaf"], smooth=True)
    if berry_builder.faces:
        berry_builder.build("ornamental_shrub_berries", MATS["ShrubBerry"], smooth=True)



# --------------------------------------------------------------------------- #
# Building Model No.7: RichTown Mosque, fixed scale 38.40 x 36.00 m,
# exactly 30.00 m to the minaret finials.  Blender +X is the eastern
# entrance front (Godot +X after Y-up export); Blender Y spans the
# 36 m north-south parcel.  This replaces the runtime sand box, plain
# sphere and two bare cylinders at X620/Z335 with a finished civic
# building: carved sandstone prayer hall, grand eastern pishtaq/iwan,
# ribbed onion dome on a windowed drum, four satellite domes, two
# balconied minarets, side arcades, mashrabiya screens, glazed tile
# bands, cedar doors, lanterns and a granite terrace.
# --------------------------------------------------------------------------- #
def build_mosque():
    stone = MATS["MosqueStone"]
    limestone = MATS["MosqueLimestone"]
    dome_mat = MATS["MosqueDome"]
    brass = MATS["MosqueBrass"]
    mosque_glass = MATS["MosqueGlass"]
    interior = MATS["MosqueInterior"]
    mosque_wood = MATS["MosqueWood"]
    tile = MATS["MosqueTile"]
    granite = MATS["MosqueGranite"]
    mosque_light = MATS["MosqueLight"]
    frame = MATS["WindowFrame"]
    roof_dark = MATS["RoofDark"]

    def torus(name, x, y, z, major, minor, material, rotation=(0.0, 0.0, 0.0)):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=major, minor_radius=minor,
            major_segments=28, minor_segments=8,
            location=(x, y, z), rotation=rotation,
        )
        obj = bpy.context.active_object
        obj.name = name
        return finish(obj, material, smooth=True)

    # Semicircular arch caps are extruded half-discs grouped by material.
    # Full cylinder discs were rejected in visual audit: their lower
    # halves turned every arched window into an oval medallion and the
    # iwan into a huge tilted disc across the portal.
    arch_builders = {
        "limestone": MeshBuilder(),
        "glass": MeshBuilder(),
        "brass": MeshBuilder(),
        "interior": MeshBuilder(),
    }

    def add_half_disc_x(builder, centre_x, centre_y, centre_z, radius, thickness, sign):
        segments = 16
        x_back = centre_x - sign * thickness * 0.5
        x_front = centre_x + sign * thickness * 0.5
        back_centre = builder.add_vertex(Vector((x_back, centre_y, centre_z)))
        front_centre = builder.add_vertex(Vector((x_front, centre_y, centre_z)))
        back_points = []
        front_points = []
        for index in range(segments + 1):
            angle = math.pi * float(index) / float(segments)
            py = centre_y + math.cos(angle) * radius
            pz = centre_z + math.sin(angle) * radius
            back_points.append(builder.add_vertex(Vector((x_back, py, pz))))
            front_points.append(builder.add_vertex(Vector((x_front, py, pz))))
        for index in range(segments):
            if sign >= 0.0:
                builder.tri(front_centre, front_points[index], front_points[index + 1])
                builder.tri(back_centre, back_points[index + 1], back_points[index])
            else:
                builder.tri(front_centre, front_points[index + 1], front_points[index])
                builder.tri(back_centre, back_points[index], back_points[index + 1])
            builder.quad(back_points[index], front_points[index], front_points[index + 1], back_points[index + 1])
        builder.quad(back_points[0], back_points[-1], front_points[-1], front_points[0])

    def add_half_disc_y(builder, centre_x, centre_y, centre_z, radius, thickness, sign):
        segments = 16
        y_back = centre_y - sign * thickness * 0.5
        y_front = centre_y + sign * thickness * 0.5
        back_centre = builder.add_vertex(Vector((centre_x, y_back, centre_z)))
        front_centre = builder.add_vertex(Vector((centre_x, y_front, centre_z)))
        back_points = []
        front_points = []
        for index in range(segments + 1):
            angle = math.pi * float(index) / float(segments)
            px = centre_x + math.cos(angle) * radius
            pz = centre_z + math.sin(angle) * radius
            back_points.append(builder.add_vertex(Vector((px, y_back, pz))))
            front_points.append(builder.add_vertex(Vector((px, y_front, pz))))
        for index in range(segments):
            if sign >= 0.0:
                builder.tri(front_centre, front_points[index + 1], front_points[index])
                builder.tri(back_centre, back_points[index], back_points[index + 1])
            else:
                builder.tri(front_centre, front_points[index], front_points[index + 1])
                builder.tri(back_centre, back_points[index + 1], back_points[index])
            builder.quad(back_points[index], back_points[index + 1], front_points[index + 1], front_points[index])
        builder.quad(back_points[0], front_points[0], front_points[-1], back_points[-1])

    def arch_window_x(face_x, centre_y, centre_z, width=1.70, height=3.60, screen=False):
        sign = 1.0 if face_x >= 0.0 else -1.0
        outer_x = face_x + sign * 0.055
        box("mosque_window_frame_x", outer_x, centre_y, centre_z,
            0.12, width + 0.26, height + 0.24, limestone)
        box("mosque_window_reveal_x", outer_x + sign * 0.035, centre_y, centre_z,
            0.07, width + 0.08, height + 0.08, interior)
        box("mosque_window_glass_x", outer_x + sign * 0.085, centre_y, centre_z,
            0.05, width, height, mosque_glass)
        add_half_disc_x(arch_builders["limestone"], outer_x, centre_y,
                        centre_z + height * 0.5, (width + 0.26) * 0.5, 0.12, sign)
        add_half_disc_x(arch_builders["glass"], outer_x + sign * 0.085, centre_y,
                        centre_z + height * 0.5, width * 0.5, 0.055, sign)
        box("mosque_window_mullion_x", outer_x + sign * 0.115, centre_y, centre_z,
            0.045, 0.085, height, brass)
        box("mosque_window_transom_x", outer_x + sign * 0.115, centre_y,
            centre_z + height * 0.12, 0.045, width, 0.085, brass)
        box("mosque_window_sill_x", outer_x + sign * 0.10, centre_y,
            centre_z - height * 0.5 - 0.17, 0.20, width + 0.42, 0.13, limestone)
        if screen:
            for offset_y in (-width * 0.30, 0.0, width * 0.30):
                box("mosque_mashrabiya_v_x", outer_x + sign * 0.145,
                    centre_y + offset_y, centre_z, 0.035, 0.055, height * 0.92, mosque_wood)
            for offset_z in (-height * 0.28, 0.0, height * 0.28):
                box("mosque_mashrabiya_h_x", outer_x + sign * 0.145, centre_y,
                    centre_z + offset_z, 0.035, width * 0.92, 0.055, mosque_wood)

    def arch_window_y(centre_x, face_y, centre_z, width=1.70, height=3.60, screen=False):
        sign = 1.0 if face_y >= 0.0 else -1.0
        outer_y = face_y + sign * 0.055
        box("mosque_window_frame_y", centre_x, outer_y, centre_z,
            width + 0.26, 0.12, height + 0.24, limestone)
        box("mosque_window_reveal_y", centre_x, outer_y + sign * 0.035, centre_z,
            width + 0.08, 0.07, height + 0.08, interior)
        box("mosque_window_glass_y", centre_x, outer_y + sign * 0.085, centre_z,
            width, 0.05, height, mosque_glass)
        add_half_disc_y(arch_builders["limestone"], centre_x, outer_y,
                        centre_z + height * 0.5, (width + 0.26) * 0.5, 0.12, sign)
        add_half_disc_y(arch_builders["glass"], centre_x, outer_y + sign * 0.085,
                        centre_z + height * 0.5, width * 0.5, 0.055, sign)
        box("mosque_window_mullion_y", centre_x, outer_y + sign * 0.115, centre_z,
            0.085, 0.045, height, brass)
        box("mosque_window_transom_y", centre_x, outer_y + sign * 0.115,
            centre_z + height * 0.12, width, 0.045, 0.085, brass)
        box("mosque_window_sill_y", centre_x, outer_y + sign * 0.10,
            centre_z - height * 0.5 - 0.17, width + 0.42, 0.20, 0.13, limestone)
        if screen:
            for offset_x in (-width * 0.30, 0.0, width * 0.30):
                box("mosque_mashrabiya_v_y", centre_x + offset_x,
                    outer_y + sign * 0.145, centre_z, 0.055, 0.035, height * 0.92, mosque_wood)
            for offset_z in (-height * 0.28, 0.0, height * 0.28):
                box("mosque_mashrabiya_h_y", centre_x, outer_y + sign * 0.145,
                    centre_z + offset_z, width * 0.92, 0.035, 0.055, mosque_wood)

    def add_lathe(builder, centre_x, centre_y, base_z, profile, segments=40):
        rows = []
        for radius, dz in profile:
            if radius <= 0.01:
                rows.append((builder.add_vertex(Vector((centre_x, centre_y, base_z + dz))),))
            else:
                row = []
                for index in range(segments):
                    angle = math.tau * float(index) / float(segments)
                    row.append(builder.add_vertex(Vector((
                        centre_x + math.cos(angle) * radius,
                        centre_y + math.sin(angle) * radius,
                        base_z + dz,
                    ))))
                rows.append(tuple(row))
        for row_index in range(len(rows) - 1):
            current = rows[row_index]
            following = rows[row_index + 1]
            v0 = float(row_index) / 3.0
            v1 = float(row_index + 1) / 3.0
            if len(current) > 1 and len(following) > 1:
                for index in range(segments):
                    nxt = (index + 1) % segments
                    u0 = float(index) / float(segments) * 8.0
                    u1 = float(index + 1) / float(segments) * 8.0
                    builder.quad(current[index], current[nxt], following[nxt], following[index],
                                 ((u0, v0), (u1, v0), (u1, v1), (u0, v1)))
            elif len(current) > 1 and len(following) == 1:
                for index in range(segments):
                    nxt = (index + 1) % segments
                    builder.tri(current[index], current[nxt], following[0])

    def add_crescent(builder, centre_x, centre_y, centre_z, scale=1.0):
        stations = 14
        outer_points = []
        inner_points = []
        for index in range(stations + 1):
            t = float(index) / float(stations)
            outer_angle = math.radians(35.0 - 250.0 * t)
            inner_angle = math.radians(14.0 - 208.0 * t)
            outer_points.append((math.cos(outer_angle) * 0.55, math.sin(outer_angle) * 0.55))
            inner_points.append((math.cos(inner_angle) * 0.465,
                                 0.20 + math.sin(inner_angle) * 0.465))
        front_outer = []
        front_inner = []
        back_outer = []
        back_inner = []
        for index in range(stations + 1):
            ox, oz = outer_points[index]
            ix, iz = inner_points[index]
            front_outer.append(builder.add_vertex(Vector((centre_x + ox * scale, centre_y - 0.045, centre_z + oz * scale))))
            front_inner.append(builder.add_vertex(Vector((centre_x + ix * scale, centre_y - 0.045, centre_z + iz * scale))))
            back_outer.append(builder.add_vertex(Vector((centre_x + ox * scale, centre_y + 0.045, centre_z + oz * scale))))
            back_inner.append(builder.add_vertex(Vector((centre_x + ix * scale, centre_y + 0.045, centre_z + iz * scale))))
        for index in range(stations):
            builder.quad(front_outer[index], front_outer[index + 1], front_inner[index + 1], front_inner[index])
            builder.quad(back_outer[index], back_inner[index], back_inner[index + 1], back_outer[index + 1])
            builder.quad(front_outer[index], back_outer[index], back_outer[index + 1], front_outer[index + 1])
            builder.quad(front_inner[index], front_inner[index + 1], back_inner[index + 1], back_inner[index])

    # --- Granite plinth, limestone terrace and eastern steps. ---
    box("mosque_granite_plinth", 0.0, 0.0, 0.18, 38.40, 36.00, 0.36, granite)
    box("mosque_terrace", 0.0, 0.0, 0.49, 37.20, 34.80, 0.26, limestone)
    box("mosque_terrace_inlay_east", 18.05, 0.0, 0.635, 0.22, 15.5, 0.025, tile)
    for joint_y in (-12.0, -6.0, 6.0, 12.0):
        box("mosque_terrace_joint", 16.5, joint_y, 0.632, 3.2, 0.07, 0.018, granite)
    for step_index, (step_x, step_top) in enumerate(((18.45, 0.50), (18.82, 0.34), (19.07, 0.18))):
        box("mosque_east_step", step_x, 0.0, step_top * 0.5,
            0.42 - step_index * 0.08, 10.5, step_top, limestone)
    for side_sign in (-1.0, 1.0):
        box("mosque_step_cheek", 18.525, side_sign * 5.55, 0.42, 1.35, 0.28, 0.84, granite)
        box("mosque_step_light", 18.78, side_sign * 5.36, 0.72, 0.07, 0.09, 0.12, mosque_light)

    # --- Prayer hall mass, cornice, stone piers and masonry seams. ---
    box("mosque_hall", 0.0, 0.0, 6.52, 28.00, 32.00, 11.80, stone)
    box("mosque_hall_plinth", 0.0, 0.0, 1.02, 28.35, 32.35, 0.80, granite)
    box("mosque_hall_cornice", 0.0, 0.0, 12.68, 28.75, 32.75, 0.54, limestone)
    box("mosque_hall_roof", 0.0, 0.0, 13.10, 28.25, 32.25, 0.30, stone)
    box("mosque_hall_parapet_trim", 0.0, 0.0, 12.32, 28.45, 32.45, 0.18, brass)
    for seam_z in (3.10, 5.90, 8.70):
        box("mosque_hall_seam_east", 14.035, 0.0, seam_z, 0.07, 31.7, 0.065, frame)
        box("mosque_hall_seam_west", -14.035, 0.0, seam_z, 0.07, 31.7, 0.065, frame)
        box("mosque_hall_seam_north", 0.0, 16.035, seam_z, 27.7, 0.07, 0.065, frame)
        box("mosque_hall_seam_south", 0.0, -16.035, seam_z, 27.7, 0.07, 0.065, frame)
    for pier_y in (-14.5, -10.0, -5.5, 5.5, 10.0, 14.5):
        box("mosque_hall_pier_east", 14.10, pier_y, 6.55, 0.28, 0.72, 11.55, limestone)
        box("mosque_hall_pier_west", -14.10, pier_y, 6.55, 0.28, 0.72, 11.55, limestone)
    for pier_x in (-12.0, -8.0, -4.0, 0.0, 4.0, 8.0, 12.0):
        box("mosque_hall_pier_north", pier_x, 16.10, 6.55, 0.72, 0.28, 11.55, limestone)
        box("mosque_hall_pier_south", pier_x, -16.10, 6.55, 0.72, 0.28, 11.55, limestone)

    # Glazed turquoise inscription-style band (abstract geometry only:
    # tile field, brass rails and diamond insets, no text geometry).
    box("mosque_tile_band_east", 14.07, 0.0, 11.18, 0.09, 31.4, 0.92, tile)
    box("mosque_tile_band_west", -14.07, 0.0, 11.18, 0.09, 31.4, 0.92, tile)
    box("mosque_tile_band_north", 0.0, 16.07, 11.18, 27.4, 0.09, 0.92, tile)
    box("mosque_tile_band_south", 0.0, -16.07, 11.18, 27.4, 0.09, 0.92, tile)
    for diamond_y in range(-14, 15, 4):
        rbox("mosque_tile_diamond_east", 14.14, float(diamond_y), 11.18,
             0.045, 0.27, 0.27, brass, rotation=(math.pi * 0.25, 0.0, 0.0))
        rbox("mosque_tile_diamond_west", -14.14, float(diamond_y), 11.18,
             0.045, 0.27, 0.27, brass, rotation=(math.pi * 0.25, 0.0, 0.0))
    for diamond_x in range(-12, 13, 4):
        rbox("mosque_tile_diamond_north", float(diamond_x), 16.14, 11.18,
             0.27, 0.045, 0.27, brass, rotation=(0.0, math.pi * 0.25, 0.0))
        rbox("mosque_tile_diamond_south", float(diamond_x), -16.14, 11.18,
             0.27, 0.045, 0.27, brass, rotation=(0.0, math.pi * 0.25, 0.0))

    # Hall windows: screened lower lights and clear upper lights.
    for window_y in (-12.25, -7.75, 7.75, 12.25):
        arch_window_x(14.0, window_y, 4.05, width=1.85, height=4.10, screen=True)
        arch_window_x(14.0, window_y, 8.55, width=1.55, height=2.45, screen=False)
        arch_window_x(-14.0, window_y, 4.05, width=1.85, height=4.10, screen=True)
        arch_window_x(-14.0, window_y, 8.55, width=1.55, height=2.45, screen=False)
    for window_x in (-10.0, -6.0, -2.0, 2.0, 6.0, 10.0):
        arch_window_y(window_x, 16.0, 8.55, width=1.55, height=2.45, screen=False)
        arch_window_y(window_x, -16.0, 8.55, width=1.55, height=2.45, screen=False)
        arch_window_y(window_x, 16.0, 3.55, width=1.70, height=3.15, screen=True)
        arch_window_y(window_x, -16.0, 3.55, width=1.70, height=3.15, screen=True)

    # Western mihrab projection with a half-dome cap.
    box("mosque_mihrab_projection", -14.65, 0.0, 4.85, 1.35, 8.40, 8.55, stone)
    box("mosque_mihrab_trim", -15.36, 0.0, 7.15, 0.12, 8.75, 0.28, limestone)
    # A small cupola crowns the mihrab bay.  The first CI render used
    # a full flattened ellipsoid here; its lower half bulged through
    # the west wall as a turquoise oval "eye", so the cap is now a
    # drum-and-dome turret that only rises above the bay roofline.
    cyl("mosque_mihrab_cupola_drum", -14.65, 0.0, 9.55, 1.05, 0.85, stone, vertices=16)
    torus("mosque_mihrab_cupola_cornice", -14.65, 0.0, 9.98, 1.08, 0.070, limestone)
    sphere("mosque_mihrab_cupola_dome", -14.65, 0.0, 10.28, 2.30, 2.30, 1.55, dome_mat)
    cyl("mosque_mihrab_cupola_finial", -14.65, 0.0, 11.18, 0.030, 0.55, brass, vertices=8)
    sphere("mosque_mihrab_cupola_orb", -14.65, 0.0, 11.32, 0.20, 0.20, 0.20, brass)
    arch_window_x(-15.32, 0.0, 4.45, width=2.15, height=4.65, screen=True)

    # --- Grand eastern pishtaq / iwan portal. ---
    box("mosque_portal", 16.10, 0.0, 9.31, 4.20, 16.00, 17.38, stone)
    box("mosque_portal_plinth", 16.10, 0.0, 1.02, 4.45, 16.35, 0.80, granite)
    box("mosque_portal_cornice", 16.10, 0.0, 18.08, 4.55, 16.55, 0.34, limestone)
    box("mosque_portal_roof", 16.10, 0.0, 18.32, 4.25, 16.20, 0.18, roof_dark)
    for side_sign in (-1.0, 1.0):
        box("mosque_portal_frame_pier", 18.24, side_sign * 7.55, 9.35,
            0.16, 0.85, 16.70, limestone)
        box("mosque_portal_tile_pier", 18.30, side_sign * 6.92, 9.35,
            0.07, 0.38, 15.90, tile)
        box("mosque_portal_lantern_frame", 18.34, side_sign * 5.85, 6.85,
            0.16, 0.42, 0.72, brass)
        sphere("mosque_portal_lantern_globe", 18.40, side_sign * 5.85, 6.85,
               0.22, 0.30, 0.48, mosque_light)
        arch_window_x(18.20, side_sign * 6.45, 3.45, width=1.05, height=2.65, screen=True)
    box("mosque_portal_top_frame", 18.24, 0.0, 17.35, 0.16, 15.95, 0.85, limestone)
    box("mosque_portal_tile_panel", 18.30, 0.0, 15.55, 0.08, 12.60, 1.85, tile)
    for diamond_y in (-5.0, -3.0, -1.0, 1.0, 3.0, 5.0):
        rbox("mosque_portal_tile_diamond", 18.37, diamond_y, 15.55,
             0.045, 0.34, 0.34, brass, rotation=(math.pi * 0.25, 0.0, 0.0))
    box("mosque_portal_tile_rail_top", 18.34, 0.0, 16.56, 0.05, 12.8, 0.08, brass)
    box("mosque_portal_tile_rail_bottom", 18.34, 0.0, 14.54, 0.05, 12.8, 0.08, brass)

    # Recessed iwan: dark vault reveal, arch orders and corbel rows.
    box("mosque_iwan_reveal", 18.16, 0.0, 7.10, 0.14, 10.40, 11.75, interior)
    add_half_disc_x(arch_builders["limestone"], 18.25, 0.0, 12.98, 5.35, 0.20, 1.0)
    add_half_disc_x(arch_builders["brass"], 18.31, 0.0, 12.98, 5.02, 0.10, 1.0)
    add_half_disc_x(arch_builders["interior"], 18.24, 0.0, 12.98, 4.72, 0.12, 1.0)
    for row_index, row_z in enumerate((10.65, 11.45, 12.25)):
        count = 9 - row_index * 2
        for cell_index in range(count):
            cell_y = -float(count - 1) * 0.52 + cell_index * 1.04
            box("mosque_muqarnas_cell", 18.34, cell_y, row_z,
                0.18, 0.72, 0.52, limestone if row_index % 2 == 0 else stone)
            box("mosque_muqarnas_shadow", 18.40, cell_y, row_z - 0.30,
                0.05, 0.55, 0.07, interior)
    box("mosque_iwan_light_slot", 18.36, 0.0, 9.92, 0.045, 7.6, 0.07, mosque_light)
    for side_sign in (-1.0, 1.0):
        door_y = side_sign * 1.18
        box("mosque_cedar_door", 18.27, door_y, 3.52, 0.16, 2.25, 5.85, mosque_wood)
        for plank_offset in (-0.72, -0.24, 0.24, 0.72):
            box("mosque_door_plank_shadow", 18.36, door_y + plank_offset, 3.52,
                0.035, 0.045, 5.45, interior)
        for stud_z in (1.35, 2.55, 3.75, 4.95, 6.00):
            cyl("mosque_door_stud", 18.39, door_y - side_sign * 0.72, stud_z,
                0.055, 0.045, brass, vertices=8, rotation=(0.0, math.pi * 0.5, 0.0))
            cyl("mosque_door_stud", 18.39, door_y + side_sign * 0.72, stud_z,
                0.055, 0.045, brass, vertices=8, rotation=(0.0, math.pi * 0.5, 0.0))
        torus("mosque_door_ring", 18.43, door_y - side_sign * 1.02, 3.25,
              0.24, 0.028, brass, rotation=(0.0, math.pi * 0.5, 0.0))
        box("mosque_door_handle_plate", 18.38, door_y - side_sign * 1.02, 3.55,
            0.05, 0.18, 0.42, brass)
    box("mosque_door_threshold", 18.30, 0.0, 0.68, 0.32, 5.05, 0.12, granite)

    # --- North/south side arcades with columns, beams and roof slats. ---
    for side_sign in (-1.0, 1.0):
        box("mosque_side_wing", 1.0, side_sign * 16.75, 2.70,
            24.00, 1.50, 4.20, stone)
        box("mosque_side_wing_roof", 1.0, side_sign * 16.95, 5.08,
            25.00, 2.10, 0.36, limestone)
        box("mosque_side_wing_tile_frieze", 1.0, side_sign * 17.54, 4.55,
            23.40, 0.07, 0.52, tile)
        for column_x in (-10.0, -6.0, -2.0, 2.0, 6.0, 10.0):
            box("mosque_arcade_column", column_x, side_sign * 17.42, 2.82,
                0.46, 0.46, 4.45, limestone)
            box("mosque_arcade_column_base", column_x, side_sign * 17.42, 0.72,
                0.68, 0.68, 0.28, granite)
            box("mosque_arcade_column_capital", column_x, side_sign * 17.42, 4.88,
                0.68, 0.68, 0.26, brass)
        for bay_x in (-8.0, -4.0, 0.0, 4.0, 8.0):
            box("mosque_arcade_beam", bay_x, side_sign * 17.42, 4.48,
                3.45, 0.18, 0.62, limestone)
            add_half_disc_y(arch_builders["interior"], bay_x, side_sign * 17.43,
                            2.92, 1.25, 0.10, side_sign)
            arch_window_y(bay_x, side_sign * 17.50, 2.45, width=1.45, height=2.55, screen=True)
        for slat_index in range(13):
            box("mosque_side_roof_slat", -10.8 + slat_index * 1.8, side_sign * 16.95, 5.34,
                0.16, 1.85, 0.09, mosque_wood)

    # --- Windowed drum and ribbed onion dome. ---
    cyl("mosque_drum", 0.0, 0.0, 14.75, 8.50, 3.00, stone, vertices=24)
    cyl("mosque_drum_plinth", 0.0, 0.0, 13.38, 8.85, 0.32, limestone, vertices=24)
    torus("mosque_drum_cornice", 0.0, 0.0, 16.28, 8.58, 0.20, limestone)
    torus("mosque_drum_tile_ring", 0.0, 0.0, 13.78, 8.56, 0.10, tile)
    for window_index in range(12):
        angle = math.tau * float(window_index) / 12.0
        wx = math.cos(angle) * 8.52
        wy = math.sin(angle) * 8.52
        rbox("mosque_drum_window_frame", wx, wy, 14.82, 1.22, 0.10, 1.95,
             limestone, rotation=(0.0, 0.0, angle + math.pi * 0.5))
        rbox("mosque_drum_window_glass", math.cos(angle) * 8.59, math.sin(angle) * 8.59,
             14.82, 0.98, 0.06, 1.72, mosque_glass,
             rotation=(0.0, 0.0, angle + math.pi * 0.5))
        rbox("mosque_drum_window_mullion", math.cos(angle) * 8.64, math.sin(angle) * 8.64,
             14.82, 0.075, 0.045, 1.72, brass,
             rotation=(0.0, 0.0, angle + math.pi * 0.5))
    dome_builder = MeshBuilder()
    dome_profile = (
        (8.85, 0.00), (9.08, 0.34), (8.92, 1.05), (8.15, 2.35),
        (6.85, 3.85), (5.05, 5.25), (3.05, 6.35), (1.35, 7.05),
        (0.30, 7.42), (0.00, 7.58),
    )
    add_lathe(dome_builder, 0.0, 0.0, 15.92, dome_profile, segments=42)
    dome_builder.build("mosque_main_dome", dome_mat, smooth=True)
    rib_builder = MeshBuilder()
    for rib_index in range(16):
        angle = math.tau * float(rib_index) / 16.0
        rib_points = []
        for radius, dz in dome_profile[:-1]:
            rib_radius = radius + 0.075
            rib_points.append(Vector((math.cos(angle) * rib_radius,
                                      math.sin(angle) * rib_radius,
                                      15.92 + dz)))
        builder_tube(rib_builder, rib_points, [0.055] * len(rib_points),
                     sides=5, uv_v_scale=0.35)
    for profile_index in (1, 3, 5, 7):
        radius, dz = dome_profile[profile_index]
        ring_points = []
        for ring_index in range(43):
            angle = math.tau * float(ring_index) / 42.0
            ring_points.append(Vector((math.cos(angle) * (radius + 0.075),
                                       math.sin(angle) * (radius + 0.075),
                                       15.92 + dz)))
        builder_tube(rib_builder, ring_points, [0.042] * len(ring_points),
                     sides=5, uv_v_scale=0.35, cap_start=False, cap_end=False)
    rib_builder.build("mosque_dome_ribs", brass, smooth=True)
    cyl("mosque_dome_finial_rod", 0.0, 0.0, 24.05, 0.055, 1.15, brass, vertices=10)
    sphere("mosque_dome_finial_orb_large", 0.0, 0.0, 23.92, 0.52, 0.52, 0.52, brass)
    sphere("mosque_dome_finial_orb_small", 0.0, 0.0, 24.32, 0.34, 0.34, 0.34, brass)
    crescent_builder = MeshBuilder()
    add_crescent(crescent_builder, 0.0, 0.0, 25.08, scale=1.05)
    crescent_builder.build("mosque_dome_crescent", brass, smooth=False)

    # Four satellite domes on the hall roof corners.
    for sx in (-10.50, 10.50):
        for sy in (-12.00, 12.00):
            cyl("mosque_satellite_drum", sx, sy, 13.85, 2.25, 1.30, stone, vertices=18)
            torus("mosque_satellite_cornice", sx, sy, 14.52, 2.28, 0.10, limestone)
            sphere("mosque_satellite_dome", sx, sy, 15.20, 4.85, 4.85, 3.15, dome_mat)
            cyl("mosque_satellite_finial", sx, sy, 17.05, 0.035, 0.65, brass, vertices=8)
            sphere("mosque_satellite_orb", sx, sy, 17.20, 0.24, 0.24, 0.24, brass)
            for satellite_window_index in range(4):
                angle = math.tau * float(satellite_window_index) / 4.0 + 0.4
                rbox("mosque_satellite_window", sx + math.cos(angle) * 2.28,
                     sy + math.sin(angle) * 2.28, 13.88, 0.48, 0.05, 0.72,
                     mosque_glass, rotation=(0.0, 0.0, angle + math.pi * 0.5))

    # --- Two 30 m minarets at the western corners. ---
    for side_sign in (-1.0, 1.0):
        cx = -16.55
        cy = side_sign * 13.50
        box("mosque_minaret_base", cx, cy, 2.90, 5.00, 5.00, 5.80, stone)
        box("mosque_minaret_base_plinth", cx, cy, 0.82, 5.30, 5.30, 0.55, granite)
        box("mosque_minaret_base_cornice", cx, cy, 5.92, 5.30, 5.30, 0.28, limestone)
        box("mosque_minaret_door", cx + 2.54, cy, 2.15, 0.10, 1.05, 2.80, mosque_wood)
        add_half_disc_x(arch_builders["limestone"], cx + 2.55, cy, 3.55, 0.62, 0.10, 1.0)
        box("mosque_minaret_base_tile", cx + 2.53, cy, 4.72, 0.07, 3.60, 0.62, tile)
        cone("mosque_minaret_transition", cx, cy, 6.85, 2.15, 1.28, 1.75, limestone, vertices=8)
        cyl("mosque_minaret_shaft", cx, cy, 14.55, 1.24, 14.10, stone, vertices=20)
        for band_z in (10.20, 13.65, 17.10):
            cyl("mosque_minaret_tile_band", cx, cy, band_z, 1.31, 0.48, tile, vertices=20)
            torus("mosque_minaret_brass_band", cx, cy, band_z + 0.34, 1.28, 0.040, brass)
        for rib_index in range(8):
            angle = math.tau * float(rib_index) / 8.0
            rbox("mosque_minaret_shaft_rib", cx + math.cos(angle) * 1.26,
                 cy + math.sin(angle) * 1.26, 14.55, 0.07, 0.07, 13.55, limestone,
                 rotation=(0.0, 0.0, angle))
        for slit_z in (9.30, 12.20, 15.10, 18.00):
            box("mosque_minaret_slit_east", cx + 1.26, cy, slit_z, 0.055, 0.30, 0.95, mosque_glass)
            box("mosque_minaret_slit_side", cx, cy + side_sign * 1.26, slit_z + 0.72,
                0.30, 0.055, 0.95, mosque_light)
        for corbel_index in range(12):
            angle = math.tau * float(corbel_index) / 12.0
            rbox("mosque_minaret_balcony_corbel", cx + math.cos(angle) * 1.55,
                 cy + math.sin(angle) * 1.55, 19.02, 0.62, 0.16, 0.38, limestone,
                 rotation=(0.0, 0.0, angle))
        cyl("mosque_minaret_balcony", cx, cy, 19.38, 2.05, 0.36, limestone, vertices=24)
        cyl("mosque_minaret_balcony_edge", cx, cy, 19.60, 2.10, 0.10, brass, vertices=24)
        for post_index in range(16):
            angle = math.tau * float(post_index) / 16.0
            cyl("mosque_minaret_rail_post", cx + math.cos(angle) * 1.86,
                cy + math.sin(angle) * 1.86, 20.05, 0.026, 0.86, brass, vertices=6)
        torus("mosque_minaret_rail_top", cx, cy, 20.48, 1.86, 0.035, brass)
        torus("mosque_minaret_rail_mid", cx, cy, 20.05, 1.86, 0.025, brass)
        cyl("mosque_minaret_upper_shaft", cx, cy, 21.95, 0.98, 4.75, stone, vertices=18)
        cyl("mosque_minaret_upper_tile", cx, cy, 22.85, 1.04, 0.42, tile, vertices=18)
        cyl("mosque_minaret_second_balcony", cx, cy, 24.05, 1.52, 0.28, limestone, vertices=22)
        torus("mosque_minaret_second_rail", cx, cy, 24.62, 1.36, 0.028, brass)
        cone("mosque_minaret_cap", cx, cy, 26.55, 1.48, 0.06, 4.20, dome_mat, vertices=22)
        torus("mosque_minaret_cap_ring", cx, cy, 24.48, 1.48, 0.065, brass)
        cyl("mosque_minaret_finial_rod", cx, cy, 29.35, 0.038, 1.30, brass, vertices=8)
        sphere("mosque_minaret_finial_orb", cx, cy, 29.28, 0.30, 0.30, 0.30, brass)
        sphere("mosque_minaret_finial_tip", cx, cy, 29.82, 0.18, 0.18, 0.18, brass)

    # Low terrace lanterns at the four parcel corners.
    for lantern_x in (-18.55, 18.55):
        for lantern_y in (-17.35, 17.35):
            box("mosque_terrace_lantern_base", lantern_x, lantern_y, 0.78,
                0.42, 0.42, 0.42, granite)
            box("mosque_terrace_lantern_frame", lantern_x, lantern_y, 1.18,
                0.30, 0.30, 0.42, brass)
            sphere("mosque_terrace_lantern_globe", lantern_x, lantern_y, 1.18,
                   0.22, 0.22, 0.30, mosque_light)
    arch_builders["limestone"].build("mosque_arch_caps_limestone", limestone, smooth=False)
    arch_builders["glass"].build("mosque_arch_caps_glass", mosque_glass, smooth=False)
    arch_builders["brass"].build("mosque_arch_caps_brass", brass, smooth=False)
    arch_builders["interior"].build("mosque_arch_caps_interior", interior, smooth=False)


# --------------------------------------------------------------------------- #
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = argv[0] if argv else os.path.join(os.getcwd(), "props_out")
    os.makedirs(out_dir, exist_ok=True)

    for build, filename in (
        (build_shelter, "bus_shelter.glb"),
        (build_lamp, "street_lamp.glb"),
        (build_park_bench, "park_bench.glb"),
        (build_park_pergola, "park_pergola.glb"),
        (build_traffic_signal_short, "traffic_signal_short.glb"),
        (build_traffic_signal_long, "traffic_signal_long.glb"),
        (build_hero, "hero_building.glb"),
        (build_townhouse, "townhouse.glb"),
        (build_villa, "villa.glb"),
        (build_glass_tower, "glass_tower.glb"),
        (build_main_tower, "main_tower.glb"),
        (build_opera, "opera_house.glb"),
        (build_mosque, "mosque.glb"),
        (build_palm_date, "palm_date.glb"),
        (build_palm_royal, "palm_royal.glb"),
        (build_grass_tuft, "grass_tuft.glb"),
        (build_flower_clump, "flower_clump.glb"),
        (build_ornamental_shrub, "ornamental_shrub.glb"),
    ):
        reset_scene()
        standard_mats()
        build()
        export(out_dir, filename)
    print("[props] done ->", out_dir)


main()
