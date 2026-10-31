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
  * grand_hotel.glb   Building Model No.8: fixed-scale beachfront grand hotel
  * museum.glb        Building Model No.9: fixed-scale civic museum (central axis)
  * cottage_dune.glb / cottage_courtyard.glb / cottage_palm.glb
                      Building Models No.10-12: exterior-only Sail Island
                      desert cottage estates with walled private grounds
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
    # Building Model No.8 is an original beachfront grand hotel for the
    # Corniche hotel parcels: travertine stone, warm plaster, bronze
    # balcony/spandrel metalwork, inhabited warm interiors behind real
    # glass, black granite and a turquoise podium-roof pool.
    mat("HotelStone", (0.74, 0.66, 0.54), roughness=0.88)
    mat("HotelPlaster", (0.88, 0.84, 0.76), roughness=0.90)
    mat("HotelBronze", (0.46, 0.30, 0.15), roughness=0.34, metallic=0.82)
    mat("HotelGlass", (0.10, 0.26, 0.32), roughness=0.07, metallic=0.15)
    mat("HotelInterior", (0.10, 0.075, 0.05), roughness=0.95)
    mat("HotelGranite", (0.06, 0.065, 0.07), roughness=0.42, metallic=0.08)
    mat("HotelWood", (0.40, 0.24, 0.12), roughness=0.78)
    mat("HotelWater", (0.05, 0.42, 0.48), roughness=0.08, metallic=0.05)
    mat("HotelCurtain", (0.78, 0.71, 0.60), roughness=1.0)
    mat("HotelAccent", (0.03, 0.38, 0.40), roughness=0.60)
    mat("HotelLight", (1.0, 0.74, 0.42), roughness=0.32, emission=(1.0, 0.58, 0.24))
    # Building Model No.9 is an original civic museum for the central
    # axis (X665, Z-340): two-tone limestone panel rainscreen over a
    # dark shadow-gap core, a full-height glazed atrium slot with a
    # real stair and mezzanines behind bronze mullions, travertine
    # plinth/plaza, black granite sculpture court detailing and a
    # still reflecting pool.  Semantic separation lets Godot assign
    # world-scale photographic PBR surfaces per material.
    mat("MuseumStone", (0.74, 0.65, 0.51), roughness=0.90)
    mat("MuseumStonePale", (0.81, 0.73, 0.60), roughness=0.90)
    mat("MuseumCore", (0.28, 0.25, 0.21), roughness=0.96)
    mat("MuseumBronze", (0.44, 0.29, 0.14), roughness=0.34, metallic=0.82)
    mat("MuseumGlass", (0.10, 0.25, 0.31), roughness=0.07, metallic=0.15)
    mat("MuseumInterior", (0.11, 0.08, 0.055), roughness=0.95)
    mat("MuseumWhite", (0.90, 0.88, 0.83), roughness=0.85)
    mat("MuseumGranite", (0.07, 0.075, 0.08), roughness=0.42, metallic=0.08)
    mat("MuseumTravertine", (0.82, 0.74, 0.60), roughness=0.88)
    mat("MuseumWater", (0.05, 0.40, 0.46), roughness=0.08, metallic=0.05)
    mat("MuseumBannerTeal", (0.02, 0.32, 0.34), roughness=0.85)
    mat("MuseumBannerOchre", (0.72, 0.42, 0.10), roughness=0.85)
    mat("MuseumLight", (1.0, 0.74, 0.42), roughness=0.32, emission=(1.0, 0.58, 0.24))
    # Building Models No.10-12 are exterior-only Dubai desert cottages
    # for Sail Island.  Their semantic set is deliberately physical:
    # matte rammed sand and limestone never share a roughness with
    # honed travertine, vesicular basalt, sun-dried teak, standing-seam
    # roof metal or bronze.  Godot binds matching albedo / normal /
    # roughness maps to these names; no interior material is authored.
    mat("CottageSand", (0.80, 0.69, 0.52), roughness=0.97)
    mat("CottageTravertine", (0.76, 0.66, 0.50), roughness=0.84)
    mat("CottageLimestone", (0.78, 0.69, 0.55), roughness=0.93)
    mat("CottageBasalt", (0.055, 0.060, 0.068), roughness=0.78, metallic=0.04)
    mat("CottageTeak", (0.34, 0.20, 0.10), roughness=0.86)
    mat("CottageBronze", (0.42, 0.27, 0.13), roughness=0.38, metallic=0.84)
    mat("CottageGlass", (0.09, 0.23, 0.30), roughness=0.06, metallic=0.12)
    mat("CottageCore", (0.025, 0.023, 0.021), roughness=0.98)
    mat("CottageBlind", (0.62, 0.55, 0.43), roughness=1.0)
    mat("CottageRoofMetal", (0.20, 0.16, 0.12), roughness=0.52, metallic=0.68)
    mat("CottagePaving", (0.68, 0.61, 0.50), roughness=0.94)
    mat("CottageGravel", (0.55, 0.48, 0.39), roughness=1.0)
    mat("CottageLawn", (0.16, 0.34, 0.11), roughness=1.0)
    mat("CottageHedge", (0.07, 0.24, 0.07), roughness=1.0)
    mat("CottageWater", (0.04, 0.36, 0.43), roughness=0.07, metallic=0.05)
    mat("CottageLight", (1.0, 0.72, 0.38), roughness=0.32, emission=(1.0, 0.55, 0.20))
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
    # 0.3.2 low-poly city set: a handful of flat accent paints so the
    # mass-produced Blender buildings/props stay distinguishable at
    # "slightly above low" geometry budgets (user direction 30.10).
    mat("CityWhitePaint", (0.90, 0.91, 0.93), roughness=0.38, metallic=0.08)
    mat("CityAccentRed", (0.55, 0.10, 0.07), roughness=0.62)
    mat("CityAccentBlue", (0.07, 0.22, 0.48), roughness=0.55)
    mat("CityArmyGreen", (0.15, 0.21, 0.10), roughness=0.90)
    mat("CityBarnRed", (0.42, 0.10, 0.07), roughness=0.88)
    mat("CitySignYellow", (0.80, 0.52, 0.05), roughness=0.60)
    mat("CityFieldGreen", (0.16, 0.34, 0.10), roughness=1.0)


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


def sphere(name, x, y, z, dx, dy, dz, material, segments=24, ring_count=16):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.5, segments=segments, ring_count=ring_count, location=(x, y, z),
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.dimensions = (dx, dy, dz)
    return finish(obj, material, smooth=True)


def panel(name, x, y, z, width, height, material, face):
    """Single-sided facade quad (2 tris) for flat window layers.

    0.3.6: interior backings, curtains, blinds, glow strips and glass
    panes sit inside solid frame/wall geometry, so their ~4 cm box
    thickness was invisible from every exterior viewpoint while
    costing 12 triangles each (thousands per premium building).  The
    quad sits exactly on the old box's outer face and is wound
    outward; frames, sills, mullions and reveals stay solid boxes
    and keep the physical depth of the opening.
    """
    hw = width / 2.0
    hh = height / 2.0
    if face in ("front", "back"):
        sign = -1.0 if face == "front" else 1.0
        points = [(x - hw, y, z - hh), (x + hw, y, z - hh), (x + hw, y, z + hh), (x - hw, y, z + hh)]
        outward = Vector((0.0, sign, 0.0))
    else:
        sign = -1.0 if face == "left" else 1.0
        points = [(x, y - hw, z - hh), (x, y + hw, z - hh), (x, y + hw, z + hh), (x, y - hw, z + hh)]
        outward = Vector((sign, 0.0, 0.0))
    normal = (Vector(points[1]) - Vector(points[0])).cross(Vector(points[3]) - Vector(points[0]))
    if normal.dot(outward) < 0.0:
        points = [points[1], points[0], points[3], points[2]]
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(points, [], [(0, 1, 2, 3)])
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for index, uv_value in enumerate(((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
        if index < len(uv_layer.data):
            uv_layer.data[index].uv = uv_value
    if material is not None:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def win_recess_0312(name, x, y, z, width, height, glass_material, frame_material, face, depth=0.20, frame_w=0.14):
    """0.3.12 recessed window: a proud frame ring with real returns
    on both edges and the glass set back near the wall plane.

    The 0.3.6-0.3.9 panel passes left the glass as a single quad
    floating up to 0.24 m in front of the wall (on the old pane box's
    outer face), which reads flat/plastic at street level and shows
    an air gap at grazing angles.  This keeps the same outer plane
    and the same two materials (part counts unchanged) but closes
    the opening with a frame ring, outer returns to the wall and
    inner returns down to the recessed glass -- real shadow lines
    and parallax for ~26 tris instead of 2.  (x, y, z) is the wall
    plane, as for panel()."""
    if face in ("front", "back"):
        outward = Vector((0.0, -1.0 if face == "front" else 1.0, 0.0))
    else:
        outward = Vector((-1.0 if face == "left" else 1.0, 0.0, 0.0))
    up = Vector((0.0, 0.0, 1.0))
    right = up.cross(outward).normalized()
    base = Vector((x, y, z))
    hw = width / 2.0
    hh = height / 2.0
    ow = hw + frame_w
    oh = hh + frame_w
    glass_d = 0.03

    def point(u, v, d, builder):
        return builder.add_vertex(base + right * u + up * v + outward * d)

    frame = MeshBuilder()
    for strip in (
        ((-ow, -oh), (ow, -oh), (ow, -hh), (-ow, -hh)),
        ((-ow, hh), (ow, hh), (ow, oh), (-ow, oh)),
        ((-ow, -hh), (-hw, -hh), (-hw, hh), (-ow, hh)),
        ((hw, -hh), (ow, -hh), (ow, hh), (hw, hh)),
    ):
        frame.quad(*[point(u, v, depth, frame) for (u, v) in strip])
    for (u0, v0), (u1, v1) in (
        ((-ow, -oh), (ow, -oh)), ((ow, -oh), (ow, oh)),
        ((ow, oh), (-ow, oh)), ((-ow, oh), (-ow, -oh)),
    ):
        frame.quad(point(u0, v0, 0.0, frame), point(u1, v1, 0.0, frame),
                   point(u1, v1, depth, frame), point(u0, v0, depth, frame))
    for (u0, v0), (u1, v1) in (
        ((-hw, -hh), (hw, -hh)), ((hw, -hh), (hw, hh)),
        ((hw, hh), (-hw, hh)), ((-hw, hh), (-hw, -hh)),
    ):
        frame.quad(point(u0, v0, depth, frame), point(u1, v1, depth, frame),
                   point(u1, v1, glass_d, frame), point(u0, v0, glass_d, frame))
    frame.build(name + "_frame", frame_material, smooth=False)
    glass = MeshBuilder()
    glass.quad(point(-hw, -hh, glass_d, glass), point(hw, -hh, glass_d, glass),
               point(hw, hh, glass_d, glass), point(-hw, hh, glass_d, glass))
    glass.build(name, glass_material, smooth=False)


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


# 0.3.12 world-density UV bake.  The runtime maps these material
# names to tiling photo textures with uv1_scale == 1 and NO
# triplanar, so the old per-face 0..1 box UVs stretched a single
# texture repeat over anything from a 0.4 m trim to a 76 m warehouse
# roof.  Rewriting UVs from model-space coordinates with a
# dominant-axis projection gives every surface the same real-metre
# texel density at zero triangle cost.  Curved objects (tanks,
# fuselages, lamp tubes) keep their wrapped primitive UVs: an
# object only bakes when >=90% of its area is near-cardinal.
_UV_DENSITY_TILES_0312 = {
    "PropsMetal": 5.0, "FacadeMain": 4.0, "FacadeAccent": 3.0,
    "RoofDark": 5.0, "RoofTile": 4.0, "PropsWood": 2.5,
    "CityWhitePaint": 4.0, "CityAccentRed": 4.0, "CityAccentBlue": 4.0,
    "CityArmyGreen": 3.0, "CityBarnRed": 3.0, "CitySignYellow": 2.0,
    "CityFieldGreen": 6.0,
}


def _bake_world_uv_density_0312():
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or len(obj.data.materials) != 1:
            continue
        material = obj.data.materials[0]
        if material is None:
            continue
        tile = _UV_DENSITY_TILES_0312.get(material.name)
        if tile is None:
            continue
        mesh = obj.data
        total_area = 0.0
        cardinal_area = 0.0
        for polygon in mesh.polygons:
            total_area += polygon.area
            if max(abs(polygon.normal.x), abs(polygon.normal.y), abs(polygon.normal.z)) >= 0.80:
                cardinal_area += polygon.area
        if total_area <= 0.0 or cardinal_area < total_area * 0.90:
            continue
        uv_layer = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
        for polygon in mesh.polygons:
            normal = polygon.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            others = [i for i in range(3) if i != axis]
            for loop_index in polygon.loop_indices:
                vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                uv_layer.data[loop_index].uv = (vertex[others[0]] / tile, vertex[others[1]] / tile)


def _merge_meshes_by_material_for_export(filename):
    """0.3.4 compression/loading pass.

    The detailed builders below author one Blender object per bolt,
    mullion and balcony slab (grand_hotel alone had 2,741 mesh
    objects).  The game has always merged those nodes back into one
    mesh per semantic material at load time; doing the identical
    join at the source leaves world-space geometry, UVs, polygon
    smoothing and material names untouched, but removes thousands of
    glTF nodes/accessors, shrinks the GLBs and makes Godot's import
    and the native part-collector dramatically cheaper.  Botanical
    models are excluded (their MeshBuilder output is already merged
    and the user asked for vegetation geometry to stay untouched).
    """
    if filename in {"palm_date.glb", "palm_royal.glb", "grass_tuft.glb", "flower_clump.glb", "ornamental_shrub.glb"}:
        return (0, 0)
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    before = len(mesh_objects)
    if before <= 1:
        return (before, before)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    try:
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    except RuntimeError:
        pass
    _bake_world_uv_density_0312()
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        material_names = tuple(mat.name if mat else "" for mat in obj.data.materials)
        if len(material_names) > 1:
            continue
        groups.setdefault(material_names, []).append(obj)
    for material_names, objs in groups.items():
        if len(objs) <= 1:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        try:
            bpy.ops.object.join()
        except RuntimeError:
            continue
        joined = bpy.context.view_layer.objects.active
        label = material_names[0] if material_names and material_names[0] else "Unmaterialled"
        joined.name = f"Merged_{label}"
        if joined.data is not None:
            joined.data.name = f"Merged_{label}_mesh"
    bpy.context.view_layer.update()
    after = sum(1 for obj in bpy.context.scene.objects if obj.type == "MESH")
    return (before, after)


def export(out_dir, filename):
    meshes_before, meshes_after = _merge_meshes_by_material_for_export(filename)
    path = os.path.join(out_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=True, export_apply=True,
    )
    tris = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"[props] {filename}: {os.path.getsize(path)} bytes, ~{tris} tris, meshes {meshes_before}->{meshes_after}")


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
    box("shelter_platform", 0, 0, 0.060, 5.45, 2.05, 0.12, dark)
    for strip_index in range(7):
        box("shelter_antislip", -2.10 + strip_index * 0.70, 0, 0.124,
            0.34, 1.86, 0.010, metal)
    for sx in (-2.62, 2.62):
        box("shelter_drain", sx, 0, 0.122, 0.10, 1.80, 0.008, dark)

    # Four square corner posts on base plates with anchor bolts.
    for sx in (-2.55, 2.55):
        for sy in (-0.88, 0.88):
            box("shelter_post", sx, sy, 1.340, 0.11, 0.11, 2.44, metal)
            box("shelter_post_plate", sx, sy, 0.135, 0.22, 0.22, 0.03, metal)
            for bx in (-0.07, 0.07):
                for by in (-0.07, 0.07):
                    cyl("shelter_post_bolt", sx + bx, sy + by, 0.16, 0.014, 0.025,
                        dark, vertices=6)

    # Roof build-up: soffit, main slab, drip rails and standing seams.
    box("shelter_soffit", 0, 0, 2.520, 5.55, 2.15, 0.08, metal)
    box("shelter_roof", 0, 0, 2.640, 5.75, 2.35, 0.12, metal, bevel=0.025)
    for sy in (-1.125, 1.125):
        box("shelter_drip_rail", 0, sy, 2.575, 5.62, 0.05, 0.045, dark)
    for seam_y in (-0.90, -0.45, 0.0, 0.45, 0.90):
        box("shelter_roof_seam", 0, seam_y, 2.712, 5.58, 0.035, 0.024, dark)

    # Rooftop solar array: framed panel, 18 individual cells, bus bars.
    box("shelter_solar_frame", 1.25, 0, 2.725, 2.45, 1.30, 0.045, dark)
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
    cyl("shelter_ac_fan_ring", -1.70, 0, 3.040, 0.27, 0.035, dark, vertices=16)
    cyl("shelter_ac_fan_hub", -1.70, 0, 3.047, 0.070, 0.022, metal, vertices=10)
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
        box("shelter_bottom_rail", 0, sy, 0.235, 5.20, 0.085, 0.190, metal)
        box("shelter_header", 0, sy, 2.415, 5.20, 0.075, 0.150, metal)
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
                metal)
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
            0.18, 0.045, 0.060, dark)
        box("shelter_door_sensor_eye", 0, sy + outward * 0.080, 2.300,
            0.07, 0.012, 0.025, glow)

    # Short glazed ends with a centre mullion and corner gaskets.
    for sx in (-2.62, 2.62):
        box("shelter_bottom_rail_end", sx, 0, 0.235, 0.085, 1.76, 0.190, metal)
        box("shelter_header_end", sx, 0, 2.415, 0.075, 1.76, 0.150, metal)
        box("shelter_midrail_end", sx, 0, 1.120, 0.055, 1.76, 0.060, metal)
        for pane_y in (-0.445, 0.445):
            box("shelter_pane_end", sx, pane_y, 1.310, 0.035, 0.82, 1.98, glass)
        for gasket_y in (-0.88, 0.0, 0.88):
            box("shelter_mullion_end", sx, gasket_y, 1.310, 0.070, 0.070, 2.10,
                metal)

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
            wood)
    for back_z in (0.840, 1.010, 1.180):
        box("shelter_bench_back_slat", 0, -0.745, back_z, 3.80, 0.045, 0.090,
            wood)
    for frame_x in (-1.65, 0.0, 1.65):
        box("shelter_bench_frame_front", frame_x, -0.335, 0.365, 0.070, 0.070, 0.47,
            metal)
        box("shelter_bench_frame_rear", frame_x, -0.715, 0.720, 0.070, 0.070, 1.18,
            metal)
        box("shelter_bench_frame_foot", frame_x, -0.510, 0.145, 0.090, 0.52, 0.035,
            metal)
        box("shelter_bench_frame_seatrail", frame_x, -0.510, 0.575, 0.060, 0.48, 0.045,
            metal)
        for slat_y in seat_ys:
            cyl("shelter_bench_bolt", frame_x, slat_y, 0.642, 0.011, 0.012,
                dark, vertices=6)

    # Lit timetable case with printed rows behind glass.
    box("shelter_info_frame", 2.30, 0.48, 1.350, 0.070, 0.95, 1.50, metal)
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
    box("lamp_plinth", 0, 0, 0.040, 0.48, 0.48, 0.080, dark)
    cyl("lamp_flange", 0, 0, 0.130, 0.270, 0.100, metal, vertices=12)
    cone("lamp_base_body", 0, 0, 0.475, 0.240, 0.165, 0.550, metal, vertices=12)
    cyl("lamp_base_collar", 0, 0, 0.790, 0.180, 0.080, metal, vertices=12)
    for bx in (-0.185, 0.185):
        for by in (-0.185, 0.185):
            cyl("lamp_anchor_bolt", bx, by, 0.195, 0.026, 0.050, dark, vertices=6)
            cyl("lamp_anchor_washer", bx, by, 0.175, 0.040, 0.012, metal, vertices=8)

    # Access door on the +X face with handle, hinges and corner screws.
    box("lamp_access_door", 0.195, 0, 0.520, 0.030, 0.240, 0.420, metal)
    box("lamp_access_gasket", 0.182, 0, 0.520, 0.012, 0.262, 0.442, dark)
    box("lamp_access_handle", 0.225, -0.070, 0.520, 0.035, 0.030, 0.120, dark)
    for hinge_z in (0.380, 0.660):
        box("lamp_access_hinge", 0.205, 0.125, hinge_z, 0.025, 0.025, 0.080, dark)
    for screw_y in (-0.095, 0.095):
        for screw_z in (0.345, 0.695):
            cyl("lamp_access_screw", 0.214, screw_y, screw_z, 0.009, 0.012,
                dark, vertices=6, rotation=(0.0, math.pi / 2.0, 0.0))

    # Tapered sectional pole with slip-joint collars and a maker's plate.
    cone("lamp_pole", 0, 0, 3.660, 0.145, 0.072, 5.720, metal, vertices=12)
    for collar_z, collar_r in ((2.100, 0.126), (4.000, 0.101), (5.700, 0.082)):
        cyl("lamp_pole_collar", 0, 0, collar_z, collar_r, 0.090, metal, vertices=12)
        cyl("lamp_pole_groove", 0, 0, collar_z - 0.060, collar_r - 0.004, 0.020,
            dark, vertices=12)
    box("lamp_maker_plate", -0.118, 0, 2.450, 0.012, 0.120, 0.180, dark)
    cyl("lamp_top_cap", 0, 0, 6.555, 0.076, 0.070, metal, vertices=12)
    sphere("lamp_finial", 0, 0, 6.595, 0.070, 0.070, 0.070, metal, segments=10, ring_count=8)

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
                         metal, vertices=10)
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
        box("lamp_head_bonnet", 0, head_y, 6.535, 0.300, 0.900, 0.060, metal)
        for fin_index in range(7):
            box("lamp_head_fin", 0, head_y + s * (-0.360 + fin_index * 0.120), 6.560,
                0.340, 0.032, 0.070, metal)
        for cap_offset in (-0.545, 0.545):
            box("lamp_head_endcap", 0, head_y + s * cap_offset, 6.430,
                0.330, 0.045, 0.140, dark)
        # Underside reflector tray, gasket, lens and corner screws.
        box("lamp_head_reflector", 0, head_y, 6.340, 0.300, 0.900, 0.022, dark)
        box("lamp_head_gasket", 0, head_y, 6.326, 0.272, 0.842, 0.010, metal)
        box("lamp_head_lens", 0, head_y, 6.318, 0.240, 0.780, 0.018, glow)
        for screw_x in (-0.120, 0.120):
            for screw_offset in (-0.390, 0.390):
                cyl("lamp_head_screw", screw_x, head_y + s * screw_offset, 6.322,
                    0.011, 0.014, dark, vertices=6)
    # Photocell on the +Y head only, as on real twin-arm columns.
    cyl("lamp_photocell_base", 0, 1.660, 6.580, 0.038, 0.030, dark, vertices=10)
    cyl("lamp_photocell", 0, 1.660, 6.608, 0.032, 0.040, metal, vertices=10)


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
            wood)
    # Reclined back: four slats tilted 12 degrees from vertical.
    back_tilt = 0.21
    for back_index in range(4):
        back_z = 0.615 + back_index * 0.115
        back_y = -0.300 - (back_z - 0.455) * math.tan(back_tilt)
        rbox("park_bench_back_slat", 0, back_y, back_z, 2.40, 0.045, 0.088,
             wood, rotation=(back_tilt, 0.0, 0.0))

    for frame_x in (-1.060, 1.060):
        # Feet with pads, front leg, back post continuing into the back
        # support, seat rail and a three-segment curved armrest.
        box("park_bench_foot", frame_x, -0.020, 0.035, 0.085, 0.720, 0.070,
            metal)
        for pad_y in (-0.300, 0.260):
            cyl("park_bench_foot_pad", frame_x, pad_y, 0.080, 0.034, 0.025,
                dark, vertices=10)
            cyl("park_bench_anchor", frame_x, pad_y, 0.078, 0.013, 0.022,
                metal, vertices=6)
        box("park_bench_leg_front", frame_x, 0.235, 0.260, 0.075, 0.085, 0.390,
            metal)
        rbox("park_bench_back_post", frame_x, -0.315, 0.540, 0.075, 0.085, 0.980,
             metal, rotation=(back_tilt, 0.0, 0.0))
        box("park_bench_seat_rail", frame_x, 0.000, 0.425, 0.065, 0.600, 0.045,
            metal)
        arm_points = (
            (frame_x, -0.300, 0.655),
            (frame_x, -0.100, 0.700),
            (frame_x, 0.120, 0.705),
            (frame_x, 0.285, 0.660),
        )
        for segment_index in range(len(arm_points) - 1):
            tube_between("park_bench_armrest", arm_points[segment_index],
                         arm_points[segment_index + 1], 0.030, 0.030,
                         metal, vertices=10)
        tube_between("park_bench_arm_support", (frame_x, 0.235, 0.455),
                     (frame_x, 0.265, 0.655), 0.022, 0.022, metal, vertices=10)
        sphere("park_bench_arm_knob", frame_x, 0.295, 0.655, 0.068, 0.068, 0.068, metal, segments=10, ring_count=8)
        # Rosette medallion bolted to the outer face of the front leg.
        outer_x = frame_x + (0.045 if frame_x > 0.0 else -0.045)
        cyl("park_bench_medallion", outer_x, 0.235, 0.260, 0.038, 0.018,
            dark, vertices=10, rotation=(0.0, math.pi / 2.0, 0.0))
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
        vertices=10, rotation=(0.0, math.pi / 2.0, 0.0))


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
        box("pergola_plinth_low", cx, cy, 0.110, 0.860, 0.860, 0.220, stone)
        box("pergola_plinth_high", cx, cy, 0.300, 0.700, 0.700, 0.180, stone)
        cyl("pergola_foot_ring", cx, cy, 0.430, 0.340, 0.090, stone, vertices=14)
        cone("pergola_column", cx, cy, 1.720, 0.295, 0.245, 2.500, stone, vertices=14)
        cyl("pergola_necking", cx, cy, 3.000, 0.275, 0.070, stone, vertices=14)
        box("pergola_capital", cx, cy, 3.100, 0.680, 0.680, 0.150, stone, bevel=0.012)
        box("pergola_abacus", cx, cy, 3.205, 0.800, 0.800, 0.070, stone)

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
             wood, rotation=(0.0, 0.0, yaw))

    # Six radial rafters run from the central hub to each column and
    # project 0.55 m past the ring as eaves tails -- the clean radial
    # geometry of a real hexagonal pergola.
    for rafter_index in range(6):
        angle = math.pi / 6.0 + rafter_index * math.tau / 6.0
        rbox("pergola_rafter", math.cos(angle) * 2.750, math.sin(angle) * 2.750, 3.500,
             6.00, 0.140, 0.170, wood, rotation=(0.0, 0.0, angle))

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
                 rotation=(0.0, 0.0, yaw))

    # Central hub where the radial rafters meet, with a ball finial.
    cyl("pergola_hub", 0, 0, 3.560, 0.300, 0.180, wood, vertices=14)
    cyl("pergola_finial_stem", 0, 0, 3.680, 0.035, 0.090, metal, vertices=12)
    sphere("pergola_finial_ball", 0, 0, 3.760, 0.150, 0.150, 0.150, metal, segments=12, ring_count=8)


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
            0.168, 0.23, housing, vertices=16,
            rotation=(math.pi / 2.0, 0.0, 0.0),
        )
        cyl(
            f"{prefix}_bezel_{index}", cx, 0.285, lamp_z,
            0.149, 0.032, housing, vertices=16,
            rotation=(math.pi / 2.0, 0.0, 0.0),
        )
        sphere(
            f"{prefix}_lens_{index}", cx, 0.292, lamp_z,
            0.25, 0.075, 0.25, lamp_materials[index], segments=12, ring_count=8,
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
    cyl("signal_base_flange", 0.0, 0.0, 0.115, 0.275, 0.10, metal, vertices=16)
    cone("signal_base_cover", 0.0, 0.0, 0.43, 0.235, 0.155, 0.58, metal, vertices=16)
    for sx in (-0.225, 0.225):
        for sy in (-0.225, 0.225):
            cyl("signal_anchor_bolt", sx, sy, 0.105, 0.035, 0.07, housing, vertices=6)
    box("signal_base_access_door", 0.0, -0.205, 0.43, 0.22, 0.025, 0.34, housing)
    sphere("signal_base_access_knob", 0.07, -0.225, 0.43, 0.045, 0.045, 0.045, metal, segments=10, ring_count=8)

    # Main tapered pole and cap.
    cone("signal_pole", 0.0, 0.0, 3.08, 0.145, 0.082, 5.95, metal, vertices=16)
    cyl("signal_pole_collar", 0.0, 0.0, 5.52, 0.105, 0.16, metal, vertices=14)
    sphere("signal_pole_cap", 0.0, 0.0, 6.08, 0.17, 0.17, 0.10, metal, segments=12, ring_count=8)

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
            vertices=14,
        )
    sphere("signal_arm_end_cap", reach, 0.0, 6.04, 0.11, 0.11, 0.11, metal, segments=10, ring_count=8)

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
            vertices=10,
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
            panel("hero_window_reveal", cx, cy + sign * 0.0525, cz, width + 0.28, height + 0.28, trim, face)
            panel("hero_window_interior", cx, cy + sign * 0.049, cz, width - 0.02, height - 0.02, interior, face)
            if variant == 0:
                for side in (-1.0, 1.0):
                    panel("hero_window_curtain", cx + side * (width / 2.0 - 0.15), cy + sign * 0.066, cz, 0.20, height - 0.12, curtain, face)
            elif variant == 1:
                blind_h = height * 0.38
                panel("hero_window_blind", cx, cy + sign * 0.068, cz + height / 2.0 - blind_h / 2.0 - 0.03, width - 0.10, blind_h, curtain, face)
            elif variant == 2:
                panel("hero_window_light", cx - width * 0.16, cy + sign * 0.066, cz + height * 0.30, width * 0.36, 0.034, glow, face)
            panel("hero_window_frame", cx, cy + sign * 0.0915, cz, width + 0.15, height + 0.15, frame, face)
            panel("hero_window_glass", cx, cy + sign * 0.097, cz, width, height, glass, face)
            divisions = max(1, int(width // 1.15))
            for division in range(1, divisions):
                mx = cx - width / 2.0 + width * division / divisions
                box("hero_window_mullion", mx, cy + sign * 0.090, cz, 0.046, 0.046, height, frame)
            box("hero_window_transom", cx, cy + sign * 0.090, cz + height * 0.24, width, 0.046, 0.046, frame)
            box("hero_window_sill", cx, cy + sign * 0.090, cz - height / 2.0 - 0.070, width + 0.34, 0.25, 0.085, trim)
        else:
            panel("hero_window_reveal", cx + sign * 0.0525, cy, cz, width + 0.28, height + 0.28, trim, face)
            panel("hero_window_interior", cx + sign * 0.049, cy, cz, width - 0.02, height - 0.02, interior, face)
            if variant == 0:
                for side in (-1.0, 1.0):
                    panel("hero_window_curtain", cx + sign * 0.066, cy + side * (width / 2.0 - 0.15), cz, 0.20, height - 0.12, curtain, face)
            elif variant == 1:
                blind_h = height * 0.38
                panel("hero_window_blind", cx + sign * 0.068, cy, cz + height / 2.0 - blind_h / 2.0 - 0.03, width - 0.10, blind_h, curtain, face)
            elif variant == 2:
                panel("hero_window_light", cx + sign * 0.066, cy - width * 0.16, cz + height * 0.30, width * 0.36, 0.034, glow, face)
            panel("hero_window_frame", cx + sign * 0.0915, cy, cz, width + 0.15, height + 0.15, frame, face)
            panel("hero_window_glass", cx + sign * 0.097, cy, cz, width, height, glass, face)
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
    box("hero_lot_plinth", 0.0, 0.0, 0.15, 32.40, 24.60, 0.30, granite)
    box("hero_podium", 0.0, 0.0, 3.00, 30.00, 20.40, 5.40, stone, bevel=0.025)
    box("hero_podium_cornice", 0.0, 0.0, 5.82, 30.55, 20.95, 0.24, trim)
    box("hero_tower", 0.0, 0.20, 15.30, 28.00, 18.40, 19.20, plaster, bevel=0.035)
    for pier_side in (-1.0, 1.0):
        box("hero_tower_end_pier", pier_side * 12.90, 0.20, 15.40, 3.40, 19.00, 19.60, stone)
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
        rbox("hero_shop_awning", shop_x, -10.78, 4.08, 3.45, 1.12, 0.08, wood, rotation=(-0.16, 0.0, 0.0))
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
    box("hero_blade_sign", 4.15, -10.62, 5.05, 0.18, 0.92, 2.45, hero_metal)
    box("hero_blade_sign_glow", 4.15, -11.10, 5.05, 0.10, 0.035, 2.05, glow)
    box("hero_address_plaque", -3.35, -10.38, 1.75, 0.55, 0.06, 0.75, granite)
    box("hero_address_inset", -3.35, -10.42, 1.75, 0.36, 0.025, 0.50, metal)

    # Rear service elevation: parking/loading door, dock, staff entry,
    # bins and bicycle parking keep the back from being an empty wall.
    box("hero_service_portal", 7.50, 10.28, 1.95, 4.15, 0.18, 3.35, trim)
    box("hero_service_door", 7.50, 10.36, 1.90, 3.65, 0.10, 3.00, hero_metal)
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
        box("hero_meter_cabinet", meter_x, -4.35, 1.35, 0.17, 0.85, 1.20, metal)
        box("hero_meter_window", meter_x + pipe_side * 0.095, -4.35, 1.55, 0.025, 0.40, 0.40, glass)
        for vent_offset in (-0.24, 0.0, 0.24):
            box("hero_podium_vent", meter_x, 3.40 + vent_offset, 4.55, 0.10, 0.16, 0.65, frame)
    for ac_x in (-11.0, 11.0):
        for ac_y in (-9.65, 9.95):
            box("hero_podium_ac", ac_x, ac_y, 6.18, 1.45, 0.78, 0.72, metal)
            cyl("hero_podium_ac_fan", ac_x, ac_y, 6.57, 0.24, 0.045, frame, vertices=12)

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
    box("hero_lift_overrun", 12.15, 4.00, 26.30, 2.55, 3.10, 2.30, stone)
    box("hero_lift_overrun_cap", 12.15, 4.00, 27.52, 2.80, 3.35, 0.16, granite)
    cyl("hero_roof_tank", -12.00, 4.20, 26.20, 0.95, 2.05, metal, vertices=14)
    cone("hero_roof_tank_cap", -12.00, 4.20, 27.48, 1.08, 0.18, 0.48, hero_metal, vertices=14)
    for hvac_x in (-8.0, 0.0, 8.0):
        for hvac_y in (-7.50, 8.55):
            box("hero_roof_hvac", hvac_x, hvac_y, 25.62, 2.25, 1.35, 0.88, metal, bevel=0.020)
            cyl("hero_roof_hvac_fan", hvac_x, hvac_y, 26.09, 0.34, 0.05, frame, vertices=12)
    for vent_x in (-4.5, 4.5):
        cyl("hero_roof_vent", vent_x, 8.20, 25.72, 0.12, 1.05, metal, vertices=12)
        cone("hero_roof_vent_cap", vent_x, 8.20, 26.34, 0.22, 0.05, 0.24, metal, vertices=12)
    for panel_x in (-6.8, -3.4, 0.0, 3.4, 6.8):
        rbox("hero_solar_frame", panel_x, 0.50, 28.38, 2.85, 2.15, 0.08, metal, rotation=(-0.12, 0.0, 0.0))
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
# 0.2.46 photoreal pass: windows are rebuilt as layered framed units
# (the old solid frame slab hid the interior, curtains and blinds,
# leaving grey panels) with recessed glass and glazing bars; the
# rear ground opening becomes a real two-leaf sliding patio door;
# bay side panes gain full frames; eaves gain soffits with rafter
# tails and a segmented ridge; festoon lights, garden trees and
# wheelie bins add lived-in detail.  Repeated parts (windows, pavers,
# slats, seams, pillars) merge into per-material MeshBuilders,
# roughly halving the mesh count.  Envelope unchanged.
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
    box("townhouse_lot_plinth", 0.0, 0.0, 0.09, 18.80, 16.20, 0.18, granite)

    # ---- merged-geometry helpers (0.2.46) ------------------------------- #
    builders = {}

    def bb(material):
        if material.name not in builders:
            builders[material.name] = (MeshBuilder(), material)
        return builders[material.name][0]

    def builder_box(builder, cx, cy, cz, dx, dy, dz):
        x0, x1 = cx - dx / 2.0, cx + dx / 2.0
        y0, y1 = cy - dy / 2.0, cy + dy / 2.0
        z0, z1 = cz - dz / 2.0, cz + dz / 2.0

        def v(x, y, z):
            return builder.add_vertex(Vector((x, y, z)))

        quads = (
            ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
            ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)),
            ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
            ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
            ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
            ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
        )
        for quad_corners in quads:
            ids = [v(*corner) for corner in quad_corners]
            builder.quad(*ids)

    def builder_rbox(builder, cx, cy, cz, dx, dy, dz, yaw):
        cs = math.cos(yaw)
        sn = math.sin(yaw)
        corners = {}
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                for sz in (-1.0, 1.0):
                    lx = sx * dx / 2.0
                    ly = sy * dy / 2.0
                    corners[(sx, sy, sz)] = builder.add_vertex(Vector((
                        cx + lx * cs - ly * sn,
                        cy + lx * sn + ly * cs,
                        cz + sz * dz / 2.0,
                    )))
        faces = (
            ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)),
            ((-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)),
            ((1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)),
            ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)),
            ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)),
            ((-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)),
        )
        for face in faces:
            builder.quad(*[corners[key] for key in face])

    def face_window(cx, cy, cz, width, height, face, shutters=False):
        # Layered framed window (0.2.46, merged builders): interior
        # reveal, curtain/blind states and a warm light line sit
        # BEHIND recessed glass - the old solid frame slab hid them
        # completely, leaving grey metal panels for windows.
        sign = -1.0 if face in ("front", "left") else 1.0
        variant = int(abs(cx * 4.3 + cy * 6.1 + cz * 7.7)) % 4
        blind_drop = height * (0.28, 0.44, 0.0, 0.58)[variant]

        def wbox(material, along, out, zc, along_sz, out_sz, z_sz):
            if face in ("front", "back"):
                builder_box(bb(material), cx + along, cy + sign * out, zc, along_sz, out_sz, z_sz)
            else:
                builder_box(bb(material), cx + sign * out, cy + along, zc, out_sz, along_sz, z_sz)

        def wquad(material, along, out, zc, along_sz, z_sz):
            # 0.3.6: flat window layers (interior/curtain/blind/glow/
            # glass) become one outward quad on the old box's outer
            # face -- 2 tris instead of 12, frames stay solid.
            builder = bb(material)
            a0, a1 = along - along_sz / 2.0, along + along_sz / 2.0
            z0, z1 = zc - z_sz / 2.0, zc + z_sz / 2.0
            if face in ("front", "back"):
                points = [Vector((cx + a0, cy + sign * out, z0)), Vector((cx + a1, cy + sign * out, z0)),
                          Vector((cx + a1, cy + sign * out, z1)), Vector((cx + a0, cy + sign * out, z1))]
                outward = Vector((0.0, sign, 0.0))
            else:
                points = [Vector((cx + sign * out, cy + a0, z0)), Vector((cx + sign * out, cy + a1, z0)),
                          Vector((cx + sign * out, cy + a1, z1)), Vector((cx + sign * out, cy + a0, z1))]
                outward = Vector((sign, 0.0, 0.0))
            normal = (points[1] - points[0]).cross(points[3] - points[0])
            if normal.dot(outward) < 0.0:
                points = [points[1], points[0], points[3], points[2]]
            ids = [builder.add_vertex(point) for point in points]
            builder.quad(*ids)

        wquad(trim, 0.0, 0.060, cz + height * 0.5 + 0.10, width + 0.34, 0.12)
        wquad(trim, 0.0, 0.060, cz - height * 0.5 - 0.10, width + 0.34, 0.12)
        for sd in (-1.0, 1.0):
            wquad(trim, sd * (width * 0.5 + 0.10), 0.060, cz, 0.12, height + 0.10)
        wquad(interior, 0.0, 0.048, cz, width - 0.03, height - 0.03)
        if variant != 1:
            for sd in (-1.0, 1.0):
                wquad(curtain, sd * (width / 2.0 - 0.16), 0.075, cz, 0.22, height - 0.13)
        if blind_drop > 0.05:
            blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.03
            wquad(curtain, 0.0, 0.076, blind_z, width - 0.10, blind_drop)
            wquad(frame, 0.0, 0.083, blind_z - blind_drop / 2.0, width - 0.08, 0.040)
        wquad(glow, -width * 0.17, 0.069, cz + height * 0.33, width * 0.34, 0.035)
        wquad(glass, 0.0, 0.100, cz, width, height)
        wbox(frame, 0.0, 0.095, cz + height * 0.5 + 0.030, width + 0.18, 0.150, 0.10)
        wbox(frame, 0.0, 0.095, cz - height * 0.5 - 0.030, width + 0.18, 0.150, 0.10)
        for sd in (-1.0, 1.0):
            wbox(frame, sd * (width * 0.5 + 0.030), 0.095, cz, 0.10, 0.150, height)
        divisions = max(1, int(width // 0.95))
        for division in range(1, divisions):
            wbox(frame, -width / 2.0 + width * division / divisions, 0.090, cz, 0.050, 0.050, height)
        wbox(frame, 0.0, 0.090, cz + height * 0.22, width, 0.050, 0.050)
        wbox(metal, width * 0.21, 0.125, cz - 0.04, 0.040, 0.035, 0.28)
        wbox(trim, 0.0, 0.110, cz - height / 2.0 - 0.075, width + 0.40, 0.26, 0.095)
        wbox(trim, 0.0, 0.075, cz + height / 2.0 + 0.085, width + 0.30, 0.13, 0.10)
        if shutters:
            for sd in (-1.0, 1.0):
                sx = sd * (width / 2.0 + 0.28)
                wbox(wood, sx, 0.045, cz, 0.38, 0.055, height + 0.08)
                for groove in (-0.30, 0.0, 0.30):
                    wbox(frame, sx, 0.080, cz + groove * height, 0.32, 0.018, 0.035)
        if cz < 3.0 and variant in (0, 3) and face in ("front", "back"):
            wbox(granite, 0.0, 0.180, cz - height / 2.0 - 0.24, width * 0.72, 0.22, 0.20)
            wbox(hedge, 0.0, 0.180, cz - height / 2.0 - 0.10, width * 0.64, 0.16, 0.16)

    def juliet_balcony(cx, face_y, sign):
        slab_y = face_y + sign * 0.30
        rail_y = face_y + sign * 0.54
        builder_box(bb(granite), cx, slab_y, 3.68, 1.95, 0.58, 0.14)
        for bracket_x in (cx - 0.72, cx + 0.72):
            rbox("town_juliet_bracket", bracket_x, slab_y, 3.42, 0.08, 0.48, 0.08, metal, rotation=(sign * 0.62, 0.0, 0.0))
        for post_offset in (-0.88, -0.44, 0.0, 0.44, 0.88):
            builder_box(bb(frame), cx + post_offset, rail_y, 4.18, 0.038, 0.045, 0.86)
        builder_box(bb(frame), cx, rail_y, 4.64, 1.92, 0.07, 0.06)
        builder_box(bb(frame), cx, rail_y, 4.18, 1.92, 0.045, 0.04)
        for side in (-1.0, 1.0):
            builder_box(bb(frame), cx + side * 0.92, face_y + sign * 0.30, 4.64, 0.06, 0.52, 0.06)

    def rear_slider(cx, face_y):
        # Two-leaf sliding patio door (0.2.46): fixed and sliding
        # sashes at two depths, meeting stiles, granite sill track.
        z0, z1 = 0.45, 2.79
        zc = (z0 + z1) * 0.5
        builder_box(bb(interior), cx, face_y + 0.015, zc, 2.60, 0.030, 2.30)
        builder_box(bb(curtain), cx - 0.85, face_y + 0.045, zc, 0.55, 0.025, 2.20)
        for leaf, lout in ((-0.66, 0.055), (0.66, 0.095)):
            builder_box(bb(glass), cx + leaf, face_y + lout, zc + 0.10, 1.24, 0.040, 1.86)
            builder_box(bb(frame), cx + leaf, face_y + lout, z1 - 0.06, 1.32, 0.070, 0.09)
            builder_box(bb(frame), cx + leaf, face_y + lout, z0 + 0.10, 1.32, 0.070, 0.20)
            for stile in (-0.63, 0.63):
                builder_box(bb(frame), cx + leaf + stile, face_y + lout, zc, 0.09, 0.070, 2.24)
        builder_box(bb(frame), cx, face_y + 0.075, z1 + 0.05, 2.83, 0.140, 0.11)
        builder_box(bb(frame), cx - 1.36, face_y + 0.075, zc, 0.11, 0.140, 2.45)
        builder_box(bb(frame), cx + 1.36, face_y + 0.075, zc, 0.11, 0.140, 2.45)
        builder_box(bb(metal), cx + 0.10, face_y + 0.135, 1.55, 0.05, 0.040, 0.55)
        builder_box(bb(granite), cx, face_y + 0.16, 0.40, 2.95, 0.34, 0.07)
        builder_box(bb(trim), cx, face_y + 0.070, z1 + 0.16, 2.95, 0.12, 0.10)

    def roof_dormer(cx, unit_material):
        builder_box(bb(unit_material), cx, -3.55, 7.88, 1.35, 1.28, 1.60)
        for cheek_side in (-1.0, 1.0):
            builder_box(bb(trim), cx + cheek_side * 0.72, -3.55, 7.88, 0.09, 1.34, 1.62)
        gable_roof("town_dormer_roof", cx, -3.55, 8.98, 1.62, 1.52, 0.66, roof_tile, ridge_axis="y")
        builder_box(bb(granite), cx, -3.55, 9.34, 0.20, 1.58, 0.09)
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
    # Eaves soffits with exposed rafter tails and a segmented ridge
    # (0.2.46) so the roof edge reads carpentered from the street.
    builder_box(bb(trim), 0.0, -4.68, 6.47, 18.70, 0.56, 0.05)
    builder_box(bb(trim), 0.0, 5.78, 6.47, 18.70, 0.56, 0.05)
    for tail_i in range(14):
        tail_x = -8.77 + tail_i * 1.35
        builder_box(bb(trim), tail_x, -4.72, 6.38, 0.12, 0.50, 0.14)
        builder_box(bb(trim), tail_x, 5.82, 6.38, 0.12, 0.50, 0.14)
    for joint_i in range(13):
        builder_box(bb(frame), -9.0 + joint_i * 1.5, 0.55, 10.16, 0.05, 0.36, 0.16)

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
        builder_box(bb(stone), unit_x, -4.46, 0.72, 9.08, 0.14, 0.88)
        builder_box(bb(stone), unit_x, 5.56, 0.72, 9.08, 0.14, 0.88)
        builder_box(bb(stone), unit_x + unit_side * 4.54, 0.55, 0.72, 0.14, 9.98, 0.88)
        builder_box(bb(trim), unit_x, -4.47, 3.42, 9.10, 0.15, 0.20)
        builder_box(bb(trim), unit_x, 5.57, 3.42, 9.10, 0.15, 0.20)
        builder_box(bb(trim), unit_x + unit_side * 4.55, 0.55, 3.42, 0.15, 10.00, 0.20)
        for quoin_z in (1.25, 2.55, 4.65, 5.95):
            builder_box(bb(trim), unit_x + unit_side * 4.38, -4.42, quoin_z, 0.42, 0.16, 0.62)
            builder_box(bb(trim), unit_x + unit_side * 4.38, 5.52, quoin_z, 0.42, 0.16, 0.62)

        # Attached garage: projecting volume, front gable, sectional
        # timber-look door, windows, lights and a real paved driveway.
        box("town_garage_body", garage_x, -2.25, 1.72, 3.70, 5.90, 2.92, accent_material, bevel=0.025)
        gable_roof("town_garage_roof", garage_x, -2.25, 3.68, 4.15, 6.35, 1.05, roof_tile, ridge_axis="y")
        box("town_garage_ridge", garage_x, -2.25, 4.25, 0.22, 6.45, 0.10, granite)
        box("town_garage_portal", garage_x, -5.25, 1.50, 3.25, 0.16, 2.62, trim)
        box("town_garage_door", garage_x, -5.35, 1.48, 2.78, 0.09, 2.24, garage_mat)
        for seam_z in (0.83, 1.38, 1.93):
            builder_box(bb(frame), garage_x, -5.405, seam_z, 2.70, 0.025, 0.045)
        for seam_offset in (-0.70, 0.0, 0.70):
            builder_box(bb(frame), garage_x + seam_offset, -5.405, 1.48, 0.035, 0.025, 2.16)
        for window_offset in (-0.82, 0.0, 0.82):
            builder_box(bb(glass), garage_x + window_offset, -5.415, 2.28, 0.56, 0.030, 0.32)
        box("town_garage_handle", garage_x, -5.425, 1.08, 0.42, 0.035, 0.07, frame)
        for jamb_offset in (-1.56, 1.56):
            builder_box(bb(trim), garage_x + jamb_offset, -5.30, 1.50, 0.20, 0.24, 2.62)
        box("town_garage_bottom_seal", garage_x, -5.41, 0.42, 2.74, 0.035, 0.09, frame)
        for light_offset in (-1.70, 1.70):
            box("town_garage_light_body", garage_x + light_offset, -5.27, 2.55, 0.16, 0.10, 0.28, frame)
            box("town_garage_light", garage_x + light_offset, -5.335, 2.55, 0.10, 0.035, 0.18, glow)
        box("town_driveway_bed", garage_x, -6.68, 0.205, 3.45, 2.75, 0.045, granite)
        for paver_dx in (-1.12, 0.0, 1.12):
            for paver_y in (-5.83, -6.68, -7.53):
                builder_box(bb(pavement), garage_x + paver_dx, paver_y, 0.245, 1.00, 0.72, 0.045)
        box("town_driveway_drain", garage_x, -5.50, 0.255, 2.90, 0.16, 0.030, frame)

        # Two-storey front bay. The angled side panes are separate
        # framed/interior/glass layers, not a texture wrapped round a box.
        box("town_bay_ground", bay_x, -4.72, 1.62, 3.15, 0.78, 2.72, accent_material)
        box("town_bay_upper", bay_x, -4.62, 4.82, 2.75, 0.50, 2.28, accent_material)
        box("town_bay_roof", bay_x, -4.82, 3.08, 3.48, 1.05, 0.18, roof_tile)
        box("town_bay_cornice", bay_x, -4.88, 6.02, 3.05, 0.72, 0.16, trim)
        for corbel_offset in (-1.05, 0.0, 1.05):
            box("town_bay_corbel", bay_x + corbel_offset, -4.62, 3.48, 0.18, 0.28, 0.34, trim)
        face_window(bay_x, -5.11, 1.72, 2.20, 1.92, "front", shutters=False)
        face_window(bay_x, -4.87, 4.86, 2.05, 1.78, "front", shutters=True)
        for pane_side in (-1.0, 1.0):
            pane_x = bay_x + pane_side * 1.43
            pane_yaw = pane_side * 0.62
            pdir_x = math.cos(pane_yaw)
            pdir_y = math.sin(pane_yaw)
            builder_rbox(bb(interior), pane_x, -4.84, 1.72, 0.78, 0.040, 1.78, pane_yaw)
            builder_rbox(bb(glass), pane_x, -4.90, 1.72, 0.82, 0.040, 1.82, pane_yaw)
            builder_rbox(bb(frame), pane_x, -4.94, 2.66, 0.94, 0.10, 0.10, pane_yaw)
            builder_rbox(bb(frame), pane_x, -4.94, 0.78, 0.94, 0.10, 0.10, pane_yaw)
            builder_rbox(bb(frame), pane_x, -4.94, 1.72, 0.94, 0.07, 0.06, pane_yaw)
            for jamb_off in (-0.44, 0.44):
                builder_rbox(bb(frame), pane_x + pdir_x * jamb_off, -4.94 + pdir_y * jamb_off, 1.72, 0.09, 0.10, 1.90, pane_yaw)
            builder_rbox(bb(trim), pane_x, -4.97, 0.68, 1.02, 0.16, 0.08, pane_yaw)

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
        box("town_entry_door", door_x, -4.53, 1.56, 1.12, 0.10, 2.34, front_door_material)
        box("town_entry_door_glass", door_x - 0.20, -4.60, 1.82, 0.38, 0.035, 1.28, glass)
        for groove_offset in (-0.28, 0.08, 0.38):
            box("town_entry_door_groove", door_x + groove_offset, -4.592, 1.56, 0.025, 0.022, 2.18, frame)
        cyl("town_entry_handle", door_x + 0.43, -4.63, 1.55, 0.022, 0.72, metal, vertices=10)
        builder_box(bb(metal), door_x, -4.60, 0.62, 1.00, 0.020, 0.28)
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
            builder_box(bb(pavement), door_x, path_y, 0.235, 1.28, 0.52, 0.045)

        # Remaining front windows and a Juliet balcony over the porch.
        face_window(garage_x, -4.40, 5.18, 1.65, 1.62, "front", shutters=True)
        face_window(door_x, -4.40, 4.92, 1.42, 2.22, "front", shutters=False)
        juliet_balcony(door_x, -4.40, -1.0)

        # Rear elevation: sliding doors, kitchen window and bedrooms.
        rear_slider(unit_x - unit_side * 1.55, 5.50)
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
        box("town_chimney", chimney_x, 2.20, 9.025, 0.86, 0.86, 3.65, stone)
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
                rbox("town_solar_frame", panel_x, 3.28, 8.43, 1.12, 1.72, 0.07, metal, rotation=(-0.57, 0.0, 0.0))
                rbox("town_solar_cell", panel_x, 3.31, 8.47, 1.00, 1.58, 0.028, solar, rotation=(-0.57, 0.0, 0.0))
                for busbar_offset in (-0.25, 0.25):
                    rbox("town_solar_busbar", panel_x + busbar_offset, 3.32, 8.48, 0.018, 1.52, 0.007, metal, rotation=(-0.57, 0.0, 0.0))

        # Downspouts, side meter and rear condenser with a fan grille.
        for pipe_y, pipe_x in ((-4.80, unit_x - unit_side * 4.32), (5.90, unit_x + unit_side * 4.25)):
            cyl("town_downspout", pipe_x, pipe_y, 3.45, 0.055, 5.85, frame, vertices=10)
            tube_between("town_downspout_shoe", (pipe_x, pipe_y, 0.58), (pipe_x, pipe_y - 0.28 if pipe_y < 0 else pipe_y + 0.28, 0.24), 0.055, 0.055, frame, vertices=8)
            bracket_y = pipe_y + 0.20 if pipe_y < 0 else pipe_y - 0.20
            for bracket_z in (1.25, 3.40, 5.55):
                builder_box(bb(metal), pipe_x, bracket_y, bracket_z, 0.16, 0.52, 0.05)
        meter_x = garage_x + unit_side * 1.94
        box("town_meter_cabinet", meter_x, -4.20, 1.25, 0.16, 0.72, 1.05, metal)
        box("town_meter_window", meter_x + unit_side * 0.09, -4.20, 1.42, 0.025, 0.34, 0.34, glass)
        ac_x = unit_side * 8.15
        box("town_ac_unit", ac_x, 6.05, 0.68, 1.00, 0.42, 0.78, metal)
        cyl("town_ac_fan", ac_x, 6.285, 0.68, 0.27, 0.045, frame, vertices=20, rotation=(math.pi / 2.0, 0.0, 0.0))
        for grille_offset in (-0.18, 0.0, 0.18):
            builder_box(bb(metal), ac_x + grille_offset, 6.315, 0.68, 0.040, 0.025, 0.52)

        # Rear patio with pergola, outdoor counter and garden furniture.
        box("town_rear_patio", unit_x, 6.50, 0.27, 7.80, 2.25, 0.12, pavement)
        for post_x in (unit_x - 3.35, unit_x + 3.35):
            for post_y in (5.78, 7.32):
                box("town_pergola_post", post_x, post_y, 1.48, 0.16, 0.16, 2.55, wood)
        for beam_y in (5.74, 7.36):
            box("town_pergola_beam", unit_x, beam_y, 2.80, 7.15, 0.17, 0.18, wood)
        for slat_index in range(11):
            slat_x = unit_x - 3.3 + slat_index * 0.66
            builder_box(bb(wood), slat_x, 6.55, 2.94, 0.14, 1.95, 0.13)
        counter_x = unit_x + unit_side * 2.55
        box("town_outdoor_counter", counter_x, 6.55, 0.72, 0.72, 1.85, 0.86, stone)
        box("town_outdoor_grill", counter_x, 6.35, 1.22, 0.58, 0.72, 0.18, dark)
        box("town_outdoor_table", unit_x - unit_side * 0.65, 6.55, 0.78, 1.55, 0.82, 0.08, deck)
        box("town_outdoor_table_leg", unit_x - unit_side * 0.65, 6.55, 0.52, 0.16, 0.58, 0.42, granite)
        for bench_y in (6.02, 7.08):
            box("town_outdoor_bench", unit_x - unit_side * 0.65, bench_y, 0.54, 1.35, 0.30, 0.09, deck)
        # Festoon string lights sagging between the pergola beams.
        for string_x in (unit_x - 1.65, unit_x + 1.65):
            festoon_points = []
            for fp in range(9):
                ft = fp / 8.0
                festoon_points.append(Vector((string_x, 5.74 + 1.62 * ft, 2.86 - 0.72 * ft * (1.0 - ft))))
            builder_tube(bb(frame), festoon_points, [0.012] * len(festoon_points), sides=4, uv_v_scale=0.35)
            for bulb_t in (0.17, 0.34, 0.50, 0.66, 0.83):
                bulb_y = 5.74 + 1.62 * bulb_t
                bulb_z = 2.86 - 0.72 * bulb_t * (1.0 - bulb_t) - 0.07
                cyl("town_festoon_bulb", string_x, bulb_y, bulb_z, 0.035, 0.075, glow, vertices=8)
                cyl("town_festoon_cap", string_x, bulb_y, bulb_z + 0.055, 0.016, 0.035, frame, vertices=6)

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
        # One small clipped garden tree per home and a wheelie bin
        # against the rear wall (0.2.46 lived-in details).
        tree_x = unit_side * 1.05
        cyl("town_garden_tree_ring", tree_x, -7.00, 0.26, 0.55, 0.06, mulch, vertices=14)
        cyl("town_garden_tree_trunk", tree_x, -7.00, 1.05, 0.065, 1.55, wood, vertices=8)
        tube_between("town_garden_tree_branch", (tree_x, -7.00, 1.65), (tree_x - 0.35, -6.85, 2.25), 0.040, 0.026, wood, vertices=6)
        tube_between("town_garden_tree_branch", (tree_x, -7.00, 1.70), (tree_x + 0.33, -7.18, 2.30), 0.040, 0.026, wood, vertices=6)
        builder_ellipsoid(bb(hedge), Vector((tree_x, -7.00, 2.72)), (0.92, 0.86, 0.78), segments=9, yaw=0.3, pitch=0.1, rings=2)
        builder_ellipsoid(bb(hedge), Vector((tree_x - 0.45, -6.82, 2.42)), (0.62, 0.58, 0.54), segments=8, yaw=-0.4, pitch=0.0, rings=2)
        builder_ellipsoid(bb(hedge), Vector((tree_x + 0.42, -7.16, 2.50)), (0.66, 0.60, 0.56), segments=8, yaw=0.8, pitch=0.2, rings=2)
        builder_ellipsoid(bb(hedge), Vector((tree_x + 0.05, -7.02, 3.18)), (0.60, 0.56, 0.50), segments=8, yaw=0.1, pitch=0.0, rings=2)
        bin_x = unit_side * 1.05
        box("town_wheelie_bin", bin_x, 5.95, 0.74, 0.52, 0.58, 1.02, dark, bevel=0.03)
        rbox("town_wheelie_bin_lid", bin_x, 5.95, 1.29, 0.56, 0.62, 0.07, frame, rotation=(0.06, 0.0, 0.0))
        box("town_wheelie_bin_handle", bin_x, 6.28, 1.18, 0.40, 0.05, 0.05, frame)
        for wheel_dx in (-0.18, 0.18):
            cyl("town_wheelie_bin_wheel", bin_x + wheel_dx, 6.20, 0.24, 0.085, 0.05, frame, vertices=10, rotation=(0.0, math.pi / 2.0, 0.0))

    # Boundary walls and gates. Driveways and both pedestrian paths are
    # left open; the timber pedestrian gates are parked ajar.
    def boundary_wall(cx, cy, dx, dy):
        builder_box(bb(stone), cx, cy, 0.58, dx, dy, 0.72)
        builder_box(bb(granite), cx, cy, 0.99, dx + 0.07, dy + 0.07, 0.09)

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
        builder_box(bb(granite), pillar_x, -8.00, 0.72, 0.36, 0.36, 1.02)
        builder_box(bb(trim), pillar_x, -8.00, 1.29, 0.46, 0.46, 0.10)
        builder_box(bb(glow), pillar_x, -8.20, 1.00, 0.16, 0.035, 0.22)
    for gate_side in (-1.0, 1.0):
        rbox("town_pedestrian_gate", gate_side * 3.86, -7.58, 0.82, 1.08, 0.06, 1.02, wood, rotation=(0.0, 0.0, gate_side * 0.48))
        box("town_driveway_gate_track", gate_side * 8.92, -6.70, 0.25, 0.15, 2.55, 0.035, metal)
        box("town_driveway_gate_panel", gate_side * 9.02, -6.70, 0.92, 0.07, 2.45, 1.22, wood)
        box("town_driveway_gate_rail", gate_side * 9.02, -6.70, 1.58, 0.10, 2.55, 0.08, frame)

    for material_name, (builder, material) in builders.items():
        builder.build("town_merged_" + material_name.lower(), material, smooth=False)


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
            box("villa_facade_pier", cx, cy, cz, width, 0.15, height, pier_material)
        else:
            box("villa_facade_pier", cx, cy, cz, 0.15, width, height, pier_material)

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
            panel("villa_window_reveal", cx, cy + sign * 0.0605, cz, width + 0.38, height + 0.38, granite, face)
            panel("villa_window_interior", cx, cy + sign * 0.058, cz, width - 0.03, height - 0.03, interior, face)
            if variant != 1:
                for curtain_side in (-1.0, 1.0):
                    curtain_x = cx + curtain_side * (width / 2.0 - 0.17)
                    panel("villa_window_curtain", curtain_x, cy + sign * 0.081, cz, 0.24, height - 0.14, curtain, face)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.035
                panel("villa_window_blind", cx, cy + sign * 0.082, blind_z, width - 0.12, blind_drop, curtain, face)
            panel("villa_window_interior_light", cx - width * 0.18, cy + sign * 0.084, cz + height * 0.34, width * 0.38, 0.040, glow, face)
            panel("villa_window_frame", cx, cy + sign * 0.113, cz, width + 0.19, height + 0.19, frame, face)
            panel("villa_window_glass", cx, cy + sign * 0.121, cz, width, height, glass, face)
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
            panel("villa_window_reveal", cx + sign * 0.0605, cy, cz, width + 0.38, height + 0.38, granite, face)
            panel("villa_window_interior", cx + sign * 0.058, cy, cz, width - 0.03, height - 0.03, interior, face)
            if variant != 1:
                for curtain_side in (-1.0, 1.0):
                    curtain_y = cy + curtain_side * (width / 2.0 - 0.17)
                    panel("villa_window_curtain", cx + sign * 0.081, curtain_y, cz, 0.24, height - 0.14, curtain, face)
            if blind_drop > 0.05:
                blind_z = cz + height / 2.0 - blind_drop / 2.0 - 0.035
                panel("villa_window_blind", cx + sign * 0.082, cy, blind_z, width - 0.12, blind_drop, curtain, face)
            panel("villa_window_interior_light", cx + sign * 0.084, cy - width * 0.18, cz + height * 0.34, width * 0.38, 0.040, glow, face)
            panel("villa_window_frame", cx + sign * 0.113, cy, cz, width + 0.19, height + 0.19, frame, face)
            panel("villa_window_glass", cx + sign * 0.121, cy, cz, width, height, glass, face)
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
        cyl("villa_entry_column", column_x, -6.62, 1.72, 0.075, 2.95, metal, vertices=12)
        tube_between(
            "villa_entry_tie_rod",
            (column_x, -6.62, 3.05),
            (column_x, -3.78, 3.28),
            0.018,
            0.018,
            metal,
            vertices=8,
        )
    box("villa_entry_door", 0.25, -3.78, 1.62, 1.32, 0.10, 2.52, wood)
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
        cyl("villa_entry_downlight", downlight_x, -5.25, 3.008, 0.055, 0.025, glow, vertices=10)
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
            rbox("villa_solar_frame", panel_x, panel_y, 7.02, 1.18, 1.85, 0.065, metal, rotation=(0.22, 0.0, 0.0))
            rbox("villa_solar_cell", panel_x, panel_y - 0.012, 7.065, 1.05, 1.68, 0.028, solar, rotation=(0.22, 0.0, 0.0))
            for busbar_offset in (-0.26, 0.0, 0.26):
                rbox("villa_solar_busbar", panel_x + busbar_offset, panel_y - 0.018, 7.084, 0.018, 1.62, 0.007, metal, rotation=(0.22, 0.0, 0.0))
            box("villa_solar_leg", panel_x - 0.42, panel_y + 0.68, 6.76, 0.07, 0.07, 0.22, metal)
            box("villa_solar_leg", panel_x + 0.42, panel_y + 0.68, 6.76, 0.07, 0.07, 0.22, metal)
    box("villa_solar_cable_tray", -5.2, 0.78, 6.78, 5.55, 0.18, 0.08, frame)
    box("villa_solar_inverter", -2.05, 0.78, 6.98, 0.58, 0.28, 0.42, metal)

    def roof_hvac(cx, cy, base_z):
        box("villa_roof_hvac", cx, cy, base_z + 0.42, 1.65, 1.05, 0.84, metal, bevel=0.025)
        cyl("villa_roof_hvac_fan", cx, cy, base_z + 0.87, 0.34, 0.05, frame, vertices=12)
        cyl("villa_roof_hvac_ring", cx, cy, base_z + 0.90, 0.22, 0.055, metal, vertices=12)
        for grille_offset in (-0.22, 0.0, 0.22):
            box("villa_roof_hvac_grille", cx + grille_offset, cy - 0.545, base_z + 0.42, 0.055, 0.025, 0.55, frame)

    roof_hvac(-6.4, 3.2, 6.69)
    roof_hvac(5.8, 2.7, 7.34)
    box("villa_skylight_frame", -1.6, 2.8, 6.80, 1.55, 1.05, 0.20, frame)
    box("villa_skylight_glass", -1.6, 2.8, 6.92, 1.38, 0.88, 0.06, glass)
    box("villa_lift_overrun", 6.7, -3.2, 8.05, 2.2, 1.8, 1.35, accent, bevel=0.025)
    box("villa_lift_overrun_cap", 6.7, -3.2, 8.78, 2.4, 2.0, 0.12, dark)
    cyl("villa_roof_vent", 2.8, -3.5, 7.85, 0.13, 1.05, metal, vertices=12)
    cone("villa_roof_vent_cap", 2.8, -3.5, 8.48, 0.24, 0.05, 0.28, metal, vertices=12)
    cyl("villa_chimney", -8.1, 3.9, 7.55, 0.20, 1.55, stone, vertices=12)
    cyl("villa_chimney_cap", -8.1, 3.9, 8.38, 0.28, 0.12, frame, vertices=12)

    # Corner downspouts with lower shoes, plus side service hardware.
    for dx, dy, top_z in ((-8.88, -6.34, 6.35), (8.28, -5.64, 7.0), (-8.88, 4.94, 6.35), (8.28, 4.84, 7.0)):
        pipe_height = top_z - 0.35
        cyl("villa_downspout", dx, dy, 0.35 + pipe_height / 2.0, 0.055, pipe_height, metal, vertices=10)
        tube_between("villa_downspout_shoe", (dx, dy, 0.42), (dx, dy - 0.28 if dy < 0 else dy + 0.28, 0.18), 0.055, 0.055, metal, vertices=10)
        for bracket_z in (1.15, 3.35, 5.45):
            if bracket_z < top_z:
                box("villa_downspout_bracket", dx, dy, bracket_z, 0.15, 0.15, 0.055, frame)

    box("villa_side_ac", 8.62, 2.85, 0.72, 0.38, 1.02, 0.82, metal, bevel=0.02)
    cyl("villa_side_ac_fan", 8.83, 2.85, 0.72, 0.29, 0.045, frame, vertices=12, rotation=(0.0, math.pi / 2.0, 0.0))
    for grille_y in (2.60, 2.85, 3.10):
        box("villa_side_ac_grille", 8.855, grille_y, 0.72, 0.025, 0.045, 0.56, metal)
    box("villa_meter_cabinet", -9.18, -0.7, 1.05, 0.16, 0.72, 1.05, metal)
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
    box("villa_mailbox", -3.82, -7.20, 1.02, 0.48, 0.22, 0.34, frame)
    box("villa_mailbox_slot", -3.82, -7.325, 1.08, 0.30, 0.025, 0.045, metal)
    for planter_x in (-7.6, -5.2, 2.2, 8.1):
        box("villa_planter", planter_x, -6.95, 0.48, 1.25, 0.48, 0.42, granite)
        box("villa_planter_soil", planter_x, -6.95, 0.70, 1.12, 0.36, 0.045, mulch)
        box("villa_planter_hedge", planter_x, -6.95, 0.84, 1.05, 0.34, 0.28, hedge, bevel=0.055)
    for light_x in (-2.1, 3.9, 8.3):
        box("villa_path_light_post", light_x, -7.02, 0.48, 0.09, 0.09, 0.42, frame)
        box("villa_path_light", light_x, -7.02, 0.72, 0.15, 0.15, 0.10, glow)


# --------------------------------------------------------------------------- #
# Building Model No.4 - detailed fixed-scale glass district tower.
# Planned envelope: 34.00 x 34.00 m, 72.90 m high. A two-storey stone
# podium carries two set-back curtain-wall shaft tiers and a mechanical
# crown; the runtime places the finished design at scale 1.0.
# 0.2.45 photoreal pass: the old continuous glass skins with 6.5 m
# mullion spacing and tray-like spandrel rings become a true unitized
# curtain wall on a ~1.65 m module - individual vision lites with
# shadow gaps, pressure-cap mullions/transoms, expressed fins on the
# same grid, a 450 mm facade zone with slab nosings and per-bay tenant
# backings (dark office, blind states, lit bays) behind the glass.
# The podium gains a subdivided storefront with stallrisers, a real
# four-leaf entrance against a lit lobby backdrop and a segmented
# clerestory; the crown gains posted rails, cooling towers with pipe
# runs, exhaust stacks, a PV row, BMU rails with a parked cradle and
# an octagonal helipad.  Facade geometry is accumulated into one
# MeshBuilder per semantic material, so the mesh count drops while
# the detail rises.  The exact outer envelope, tier heights and the
# 72.90 m beacon top are unchanged, so all eight audited placements,
# colliders and the far proxy stay exact.  Exterior only throughout.
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
    solar = MATS["SolarCell"]

    # ---- merged-geometry helpers (0.2.45) ------------------------------- #
    # The curtain wall and podium storefront are accumulated into one
    # MeshBuilder per semantic material, so thousands of real panes,
    # mullions and tenant backings export as a handful of meshes.
    builders = {}

    def bb(material):
        if material.name not in builders:
            builders[material.name] = (MeshBuilder(), material)
        return builders[material.name][0]

    def builder_box(builder, cx, cy, cz, dx, dy, dz):
        x0, x1 = cx - dx / 2.0, cx + dx / 2.0
        y0, y1 = cy - dy / 2.0, cy + dy / 2.0
        z0, z1 = cz - dz / 2.0, cz + dz / 2.0

        def v(x, y, z):
            return builder.add_vertex(Vector((x, y, z)))

        quads = (
            # +Z, -Z, +Y, -Y, +X, -X (outward windings)
            ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
            ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)),
            ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
            ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
            ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
            ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
        )
        for quad_corners in quads:
            ids = [v(*corner) for corner in quad_corners]
            builder.quad(*ids)

    def face_box(material, face, along_c, out_c, z_c, along_sz, out_sz, z_sz):
        builder = bb(material)
        if face in ("front", "back"):
            sign = -1.0 if face == "front" else 1.0
            builder_box(builder, along_c, sign * out_c, z_c, along_sz, out_sz, z_sz)
        else:
            sign = -1.0 if face == "left" else 1.0
            builder_box(builder, sign * out_c, along_c, z_c, out_sz, along_sz, z_sz)

    def face_quad(material, face, along_0, along_1, z_0, z_1, out_c):
        builder = bb(material)
        if face in ("front", "back"):
            sign = -1.0 if face == "front" else 1.0
            points = {
                (0, 0): Vector((along_0, sign * out_c, z_0)),
                (1, 0): Vector((along_1, sign * out_c, z_0)),
                (1, 1): Vector((along_1, sign * out_c, z_1)),
                (0, 1): Vector((along_0, sign * out_c, z_1)),
            }
            outward = Vector((0.0, sign, 0.0))
        else:
            sign = -1.0 if face == "left" else 1.0
            points = {
                (0, 0): Vector((sign * out_c, along_0, z_0)),
                (1, 0): Vector((sign * out_c, along_1, z_0)),
                (1, 1): Vector((sign * out_c, along_1, z_1)),
                (0, 1): Vector((sign * out_c, along_0, z_1)),
            }
            outward = Vector((sign, 0.0, 0.0))
        order = [(0, 0), (1, 0), (1, 1), (0, 1)]
        a = points[(0, 0)]
        normal = (points[(1, 0)] - a).cross(points[(0, 1)] - a)
        if normal.dot(outward) < 0.0:
            order = [(1, 0), (0, 0), (0, 1), (1, 1)]
        ids = [builder.add_vertex(points[key]) for key in order]
        builder.quad(*ids)

    def tenant_material(floor_index, bay_index, face_index, tier_seed):
        value = (floor_index * 31 + bay_index * 17 + face_index * 7 + tier_seed * 13) % 100
        if value < 50:
            return core, 1.0
        if value < 68:
            return curtain, 1.0
        if value < 80:
            return curtain, 0.52  # half-drawn blind
        return glow, 1.0

    # ---- curtain-wall shaft tiers --------------------------------------- #
    def curtain_tier(half, z_bottom, z_top, floors, bays, seed):
        height = z_top - z_bottom
        centre_z = (z_bottom + z_top) * 0.5
        floor_h = height / float(floors)
        field_half = half - 0.475  # glass field between corner-pier faces
        bay_w = (field_half * 2.0) / float(bays)
        glass_out = half + 0.025
        backing_out = half - 0.42

        # Occupied core, inset so slab edges and tenant backings have a
        # real 450 mm facade zone in front of it.
        box("tower_shaft_core", 0.0, 0.0, centre_z, half * 2.0 - 0.90, half * 2.0 - 0.90, height, core, bevel=0.035)
        for corner_x in (-1.0, 1.0):
            for corner_y in (-1.0, 1.0):
                box("tower_corner_pier", corner_x * (half - 0.050), corner_y * (half - 0.050), centre_z, 0.850, 0.850, height, trim)
                box("tower_corner_pier_cap", corner_x * (half - 0.050), corner_y * (half - 0.050), z_top - 0.055, 0.94, 0.94, 0.11, tower_metal)

        fin_bays = {bays // 4, bays // 2, (3 * bays) // 4}
        for face_index, face in enumerate(("front", "back", "left", "right")):
            # Continuous mullions on every bay boundary; every fourth
            # line deepens into an expressed fin tied to the same grid.
            for boundary in range(bays + 1):
                along = -field_half + boundary * bay_w
                if boundary in fin_bays:
                    face_box(tower_metal, face, along, half + 0.235, centre_z, 0.150, 0.470, height)
                    face_quad(frame, face, along - 0.085, along + 0.085, z_bottom, z_top, half + 0.080)
                    if boundary == bays // 2:
                        face_box(glow, face, along, half + 0.478, centre_z, 0.060, 0.020, height * 0.94)
                else:
                    face_box(frame, face, along, half + 0.045, centre_z, 0.075, 0.170, height)
            for floor_index in range(floors):
                z_floor = z_bottom + floor_index * floor_h
                # Slab nosing bridging core -> glass line.
                face_quad(core, face, -field_half, field_half, z_floor + 0.0, z_floor + 0.22, half)
                # Floor-line transom, spandrel band, sill transom.
                face_box(frame, face, 0.0, half + 0.035, z_floor + 0.075, field_half * 2.0, 0.150, 0.150)
                # Shadow-box spandrel: panel recessed behind a glass strip
                # flush with the vision lites, so the shaft reads as one
                # glass surface with a darker band behind it.
                face_quad(spandrel, face, -field_half, field_half, z_floor + 0.150, z_floor + 1.050, half - 0.070)
                face_quad(glass, face, -field_half, field_half, z_floor + 0.150, z_floor + 1.050, glass_out)
                face_quad(frame, face, -field_half, field_half, z_floor + 1.045, z_floor + 1.135, half + 0.110)
                # Ceiling-edge hint behind the head of the vision zone.
                face_quad(trim, face, -field_half, field_half, z_floor + 3.200, z_floor + 3.330, backing_out + 0.010)
                for bay_index in range(bays):
                    bay_centre = -field_half + (bay_index + 0.5) * bay_w
                    # Vision lite with a real shadow gap to its frame.
                    face_quad(glass, face, bay_centre - (bay_w - 0.095) / 2.0, bay_centre + (bay_w - 0.095) / 2.0, z_floor + 1.105, z_floor + 3.315, glass_out)
                    # Tenant backing: dark office, blind states, lit bay.
                    backing_material, height_fraction = tenant_material(floor_index, bay_index, face_index, seed)
                    backing_height = 2.210 * height_fraction
                    face_quad(
                        backing_material, face,
                        bay_centre - (bay_w - 0.120) / 2.0, bay_centre + (bay_w - 0.120) / 2.0,
                        z_floor + 1.135, z_floor + 1.135 + backing_height, backing_out,
                    )
                    if height_fraction < 1.0:
                        # Blind headrail at the drop line.
                        face_quad(frame, face, bay_centre - (bay_w - 0.120) / 2.0, bay_centre + (bay_w - 0.120) / 2.0, z_floor + 1.135 + backing_height - 0.0225, z_floor + 1.135 + backing_height + 0.0225, backing_out + 0.030)
            # Head transom closing the tier.
            face_box(frame, face, 0.0, half + 0.035, z_top - 0.075, field_half * 2.0, 0.150, 0.150)

    # ---- podium storefront ---------------------------------------------- #
    def podium_bay(face, offset, lit=False):
        # 3.55 m structural bay subdivided into three lites with a real
        # transom at door-head height and a stallriser below the sill.
        backing = glow if lit else core
        face_quad(backing, face, offset - 1.715, offset + 1.715, 0.880, 5.400, 15.500)
        for lite in (-1, 0, 1):
            lite_centre = offset + lite * 1.183
            face_quad(glass, face, lite_centre - 0.550, lite_centre + 0.550, 0.910, 3.050, 15.610)
            face_quad(glass, face, lite_centre - 0.550, lite_centre + 0.550, 3.190, 5.430, 15.610)
        for mullion_offset in (-0.592, 0.592):
            face_box(frame, face, offset + mullion_offset, 15.605, 3.145, 0.060, 0.110, 4.530)
        face_box(frame, face, offset, 15.605, 3.145, 3.550, 0.110, 0.080)   # transom
        face_box(frame, face, offset, 15.605, 5.450, 3.550, 0.110, 0.090)   # head
        face_box(granite, face, offset, 15.560, 0.545, 3.600, 0.100, 0.470)  # stallriser
        face_box(trim, face, offset, 15.610, 0.810, 3.750, 0.180, 0.090)     # sill

    # Plaza parcel and two-storey stone podium.
    box("tower_lot_plinth", 0.0, 0.0, 0.15, 34.00, 34.00, 0.30, granite)
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
        podium_bay("front", bay_offset, lit=bay_offset in (-2.17, 2.17))
        podium_bay("left", bay_offset)
        if bay_offset != 6.50:  # garage portal occupies this bay
            podium_bay("right", bay_offset)
    for bay_offset in (-10.83, -6.50, -2.17, 2.17):
        podium_bay("back", bay_offset)
    # Segmented clerestory under the cornice, aligned to the bay grid,
    # over a recessed dark shadow gap.
    for face in ("front", "back", "left", "right"):
        face_quad(spandrel, face, -13.70, 13.70, 6.610, 7.030, 15.550)
        for bay_offset in (-10.83, -6.50, -2.17, 2.17, 6.50, 10.83):
            face_quad(glass, face, bay_offset - 1.715, bay_offset + 1.715, 5.650, 6.550, 15.600)
            face_box(frame, face, bay_offset, 15.600, 6.100, 0.060, 0.110, 0.900)
        face_box(frame, face, 0.0, 15.600, 5.620, 27.40, 0.110, 0.070)
        face_box(frame, face, 0.0, 15.600, 6.590, 27.40, 0.110, 0.070)
    box("tower_sign_band", 0.0, -15.700, 5.78, 10.20, 0.180, 0.64, tower_metal)
    for sign_segment, (seg_x, seg_w) in enumerate(((-3.05, 2.40), (-0.60, 1.50), (2.40, 2.90))):
        box(f"tower_sign_glow_{sign_segment}", seg_x, -15.800, 5.78, seg_w, 0.035, 0.26, glow)
    for banner_side in (-1.0, 1.0):
        box("tower_entry_banner", banner_side * 5.85, -15.720, 5.20, 0.78, 0.055, 2.15, spandrel)
        box("tower_entry_banner_stripe", banner_side * 5.85, -15.755, 5.20, 0.14, 0.025, 1.85, glow)
        box("tower_entry_banner_rail", banner_side * 5.85, -15.730, 6.32, 0.92, 0.070, 0.070, tower_metal)
        box("tower_entry_banner_rail", banner_side * 5.85, -15.730, 4.08, 0.92, 0.070, 0.070, tower_metal)

    # Main entrance: stone portal, canopy on columns/tie rods, steps and
    # four real door leaves with a lit lobby backdrop behind the glass.
    box("tower_entry_header", 0.0, -15.700, 5.12, 9.60, 0.35, 0.58, trim)
    box("tower_entry_canopy", 0.0, -16.150, 4.66, 9.80, 1.35, 0.22, granite, bevel=0.020)
    box("tower_entry_canopy_soffit", 0.0, -16.150, 4.52, 9.35, 1.18, 0.055, wood)
    box("tower_entry_portal_left", -3.05, -15.620, 2.45, 0.46, 0.38, 4.90, granite)
    box("tower_entry_portal_right", 3.05, -15.620, 2.45, 0.46, 0.38, 4.90, granite)
    face_quad(core, "front", -2.78, 2.78, 0.30, 4.90, 15.460)
    face_quad(glow, "front", -2.20, 2.20, 1.45, 3.60, 15.470)
    face_box(granite, "front", 0.0, 15.490, 0.780, 2.60, 0.060, 0.900)  # reception desk silhouette
    for leaf_centre in (-1.425, -0.475, 0.475, 1.425):
        face_box(glass, "front", leaf_centre, 15.590, 1.700, 0.880, 0.045, 2.760)
        face_box(frame, "front", leaf_centre, 15.600, 0.500, 0.880, 0.080, 0.360)
        face_box(frame, "front", leaf_centre, 15.600, 3.110, 0.880, 0.080, 0.080)
    face_box(glass, "front", 0.0, 15.590, 3.920, 3.800, 0.045, 1.460)  # fanlight
    face_box(frame, "front", 0.0, 15.605, 3.165, 3.800, 0.110, 0.070)
    for column_side in (-1.0, 1.0):
        column_x = column_side * 4.40
        box("tower_entry_column_base", column_x, -16.55, 0.48, 0.38, 0.38, 0.36, granite)
        cyl("tower_entry_column", column_x, -16.55, 2.50, 0.120, 3.95, tower_metal, vertices=10)
        tube_between("tower_entry_tie_rod", (column_x, -16.55, 4.50), (column_x, -15.55, 5.55), 0.025, 0.025, tower_metal, vertices=8)
        cyl("tower_lobby_door_handle", column_side * 0.18, -15.680, 1.55, 0.024, 0.92, metal, vertices=6)
        cyl("tower_lobby_door_handle", column_side * 1.12, -15.680, 1.55, 0.024, 0.92, metal, vertices=6)
    for step_index, (step_y, step_top) in enumerate(((-15.85, 0.75), (-16.30, 0.60), (-16.72, 0.45))):
        box("tower_entry_step", 0.0, step_y, (0.30 + step_top) / 2.0, 7.40 - step_index * 0.40, 0.48, step_top - 0.30, pavement)
    box("tower_entry_mat", 0.0, -16.05, 0.765, 4.40, 0.85, 0.030, dark)
    box("tower_address_plaque", -4.95, -15.720, 1.75, 0.62, 0.060, 0.85, granite)
    box("tower_address_inset", -4.95, -15.760, 1.75, 0.40, 0.025, 0.56, metal)

    # Rear service door, loading dock and side parking-garage portal.
    box("tower_service_portal", 8.70, 15.600, 2.05, 4.35, 0.18, 3.45, trim)
    box("tower_service_door", 8.70, 15.680, 1.98, 3.85, 0.10, 3.10, tower_metal)
    for seam_z in (1.10, 1.95, 2.80):
        box("tower_service_door_seam", 8.70, 15.740, seam_z, 3.75, 0.025, 0.045, frame)
    box("tower_loading_dock", 8.70, 16.15, 0.50, 5.40, 1.30, 0.42, pavement)
    for bumper_x in (7.15, 10.25):
        box("tower_dock_bumper", bumper_x, 15.720, 0.95, 0.42, 0.16, 0.55, dark)
    box("tower_service_canopy", 8.70, 16.05, 3.95, 5.20, 1.05, 0.15, granite)
    box("tower_service_canopy_light", 8.70, 16.05, 3.855, 1.60, 0.28, 0.045, glow)
    box("tower_garage_portal", 15.600, 8.00, 2.00, 0.18, 5.00, 3.40, trim)
    box("tower_garage_door", 15.680, 8.00, 1.95, 0.10, 4.45, 3.05, tower_metal)
    for seam_y in (6.85, 8.00, 9.15):
        box("tower_garage_door_seam", 15.740, seam_y, 1.95, 0.025, 0.045, 2.95, frame)
    box("tower_garage_clearance_bar", 15.760, 8.00, 3.62, 0.070, 4.30, 0.22, glow)
    rbox("tower_garage_ramp", 16.25, 8.00, 0.38, 1.35, 5.30, 0.12, pavement, rotation=(0.0, 0.11, 0.0))
    for bin_x in (-12.20, -10.00):
        box("tower_waste_bin", bin_x, 16.15, 0.82, 1.85, 1.00, 1.08, dark, bevel=0.025)
        box("tower_waste_bin_lid", bin_x, 16.15, 1.40, 1.92, 1.05, 0.09, tower_metal)
    for vent_x in (-6.0, -3.2, 3.4):
        box("tower_rear_vent", vent_x, 15.560, 4.35, 1.90, 0.10, 1.15, tower_metal)
        for louvre_index in range(4):
            box("tower_rear_vent_slat", vent_x, 15.620, 3.98 + louvre_index * 0.25, 1.74, 0.035, 0.085, frame)
    box("tower_utility_cabinet", -13.90, 15.75, 1.05, 1.30, 0.45, 1.55, tower_metal)
    box("tower_utility_cabinet_door", -13.90, 15.990, 1.05, 1.10, 0.030, 1.35, frame)

    # Two shaft tiers and the setback between them.
    curtain_tier(13.00, 7.35, 41.85, 10, 15, 1)
    box("tower_setback_slab", 0.0, 0.0, 42.05, 27.40, 27.40, 0.45, trim)
    box("tower_setback_flashing", 0.0, 0.0, 42.315, 27.52, 27.52, 0.070, tower_metal)
    curtain_tier(11.00, 42.30, 66.45, 7, 13, 3)

    # Podium and setback roof terraces: posted glass rails, planters,
    # pergola and rooftop plant.
    def terrace_rail(half_extent, z_base, prefix):
        for rail_sign in (-1.0, 1.0):
            box(prefix + "_rail", 0.0, rail_sign * half_extent, z_base + 0.42, half_extent * 2.0 - 0.60, 0.055, 0.78, glass)
            box(prefix + "_rail_side", rail_sign * half_extent, 0.0, z_base + 0.42, 0.055, half_extent * 2.0 - 0.60, 0.78, glass)
            box(prefix + "_toprail", 0.0, rail_sign * half_extent, z_base + 0.85, half_extent * 2.0 - 0.45, 0.075, 0.065, frame)
            box(prefix + "_toprail_side", rail_sign * half_extent, 0.0, z_base + 0.85, 0.075, half_extent * 2.0 - 0.45, 0.065, frame)
            post = -half_extent + 0.85
            while post < half_extent - 0.60:
                box(prefix + "_rail_post", post, rail_sign * half_extent, z_base + 0.42, 0.055, 0.075, 0.84, frame)
                box(prefix + "_rail_post_side", rail_sign * half_extent, post, z_base + 0.42, 0.075, 0.055, 0.84, frame)
                post += 1.75

    terrace_rail(15.25, 7.40, "tower_podium_roof")
    terrace_rail(13.35, 42.33, "tower_setback")
    for planter_x in (-10.0, -5.0, 5.0, 10.0):
        for planter_y in (-14.25, 14.25):
            box("tower_podium_roof_planter", planter_x, planter_y, 7.62, 1.90, 0.72, 0.48, granite)
            box("tower_podium_roof_hedge", planter_x, planter_y, 7.96, 1.66, 0.50, 0.30, hedge, bevel=0.040)
        for planter_y in (-12.25, 12.25):
            box("tower_setback_planter", planter_x, planter_y, 42.55, 1.75, 0.68, 0.45, granite)
            box("tower_setback_hedge", planter_x, planter_y, 42.87, 1.52, 0.48, 0.28, hedge, bevel=0.038)
    for hvac_x, hvac_y in ((-14.30, -8.00), (-14.30, 8.00), (14.30, -8.00), (14.30, 8.00)):
        box("tower_podium_hvac", hvac_x, hvac_y, 7.78, 1.60, 1.45, 0.92, metal)
        cyl("tower_podium_hvac_fan", hvac_x, hvac_y, 8.27, 0.32, 0.045, frame, vertices=12)
        for louvre_index in range(3):
            box("tower_podium_hvac_slat", hvac_x, hvac_y - 0.735, 7.56 + louvre_index * 0.22, 1.30, 0.025, 0.070, frame)
    for post_x in (-7.0, 7.0):
        for post_y in (-12.85, -11.55):
            box("tower_setback_pergola_post", post_x, post_y, 43.35, 0.15, 0.15, 2.05, wood)
    for beam_y in (-12.88, -11.52):
        box("tower_setback_pergola_beam", 0.0, beam_y, 44.45, 15.20, 0.16, 0.17, wood)
    for slat_index in range(8):
        box("tower_setback_pergola_slat", -6.65 + slat_index * 1.90, -12.20, 44.60, 0.14, 1.58, 0.12, wood)

    # Mechanical crown: parapet cap, posted rail, louvred penthouse,
    # cooling towers with pipe runs, PV row, BMU rails + parked cradle,
    # octagonal helipad, exhaust stacks and the aviation mast.
    box("tower_crown_frame", 0.0, 0.0, 66.65, 19.40, 19.40, 0.40, trim)
    for cap_sign in (-1.0, 1.0):
        box("tower_roof_parapet_cap", 0.0, cap_sign * 10.95, 66.58, 22.30, 0.30, 0.14, tower_metal)
        box("tower_roof_parapet_cap_side", cap_sign * 10.95, 0.0, 66.58, 0.30, 22.30, 0.14, tower_metal)
    box("tower_mechanical_penthouse", 0.0, 0.0, 68.65, 15.50, 15.50, 3.60, spandrel, bevel=0.020)
    box("tower_mechanical_roof", 0.0, 0.0, 70.60, 16.30, 16.30, 0.30, trim)
    for louvre_z in (67.85, 68.45, 69.05, 69.65):
        box("tower_crown_louvre_front", 0.0, -7.80, louvre_z, 12.60, 0.10, 0.16, frame)
        box("tower_crown_louvre_rear", 0.0, 7.80, louvre_z, 12.60, 0.10, 0.16, frame)
        box("tower_crown_louvre_left", -7.80, 0.0, louvre_z, 0.10, 12.60, 0.16, frame)
        box("tower_crown_louvre_right", 7.80, 0.0, louvre_z, 0.10, 12.60, 0.16, frame)
    box("tower_penthouse_door", -3.40, -7.820, 67.95, 0.95, 0.07, 2.15, tower_metal)
    box("tower_penthouse_door_handle", -3.02, -7.870, 67.95, 0.16, 0.040, 0.05, frame)
    box("tower_roof_access_bulkhead", 5.90, 5.90, 67.55, 2.20, 1.60, 1.35, spandrel)
    box("tower_roof_access_lid", 5.90, 5.90, 68.27, 2.34, 1.74, 0.10, tower_metal)
    for fin_x in (-9.35, 9.35):
        for fin_y in (-9.35, 9.35):
            box("tower_crown_fin", fin_x, fin_y, 68.98, 0.55, 0.55, 5.15, tower_metal)
            box("tower_crown_fin_light", fin_x, fin_y, 71.62, 0.34, 0.34, 0.14, glow)
    for rail_sign in (-1.0, 1.0):
        box("tower_crown_rail", 0.0, rail_sign * 9.45, 67.30, 18.20, 0.050, 0.72, glass)
        box("tower_crown_rail_side", rail_sign * 9.45, 0.0, 67.30, 0.050, 18.20, 0.72, glass)
        post = -8.40
        while post < 8.60:
            box("tower_crown_rail_post", post, rail_sign * 9.45, 67.30, 0.050, 0.070, 0.72, frame)
            box("tower_crown_rail_post_side", rail_sign * 9.45, post, 67.30, 0.070, 0.050, 0.72, frame)
            post += 1.70
    for tower_x, tower_y in ((8.45, -4.00), (-8.45, 4.00)):
        cyl("tower_cooling_tower", tower_x, tower_y, 67.82, 0.95, 1.92, metal, vertices=12)
        cyl("tower_cooling_fan", tower_x, tower_y, 68.82, 0.62, 0.06, frame, vertices=12)
        for band_index in range(3):
            cyl("tower_cooling_band", tower_x, tower_y, 67.30 + band_index * 0.42, 0.965, 0.09, frame, vertices=12)
        tube_between("tower_cooling_pipe", (tower_x, tower_y, 67.15), (tower_x * 0.72, tower_y * 0.72, 67.15), 0.09, 0.09, tower_metal, vertices=10)
    for stack_x, stack_y in ((-8.60, -7.60), (8.60, 7.60)):
        cyl("tower_exhaust_stack", stack_x, stack_y, 67.60, 0.21, 1.50, tower_metal, vertices=10)
        cyl("tower_exhaust_cap", stack_x, stack_y, 68.48, 0.30, 0.10, frame, vertices=10)
    # Rooftop PV row along the south roof ring.
    for pv_index in range(6):
        pv_x = -6.25 + pv_index * 2.50
        box("tower_roof_pv_frame", pv_x, -9.55, 66.78, 2.05, 0.90, 0.08, frame)
        rbox("tower_roof_pv_panel", pv_x, -9.55, 67.02, 1.95, 1.05, 0.05, solar, rotation=(math.radians(-18.0), 0.0, 0.0))
    # BMU (window-washing) rails, machine and a cradle parked at the
    # east crown edge.
    for rail_y in (-10.30, 10.30):
        box("tower_bmu_rail", 0.0, rail_y, 66.52, 19.60, 0.14, 0.10, tower_metal)
    box("tower_bmu_machine", 8.90, -10.30, 67.05, 1.70, 0.95, 0.95, tower_metal, bevel=0.02)
    box("tower_bmu_jib", 9.85, -10.30, 67.62, 0.35, 0.22, 0.18, frame)
    rbox("tower_bmu_jib_arm", 10.55, -10.30, 67.30, 1.30, 0.16, 0.14, frame, rotation=(0.0, math.radians(35.0), 0.0))
    box("tower_bmu_cradle", 11.38, -10.30, 64.60, 0.62, 2.30, 1.05, tower_metal)
    box("tower_bmu_cradle_rail", 11.38, -10.30, 65.18, 0.66, 2.36, 0.06, frame)
    for cable_y in (-11.25, -9.35):
        cyl("tower_bmu_cable", 11.38, cable_y, 65.95, 0.016, 1.70, frame, vertices=6)
    # Octagonal helipad on the penthouse roof with edge lights.
    cyl("tower_helipad", 0.0, 0.0, 70.86, 5.60, 0.22, dark, vertices=8, rotation=(0.0, 0.0, math.radians(22.5)))
    cyl("tower_helipad_ring", 0.0, 0.0, 70.985, 4.35, 0.035, trim, vertices=24)
    cyl("tower_helipad_centre", 0.0, 0.0, 70.99, 3.95, 0.030, dark, vertices=24)
    for h_side in (-0.85, 0.85):
        box("tower_helipad_h_leg", h_side, 0.0, 71.01, 0.45, 3.10, 0.035, glow)
    box("tower_helipad_h_cross", 0.0, 0.0, 71.01, 2.10, 0.45, 0.035, glow)
    for light_index in range(8):
        angle = math.radians(22.5 + light_index * 45.0)
        box("tower_helipad_edge_light", 5.05 * math.cos(angle), 5.05 * math.sin(angle), 71.00, 0.20, 0.20, 0.09, glow)
    cyl("tower_mast", 8.85, 8.85, 69.72, 0.075, 5.75, tower_metal, vertices=8)
    box("tower_beacon", 8.85, 8.85, 72.75, 0.30, 0.30, 0.30, glow)

    # Forecourt, lit bollards, benches, flag poles and landscape strips.
    box("tower_forecourt_paving", 0.0, -16.15, 0.345, 24.00, 1.55, 0.07, pavement)
    for joint_x in (-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0):
        box("tower_forecourt_joint", joint_x, -16.15, 0.383, 0.045, 1.55, 0.006, granite)
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
        cyl("tower_front_bollard", bollard_x, -16.78, 0.68, 0.085, 0.76, tower_metal, vertices=8)
        box("tower_front_bollard_light", bollard_x, -16.78, 1.08, 0.10, 0.10, 0.045, glow)
    for bench_x in (-12.20, 12.20):
        box("tower_front_bench", bench_x, -16.05, 0.58, 2.20, 0.50, 0.10, wood)
        box("tower_front_bench_base", bench_x, -16.05, 0.42, 1.80, 0.36, 0.24, granite)
    for flag_x in (13.60, 14.45, 15.30):
        cyl("tower_flag_pole", flag_x, -15.90, 3.95, 0.045, 7.30, tower_metal, vertices=8)
        sphere("tower_flag_finial", flag_x, -15.90, 7.68, 0.11, 0.11, 0.11, tower_metal, segments=8, ring_count=6)
        box("tower_flag_base", flag_x, -15.90, 0.42, 0.34, 0.34, 0.24, granite)
    for rear_hedge_x in (-14.0, -4.5, 0.5, 13.5):
        box("tower_rear_hedge", rear_hedge_x, 16.35, 0.60, 2.60, 0.55, 0.52, hedge, bevel=0.055)

    # Emit the merged facade/storefront geometry, one mesh per material.
    for material_name, (builder, material) in builders.items():
        builder.build("tower_facade_" + material_name.lower(), material, smooth=False)


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

    # 0.3.7: flat interior light/curtain panels behind the shaft glass
    # become single outward quads in per-material merged builders
    # (2 tris instead of a 12-tri slab).  Only the outer face is ever
    # visible through the capsule glass skin, so nothing else changes.
    panel_builders = {}

    def local_panel(material, cx, cy, cz, lx, ly, width, height, yaw, extra_yaw, outward_shaft):
        if material.name not in panel_builders:
            panel_builders[material.name] = (MeshBuilder(), material)
        builder = panel_builders[material.name][0]
        centre_x, centre_y = rotate_xy(cx, cy, lx, ly, yaw)
        total_yaw = yaw + extra_yaw
        along = Vector((math.cos(total_yaw), math.sin(total_yaw), 0.0)) * (width * 0.5)
        centre = Vector((centre_x, centre_y, cz))
        up = Vector((0.0, 0.0, height * 0.5))
        points = [centre - along - up, centre + along - up, centre + along + up, centre - along + up]
        ox, oy = outward_shaft
        c = math.cos(yaw)
        s = math.sin(yaw)
        outward = Vector((c * ox - s * oy, s * ox + c * oy, 0.0))
        if (points[1] - points[0]).cross(points[3] - points[0]).dot(outward) < 0.0:
            points = [points[1], points[0], points[3], points[2]]
        ids = [builder.add_vertex(point) for point in points]
        builder.quad(*ids)

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
    capsule_volume("main_site_plinth", 0.0, 0.0, 0.18, 50.00, 42.00, 0.36, granite, vertices=20)
    capsule_volume("main_site_paving_inset", 0.0, 0.0, 0.385, 48.60, 40.60, 0.045, pavement, vertices=20)

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
            length + 0.08, width + 0.08, glass_height, core, yaw=yaw, vertices=18,
        )
        capsule_volume(
            "main_podium_glass_band_%d" % tier_index, 0.0, 0.0, glass_center,
            length + 0.17, width + 0.17, glass_height, glass, yaw=yaw, vertices=18,
        )
        perimeter_mullions(
            0.0, 0.0, length + 0.17, width + 0.17, yaw,
            glass_center, glass_height,
            (-0.44, -0.30, -0.15, 0.0, 0.15, 0.30, 0.44), frame,
        )
        capsule_volume(
            "main_podium_cornice_%d" % tier_index, 0.0, 0.0, z_top + 0.06,
            length + 0.70, width + 0.70, 0.24, trim, yaw=yaw, vertices=20,
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
            yaw=yaw, vertices=14,
        )
        if boundary_index % 5 == 0 and boundary_index not in (0, floor_count):
            capsule_volume(
                "main_five_floor_trim", cx, cy, slab_z + 0.20,
                length + 0.82, width + 0.82, 0.11, trim,
                yaw=yaw, vertices=14,
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
            yaw=yaw, vertices=12,
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
                local_panel(
                    panel_material, cx, cy, floor_center + 0.10,
                    panel_ratio * straight, face_sign * (width * 0.5 - 0.079),
                    panel_width_ratio * straight, 1.10,
                    yaw, 0.0, (0.0, face_sign),
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
                lx = cap_x + math.cos(angle) * (width * 0.5 - 0.079)
                ly = math.sin(angle) * (width * 0.5 - 0.079)
                local_panel(
                    curtain if floor_index % 6 == 0 else glow,
                    cx, cy, floor_center + 0.08,
                    lx, ly, 2.05, 1.02,
                    yaw, angle + math.pi * 0.5, (math.cos(angle), math.sin(angle)),
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
            yaw=yaw, vertices=16,
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
        yaw=top_yaw, vertices=16,
    )
    capsule_volume(
        "main_crown_core", top_cx, top_cy, shaft_top + 0.95,
        top_length - 3.90, top_width - 2.65, 1.55, spandrel,
        yaw=top_yaw, vertices=16,
    )
    capsule_volume(
        "main_crown_observation_glass", top_cx, top_cy, shaft_top + 1.00,
        top_length - 3.55, top_width - 2.30, 0.92, glass,
        yaw=top_yaw, vertices=16,
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
        yaw=top_yaw, vertices=16,
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
    sphere("main_forecourt_sculpture", -17.00, -15.20, 2.05, 2.05, 2.05, 2.35, trim, segments=18, ring_count=12)
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

    for material_name, (builder, material) in panel_builders.items():
        builder.build("main_merged_" + material_name.lower(), material, smooth=False)

# --------------------------------------------------------------------------- #
# Building Model No.6: RichTown Opera.  The fixed parcel is 52 x 56 m and
# the finial is exactly 22.00 m above the lot.  Blender -Y is the public
# west front after the native landmark yaw: a curved, inhabited glass
# foyer sits below three pleated ceramic shell vaults, while the fly
# tower, loading dock and service yard occupy the rear (+Y).  The design
# is original: three interlocking dhow-sail shells stand on a tall
# travertine podium rather than copying an existing opera house.
# 0.2.46 photoreal pass: the curved foyer wall becomes per-lite
# glazing (two columns by three rows per bay) with framed double-leaf
# entrance doors and sidelights; podium side/rear windows and the
# artists' door become framed units with recessed glass instead of
# glass slabs on solid bronze panels; the shells gain half-module
# ceramic panel seams; podium corners gain quoins; the fly-tower
# roof rails gain posts; the dock gains a seal and leveler; the
# emergency stairs move out of the solid podium volume (where they
# were invisible) onto the rear wall with treads and handrails.
# Repeated parts merge into per-material MeshBuilders.  The 52 x 56 m
# parcel, masses and the exact 22.00 m finial are unchanged.
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

    # ---- merged-geometry helpers (0.2.46) ------------------------------- #
    builders = {}

    def bb(material):
        if material.name not in builders:
            builders[material.name] = (MeshBuilder(), material)
        return builders[material.name][0]

    def builder_box(builder, cx, cy, cz, dx, dy, dz):
        x0, x1 = cx - dx / 2.0, cx + dx / 2.0
        y0, y1 = cy - dy / 2.0, cy + dy / 2.0
        z0, z1 = cz - dz / 2.0, cz + dz / 2.0

        def v(x, y, z):
            return builder.add_vertex(Vector((x, y, z)))

        quads = (
            ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
            ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)),
            ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
            ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
            ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
            ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
        )
        for quad_corners in quads:
            ids = [v(*corner) for corner in quad_corners]
            builder.quad(*ids)

    def builder_rbox(builder, cx, cy, cz, dx, dy, dz, yaw):
        cs = math.cos(yaw)
        sn = math.sin(yaw)
        corners = {}
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                for sz in (-1.0, 1.0):
                    lx = sx * dx / 2.0
                    ly = sy * dy / 2.0
                    corners[(sx, sy, sz)] = builder.add_vertex(Vector((
                        cx + lx * cs - ly * sn,
                        cy + lx * sn + ly * cs,
                        cz + sz * dz / 2.0,
                    )))
        faces = (
            ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)),
            ((-1, 1, -1), (1, 1, -1), (1, -1, -1), (-1, -1, -1)),
            ((1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)),
            ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)),
            ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)),
            ((-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)),
        )
        for face in faces:
            builder.quad(*[corners[key] for key in face])

    def builder_panel(builder, centre, along, height, outward):
        # 0.3.7: single outward quad for flat glass/interior layers
        # that sit inside solid frames (2 tris instead of a slab);
        # frames, sills and mullions stay solid builder boxes.
        up = Vector((0.0, 0.0, height * 0.5))
        points = [centre - along - up, centre + along - up, centre + along + up, centre - along + up]
        if (points[1] - points[0]).cross(points[3] - points[0]).dot(outward) < 0.0:
            points = [points[1], points[0], points[3], points[2]]
        ids = [builder.add_vertex(point) for point in points]
        builder.quad(*ids)

    def side_window(face_x, centre_y, centre_z, depth=2.45, height=3.35):
        # Framed punched window (0.2.46): dark reveal on the wall
        # face, glass recessed behind a bronze frame and cross.
        side_sign = 1.0 if face_x >= 0.0 else -1.0
        builder_panel(bb(interior), Vector((face_x + side_sign * 0.030, centre_y, centre_z)),
                      Vector((0.0, (depth - 0.04) * 0.5, 0.0)), height - 0.04, Vector((side_sign, 0.0, 0.0)))
        builder_panel(bb(opera_glass), Vector((face_x + side_sign * 0.075, centre_y, centre_z)),
                      Vector((0.0, depth * 0.5, 0.0)), height, Vector((side_sign, 0.0, 0.0)))
        frame_x = face_x + side_sign * 0.095
        builder_box(bb(bronze), frame_x, centre_y, centre_z + height * 0.5 + 0.045, 0.150, depth + 0.22, 0.11)
        builder_box(bb(bronze), frame_x, centre_y, centre_z - height * 0.5 - 0.045, 0.150, depth + 0.22, 0.11)
        for sd in (-1.0, 1.0):
            builder_box(bb(bronze), frame_x, centre_y + sd * (depth * 0.5 + 0.045), centre_z, 0.150, 0.11, height)
        builder_box(bb(bronze), face_x + side_sign * 0.100, centre_y, centre_z, 0.060, 0.07, height)
        builder_box(bb(bronze), face_x + side_sign * 0.100, centre_y, centre_z + height * 0.18, 0.060, depth, 0.07)
        box("opera_side_window_sill", face_x + side_sign * 0.165, centre_y, centre_z - height * 0.5 - 0.16,
            0.20, depth + 0.38, 0.13, limestone)
        box("opera_side_window_light", face_x + side_sign * 0.160, centre_y, centre_z + height * 0.5 + 0.20,
            0.05, depth * 0.72, 0.055, opera_light)

    def rear_window(centre_x, face_y, centre_z, width=2.60, height=3.10):
        # Framed punched window (0.2.46), as side_window.
        side_sign = 1.0 if face_y >= 0.0 else -1.0
        builder_panel(bb(interior), Vector((centre_x, face_y + side_sign * 0.030, centre_z)),
                      Vector(((width - 0.04) * 0.5, 0.0, 0.0)), height - 0.04, Vector((0.0, side_sign, 0.0)))
        builder_panel(bb(opera_glass), Vector((centre_x, face_y + side_sign * 0.075, centre_z)),
                      Vector((width * 0.5, 0.0, 0.0)), height, Vector((0.0, side_sign, 0.0)))
        frame_y = face_y + side_sign * 0.095
        builder_box(bb(bronze), centre_x, frame_y, centre_z + height * 0.5 + 0.045, width + 0.22, 0.150, 0.11)
        builder_box(bb(bronze), centre_x, frame_y, centre_z - height * 0.5 - 0.045, width + 0.22, 0.150, 0.11)
        for sd in (-1.0, 1.0):
            builder_box(bb(bronze), centre_x + sd * (width * 0.5 + 0.045), frame_y, centre_z, 0.11, 0.150, height)
        builder_box(bb(bronze), centre_x, face_y + side_sign * 0.100, centre_z, 0.07, 0.060, height)
        builder_box(bb(bronze), centre_x, face_y + side_sign * 0.100, centre_z + height * 0.18, width, 0.060, 0.07)
        box("opera_rear_window_sill", centre_x, face_y + side_sign * 0.165, centre_z - height * 0.5 - 0.16,
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
    # Limestone coping caps finish the basin rim (0.2.46).
    for coping_dy in (-1.62, 1.62):
        builder_box(bb(limestone), 0.0, -21.55 + coping_dy, 0.615, 39.10, 0.30, 0.05)
    for coping_x in (-19.42, 19.42):
        builder_box(bb(limestone), coping_x, -21.55, 0.615, 0.30, 3.55, 0.05)
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
            builder_panel(bb(interior), Vector((side_sign * 21.030, clerestory_y, 8.65)),
                          Vector((0.0, 1.93, 0.0)), 1.06, Vector((side_sign, 0.0, 0.0)))
            builder_panel(bb(opera_glass), Vector((side_sign * 21.075, clerestory_y, 8.65)),
                          Vector((0.0, 1.95, 0.0)), 1.10, Vector((side_sign, 0.0, 0.0)))
            builder_box(bb(bronze), side_sign * 21.095, clerestory_y, 9.225, 0.150, 4.10, 0.10)
            builder_box(bb(bronze), side_sign * 21.095, clerestory_y, 8.075, 0.150, 4.10, 0.10)
            for fin_dy in (-2.00, -1.28, -0.64, 0.0, 0.64, 1.28, 2.00):
                builder_box(bb(bronze), side_sign * 21.16, clerestory_y + fin_dy, 8.65, 0.20, 0.09, 1.25)
    for rear_pier_x in range(-20, 21, 5):
        box("opera_rear_pier", float(rear_pier_x), 20.17, 2.98, 0.78, 0.34, 5.05, limestone)
    for rear_seam_z in (1.55, 2.85, 4.15, 5.25):
        box("opera_rear_stone_seam", 0.0, 20.055, rear_seam_z, 45.3, 0.07, 0.065, frame)
    for rear_window_x in (-17.5, -12.5, 12.5, 17.5):
        rear_window(rear_window_x, 20.0, 3.15, width=2.70, height=3.30)
    # Corner quoins on the podium's outer corners (0.2.46), coursing
    # with the horizontal stone seams front and rear.
    for qx in (-1.0, 1.0):
        for qedge_y, qsign in ((20.0, 1.0), (-16.0, -1.0)):
            for course in range(4):
                qz = 0.98 + course * 1.30
                qlen_a = 1.05 if course % 2 == 0 else 0.68
                qlen_b = 0.68 if course % 2 == 0 else 1.05
                builder_box(bb(limestone), qx * (23.0 - qlen_a * 0.5 + 0.02), qedge_y + qsign * 0.075, qz, qlen_a, 0.15, 1.18)
                builder_box(bb(limestone), qx * 23.075, qedge_y - qsign * (qlen_b * 0.5 - 0.02), qz, 0.15, qlen_b, 1.18)

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
        cyl("opera_fly_roof_fan", plant_x - plant_w * 0.22, plant_y, 21.48, 0.42, 0.13, bronze, vertices=12)
        cyl("opera_fly_roof_fan_hub", plant_x - plant_w * 0.22, plant_y, 21.57, 0.11, 0.08, frame, vertices=10)
    for rail_y in (9.85, 19.15):
        box("opera_fly_roof_rail", 0.0, rail_y, 20.78, 24.2, 0.055, 0.055, bronze)
    for rail_x in (-12.1, 12.1):
        box("opera_fly_roof_side_rail", rail_x, 14.5, 20.78, 0.055, 9.3, 0.055, bronze)
    # Guard-rail posts and mid rails so the roof rails do not float.
    for post_i in range(11):
        post_x = -12.1 + post_i * 2.42
        builder_box(bb(bronze), post_x, 9.85, 20.52, 0.045, 0.045, 0.52)
        builder_box(bb(bronze), post_x, 19.15, 20.52, 0.045, 0.045, 0.52)
    for post_i in range(5):
        post_y = 9.85 + post_i * 2.325
        builder_box(bb(bronze), -12.1, post_y, 20.52, 0.045, 0.045, 0.52)
        builder_box(bb(bronze), 12.1, post_y, 20.52, 0.045, 0.045, 0.52)
    builder_box(bb(bronze), 0.0, 9.85, 20.52, 24.2, 0.035, 0.035)
    builder_box(bb(bronze), 0.0, 19.15, 20.52, 24.2, 0.035, 0.035)
    builder_box(bb(bronze), -12.1, 14.5, 20.52, 0.035, 9.3, 0.035)
    builder_box(bb(bronze), 12.1, 14.5, 20.52, 0.035, 9.3, 0.035)
    cyl("opera_lightning_mast", 11.2, 18.4, 20.98, 0.035, 1.45, bronze, vertices=8)
    sphere("opera_lightning_mast_tip", 11.2, 18.4, 21.74, 0.13, 0.13, 0.13, opera_light)

    # Rear stage door, dock, canopy and service yard.
    box("opera_stage_door_frame", 0.0, 19.66, 3.55, 7.55, 0.22, 6.15, bronze)
    for slat_index in range(8):
        box("opera_stage_door_slat", 0.0, 19.79, 0.95 + slat_index * 0.72, 7.05, 0.08, 0.62, metal)
    box("opera_stage_door_centre_rail", 0.0, 19.84, 3.55, 0.14, 0.07, 5.85, frame)
    # Dock seal cushions and a leveler plate at the stage door.
    for seal_x in (-3.98, 3.98):
        box("opera_dock_seal", seal_x, 19.82, 3.55, 0.36, 0.22, 6.30, interior)
    box("opera_dock_seal_top", 0.0, 19.82, 6.85, 8.30, 0.22, 0.36, interior)
    box("opera_dock_leveler", 0.0, 20.15, 1.02, 2.20, 0.60, 0.06, frame)
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
        cyl("opera_foyer_column", column_x, -14.55, 6.85, 0.23, 12.95, bronze, vertices=12)
        cyl("opera_foyer_column_base", column_x, -14.55, 0.62, 0.42, 0.52, opera_granite, vertices=12)
    # A pleated crimson performance curtain is visible through the foyer.
    box("opera_curtain_backing", 0.0, -12.35, 5.55, 13.4, 0.22, 9.0, interior)
    for pleat_index in range(21):
        pleat_x = -5.5 + pleat_index * 0.55
        cyl("opera_curtain_pleat", pleat_x, -12.55, 5.30, 0.17, 8.45, curtain, vertices=8)
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
    # Per-lite glazing (0.2.46): each 3.8 m bay is two columns by
    # three rows of recessed lites behind bronze rails and mullions
    # (merged builder geometry); the four centre bays carry framed
    # double-leaf doors with sidelights instead of glass slabs.
    lite_rows = ((1.96, 5.36), (5.52, 9.01), (9.15, 12.54))
    for bay_index in range(10):
        x0, y0 = facade_points[bay_index]
        x1, y1 = facade_points[bay_index + 1]
        mid_x = (x0 + x1) * 0.5
        mid_y = (y0 + y1) * 0.5
        bay_dx = x1 - x0
        bay_dy = y1 - y0
        bay_length = math.hypot(bay_dx, bay_dy)
        bay_yaw = math.atan2(bay_dy, bay_dx)
        dir_x = bay_dx / bay_length
        dir_y = bay_dy / bay_length
        normal_x = dir_y
        normal_y = -dir_x
        is_door_bay = 3 <= bay_index <= 6

        def bay_bar(along, out, zc, w, d, h, material):
            builder_rbox(bb(material), mid_x + dir_x * along + normal_x * out,
                         mid_y + dir_y * along + normal_y * out, zc, w, d, h, bay_yaw)

        def bay_lite(along, z0, z1, w, out_face=0.0225):
            # 0.3.7: recessed lite as one outward quad on the old
            # slab's outer face; the inhabited foyer behind the
            # curtain wall hides the quad's back from every angle.
            centre = Vector((mid_x + dir_x * along + normal_x * out_face,
                             mid_y + dir_y * along + normal_y * out_face,
                             (z0 + z1) * 0.5))
            builder_panel(bb(opera_glass), centre,
                          Vector((dir_x, dir_y, 0.0)) * (w * 0.5), z1 - z0,
                          Vector((normal_x, normal_y, 0.0)))

        for rail_z in (1.82, 5.45, 9.08, 12.62):
            bay_bar(0.0, 0.055, rail_z, bay_length + 0.04, 0.14, 0.16, bronze)
        bay_bar(0.0, 0.05, 12.74, bay_length + 0.04, 0.19, 0.10, bronze)
        if is_door_bay:
            bay_bar(0.0, 0.045, 8.28, 0.09, 0.20, 8.68, bronze)
            # Sidelights flanking the door unit, fanlight above it.
            for side_along in (-1.40, 1.40):
                bay_bar(side_along, 0.055, 0.98, 0.85, 0.13, 1.08, opera_granite)
                bay_bar(side_along, 0.04, 1.73, 0.85, 0.10, 0.36, bronze)
                bay_lite(side_along, 1.98, 3.92, 0.80)
            for col in (-0.25, 0.25):
                bay_lite(col * bay_length, 4.02, 5.36, bay_length * 0.5 - 0.10)
            for (lz0, lz1) in lite_rows[1:]:
                for col in (-0.25, 0.25):
                    bay_lite(col * bay_length, lz0, lz1, bay_length * 0.5 - 0.10)
            # Framed double-leaf door: jambs, stiles, rails, lites.
            for jamb in (-0.99, 0.99):
                bay_bar(jamb, 0.06, 2.15, 0.11, 0.18, 3.10, bronze)
            bay_bar(0.0, 0.06, 3.82, 2.10, 0.18, 0.24, bronze)
            bay_bar(0.0, 0.03, 0.60, 2.10, 0.24, 0.06, opera_granite)
            for leaf in (-0.475, 0.475):
                for stile in (-0.435, 0.435):
                    bay_bar(leaf + stile, 0.05, 2.15, 0.075, 0.11, 3.00, bronze)
                bay_bar(leaf, 0.05, 3.54, 0.90, 0.11, 0.28, bronze)
                bay_bar(leaf, 0.05, 1.84, 0.90, 0.11, 0.12, bronze)
                bay_bar(leaf, 0.05, 0.92, 0.90, 0.11, 0.60, bronze)
                bay_lite(leaf, 1.96, 3.36, 0.76, out_face=0.065)
                bay_lite(leaf, 1.25, 1.77, 0.76, out_face=0.065)
                handle_along = leaf + (0.36 if leaf < 0.0 else -0.36)
                hx = mid_x + dir_x * handle_along + normal_x * 0.16
                hy = mid_y + dir_y * handle_along + normal_y * 0.16
                cyl("opera_door_handle", hx, hy, 1.62, 0.026, 0.90, bronze, vertices=8)
                for mount_z in (1.32, 1.92):
                    bay_bar(handle_along, 0.105, mount_z, 0.05, 0.12, 0.05, bronze)
        else:
            bay_bar(0.0, 0.045, 7.28, 0.09, 0.20, 10.68, bronze)
            bay_bar(0.0, 0.055, 0.98, bay_length, 0.13, 1.08, opera_granite)
            bay_bar(0.0, 0.04, 1.73, bay_length, 0.10, 0.36, bronze)
            for (lz0, lz1) in lite_rows:
                for col in (-0.25, 0.25):
                    bay_lite(col * bay_length, lz0, lz1, bay_length * 0.5 - 0.10)
    for point_index, (point_x, point_y) in enumerate(facade_points):
        if point_index == 0:
            tangent_yaw = math.atan2(facade_points[1][1] - point_y, facade_points[1][0] - point_x)
        elif point_index == len(facade_points) - 1:
            tangent_yaw = math.atan2(point_y - facade_points[-2][1], point_x - facade_points[-2][0])
        else:
            tangent_yaw = math.atan2(facade_points[point_index + 1][1] - facade_points[point_index - 1][1],
                                     facade_points[point_index + 1][0] - facade_points[point_index - 1][0])
        builder_rbox(bb(bronze), point_x, point_y - 0.03, 7.15, 0.20, 0.27, 11.35, tangent_yaw)

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
             bay_length + 0.06, 2.55, 0.17, bronze, rotation=(0.055, 0.0, bay_yaw))
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

    cross_segments = 28
    length_segments = 14
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
                         sides=4, uv_v_scale=0.35)
        # Longitudinal ceramic-panel ribs and transverse movement joints.
        for rib_u in (-0.84, -0.63, -0.42, -0.21, 0.0, 0.21, 0.42, 0.63, 0.84):
            rib_points = [offset_shell_point(spec, rib_u, rib_index / 12.0) for rib_index in range(13)]
            builder_tube(shell_seam_builder, rib_points, [0.055] * len(rib_points),
                         sides=4, uv_v_scale=0.45)
        for seam_t in (0.16, 0.32, 0.48, 0.64, 0.80):
            seam_points = [offset_shell_point(spec, -1.0 + seam_index / 12.0, seam_t, outward=0.050)
                           for seam_index in range(25)]
            builder_tube(shell_seam_builder, seam_points, [0.040] * len(seam_points),
                         sides=4, uv_v_scale=0.45)
        # Finer ceramic panel grain between the main ribs and joints
        # (0.2.46): half-module seams so the vaults do not read as
        # smooth moulded shells at boulevard distance.
        for seam_u in (-0.945, -0.735, -0.525, -0.315, -0.105, 0.105, 0.315, 0.525, 0.735, 0.945):
            fine_points = [offset_shell_point(spec, seam_u, seam_i / 9.0, outward=0.058) for seam_i in range(10)]
            builder_tube(shell_seam_builder, fine_points, [0.026] * len(fine_points),
                         sides=4, uv_v_scale=0.45)
        for seam_t2 in (0.08, 0.24, 0.40, 0.56, 0.72, 0.88):
            fine_points2 = [offset_shell_point(spec, -1.0 + seam_j / 12.0, seam_t2, outward=0.042)
                            for seam_j in range(25)]
            builder_tube(shell_seam_builder, fine_points2, [0.024] * len(fine_points2),
                         sides=4, uv_v_scale=0.45)
        # Heavy front/rear fasciae and side edge beams show shell depth.
        for fascia_t, fascia_radius in ((0.0, 0.165), (1.0, 0.135)):
            fascia_points = [offset_shell_point(spec, -1.0 + fascia_index / 12.0, fascia_t, outward=0.035)
                             for fascia_index in range(25)]
            builder_tube(shell_seam_builder, fascia_points, [fascia_radius] * len(fascia_points),
                         sides=5, uv_v_scale=0.45)
        for edge_u in (-1.0, 1.0):
            edge_points = [offset_shell_point(spec, edge_u, edge_index / 12.0, outward=0.045)
                           for edge_index in range(13)]
            builder_tube(shell_seam_builder, edge_points, [0.135] * len(edge_points),
                         sides=5, uv_v_scale=0.45)
        # Continuous warm cove light under each front fascia.
        cove_points = []
        for cove_index in range(25):
            cove_u = -1.0 + cove_index / 12.0
            cove_point = shell_point(spec, cove_u, 0.0, drop=0.24, y_offset=-0.10)
            cove_points.append(cove_point)
        builder_tube(shell_light_builder, cove_points, [0.035] * len(cove_points),
                     sides=4, uv_v_scale=0.35)
        # Central bronze-framed skylight spine follows the vault crown.
        spine_points = [offset_shell_point(spec, 0.0, spine_index / 12.0, outward=0.10)
                        for spine_index in range(13)]
        builder_tube(shell_glass_builder, spine_points, [0.20] * len(spine_points),
                     sides=5, uv_v_scale=0.45)
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
        cyl("opera_terrace_table_top", 24.25, table_y, 1.32, 0.58, 0.07, limestone, vertices=12)
        cyl("opera_terrace_table_leg", 24.25, table_y, 0.97, 0.055, 0.66, bronze, vertices=10)
        for chair_offset in (-0.82, 0.82):
            box("opera_terrace_chair_seat", 24.25, table_y + chair_offset, 1.03, 0.46, 0.42, 0.07, opera_wood)
            box("opera_terrace_chair_back", 24.25, table_y + chair_offset + (0.20 if chair_offset > 0.0 else -0.20),
                1.27, 0.46, 0.06, 0.48, opera_wood)
        box("opera_terrace_table_light", 24.25, table_y, 1.43, 0.12, 0.12, 0.12, opera_light)

    # Framed artist door leaf (0.2.46) instead of a glass slab.
    builder_panel(bb(interior), Vector((-23.030, 0.0, 2.05)), Vector((0.0, 0.72, 0.0)), 3.01, Vector((-1.0, 0.0, 0.0)))
    builder_panel(bb(opera_glass), Vector((-23.075, 0.0, 2.41)), Vector((0.0, 0.55, 0.0)), 1.72, Vector((-1.0, 0.0, 0.0)))
    builder_panel(bb(opera_glass), Vector((-23.075, 0.0, 1.21)), Vector((0.0, 0.55, 0.0)), 0.42, Vector((-1.0, 0.0, 0.0)))
    builder_box(bb(bronze), -23.10, 0.0, 3.66, 0.16, 1.75, 0.12)
    builder_box(bb(bronze), -23.10, 0.0, 0.44, 0.16, 1.75, 0.12)
    for jamb_y in (-0.82, 0.82):
        builder_box(bb(bronze), -23.10, jamb_y, 2.05, 0.16, 0.11, 3.35)
    for stile_y in (-0.60, 0.60):
        builder_box(bb(bronze), -23.085, stile_y, 2.05, 0.09, 0.09, 3.10)
    builder_box(bb(bronze), -23.085, 0.0, 3.42, 0.09, 1.28, 0.24)
    builder_box(bb(bronze), -23.085, 0.0, 1.48, 0.09, 1.28, 0.12)
    builder_box(bb(bronze), -23.085, 0.0, 0.78, 0.09, 1.28, 0.55)
    cyl("opera_artist_door_handle", -23.20, 0.42, 1.95, 0.024, 0.85, bronze, vertices=8)
    box("opera_artist_canopy", -23.82, 0.0, 3.92, 1.55, 2.75, 0.15, bronze)
    box("opera_artist_entrance_light", -23.34, 0.0, 3.48, 0.06, 1.25, 0.08, opera_light)
    box("opera_artist_step", -23.75, 0.0, 0.48, 1.35, 2.55, 0.14, limestone)

    # Emergency stairs at the service corners (0.2.46: moved out of
    # the solid podium volume, where the flights were invisible, to
    # the rear wall face with real treads, landings and handrails).
    for stair_side in (-1.0, 1.0):
        stair_x = stair_side * 21.65
        for flight_index in range(4):
            flight_base_z = 0.55 + flight_index * 1.28
            rise_dir = 1.0 if flight_index % 2 == 0 else -1.0
            rbox("opera_emergency_flight", stair_x, 21.55, flight_base_z + 0.56, 1.05, 2.75, 0.12, metal,
                 rotation=(0.43 * rise_dir, 0.0, 0.0))
            for tread_i in range(7):
                tread_along = -1.25 + 2.50 * (tread_i + 0.5) / 7.0
                builder_box(bb(metal), stair_x, 21.55 + tread_along,
                            flight_base_z + 0.645 + rise_dir * tread_along * 0.4587, 1.00, 0.30, 0.05)
            box("opera_emergency_landing", stair_x, 21.55 + rise_dir * 1.62,
                flight_base_z + 1.18, 1.15, 0.85, 0.11, metal)
            tube_between("opera_emergency_rail",
                         (stair_x + stair_side * 0.52, 21.55 - rise_dir * 1.25, flight_base_z + 0.95),
                         (stair_x + stair_side * 0.52, 21.55 + rise_dir * 1.25, flight_base_z + 2.10),
                         0.030, 0.030, bronze, vertices=8)
        for post_dx in (-0.52, 0.52):
            box("opera_emergency_post", stair_x + post_dx, 23.17, 2.12, 0.07, 0.07, 4.24, metal)
        tube_between("opera_emergency_brace", (stair_x, 22.80, 4.20), (stair_x, 20.05, 3.00),
                     0.035, 0.035, metal, vertices=8)

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

    for material_name, (builder, material) in builders.items():
        builder.build("opera_merged_" + material_name.lower(), material, smooth=False)


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
            # 0.3.7: thin brass rails/bands do not need the drum
            # cornice's segment count; scale by the ring's size.
            major_segments=28 if major > 3.0 else 20,
            minor_segments=6 if minor > 0.08 else 5,
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
        segments = 16 if radius > 2.0 else 12
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
        segments = 16 if radius > 2.0 else 12
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
        panel("mosque_window_reveal_x", outer_x + sign * 0.070, centre_y, centre_z,
              width + 0.08, height + 0.08, interior, "right" if sign > 0.0 else "left")
        panel("mosque_window_glass_x", outer_x + sign * 0.110, centre_y, centre_z,
              width, height, mosque_glass, "right" if sign > 0.0 else "left")
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
        panel("mosque_window_reveal_y", centre_x, outer_y + sign * 0.070, centre_z,
              width + 0.08, height + 0.08, interior, "back" if sign > 0.0 else "front")
        panel("mosque_window_glass_y", centre_x, outer_y + sign * 0.110, centre_z,
              width, height, mosque_glass, "back" if sign > 0.0 else "front")
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
    sphere("mosque_mihrab_cupola_dome", -14.65, 0.0, 10.28, 2.30, 2.30, 1.55, dome_mat, segments=16, ring_count=12)
    cyl("mosque_mihrab_cupola_finial", -14.65, 0.0, 11.18, 0.030, 0.55, brass, vertices=8)
    sphere("mosque_mihrab_cupola_orb", -14.65, 0.0, 11.32, 0.20, 0.20, 0.20, brass, segments=10, ring_count=8)
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
               0.22, 0.30, 0.48, mosque_light, segments=12, ring_count=8)
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
                     sides=4, uv_v_scale=0.35)
    for profile_index in (1, 3, 5, 7):
        radius, dz = dome_profile[profile_index]
        ring_points = []
        for ring_index in range(43):
            angle = math.tau * float(ring_index) / 42.0
            ring_points.append(Vector((math.cos(angle) * (radius + 0.075),
                                       math.sin(angle) * (radius + 0.075),
                                       15.92 + dz)))
        builder_tube(rib_builder, ring_points, [0.042] * len(ring_points),
                     sides=4, uv_v_scale=0.35, cap_start=False, cap_end=False)
    rib_builder.build("mosque_dome_ribs", brass, smooth=True)
    cyl("mosque_dome_finial_rod", 0.0, 0.0, 24.05, 0.055, 1.15, brass, vertices=10)
    sphere("mosque_dome_finial_orb_large", 0.0, 0.0, 23.92, 0.52, 0.52, 0.52, brass, segments=12, ring_count=8)
    sphere("mosque_dome_finial_orb_small", 0.0, 0.0, 24.32, 0.34, 0.34, 0.34, brass, segments=12, ring_count=8)
    crescent_builder = MeshBuilder()
    add_crescent(crescent_builder, 0.0, 0.0, 25.08, scale=1.05)
    crescent_builder.build("mosque_dome_crescent", brass, smooth=False)

    # Four satellite domes on the hall roof corners.
    for sx in (-10.50, 10.50):
        for sy in (-12.00, 12.00):
            cyl("mosque_satellite_drum", sx, sy, 13.85, 2.25, 1.30, stone, vertices=18)
            torus("mosque_satellite_cornice", sx, sy, 14.52, 2.28, 0.10, limestone)
            sphere("mosque_satellite_dome", sx, sy, 15.20, 4.85, 4.85, 3.15, dome_mat, segments=18, ring_count=12)
            cyl("mosque_satellite_finial", sx, sy, 17.05, 0.035, 0.65, brass, vertices=8)
            sphere("mosque_satellite_orb", sx, sy, 17.20, 0.24, 0.24, 0.24, brass, segments=10, ring_count=8)
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
        cyl("mosque_minaret_shaft", cx, cy, 14.55, 1.24, 14.10, stone, vertices=16)
        for band_z in (10.20, 13.65, 17.10):
            cyl("mosque_minaret_tile_band", cx, cy, band_z, 1.31, 0.48, tile, vertices=16)
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
        cyl("mosque_minaret_balcony", cx, cy, 19.38, 2.05, 0.36, limestone, vertices=16)
        cyl("mosque_minaret_balcony_edge", cx, cy, 19.60, 2.10, 0.10, brass, vertices=16)
        for post_index in range(16):
            angle = math.tau * float(post_index) / 16.0
            cyl("mosque_minaret_rail_post", cx + math.cos(angle) * 1.86,
                cy + math.sin(angle) * 1.86, 20.05, 0.026, 0.86, brass, vertices=6)
        torus("mosque_minaret_rail_top", cx, cy, 20.48, 1.86, 0.035, brass)
        torus("mosque_minaret_rail_mid", cx, cy, 20.05, 1.86, 0.025, brass)
        cyl("mosque_minaret_upper_shaft", cx, cy, 21.95, 0.98, 4.75, stone, vertices=14)
        cyl("mosque_minaret_upper_tile", cx, cy, 22.85, 1.04, 0.42, tile, vertices=14)
        cyl("mosque_minaret_second_balcony", cx, cy, 24.05, 1.52, 0.28, limestone, vertices=16)
        torus("mosque_minaret_second_rail", cx, cy, 24.62, 1.36, 0.028, brass)
        cone("mosque_minaret_cap", cx, cy, 26.55, 1.48, 0.06, 4.20, dome_mat, vertices=16)
        torus("mosque_minaret_cap_ring", cx, cy, 24.48, 1.48, 0.065, brass)
        cyl("mosque_minaret_finial_rod", cx, cy, 29.35, 0.038, 1.30, brass, vertices=8)
        sphere("mosque_minaret_finial_orb", cx, cy, 29.28, 0.30, 0.30, 0.30, brass, segments=10, ring_count=8)
        sphere("mosque_minaret_finial_tip", cx, cy, 29.82, 0.18, 0.18, 0.18, brass, segments=10, ring_count=8)

    # Low terrace lanterns at the four parcel corners.
    for lantern_x in (-18.55, 18.55):
        for lantern_y in (-17.35, 17.35):
            box("mosque_terrace_lantern_base", lantern_x, lantern_y, 0.78,
                0.42, 0.42, 0.42, granite)
            box("mosque_terrace_lantern_frame", lantern_x, lantern_y, 1.18,
                0.30, 0.30, 0.42, brass)
            sphere("mosque_terrace_lantern_globe", lantern_x, lantern_y, 1.18,
                   0.22, 0.22, 0.30, mosque_light, segments=12, ring_count=8)
    arch_builders["limestone"].build("mosque_arch_caps_limestone", limestone, smooth=False)
    arch_builders["glass"].build("mosque_arch_caps_glass", mosque_glass, smooth=False)
    arch_builders["brass"].build("mosque_arch_caps_brass", brass, smooth=False)
    arch_builders["interior"].build("mosque_arch_caps_interior", interior, smooth=False)


# --------------------------------------------------------------------------- #
def build_hotel():
    """Building Model No.8: an original beachfront grand hotel authored
    for the 34 x 26 m Corniche hotel parcels (X892 row).  Two-storey
    stone podium with a porte-cochere entrance, an 11-floor guest tower
    with balconied bays and a full-height bronze/glass centre bay, a
    pool terrace on the podium roof and a set-back penthouse crown.
    Authored envelope 33.6 x 26.0 m, about 49 m to the beacon."""
    stone = MATS["HotelStone"]
    plaster = MATS["HotelPlaster"]
    bronze = MATS["HotelBronze"]
    glass = MATS["HotelGlass"]
    interior = MATS["HotelInterior"]
    granite = MATS["HotelGranite"]
    wood = MATS["HotelWood"]
    water = MATS["HotelWater"]
    light = MATS["HotelLight"]
    curtain = MATS["HotelCurtain"]
    accent = MATS["HotelAccent"]
    frame = MATS["WindowFrame"]
    dark = MATS["RoofDark"]
    hedge = MATS["VillaHedge"]

    def tower_window(cx, cy, cz, width, height, face):
        sign = -1.0 if face in ("front", "left") else 1.0
        variant = int(abs(cx * 3.1 + cy * 4.7 + cz * 6.3)) % 5
        if face in ("front", "back"):
            box("hotel_win_frame", cx, cy + sign * 0.030, cz, width + 0.16, 0.14, height + 0.16, frame)
            panel("hotel_win_interior", cx, cy + sign * 0.027, cz, width - 0.02, height - 0.02, interior, face)
            if variant == 0:
                panel("hotel_win_lit", cx, cy + sign * 0.065, cz, width - 0.14, height - 0.14, light, face)
            elif variant == 1:
                for sd in (-1.0, 1.0):
                    panel("hotel_win_curtain", cx + sd * (width / 2.0 - 0.16), cy + sign * 0.067, cz, 0.22, height - 0.14, curtain, face)
            elif variant == 2:
                panel("hotel_win_blind", cx, cy + sign * 0.067, cz + height * 0.31, width - 0.10, height * 0.34, curtain, face)
            panel("hotel_win_glass", cx, cy + sign * 0.108, cz, width, height, glass, face)
            box("hotel_win_mullion", cx, cy + sign * 0.102, cz, 0.05, 0.05, height, frame)
            box("hotel_win_sill", cx, cy + sign * 0.10, cz - height / 2.0 - 0.065, width + 0.30, 0.26, 0.09, stone)
        else:
            box("hotel_win_frame", cx + sign * 0.030, cy, cz, 0.14, width + 0.16, height + 0.16, frame)
            panel("hotel_win_interior", cx + sign * 0.027, cy, cz, width - 0.02, height - 0.02, interior, face)
            if variant == 0:
                panel("hotel_win_lit", cx + sign * 0.065, cy, cz, width - 0.14, height - 0.14, light, face)
            elif variant == 1:
                for sd in (-1.0, 1.0):
                    panel("hotel_win_curtain", cx + sign * 0.067, cy + sd * (width / 2.0 - 0.16), cz, 0.22, height - 0.14, curtain, face)
            elif variant == 2:
                panel("hotel_win_blind", cx + sign * 0.067, cy, cz + height * 0.31, width - 0.10, height * 0.34, curtain, face)
            panel("hotel_win_glass", cx + sign * 0.108, cy, cz, width, height, glass, face)
            box("hotel_win_mullion", cx + sign * 0.102, cy, cz, 0.05, 0.05, height, frame)
            box("hotel_win_sill", cx + sign * 0.10, cy, cz - height / 2.0 - 0.065, 0.26, width + 0.30, 0.09, stone)

    def balcony(cx, face_y, sign, floor_base):
        slab_y = face_y + sign * 0.80
        box("hotel_balcony_slab", cx, slab_y, floor_base + 0.10, 2.95, 1.62, 0.16, stone)
        box("hotel_balcony_rail_glass", cx, face_y + sign * 1.54, floor_base + 0.66, 2.85, 0.05, 0.78, glass)
        box("hotel_balcony_rail_top", cx, face_y + sign * 1.54, floor_base + 1.09, 2.96, 0.09, 0.07, bronze)
        box("hotel_balcony_divider", cx + 1.56, slab_y, floor_base + 0.72, 0.09, 1.52, 1.18, bronze)

    def side_balcony(face_x, cy, sign, floor_base):
        slab_x = face_x + sign * 0.80
        box("hotel_side_balcony_slab", slab_x, cy, floor_base + 0.10, 1.62, 2.95, 0.16, stone)
        box("hotel_side_balcony_rail_glass", face_x + sign * 1.54, cy, floor_base + 0.66, 0.05, 2.85, 0.78, glass)
        box("hotel_side_balcony_rail_top", face_x + sign * 1.54, cy, floor_base + 1.09, 0.09, 2.96, 0.07, bronze)
        for ret in (-1.44, 1.44):
            box("hotel_side_balcony_return", slab_x, cy + ret, floor_base + 0.66, 1.52, 0.05, 0.78, glass)
            box("hotel_side_balcony_return_top", slab_x, cy + ret, floor_base + 1.09, 1.56, 0.07, 0.07, bronze)

    # ---- parcel plinth and two-storey podium -------------------------
    box("hotel_plinth", 0.0, 0.0, 0.15, 33.60, 26.00, 0.30, granite, bevel=0.015)
    box("hotel_podium", 0.0, 0.0, 3.80, 32.40, 22.40, 7.00, stone, bevel=0.02)
    box("hotel_podium_cornice", 0.0, 0.0, 7.45, 33.00, 23.00, 0.30, plaster)
    box("hotel_podium_roof", 0.0, 0.0, 7.63, 32.20, 22.20, 0.08, stone)
    for side_y in (-11.24, 11.24):
        box("hotel_podium_base", 0.0, side_y, 0.80, 32.55, 0.14, 1.00, granite)
        box("hotel_podium_bronze_band", 0.0, side_y, 4.62, 32.55, 0.12, 0.34, bronze)
    for side_x in (-16.24, 16.24):
        box("hotel_podium_base_side", side_x, 0.0, 0.80, 0.14, 22.55, 1.00, granite)
        box("hotel_podium_bronze_band_side", side_x, 0.0, 4.62, 0.12, 22.55, 0.34, bronze)

    # Podium colonnade: piers, lobby glazing and a restaurant row above.
    pier_xs = [-14.4 + 3.6 * i for i in range(9)]
    bay_xs = [-12.6 + 3.6 * i for i in range(8)]
    for face_y, face in ((-11.20, "front"), (11.20, "back")):
        sign = -1.0 if face == "front" else 1.0
        for px in pier_xs:
            box("hotel_podium_pier", px, face_y + sign * 0.10, 2.60, 0.95, 0.34, 4.40, plaster)
            box("hotel_podium_pier_cap", px, face_y + sign * 0.12, 4.92, 1.15, 0.38, 0.22, bronze)
        for bx in bay_xs:
            if face == "front" and abs(bx) < 3.7:
                continue  # entrance bays are built separately below
            box("hotel_lobby_frame", bx, face_y + sign * 0.045, 2.55, 3.00, 0.15, 4.00, frame)
            panel("hotel_lobby_interior", bx, face_y + sign * 0.030, 2.55, 2.86, 3.86, interior, face)
            panel("hotel_lobby_lit", bx, face_y + sign * 0.055, 2.45, 2.70, 3.60, light, face)
            panel("hotel_lobby_glass", bx, face_y + sign * 0.125, 2.55, 2.86, 3.86, glass, face)
            box("hotel_lobby_mullion", bx, face_y + sign * 0.12, 2.55, 0.06, 0.05, 3.86, bronze)
            box("hotel_upper_frame", bx, face_y + sign * 0.04, 6.15, 2.50, 0.13, 1.55, frame)
            panel("hotel_upper_interior", bx, face_y + sign * 0.027, 6.15, 2.36, 1.41, interior, face)
            panel("hotel_upper_glass", bx, face_y + sign * 0.110, 6.15, 2.36, 1.41, glass, face)
    for side_x, face in ((-16.20, "left"), (16.20, "right")):
        sign = -1.0 if face == "left" else 1.0
        for wy in (-8.0, -4.0, 0.0, 4.0, 8.0):
            tower_window(side_x, wy, 2.60, 2.30, 3.60, face)
            tower_window(side_x, wy, 6.15, 2.10, 1.50, face)

    # ---- porte-cochere entrance (front, -Y) --------------------------
    panel("hotel_entrance_interior", 0.0, -11.30, 2.55, 9.60, 4.30, interior, "front")
    panel("hotel_entrance_lit", 0.0, -11.32, 2.45, 9.30, 4.00, light, "front")
    panel("hotel_entrance_glass", 0.0, -11.36, 2.55, 9.40, 4.20, glass, "front")
    for mx in (-4.7, -2.35, 2.35, 4.7):
        box("hotel_entrance_mullion", mx, -11.37, 2.55, 0.09, 0.06, 4.20, bronze)
    cyl("hotel_revolving_drum", 0.0, -11.40, 1.95, 1.45, 3.30, glass, vertices=18)
    cyl("hotel_revolving_top", 0.0, -11.40, 3.68, 1.55, 0.18, bronze, vertices=18)
    cyl("hotel_revolving_post", 0.0, -11.40, 1.95, 0.09, 3.30, bronze, vertices=10)
    for dx in (-3.45, 3.45):
        box("hotel_side_door_frame", dx, -11.36, 1.95, 1.70, 0.10, 3.30, bronze)
        box("hotel_side_door_glass", dx, -11.40, 1.95, 1.50, 0.04, 3.10, glass)
    box("hotel_carpet", 0.0, -12.25, 0.325, 3.60, 1.50, 0.05, curtain)
    box("hotel_canopy", 0.0, -11.35, 4.85, 13.00, 2.90, 0.22, stone)
    box("hotel_canopy_fascia", 0.0, -12.85, 4.72, 13.00, 0.14, 0.50, bronze)
    for sx in (-3.2, -1.6, 0.0, 1.6, 3.2):
        rbox("hotel_star", sx, -12.94, 4.72, 0.34, 0.05, 0.34, light, rotation=(0.0, 0.785398, 0.0))
    for cx in (-5.90, 5.90):
        cyl("hotel_canopy_column", cx, -12.45, 2.55, 0.16, 4.50, bronze, vertices=12)
        cyl("hotel_canopy_column_base", cx, -12.45, 0.42, 0.26, 0.24, granite, vertices=12)
    for lx in (-7.60, 7.60):
        cyl("hotel_lantern_post", lx, -12.30, 1.55, 0.05, 2.50, bronze, vertices=8)
        sphere("hotel_lantern_globe", lx, -12.30, 2.95, 0.34, 0.34, 0.40, light, segments=14, ring_count=10)
    for fx, flag_mat in ((-10.50, accent), (10.50, curtain)):
        # Tapered pole on a granite base; both flags fly the same way
        # (one wind) as a ripple of four overlapping yawed cloth
        # segments, so they read as flags instead of flat panels.
        cone("hotel_flag_pole", fx, -12.20, 5.10, 0.09, 0.04, 9.60, frame, vertices=10)
        cyl("hotel_flag_pole_base", fx, -12.20, 0.55, 0.30, 0.50, granite, vertices=12)
        sphere("hotel_flag_finial", fx, -12.20, 10.02, 0.17, 0.17, 0.17, bronze, segments=10, ring_count=8)
        box("hotel_flag_hoist", fx + 0.07, -12.20, 9.28, 0.05, 0.06, 1.30, bronze)
        for seg in range(4):
            seg_x = fx + 0.38 + seg * 0.56
            seg_y = -12.20 + math.sin(seg * 1.15) * 0.11
            seg_z = 9.30 - seg * 0.055
            seg_yaw = 0.30 if seg % 2 == 0 else -0.30
            rbox("hotel_flag", seg_x, seg_y, seg_z, 0.64, 0.035, 1.24, flag_mat, rotation=(0.0, 0.0, seg_yaw))
    for px in (-14.60, 14.60):
        box("hotel_planter", px, -11.90, 0.55, 2.60, 0.90, 0.50, granite)
        box("hotel_planter_hedge", px, -11.90, 0.88, 2.42, 0.74, 0.30, hedge, bevel=0.04)

    # ---- podium-roof pool terrace ------------------------------------
    box("hotel_terrace_deck", 0.0, -9.50, 7.70, 26.00, 3.40, 0.10, wood)
    box("hotel_pool_basin", -4.50, -9.50, 8.02, 13.00, 2.70, 0.66, granite)
    box("hotel_pool_water", -4.50, -9.50, 8.30, 12.55, 2.25, 0.08, water)
    for rim_y in (-10.92, -8.08):
        box("hotel_pool_coping", -4.50, rim_y, 8.37, 13.30, 0.28, 0.07, stone)
    for rim_x in (-11.12, 2.12):
        box("hotel_pool_coping_end", rim_x, -9.50, 8.37, 0.28, 2.60, 0.07, stone)
    for post_x in (6.40, 11.60):
        for post_y in (-10.70, -8.30):
            cyl("hotel_pergola_post", post_x, post_y, 8.80, 0.09, 2.20, wood, vertices=8)
    for beam_x in (6.40, 7.70, 9.00, 10.30, 11.60):
        box("hotel_pergola_beam", beam_x, -9.50, 9.95, 0.16, 3.00, 0.14, wood)
    box("hotel_terrace_rail_glass", 0.0, -11.38, 8.15, 32.60, 0.05, 0.85, glass)
    box("hotel_terrace_rail_top", 0.0, -11.38, 8.62, 32.70, 0.09, 0.07, bronze)
    for rx in range(-16, 17, 4):
        box("hotel_terrace_rail_post", float(rx), -11.38, 8.12, 0.06, 0.06, 0.95, frame)
    for px in (-13.50, 13.50):
        box("hotel_terrace_planter", px, 9.60, 7.95, 3.40, 1.00, 0.55, granite)
        box("hotel_terrace_hedge", px, 9.60, 8.30, 3.20, 0.82, 0.34, hedge, bevel=0.04)

    # ---- guest tower ---------------------------------------------------
    box("hotel_tower", 0.0, 1.00, 22.10, 26.00, 17.60, 43.60, plaster, bevel=0.03)
    box("hotel_tower_plinth", 0.0, 1.00, 7.95, 26.80, 18.40, 0.70, stone)
    for fin_side in (-13.68, 13.68):
        for fin_y in (-1.70, 3.70):
            box("hotel_side_fin", fin_side, fin_y, 26.02, 0.14, 0.50, 35.75, bronze)
    for pier_x in (-12.35, 12.35):
        box("hotel_tower_end_pier", pier_x, 1.00, 22.10, 2.50, 18.40, 43.60, stone, bevel=0.02)
        box("hotel_tower_pier_bronze", pier_x, -8.28, 26.02, 0.50, 0.14, 35.75, bronze)
        box("hotel_tower_pier_bronze_back", pier_x, 10.28, 26.02, 0.50, 0.14, 35.75, bronze)
    for fin_x in (-1.70, 1.70):
        box("hotel_centre_fin_front", fin_x, -7.98, 26.02, 0.35, 0.55, 35.75, bronze)
        box("hotel_centre_fin_back", fin_x, 9.98, 26.02, 0.35, 0.55, 35.75, bronze)

    tower_bays = [-9.75 + 3.25 * i for i in range(7)]
    for floor in range(11):
        floor_base = 8.15 + 3.25 * floor
        win_z = floor_base + 1.68
        for face_y, face in ((-7.80, "front"), (9.80, "back")):
            sign = -1.0 if face == "front" else 1.0
            box("hotel_spandrel", 0.0, face_y + sign * 0.045, floor_base + 0.30, 22.20, 0.13, 0.52, bronze)
            for bx in tower_bays:
                if abs(bx) < 0.10:
                    # Full-height glazed centre bay (lift/atrium slot).
                    box("hotel_centre_frame", 0.0, face_y + sign * 0.04, win_z, 3.10, 0.14, 3.00, frame)
                    box("hotel_centre_interior", 0.0, face_y + sign * 0.012, win_z, 2.92, 0.03, 2.86, interior)
                    box("hotel_centre_glass", 0.0, face_y + sign * 0.095, win_z, 2.92, 0.04, 2.86, glass)
                    box("hotel_centre_transom", 0.0, face_y + sign * 0.11, win_z + 0.55, 2.92, 0.05, 0.07, bronze)
                    continue
                tower_window(bx, face_y, win_z, 2.30, 2.15, face)
                balcony(bx, face_y, sign, floor_base)
            box("hotel_balcony_end_divider", -11.31, face_y + sign * 0.80, floor_base + 0.72, 0.09, 1.52, 1.18, bronze)
        for side_x, face in ((-13.60, "left"), (13.60, "right")):
            sign = -1.0 if face == "left" else 1.0
            for wy in (-4.40, 1.00, 6.40):
                tower_window(side_x, wy, win_z, 2.20, 2.15, face)
                side_balcony(side_x, wy, sign, floor_base)

    # ---- crown: cornice, penthouse tier, roof furniture ---------------
    box("hotel_cornice", 0.0, 1.00, 44.15, 27.60, 19.20, 0.50, stone)
    box("hotel_cornice_bronze", 0.0, 1.00, 43.86, 27.70, 19.30, 0.10, bronze)
    box("hotel_roof_slab", 0.0, 1.00, 44.44, 26.40, 18.00, 0.08, dark)
    box("hotel_penthouse", 0.0, 1.20, 46.00, 20.00, 13.60, 3.20, plaster, bevel=0.02)
    box("hotel_penthouse_cornice", 0.0, 1.20, 47.72, 20.80, 14.40, 0.25, stone)
    box("hotel_penthouse_roof", 0.0, 1.20, 47.88, 19.60, 13.20, 0.08, dark)
    for face_y, face in ((-5.60, "front"), (8.00, "back")):
        for bx in (-7.80, -3.90, 0.0, 3.90, 7.80):
            tower_window(bx, face_y, 46.05, 2.60, 2.20, face)
    for px in (-10.60, 10.60):
        box("hotel_roof_plant", px, 5.00, 45.30, 3.40, 4.20, 1.70, dark, bevel=0.02)
        cyl("hotel_roof_vent", px, 5.00, 46.35, 0.55, 0.50, frame, vertices=12)
    box("hotel_roof_rail_front_glass", 0.0, -7.55, 44.85, 26.00, 0.05, 0.70, glass)
    box("hotel_roof_rail_back_glass", 0.0, 9.55, 44.85, 26.00, 0.05, 0.70, glass)
    box("hotel_roof_rail_front_top", 0.0, -7.55, 45.24, 26.10, 0.09, 0.07, bronze)
    box("hotel_roof_rail_back_top", 0.0, 9.55, 45.24, 26.10, 0.09, 0.07, bronze)
    cyl("hotel_beacon_mast", 0.0, 1.20, 48.35, 0.06, 0.90, bronze, vertices=8)
    sphere("hotel_beacon", 0.0, 1.20, 48.92, 0.30, 0.30, 0.30, light, segments=12, ring_count=8)
    # Penthouse-roof plant and a tilted solar field break up the slab.
    solar = MATS["SolarCell"]
    for px in (-6.50, 6.50):
        box("hotel_penthouse_plant", px, 3.60, 48.35, 3.20, 2.60, 0.90, frame, bevel=0.02)
    for row_y in (-2.40, 0.60):
        for panel_x in (-6.90, -3.45, 0.0, 3.45, 6.90):
            rbox("hotel_solar_panel", panel_x, row_y, 48.28, 3.10, 2.00, 0.09, solar, rotation=(-0.32, 0.0, 0.0))
            box("hotel_solar_stand", panel_x, row_y + 0.55, 48.02, 0.14, 0.14, 0.42, frame)


def build_museum():
    """Building Model No.9: an original civic museum for the central
    RichTown axis (landmark rt-museum, X665 Z-340), replacing the
    primitive metal torus on a marble slab.  A limestone panel
    rainscreen (individual 3.0 x 1.95 m panels over a dark shadow-gap
    core, two stone tones) wraps a 15.6 m gallery mass; a full-height
    glazed atrium slot cuts the front with bronze mullions, two
    mezzanine slabs and a real switchback stair visible behind the
    glass.  A thin floating roof slab with a clerestory lantern,
    travertine plinth plaza, reflecting pool, sculpture court,
    exhibition banners and a serviced rear dock complete the parcel.
    Authored envelope 54.0 x 38.0 m, 19.0 m to the lantern cap;
    Blender -Y is the public front (fountain axis in game).

    0.2.45 photoreal pass: every glazed surface becomes per-lite
    unitized glazing with recessed panes behind expressed bronze
    framing (atrium slot, rear garden slot, four-face lantern, slit
    windows, cafe ribbons); the rainscreen, stair and slit geometry
    is accumulated into merged MeshBuilders, cutting the mesh count
    while adding corner quoins, framed double-leaf entrance doors,
    canopy tie-rods and soffit lights, a ceremonial axis step with
    handrails, plaza expansion joints and a drainage slot, roof
    membrane seams/walkway pads/hatch/vents, a serviced dock with
    seal, bumpers, leveler and roof ladder, multi-blob clipped
    trees, civic flagpoles and furnished atrium depth (desk,
    benches, plinth sculptures, wall-washer).  The authored
    envelope and all masses are unchanged; exterior only."""
    stone = MATS["MuseumStone"]
    stone_pale = MATS["MuseumStonePale"]
    core_mat = MATS["MuseumCore"]
    bronze = MATS["MuseumBronze"]
    glass = MATS["MuseumGlass"]
    interior = MATS["MuseumInterior"]
    white = MATS["MuseumWhite"]
    granite = MATS["MuseumGranite"]
    trav = MATS["MuseumTravertine"]
    water = MATS["MuseumWater"]
    banner_teal = MATS["MuseumBannerTeal"]
    banner_ochre = MATS["MuseumBannerOchre"]
    light = MATS["MuseumLight"]
    frame = MATS["WindowFrame"]
    dark = MATS["RoofDark"]
    hedge = MATS["VillaHedge"]

    def wedge(name, x, y, z, dx, dy, dz, material):
        """Triangular ramp prism rising toward +Y (low edge at -Y)."""
        obj = box(name, x, y, z, dx, dy, dz, material)
        for v in obj.data.vertices:
            if v.co.y < 0.0:
                v.co.z = -dz * 0.5
        obj.data.update()
        return obj

    # ---- merged-geometry helpers (0.2.45) ------------------------------- #
    # Rainscreen panels, slit/stair parts and all new unitized glazing
    # accumulate into one MeshBuilder per semantic material.
    builders = {}

    def bb(material):
        if material.name not in builders:
            builders[material.name] = (MeshBuilder(), material)
        return builders[material.name][0]

    def builder_box(builder, cx, cy, cz, dx, dy, dz):
        x0, x1 = cx - dx / 2.0, cx + dx / 2.0
        y0, y1 = cy - dy / 2.0, cy + dy / 2.0
        z0, z1 = cz - dz / 2.0, cz + dz / 2.0

        def v(x, y, z):
            return builder.add_vertex(Vector((x, y, z)))

        quads = (
            # +Z, -Z, +Y, -Y, +X, -X (outward windings)
            ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),
            ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)),
            ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),
            ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),
            ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),
            ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),
        )
        for quad_corners in quads:
            ids = [v(*corner) for corner in quad_corners]
            builder.quad(*ids)

    def builder_panel(builder, centre, along, height, outward):
        # 0.3.7: single outward quad for recessed lites/panes that
        # sit in front of the interior core (2 tris instead of a
        # slab); bronze framing stays solid builder boxes.
        up = Vector((0.0, 0.0, height * 0.5))
        points = [centre - along - up, centre + along - up, centre + along + up, centre - along + up]
        if (points[1] - points[0]).cross(points[3] - points[0]).dot(outward) < 0.0:
            points = [points[1], points[0], points[3], points[2]]
        ids = [builder.add_vertex(point) for point in points]
        builder.quad(*ids)

    def glazed_slot(y_c, sign, width, module, row_edges):
        # Per-lite unitized glazing in a vertical slot: recessed panes
        # with shadow gaps behind expressed bronze mullions/transoms.
        cols = int(round(width / module))
        bay = width / cols
        fy = y_c + sign * 0.055
        z_mid_slot = (row_edges[0] + row_edges[-1]) * 0.5
        z_len_slot = row_edges[-1] - row_edges[0]
        for i in range(cols + 1):
            mx = -width * 0.5 + bay * i
            builder_box(bb(bronze), mx, fy, z_mid_slot, 0.10, 0.15, z_len_slot)
        for tz in row_edges[1:-1]:
            builder_box(bb(bronze), 0.0, fy, tz, width, 0.15, 0.10)
        builder_box(bb(bronze), 0.0, fy, row_edges[0] + 0.04, width, 0.18, 0.16)
        builder_box(bb(bronze), 0.0, fy, row_edges[-1] - 0.04, width, 0.18, 0.16)
        for ci in range(cols):
            pcx = -width * 0.5 + bay * (ci + 0.5)
            for ri in range(len(row_edges) - 1):
                z0, z1 = row_edges[ri], row_edges[ri + 1]
                builder_panel(bb(glass), Vector((pcx, y_c + sign * 0.0225, (z0 + z1) * 0.5)),
                              Vector(((bay - 0.15) * 0.5, 0.0, 0.0)), (z1 - z0) - 0.15,
                              Vector((0.0, sign, 0.0)))

    def panel_wall(face, fixed, sign, cols, pitch, openings, rows=8, pitch_h=1.95, z_base=0.60, centre_offset=0.0):
        length = cols * pitch
        for c in range(cols):
            centre = centre_offset - length * 0.5 + pitch * (c + 0.5)
            for r in range(rows):
                zc = z_base + pitch_h * (r + 0.5)
                skip = False
                for (o_lo, o_hi, z_lo, z_hi) in openings:
                    if o_lo <= centre <= o_hi and z_lo <= zc <= z_hi:
                        skip = True
                        break
                if skip:
                    continue
                m = stone_pale if (c * 7 + r * 13) % 5 == 0 else stone
                if face in ("front", "back"):
                    builder_box(bb(m), centre, fixed + sign * 0.05, zc, pitch - 0.06, 0.10, pitch_h - 0.06)
                else:
                    builder_box(bb(m), fixed + sign * 0.05, centre, zc, 0.10, pitch - 0.06, pitch_h - 0.06)

    def slit(face, fixed, sign, centre, z_lo=2.55, z_hi=14.25, width=1.04, pitch=3.04):
        # The tall slit is four stacked lites behind bronze transoms,
        # not one 11.7 m glass strip (0.2.45).
        z_mid = (z_lo + z_hi) * 0.5
        z_len = z_hi - z_lo
        strip = (pitch - 0.06 - width) * 0.5
        lite_edges = [z_lo + z_len * f for f in (0.0, 0.25, 0.5, 0.75, 1.0)]
        for sd in (-1.0, 1.0):
            off = centre + sd * (width * 0.5 + strip * 0.5 + 0.01)
            if face in ("front", "back"):
                builder_box(bb(stone), off, fixed + sign * 0.05, z_mid, strip, 0.10, z_len)
            else:
                builder_box(bb(stone), fixed + sign * 0.05, off, z_mid, 0.10, strip, z_len)
        if face in ("front", "back"):
            panel("museum_slit_interior", centre, fixed - sign * 0.27, z_mid, width - 0.04, z_len - 0.04, interior, "back" if sign > 0.0 else "front")
            for li in range(4):
                lz0, lz1 = lite_edges[li], lite_edges[li + 1]
                builder_panel(bb(glass), Vector((centre, fixed + sign * 0.0325, (lz0 + lz1) * 0.5)),
                              Vector(((width - 0.06) * 0.5, 0.0, 0.0)), (lz1 - lz0) - 0.13,
                              Vector((0.0, sign, 0.0)))
            for tz in lite_edges[1:-1]:
                builder_box(bb(bronze), centre, fixed + sign * 0.045, tz, width + 0.04, 0.10, 0.085)
            box("museum_slit_head", centre, fixed + sign * 0.07, z_hi + 0.055, width + 0.24, 0.16, 0.11, bronze)
            box("museum_slit_sill", centre, fixed + sign * 0.07, z_lo - 0.055, width + 0.24, 0.16, 0.11, bronze)
        else:
            panel("museum_slit_interior", fixed - sign * 0.27, centre, z_mid, width - 0.04, z_len - 0.04, interior, "right" if sign > 0.0 else "left")
            for li in range(4):
                lz0, lz1 = lite_edges[li], lite_edges[li + 1]
                builder_panel(bb(glass), Vector((fixed + sign * 0.0325, centre, (lz0 + lz1) * 0.5)),
                              Vector((0.0, (width - 0.06) * 0.5, 0.0)), (lz1 - lz0) - 0.13,
                              Vector((sign, 0.0, 0.0)))
            for tz in lite_edges[1:-1]:
                builder_box(bb(bronze), fixed + sign * 0.045, centre, tz, 0.10, width + 0.04, 0.085)
            box("museum_slit_head", fixed + sign * 0.07, centre, z_hi + 0.055, 0.16, width + 0.24, 0.11, bronze)
            box("museum_slit_sill", fixed + sign * 0.07, centre, z_lo - 0.055, 0.16, width + 0.24, 0.11, bronze)

    def punched_window(face, fixed, sign, centre, zc, w=1.70, h=1.55):
        # Deep-set bronze window: glass recessed behind a slender
        # cross mullion instead of sitting proud of its frame (0.2.45).
        if face in ("front", "back"):
            box("museum_win_frame", centre, fixed + sign * 0.045, zc, w + 0.16, 0.13, h + 0.16, bronze)
            builder_box(bb(bronze), centre, fixed + sign * 0.075, zc, 0.055, 0.06, h - 0.02)
            builder_box(bb(bronze), centre, fixed + sign * 0.075, zc, w - 0.02, 0.06, 0.055)
            panel("museum_win_interior", centre, fixed - sign * 0.195, zc, w - 0.04, h - 0.04, interior, "back" if sign > 0.0 else "front")
            panel("museum_win_glass", centre, fixed + sign * 0.035, zc, w, h, glass, "back" if sign > 0.0 else "front")
            box("museum_win_sill", centre, fixed + sign * 0.09, zc - h * 0.5 - 0.06, w + 0.30, 0.24, 0.09, trav)
        else:
            box("museum_win_frame", fixed + sign * 0.045, centre, zc, 0.13, w + 0.16, h + 0.16, bronze)
            builder_box(bb(bronze), fixed + sign * 0.075, centre, zc, 0.06, 0.055, h - 0.02)
            builder_box(bb(bronze), fixed + sign * 0.075, centre, zc, 0.06, w - 0.02, 0.055)
            panel("museum_win_interior", fixed - sign * 0.195, centre, zc, w - 0.04, h - 0.04, interior, "right" if sign > 0.0 else "left")
            panel("museum_win_glass", fixed + sign * 0.035, centre, zc, w, h, glass, "right" if sign > 0.0 else "left")
            box("museum_win_sill", fixed + sign * 0.09, centre, zc - h * 0.5 - 0.06, 0.24, w + 0.30, 0.09, trav)

    # ---- travertine plinth plaza (two monumental steps) ---------------
    box("museum_plinth_lower", 0.0, 0.0, 0.15, 54.00, 38.00, 0.30, granite, bevel=0.015)
    box("museum_plinth_upper", 0.0, 0.0, 0.45, 50.00, 34.00, 0.30, trav, bevel=0.015)
    for rx in (-13.5, 13.5):
        wedge("museum_plaza_ramp", rx, -17.05, 0.31, 1.70, 3.90, 0.62, trav)
        for sd in (-1.0, 1.0):
            tube_between("museum_ramp_rail", (rx + sd * 0.78, -18.80, 0.85), (rx + sd * 0.78, -15.30, 1.45), 0.035, 0.035, bronze, vertices=8)
            cyl("museum_ramp_rail_post", rx + sd * 0.78, -15.45, 1.02, 0.030, 0.84, bronze, vertices=8)
    # Ceremonial centre step with bronze handrails on the entry axis,
    # so the monumental climb reads at the door, not only at ramps.
    box("museum_axis_step", 0.0, -17.42, 0.375, 14.00, 0.82, 0.15, trav)
    for sx2 in (-6.20, 6.20):
        cyl("museum_axis_rail_post", sx2, -18.55, 0.75, 0.030, 0.90, bronze, vertices=8)
        cyl("museum_axis_rail_post", sx2, -16.55, 1.05, 0.030, 0.90, bronze, vertices=8)
        tube_between("museum_axis_rail", (sx2, -18.55, 1.20), (sx2, -16.55, 1.50), 0.032, 0.032, bronze, vertices=8)
    # Plaza expansion joints and a facade drainage slot (merged lines).
    for jy in (-16.00, -15.00):
        builder_box(bb(core_mat), 0.0, jy, 0.606, 49.60, 0.055, 0.014)
    for jx2 in range(-4, 5):
        builder_box(bb(core_mat), jx2 * 6.08, -15.45, 0.606, 0.055, 3.05, 0.014)
    for sx3 in (-23.95, 23.95):
        builder_box(bb(core_mat), sx3, 0.0, 0.606, 0.055, 33.60, 0.014)
    builder_box(bb(core_mat), 0.0, -14.28, 0.606, 45.80, 0.20, 0.016)
    builder_box(bb(core_mat), 0.0, 16.28, 0.606, 45.80, 0.20, 0.016)
    for sx3 in (-23.28, 23.28):
        builder_box(bb(core_mat), sx3, 1.00, 0.606, 0.20, 30.00, 0.016)

    # ---- gallery mass: two side blocks + rear block around the atrium --
    box("museum_block_left", -14.45, 1.00, 8.40, 16.70, 29.60, 15.60, core_mat, bevel=0.02)
    box("museum_block_right", 14.45, 1.00, 8.40, 16.70, 29.60, 15.60, core_mat, bevel=0.02)
    box("museum_block_rear", 0.0, 10.13, 8.40, 12.20, 4.25, 15.60, core_mat, bevel=0.02)
    box("museum_atrium_header", 0.0, -13.55, 15.75, 12.20, 0.50, 0.90, bronze)

    front_y = -13.80
    back_y = 15.80
    side_x = 22.80
    # Front: atrium slot (centres -6.08..6.08) + 4 slit columns.
    panel_wall("front", front_y, -1.0, 15, 3.04, [
        (-6.10, 6.10, 0.0, 16.2),
        (-12.80, -11.50, 2.40, 14.40), (11.50, 12.80, 2.40, 14.40),
        (-18.90, -17.60, 2.40, 14.40), (17.60, 18.90, 2.40, 14.40),
    ])
    # Back: garden slot (centres -3.04..3.04), loading dock at +12.16,
    # punched windows on two gallery levels.
    back_openings = [(-3.10, 3.10, 0.0, 16.2), (11.50, 12.80, 0.0, 4.60)]
    back_windows = []
    for wc in (-21.28, -15.20, -9.12, 9.12, 15.20, 21.28):
        for (wz_lo, wz_hi, wz_c) in ((4.40, 6.40, 5.48), (10.30, 12.30, 11.33)):
            back_openings.append((wc - 0.70, wc + 0.70, wz_lo, wz_hi))
            back_windows.append((wc, wz_c))
    panel_wall("back", back_y, 1.0, 15, 3.04, back_openings)
    for (wc, wz_c) in back_windows:
        punched_window("back", back_y, 1.0, wc, wz_c)
    # Sides: three slits per face + a ground-level cafe ribbon toward
    # the front (local -Y end of each side wall).
    for face, fixed, sign in (("left", -side_x, -1.0), ("right", side_x, 1.0)):
        panel_wall(face, fixed, sign, 10, 2.96, [
            (-7.05, -5.75, 2.40, 14.40), (1.85, 3.15, 2.40, 14.40), (7.75, 9.05, 2.40, 14.40),
            (-13.90, -7.80, 0.00, 4.60),
        ], centre_offset=1.0)
        for sc in (-6.40, 2.48, 8.40):
            slit(face, fixed, sign, sc, pitch=2.96)
        panel("museum_cafe_interior", fixed - sign * 0.27, -10.84, 2.55, 5.80, 3.80, interior, "right" if sign > 0.0 else "left")
        panel("museum_cafe_glass", fixed + sign * 0.045, -10.84, 2.55, 5.80, 3.80, glass, "right" if sign > 0.0 else "left")
        for my in (-13.30, -11.85, -10.40, -8.95):
            box("museum_cafe_mullion", fixed + sign * 0.06, my, 2.55, 0.07, 0.09, 3.80, bronze)
        box("museum_cafe_head", fixed + sign * 0.07, -10.84, 4.52, 0.16, 6.10, 0.14, bronze)
        builder_box(bb(bronze), fixed + sign * 0.06, -10.84, 3.38, 0.09, 5.80, 0.07)
        builder_box(bb(bronze), fixed + sign * 0.06, -10.84, 0.72, 0.10, 5.90, 0.12)
    for sc in (-18.24, -12.16, 12.16, 18.24):
        slit("front", front_y, -1.0, sc)
    # Corner quoins: alternating pale stones proud of the panel field,
    # so the gallery mass gains crafted corners, not butt joints.
    for qx in (-1.0, 1.0):
        for qy, edge_y in ((-1.0, front_y), (1.0, back_y)):
            for r in range(8):
                qzc = 0.60 + 1.95 * (r + 0.5)
                fw = 1.10 if r % 2 == 0 else 0.70
                swq = 0.70 if r % 2 == 0 else 1.10
                builder_box(bb(stone_pale), qx * (side_x - fw * 0.5 + 0.02), edge_y + qy * 0.075, qzc, fw, 0.15, 1.84)
                builder_box(bb(stone_pale), qx * (side_x + 0.075), edge_y - qy * (swq * 0.5 - 0.02), qzc, 0.15, swq, 1.84)

    # ---- atrium slot: glass curtain, mezzanines, stair, artwork --------
    box("museum_atrium_floor", 0.0, -10.90, 0.66, 12.20, 5.80, 0.12, trav)
    box("museum_atrium_backdrop", 0.0, -8.00, 8.40, 12.20, 0.30, 15.60, white)
    box("museum_atrium_art_teal", -2.20, -8.22, 9.60, 6.40, 0.10, 4.60, banner_teal)
    box("museum_atrium_art_ochre", 3.60, -8.22, 5.40, 3.00, 0.10, 5.20, banner_ochre)
    for sx in (-6.05, 6.05):
        box("museum_atrium_reveal", sx, -10.90, 8.40, 0.12, 5.80, 15.60, white)
    glass_y = -13.25
    glazed_slot(glass_y, -1.0, 12.20, 1.22, [0.68, 3.20, 5.80, 8.40, 11.00, 13.60, 16.12])
    for fx in (-6.55, 6.55):
        box("museum_atrium_fin", fx, -13.62, 8.40, 0.85, 0.44, 15.60, bronze)
    for mz in (6.00, 11.20):
        box("museum_mezzanine", 0.0, -9.98, mz, 12.00, 3.65, 0.35, white)
        box("museum_mezzanine_edge", 0.0, -11.83, mz, 12.00, 0.06, 0.35, bronze)
        box("museum_mezzanine_balustrade", 0.0, -11.80, mz + 0.62, 12.00, 0.04, 0.90, glass)
        box("museum_mezzanine_rail", 0.0, -11.80, mz + 1.10, 12.00, 0.07, 0.06, bronze)

    def atrium_stair(z_from, z_to, x_from, direction):
        steps = 30
        rise = (z_to - z_from) / steps
        tread = 0.30
        for i in range(steps):
            sx = x_from + direction * tread * (i + 0.5)
            builder_box(bb(white), sx, -9.85, z_from + rise * (i + 0.5), tread + 0.02, 2.30, 0.16)
        x_to = x_from + direction * tread * steps
        for ry in (-10.92, -8.78):
            tube_between("museum_stair_rail", (x_from, ry, z_from + 1.00), (x_to, ry, z_to + 1.00), 0.035, 0.035, bronze, vertices=8)

    atrium_stair(0.72, 6.00, -5.60, 1.0)
    atrium_stair(6.00, 11.20, 5.60, -1.0)
    # Closed stringers under both flights so the stair reads as a
    # folded sculptural ribbon, not floating treads.
    rbox("museum_stair_stringer_a", -1.10, -9.85, 3.08, 10.45, 1.90, 0.30, white, rotation=(0.0, -0.531, 0.0))
    rbox("museum_stair_stringer_b", 1.10, -9.85, 8.32, 10.45, 1.90, 0.30, white, rotation=(0.0, 0.524, 0.0))
    for lx in (-3.60, 0.0, 3.60):
        cyl("museum_atrium_pendant_rod", lx, -11.20, 15.35, 0.025, 1.50, frame, vertices=8)
        box("museum_atrium_pendant", lx, -11.20, 14.55, 2.60, 0.10, 0.10, light)
    # Atrium furnishings legible through the glazing: information
    # desk, benches, two plinth sculptures and a backdrop wall-washer.
    box("museum_atrium_desk", 0.0, -10.55, 1.27, 3.40, 0.85, 1.10, granite)
    box("museum_atrium_desk_top", 0.0, -10.55, 1.86, 3.56, 1.00, 0.08, trav)
    for bx4 in (-3.60, 3.60):
        box("museum_atrium_bench", bx4, -11.55, 0.97, 2.20, 0.50, 0.50, white)
    box("museum_atrium_plinth_a", 4.65, -9.55, 1.32, 0.70, 0.70, 1.20, white)
    sphere("museum_atrium_sculpture_a", 4.65, -9.55, 2.32, 0.80, 0.80, 0.80, bronze, segments=14, ring_count=10)
    box("museum_atrium_plinth_b", -4.65, -9.55, 1.02, 0.85, 0.85, 0.60, white)
    rbox("museum_atrium_sculpture_b", -4.65, -9.55, 2.25, 0.18, 1.15, 1.85, trav, rotation=(0.0, 0.30, 0.0))
    box("museum_atrium_washer", 0.0, -8.28, 14.85, 10.50, 0.06, 0.09, light)
    for mz2 in (6.00, 11.20):
        box("museum_mezzanine_underlight", 0.0, -11.78, mz2 - 0.21, 11.80, 0.05, 0.05, light)

    # Entrance doors, canopy and threshold at the atrium base.
    # Three monumental doorways rebuilt as framed double leaves:
    # stiles, top/lock/bottom rails, two lites per leaf and pull
    # handles on standoff mounts (merged bronze/glass).
    for dx in (-3.65, 0.0, 3.65):
        for jx in (-1.07, 1.07):
            builder_box(bb(bronze), dx + jx, glass_y - 0.115, 2.28, 0.12, 0.19, 3.36)
        builder_box(bb(bronze), dx, glass_y - 0.115, 4.00, 2.26, 0.19, 0.12)
        builder_box(bb(bronze), dx, glass_y - 0.115, 0.645, 2.26, 0.21, 0.05)
        for leaf_side in (-1.0, 1.0):
            lc = dx + leaf_side * 0.515
            for stx in (-0.475, 0.475):
                builder_box(bb(bronze), lc + stx, glass_y - 0.105, 2.28, 0.075, 0.11, 3.26)
            builder_box(bb(bronze), lc, glass_y - 0.105, 3.76, 1.02, 0.11, 0.32)
            builder_box(bb(bronze), lc, glass_y - 0.105, 1.56, 1.02, 0.11, 0.13)
            builder_box(bb(bronze), lc, glass_y - 0.105, 0.87, 1.02, 0.11, 0.44)
            builder_panel(bb(glass), Vector((lc, glass_y - 0.120, 2.61)),
                          Vector((0.44, 0.0, 0.0)), 1.92, Vector((0.0, -1.0, 0.0)))
            builder_panel(bb(glass), Vector((lc, glass_y - 0.120, 1.29)),
                          Vector((0.44, 0.0, 0.0)), 0.36, Vector((0.0, -1.0, 0.0)))
            hx = dx + leaf_side * 0.10
            tube_between("museum_door_handle", (hx, glass_y - 0.24, 1.30), (hx, glass_y - 0.24, 2.50), 0.026, 0.026, bronze, vertices=8)
            for mz in (1.45, 2.35):
                builder_box(bb(bronze), hx, glass_y - 0.175, mz, 0.05, 0.14, 0.05)
    box("museum_threshold", 0.0, -13.85, 0.66, 12.40, 0.90, 0.12, granite)
    box("museum_canopy", 0.0, -15.15, 4.62, 13.20, 3.10, 0.16, white)
    box("museum_canopy_edge", 0.0, -16.68, 4.62, 13.20, 0.08, 0.30, bronze)
    for cxp in (-5.90, 5.90):
        cyl("museum_canopy_column", cxp, -16.20, 2.57, 0.09, 3.94, bronze, vertices=12)
    # Tie rods back to the 8.40 transom line, side edge beams and a
    # row of recessed soffit lights complete the canopy.
    for rod_x in (-4.60, -1.55, 1.55, 4.60):
        tube_between("museum_canopy_tie_rod", (rod_x, -16.55, 4.78), (rod_x, -13.38, 8.42), 0.022, 0.022, bronze, vertices=8)
    for side_edge_x in (-6.56, 6.56):
        box("museum_canopy_edge_side", side_edge_x, -15.15, 4.62, 0.08, 3.10, 0.30, bronze)
    for light_i in range(7):
        box("museum_canopy_light", -5.40 + 1.80 * light_i, -16.00, 4.525, 0.55, 0.20, 0.03, light)

    # Exhibition banners flanking the slot: cloth on a pale backing
    # plate with bronze standoffs, so they read as banners, not slits.
    for bx, bmat in ((-8.90, banner_teal), (8.90, banner_ochre)):
        box("museum_banner_backing", bx, -14.12, 9.60, 2.15, 0.05, 6.30, white)
        box("museum_banner", bx, -14.18, 9.60, 1.85, 0.05, 5.90, bmat)
        tube_between("museum_banner_rod", (bx - 1.10, -14.22, 12.72), (bx + 1.10, -14.22, 12.72), 0.035, 0.035, bronze, vertices=8)
        box("museum_banner_bar", bx, -14.18, 6.58, 1.95, 0.08, 0.10, bronze)
        for ax in (-0.85, 0.85):
            tube_between("museum_banner_arm", (bx + ax, -13.90, 12.72), (bx + ax, -14.24, 12.72), 0.028, 0.028, bronze, vertices=8)
            tube_between("museum_banner_arm", (bx + ax, -13.90, 6.58), (bx + ax, -14.24, 6.58), 0.028, 0.028, bronze, vertices=8)
    # Entrance pylons marking the axis.
    for tx in (-7.80, 7.80):
        box("museum_entry_pylon", tx, -16.35, 2.70, 0.62, 0.34, 4.20, granite)
        box("museum_entry_pylon_light", tx, -16.54, 3.40, 0.12, 0.03, 2.60, light)
        box("museum_entry_pylon_cap", tx, -16.35, 4.86, 0.70, 0.42, 0.12, bronze)

    # ---- rear garden slot, cafe depth and loading dock ------------------
    box("museum_rear_backdrop", 0.0, 12.40, 8.40, 9.00, 0.30, 15.60, white)
    box("museum_rear_floor", 0.0, 14.05, 0.66, 9.00, 3.40, 0.12, trav)
    glazed_slot(15.30, 1.0, 9.00, 9.00 / 7.0, [0.68, 3.20, 5.80, 8.40, 11.00, 13.60, 16.12])
    for fx in (-4.95, 4.95):
        box("museum_rear_fin", fx, 15.62, 8.40, 0.80, 0.42, 15.60, bronze)
    box("museum_rear_counter", 0.0, 12.95, 1.30, 6.40, 0.70, 1.10, granite)
    for tx in (-2.60, 0.0, 2.60):
        cyl("museum_cafe_table_top", tx, 14.45, 1.48, 0.55, 0.05, white, vertices=12)
        cyl("museum_cafe_table_leg", tx, 14.45, 1.08, 0.05, 0.75, bronze, vertices=8)
    box("museum_rear_terrace", 0.0, 17.60, 0.55, 20.00, 2.60, 0.10, trav)
    # Loading dock against the eastern rear bay.
    box("museum_dock_recess", 12.16, 15.86, 2.30, 4.60, 0.10, 3.60, core_mat)
    for i in range(7):
        box("museum_dock_door_slat", 12.16, 15.93, 0.85 + 0.50 * i, 4.20, 0.07, 0.44, frame)
    box("museum_dock_canopy", 12.16, 16.45, 4.35, 5.20, 1.30, 0.14, bronze)
    box("museum_dock_platform", 12.16, 16.35, 0.55, 5.40, 1.10, 0.14, granite)
    for bx2 in (9.90, 14.42):
        cyl("museum_dock_bollard", bx2, 16.95, 1.00, 0.09, 0.85, frame, vertices=10)
    box("museum_service_door", 17.50, 15.90, 1.75, 1.10, 0.10, 2.30, bronze)
    for i in range(4):
        box("museum_vent_louvre", -17.50, 15.90, 3.30 + 0.34 * i, 2.20, 0.08, 0.20, frame)
    # Dock seal, bumpers, leveler plate, framed vent bank and a
    # fixed roof-access ladder up the rear wall (0.2.45 servicing).
    for dsx in (9.86, 14.46):
        box("museum_dock_seal", dsx, 15.99, 2.35, 0.38, 0.20, 3.90, core_mat)
    box("museum_dock_seal_top", 12.16, 15.99, 4.42, 4.98, 0.20, 0.38, core_mat)
    for dbx in (10.55, 13.77):
        box("museum_dock_bumper", dbx, 16.02, 0.90, 0.52, 0.26, 0.72, dark)
    box("museum_dock_leveler", 12.16, 16.08, 0.63, 2.05, 0.55, 0.06, frame)
    box("museum_vent_back", -17.50, 15.855, 3.81, 2.42, 0.05, 1.52, core_mat)
    for lrx in (20.38, 20.82):
        builder_box(bb(frame), lrx, 16.08, 8.40, 0.06, 0.06, 15.50)
    for lri in range(27):
        builder_box(bb(frame), 20.60, 16.08, 1.15 + 0.55 * lri, 0.40, 0.05, 0.05)
    for lbz in (3.00, 9.00, 15.00):
        builder_box(bb(frame), 20.60, 15.97, lbz, 0.44, 0.18, 0.06)

    # Granite base band around the gallery mass.
    box("museum_base_band_f_l", -14.90, -13.88, 1.05, 15.80, 0.12, 0.90, granite)
    box("museum_base_band_f_r", 14.90, -13.88, 1.05, 15.80, 0.12, 0.90, granite)
    box("museum_base_band_b_l", -14.10, 15.88, 1.05, 17.40, 0.12, 0.90, granite)
    box("museum_base_band_b_m", 7.60, 15.88, 1.05, 4.40, 0.12, 0.90, granite)
    box("museum_base_band_b_r", 18.65, 15.88, 1.05, 8.30, 0.12, 0.90, granite)
    box("museum_base_band_l", -22.88, 1.00, 1.05, 0.12, 29.60, 0.90, granite)
    box("museum_base_band_r", 22.88, 1.00, 1.05, 0.12, 29.60, 0.90, granite)

    # ---- floating roof slab, clerestory lantern, roof plant -------------
    box("museum_roof_slab", 0.0, 1.00, 16.48, 49.60, 33.60, 0.55, white, bevel=0.02)
    box("museum_roof_fascia_f", 0.0, -15.82, 16.48, 49.60, 0.10, 0.36, bronze)
    box("museum_roof_fascia_b", 0.0, 17.82, 16.48, 49.60, 0.10, 0.36, bronze)
    box("museum_roof_fascia_l", -24.82, 1.00, 16.48, 0.10, 33.60, 0.36, bronze)
    box("museum_roof_fascia_r", 24.82, 1.00, 16.48, 0.10, 33.60, 0.36, bronze)
    box("museum_frieze_f_l", -15.20, -13.94, 15.52, 15.20, 0.08, 0.55, bronze)
    box("museum_frieze_f_r", 15.20, -13.94, 15.52, 15.20, 0.08, 0.55, bronze)
    box("museum_frieze_b_l", -13.70, 15.94, 15.52, 18.20, 0.08, 0.55, bronze)
    box("museum_frieze_b_r", 13.70, 15.94, 15.52, 18.20, 0.08, 0.55, bronze)
    box("museum_frieze_l", -22.94, 1.00, 15.52, 0.08, 29.60, 0.55, bronze)
    box("museum_frieze_r", 22.94, 1.00, 15.52, 0.08, 29.60, 0.55, bronze)
    box("museum_roof_light_slot_f", 0.0, -15.15, 16.18, 48.20, 0.14, 0.05, light)
    box("museum_roof_light_slot_b", 0.0, 17.15, 16.18, 48.20, 0.14, 0.05, light)
    box("museum_roof_field", 0.0, 1.00, 16.79, 45.00, 29.00, 0.06, dark)
    box("museum_lantern_base", 0.0, 1.00, 16.95, 30.00, 9.00, 0.40, trav)
    box("museum_lantern_core", 0.0, 1.00, 17.90, 28.60, 8.00, 1.50, interior)
    # Per-lite lantern glazing on all four faces with corner posts
    # and continuous sill/head channels (merged geometry).
    for chan_z in (17.19, 18.61):
        builder_box(bb(bronze), 0.0, -3.30, chan_z, 29.35, 0.17, 0.12)
        builder_box(bb(bronze), 0.0, 5.30, chan_z, 29.35, 0.17, 0.12)
        builder_box(bb(bronze), -14.60, 1.00, chan_z, 0.17, 8.75, 0.12)
        builder_box(bb(bronze), 14.60, 1.00, chan_z, 0.17, 8.75, 0.12)
    for i in range(13):
        mx = -14.60 + 2.433 * i
        builder_box(bb(bronze), mx, -3.365, 17.90, 0.09, 0.13, 1.36)
        builder_box(bb(bronze), mx, 5.365, 17.90, 0.09, 0.13, 1.36)
    for sx5 in (-14.665, 14.665):
        for my2 in (-1.15, 1.00, 3.15):
            builder_box(bb(bronze), sx5, my2, 17.90, 0.13, 0.09, 1.36)
    for cx6 in (-14.60, 14.60):
        for cy6 in (-3.30, 5.30):
            builder_box(bb(bronze), cx6, cy6, 17.90, 0.15, 0.15, 1.50)
    for i in range(12):
        pcx2 = -14.60 + 2.433 * (i + 0.5)
        builder_panel(bb(glass), Vector((pcx2, -3.3225, 17.90)),
                      Vector((1.14, 0.0, 0.0)), 1.24, Vector((0.0, -1.0, 0.0)))
        builder_panel(bb(glass), Vector((pcx2, 5.3225, 17.90)),
                      Vector((1.14, 0.0, 0.0)), 1.24, Vector((0.0, 1.0, 0.0)))
    for sx5 in (-14.60, 14.60):
        for pcy2 in (-2.225, -0.075, 2.075, 4.225):
            builder_panel(bb(glass), Vector((sx5 + math.copysign(0.0225, sx5), pcy2, 17.90)),
                          Vector((0.0, 1.00, 0.0)), 1.24, Vector((math.copysign(1.0, sx5), 0.0, 0.0)))
    box("museum_lantern_cap", 0.0, 1.00, 18.83, 31.40, 10.40, 0.35, white, bevel=0.02)
    box("museum_lantern_cap_edge", 0.0, -4.22, 18.83, 31.40, 0.08, 0.20, bronze)
    box("museum_lantern_cap_edge_b", 0.0, 6.22, 18.83, 31.40, 0.08, 0.20, bronze)
    box("museum_lantern_cap_edge_l", -15.72, 1.00, 18.83, 0.08, 10.40, 0.20, bronze)
    box("museum_lantern_cap_edge_r", 15.72, 1.00, 18.83, 0.08, 10.40, 0.20, bronze)
    for csx in (-10.00, 0.00, 10.00):
        builder_box(bb(core_mat), csx, 1.00, 19.002, 0.06, 10.30, 0.012)
    for hx, hy in ((-18.0, 10.0), (-13.0, 10.0), (17.0, 10.5)):
        box("museum_hvac", hx, hy, 17.45, 3.60, 2.20, 1.25, frame)
        for i in range(4):
            box("museum_hvac_louvre", hx, hy - 1.12, 17.10 + 0.26 * i, 3.30, 0.05, 0.14, dark)
        cyl("museum_hvac_fan", hx, hy, 18.10, 0.55, 0.08, dark, vertices=12)
    for i in range(9):
        px = -20.0 + 5.0 * i
        cyl("museum_roof_rail_post", px, 15.90, 17.30, 0.035, 1.05, bronze, vertices=8)
    box("museum_roof_rail_top", 0.0, 15.90, 17.82, 40.40, 0.06, 0.06, bronze)
    box("museum_roof_rail_mid", 0.0, 15.90, 17.32, 40.40, 0.05, 0.05, bronze)
    # Roof membrane seams, maintenance walkway pads, an access
    # hatch and two vent stacks break up the bare field.
    for sy in (-8.00, -2.00, 4.00, 10.00):
        builder_box(bb(core_mat), 0.0, sy, 16.828, 44.80, 0.07, 0.016)
    for sx4 in (-15.00, 0.00, 15.00):
        builder_box(bb(core_mat), sx4, 1.00, 16.828, 0.07, 28.80, 0.016)
    for px2 in (-18.00, -12.00, -6.00, 0.00, 6.00, 12.00, 18.00):
        box("museum_roof_pad", px2, 8.20, 16.845, 2.40, 0.95, 0.045, trav)
    for py2 in (-8.00, -4.00, 0.00, 4.00):
        box("museum_roof_pad", -20.50, py2, 16.845, 0.95, 2.40, 0.045, trav)
    box("museum_roof_hatch", 5.50, -8.50, 17.12, 1.10, 1.10, 0.55, frame)
    box("museum_roof_hatch_lid", 5.50, -8.50, 17.43, 1.18, 1.18, 0.07, dark)
    for vx, vy in ((-8.00, 12.50), (11.00, -9.00)):
        cyl("museum_roof_vent", vx, vy, 17.32, 0.27, 1.00, frame, vertices=14)
        cyl("museum_roof_vent_cap", vx, vy, 17.90, 0.38, 0.09, dark, vertices=14)
        cyl("museum_roof_vent_band", vx, vy, 17.05, 0.29, 0.10, bronze, vertices=14)

    # ---- plaza: reflecting pool, sculpture court, planters, totems ------
    box("museum_pool_basin", -15.50, -15.35, 0.66, 17.00, 2.60, 0.12, granite)
    box("museum_pool_water", -15.50, -15.35, 0.74, 16.50, 2.10, 0.05, water)
    box("museum_pool_rim_f", -15.50, -16.73, 0.72, 17.00, 0.16, 0.24, granite)
    box("museum_pool_rim_b", -15.50, -13.97, 0.72, 17.00, 0.16, 0.24, granite)
    for ex in (-23.92, -7.08):
        box("museum_pool_rim_e", ex, -15.35, 0.72, 0.16, 2.60, 0.24, granite)
    for i in range(5):
        box("museum_pool_step_stone", -21.50 + 3.0 * i, -15.35, 0.78, 1.30, 1.50, 0.07, trav)
    # Travertine coping caps and bronze bubbler discs finish the pool.
    box("museum_pool_coping_f", -15.50, -16.73, 0.865, 17.10, 0.26, 0.05, trav)
    box("museum_pool_coping_b", -15.50, -13.97, 0.865, 17.10, 0.26, 0.05, trav)
    for ex2 in (-23.92, -7.08):
        box("museum_pool_coping_e", ex2, -15.35, 0.865, 0.26, 2.70, 0.05, trav)
    for bubx in (-20.00, -15.50, -11.00):
        cyl("museum_pool_bubbler", bubx, -15.35, 0.78, 0.14, 0.06, bronze, vertices=12)
    # Sculpture court (east forecourt): sphere, crossed slabs, ring.
    box("museum_plinth_a", 13.50, -15.40, 1.15, 1.30, 1.30, 1.10, granite)
    sphere("museum_sculpture_sphere", 13.50, -15.40, 2.60, 1.75, 1.75, 1.75, bronze)
    box("museum_plinth_b", 17.60, -15.90, 0.95, 1.50, 1.50, 0.70, granite)
    rbox("museum_sculpture_slab_a", 17.60, -15.90, 2.35, 0.22, 1.70, 2.20, trav, rotation=(0.0, 0.42, 0.0))
    rbox("museum_sculpture_slab_b", 17.60, -15.90, 2.30, 1.70, 0.22, 2.05, granite, rotation=(0.0, -0.35, 0.0))
    box("museum_plinth_c", 21.40, -15.20, 1.00, 1.20, 1.20, 0.80, granite)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.25, minor_radius=0.16, major_segments=32, minor_segments=10, location=(21.40, -15.20, 2.90))
    ring = bpy.context.active_object
    ring.name = "museum_sculpture_ring"
    finish(ring, bronze, smooth=True)
    for bxp in (11.00, 19.00):
        box("museum_front_bench_top", bxp, -14.55, 1.02, 2.40, 0.55, 0.14, trav)
        for fx in (-0.90, 0.90):
            box("museum_front_bench_foot", bxp + fx, -14.55, 0.82, 0.18, 0.48, 0.42, granite)
    for cxp in (-20.00, -11.00):
        box("museum_pool_seat", cxp, -18.25, 0.58, 0.55, 0.55, 0.55, granite)
    for tx in (-11.50, 11.50):
        box("museum_totem", tx, -18.30, 2.10, 0.55, 0.28, 3.60, granite)
        box("museum_totem_band", tx, -18.46, 3.30, 0.57, 0.04, 0.85, bronze)
        box("museum_totem_light", tx, -18.47, 1.70, 0.10, 0.03, 2.20, light)
    for bx3 in (-20.0, -17.0, 17.0, 20.0):
        cyl("museum_plaza_bollard", bx3, -18.55, 0.72, 0.07, 0.85, bronze, vertices=10)
        cyl("museum_plaza_bollard_light", bx3, -18.55, 1.16, 0.073, 0.06, light, vertices=10)
    # Civic flagpoles flanking the axis, cloth in banner colours,
    # based on the lower plinth beside the totems.
    for fpx, fmat in ((-15.20, banner_teal), (-13.60, white), (13.60, banner_ochre), (15.20, banner_teal)):
        cyl("museum_flagpole_base", fpx, -18.15, 0.55, 0.20, 0.50, granite, vertices=12)
        cyl("museum_flagpole", fpx, -18.15, 4.90, 0.045, 9.20, bronze, vertices=10)
        sphere("museum_flagpole_finial", fpx, -18.15, 9.58, 0.16, 0.16, 0.16, bronze)
        rbox("museum_flag", fpx + 0.80, -18.15, 8.80, 1.50, 0.03, 0.95, fmat, rotation=(0.0, 0.0, 0.05))
    # Side aprons: long planter hedges, stone benches and clipped trees
    # so the flanks are furnished, not empty travertine.
    for sx in (-24.35, 24.35):
        box("museum_side_planter", sx, 1.00, 0.85, 1.00, 26.00, 0.50, granite)
        box("museum_side_hedge", sx, 1.00, 1.22, 0.78, 25.60, 0.34, hedge)
        for by in (-6.0, 8.0):
            box("museum_side_bench_top", sx * 0.965, by, 1.02, 0.55, 2.30, 0.14, trav)
            for fy in (-0.85, 0.85):
                box("museum_side_bench_foot", sx * 0.965, by + fy, 0.82, 0.48, 0.18, 0.42, granite)
        for ty in (-13.00, 15.00):
            box("museum_tree_planter", sx, ty, 0.95, 1.50, 1.50, 0.70, granite)
            cyl("museum_tree_trunk", sx, ty, 1.85, 0.085, 1.15, frame, vertices=8)
            tube_between("museum_tree_branch", (sx, ty, 2.30), (sx - 0.42, ty + 0.30, 2.85), 0.045, 0.030, frame, vertices=6)
            tube_between("museum_tree_branch", (sx, ty, 2.35), (sx + 0.40, ty - 0.28, 2.90), 0.045, 0.030, frame, vertices=6)
            # Clipped multi-blob canopy instead of one lollipop sphere.
            sphere("museum_tree_crown", sx, ty, 3.15, 2.35, 2.35, 1.85, hedge)
            sphere("museum_tree_crown", sx - 0.58, ty + 0.34, 2.82, 1.45, 1.45, 1.25, hedge)
            sphere("museum_tree_crown", sx + 0.54, ty - 0.38, 2.88, 1.55, 1.55, 1.30, hedge)
            sphere("museum_tree_crown", sx + 0.10, ty - 0.04, 3.62, 1.35, 1.35, 1.05, hedge)


    for material_name, (builder, material) in builders.items():
        builder.build("museum_merged_" + material_name.lower(), material, smooth=False)


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
        (build_hotel, "grand_hotel.glb"),
        (build_museum, "museum.glb"),
        (build_cottage_dune, "cottage_dune.glb"),
        (build_cottage_courtyard, "cottage_courtyard.glb"),
        (build_cottage_palm, "cottage_palm.glb"),
        (build_palm_date, "palm_date.glb"),
        (build_palm_royal, "palm_royal.glb"),
        (build_grass_tuft, "grass_tuft.glb"),
        (build_flower_clump, "flower_clump.glb"),
        (build_ornamental_shrub, "ornamental_shrub.glb"),
        (build_school, "school.glb"),
        (build_airport_terminal, "airport_terminal.glb"),
        (build_atc_tower, "atc_tower.glb"),
        (build_hangar_large, "hangar_large.glb"),
        (build_hangar_small, "hangar_small.glb"),
        (build_airliner, "airliner.glb"),
        (build_yacht_sail, "yacht_sail.glb"),
        (build_yacht_motor, "yacht_motor.glb"),
        (build_cooling_tower, "cooling_tower.glb"),
        (build_reactor, "reactor.glb"),
        (build_chimney, "chimney.glb"),
        (build_radar_station, "radar_station.glb"),
        (build_watchtower, "watchtower.glb"),
        (build_storage_tank, "storage_tank.glb"),
        (build_silo, "silo.glb"),
        (build_afv, "afv.glb"),
        (build_stadium, "stadium.glb"),
        (build_office_tower_low, "office_tower_low.glb"),
        (build_office_tower_mid, "office_tower_mid.glb"),
        (build_office_tower_high, "office_tower_high.glb"),
        (build_midrise_a, "midrise_a.glb"),
        (build_midrise_b, "midrise_b.glb"),
        (build_warehouse_large, "warehouse_large.glb"),
        (build_warehouse_small, "warehouse_small.glb"),
        (build_shopping_mall, "shopping_mall.glb"),
        (build_turbine_hall_long, "turbine_hall_long.glb"),
        (build_turbine_hall_short, "turbine_hall_short.glb"),
        (build_container_red, "container_red.glb"),
        (build_container_blue, "container_blue.glb"),
        (build_villa_b, "villa_b.glb"),
        (build_townhouse_b, "townhouse_b.glb"),
        (build_barn, "barn.glb"),
        (build_greenhouse, "greenhouse.glb"),
        (build_port_crane, "port_crane.glb"),
        (build_barge, "barge.glb"),
    ):
        # Local model reviews can build one asset without regenerating
        # the whole city set, e.g. NITCHES_PROPS_ONLY=cottage_dune.glb.
        # CI leaves the variable unset and always builds every prop.
        requested = {name.strip() for name in os.environ.get("NITCHES_PROPS_ONLY", "").split(",") if name.strip()}
        if requested and filename not in requested:
            continue
        reset_scene()
        standard_mats()
        build()
        export(out_dir, filename)
    print("[props] done ->", out_dir)


# --------------------------------------------------------------------------- #
# Building Models No.10-12 - Sail Island desert cottage estates.
#
# These are not scaled copies of Building Model No.1.  Each asset is a
# complete exterior-only private estate in one fixed 36 x 27 m envelope:
# chamfered perimeter wall, vehicle and pedestrian gates, driveway,
# garage, entrance court, house shell, rear terrace and pool.  Window
# assemblies contain only a dark exterior backing/blind immediately
# behind reflective glass; there are no rooms, stairs or furniture.
# The front is Blender -Y, matching the established villa convention.
# --------------------------------------------------------------------------- #

def _cottage_window(cx, cy, cz, width, height, face, blind_fraction=0.0, divisions=None):
    sand = MATS["CottageSand"]
    basalt = MATS["CottageBasalt"]
    bronze = MATS["CottageBronze"]
    glass = MATS["CottageGlass"]
    core = MATS["CottageCore"]
    blind = MATS["CottageBlind"]
    if divisions is None:
        divisions = max(1, int(width // 1.15))
    sign = -1.0 if face in ("front", "left") else 1.0
    blind_drop = height * blind_fraction
    if face in ("front", "back"):
        box("cottage_window_reveal", cx, cy + sign * 0.025, cz, width + 0.34, 0.09, height + 0.34, basalt)
        panel("cottage_window_core", cx, cy + sign * 0.0775, cz, width - 0.02, height - 0.02, core, face)
        if blind_drop > 0.04:
            panel("cottage_window_blind", cx, cy + sign * 0.100, cz + height / 2.0 - blind_drop / 2.0 - 0.03, width - 0.14, blind_drop, blind, face)
            box("cottage_window_blind_rail", cx, cy + sign * 0.090, cz + height / 2.0 - blind_drop - 0.055, width - 0.10, 0.035, 0.045, bronze)
        for side in (-1.0, 1.0):
            box("cottage_window_frame_side", cx + side * (width / 2.0 + 0.035), cy + sign * 0.085, cz, 0.15, 0.15, height + 0.24, bronze)
            box("cottage_window_frame_rail", cx, cy + sign * 0.085, cz + side * (height / 2.0 + 0.035), width + 0.30, 0.15, 0.15, bronze)
        panel("cottage_window_glass", cx, cy + sign * 0.1455, cz, width, height, glass, face)
        for division in range(1, divisions):
            mx = cx - width / 2.0 + width * division / divisions
            box("cottage_window_mullion", mx, cy + sign * 0.152, cz, 0.055, 0.045, height, bronze)
        box("cottage_window_transom", cx, cy + sign * 0.152, cz + height * 0.24, width, 0.045, 0.055, bronze)
        box("cottage_window_sill", cx, cy + sign * 0.155, cz - height / 2.0 - 0.16, width + 0.42, 0.32, 0.10, basalt)
        box("cottage_window_header", cx, cy + sign * 0.110, cz + height / 2.0 + 0.17, width + 0.34, 0.20, 0.10, sand)
    else:
        box("cottage_window_reveal", cx + sign * 0.025, cy, cz, 0.09, width + 0.34, height + 0.34, basalt)
        panel("cottage_window_core", cx + sign * 0.0775, cy, cz, width - 0.02, height - 0.02, core, face)
        if blind_drop > 0.04:
            panel("cottage_window_blind", cx + sign * 0.100, cy, cz + height / 2.0 - blind_drop / 2.0 - 0.03, width - 0.14, blind_drop, blind, face)
            box("cottage_window_blind_rail", cx + sign * 0.090, cy, cz + height / 2.0 - blind_drop - 0.055, 0.035, width - 0.10, 0.045, bronze)
        for side in (-1.0, 1.0):
            box("cottage_window_frame_side", cx + sign * 0.085, cy + side * (width / 2.0 + 0.035), cz, 0.15, 0.15, height + 0.24, bronze)
            box("cottage_window_frame_rail", cx + sign * 0.085, cy, cz + side * (height / 2.0 + 0.035), 0.15, width + 0.30, 0.15, bronze)
        panel("cottage_window_glass", cx + sign * 0.1455, cy, cz, width, height, glass, face)
        for division in range(1, divisions):
            my = cy - width / 2.0 + width * division / divisions
            box("cottage_window_mullion", cx + sign * 0.152, my, cz, 0.045, 0.055, height, bronze)
        box("cottage_window_transom", cx + sign * 0.152, cy, cz + height * 0.24, 0.045, width, 0.055, bronze)
        box("cottage_window_sill", cx + sign * 0.155, cy, cz - height / 2.0 - 0.16, 0.32, width + 0.42, 0.10, basalt)
        box("cottage_window_header", cx + sign * 0.110, cy, cz + height / 2.0 + 0.17, 0.20, width + 0.34, 0.10, sand)


def _cottage_louver(cx, cy, cz, width, height, face, material=None):
    bronze = MATS["CottageBronze"]
    core = MATS["CottageCore"]
    slat_material = MATS["CottageTeak"] if material is None else material
    sign = -1.0 if face in ("front", "left") else 1.0
    count = max(3, int(width / 0.34))
    if face in ("front", "back"):
        panel("cottage_louver_core", cx, cy + sign * 0.070, cz, width, height, core, face)
        for side in (-1.0, 1.0):
            box("cottage_louver_frame", cx + side * (width / 2.0 + 0.04), cy + sign * 0.13, cz, 0.12, 0.18, height + 0.18, bronze)
            box("cottage_louver_frame", cx, cy + sign * 0.13, cz + side * (height / 2.0 + 0.04), width + 0.22, 0.18, 0.12, bronze)
        for index in range(count):
            x = cx - width / 2.0 + (index + 0.5) * width / count
            box("cottage_louver_slat", x, cy + sign * 0.15, cz, 0.11, 0.07, height - 0.08, slat_material)
    else:
        panel("cottage_louver_core", cx + sign * 0.070, cy, cz, width, height, core, face)
        for side in (-1.0, 1.0):
            box("cottage_louver_frame", cx + sign * 0.13, cy + side * (width / 2.0 + 0.04), cz, 0.18, 0.12, height + 0.18, bronze)
            box("cottage_louver_frame", cx + sign * 0.13, cy, cz + side * (height / 2.0 + 0.04), 0.18, width + 0.22, 0.12, bronze)
        for index in range(count):
            y = cy - width / 2.0 + (index + 0.5) * width / count
            box("cottage_louver_slat", cx + sign * 0.15, y, cz, 0.07, 0.11, height - 0.08, slat_material)


def _cottage_mashrabiya(cx, cy, cz, width, height, face):
    bronze = MATS["CottageBronze"]
    stone = MATS["CottageTravertine"]
    core = MATS["CottageCore"]
    sign = -1.0 if face in ("front", "left") else 1.0
    verticals = max(3, int(width / 0.42))
    horizontals = max(3, int(height / 0.48))
    if face in ("front", "back"):
        panel("cottage_mashrabiya_core", cx, cy + sign * 0.065, cz, width, height, core, face)
        for side in (-1.0, 1.0):
            box("cottage_mashrabiya_frame", cx + side * (width / 2.0 + 0.05), cy + sign * 0.12, cz, 0.16, 0.18, height + 0.22, stone)
            box("cottage_mashrabiya_frame", cx, cy + sign * 0.12, cz + side * (height / 2.0 + 0.05), width + 0.28, 0.18, 0.16, stone)
        for index in range(verticals):
            x = cx - width / 2.0 + (index + 0.5) * width / verticals
            box("cottage_mashrabiya_bar_v", x, cy + sign * 0.14, cz, 0.065, 0.07, height, bronze)
        for index in range(horizontals):
            z = cz - height / 2.0 + (index + 0.5) * height / horizontals
            box("cottage_mashrabiya_bar_h", cx, cy + sign * 0.145, z, width, 0.075, 0.065, bronze)
    else:
        panel("cottage_mashrabiya_core", cx + sign * 0.065, cy, cz, width, height, core, face)
        for side in (-1.0, 1.0):
            box("cottage_mashrabiya_frame", cx + sign * 0.12, cy + side * (width / 2.0 + 0.05), cz, 0.18, 0.16, height + 0.22, stone)
            box("cottage_mashrabiya_frame", cx + sign * 0.12, cy, cz + side * (height / 2.0 + 0.05), 0.18, width + 0.28, 0.16, stone)
        for index in range(verticals):
            y = cy - width / 2.0 + (index + 0.5) * width / verticals
            box("cottage_mashrabiya_bar_v", cx + sign * 0.14, y, cz, 0.07, 0.065, height, bronze)
        for index in range(horizontals):
            z = cz - height / 2.0 + (index + 0.5) * height / horizontals
            box("cottage_mashrabiya_bar_h", cx + sign * 0.145, cy, z, 0.075, width, 0.065, bronze)


def _cottage_door(cx, cy, face="front"):
    teak = MATS["CottageTeak"]
    bronze = MATS["CottageBronze"]
    basalt = MATS["CottageBasalt"]
    glass = MATS["CottageGlass"]
    core = MATS["CottageCore"]
    sign = -1.0 if face in ("front", "left") else 1.0
    if face in ("front", "back"):
        box("cottage_door_reveal", cx, cy + sign * 0.035, 1.72, 2.05, 0.10, 3.05, basalt)
        box("cottage_door_leaf", cx - 0.28, cy + sign * 0.105, 1.68, 1.28, 0.09, 2.92, teak)
        for groove in (-0.42, 0.0, 0.42):
            box("cottage_door_groove", cx - 0.28 + groove, cy + sign * 0.158, 1.68, 0.025, 0.018, 2.72, basalt)
        panel("cottage_door_sidelight_core", cx + 0.72, cy + sign * 0.0925, 1.68, 0.42, 2.86, core, face)
        panel("cottage_door_sidelight", cx + 0.72, cy + sign * 0.1295, 1.68, 0.36, 2.80, glass, face)
        box("cottage_door_handle", cx + 0.24, cy + sign * 0.20, 1.55, 0.055, 0.055, 1.35, bronze)
        box("cottage_door_step", cx, cy + sign * 0.48, 0.16, 2.35, 0.72, 0.18, basalt)
        box("cottage_door_canopy", cx, cy + sign * 0.62, 3.38, 2.75, 1.25, 0.14, bronze)
        box("cottage_door_canopy_light", cx, cy + sign * 0.62, 3.29, 1.55, 0.055, 0.025, MATS["CottageLight"])
    else:
        box("cottage_door_reveal", cx + sign * 0.035, cy, 1.72, 0.10, 2.05, 3.05, basalt)
        box("cottage_door_leaf", cx + sign * 0.105, cy - 0.28, 1.68, 0.09, 1.28, 2.92, teak)
        panel("cottage_door_sidelight_core", cx + sign * 0.0925, cy + 0.72, 1.68, 0.42, 2.86, core, face)
        panel("cottage_door_sidelight", cx + sign * 0.1295, cy + 0.72, 1.68, 0.36, 2.80, glass, face)
        box("cottage_door_handle", cx + sign * 0.20, cy + 0.24, 1.55, 0.055, 0.055, 1.35, bronze)
        box("cottage_door_step", cx + sign * 0.48, cy, 0.16, 0.72, 2.35, 0.18, basalt)


def _cottage_garage_door(cx, cy, width=4.8, face="front"):
    bronze = MATS["CottageBronze"]
    basalt = MATS["CottageBasalt"]
    core = MATS["CottageCore"]
    glass = MATS["CottageGlass"]
    sign = -1.0 if face in ("front", "left") else 1.0
    if face in ("front", "back"):
        box("cottage_garage_reveal", cx, cy + sign * 0.035, 1.62, width + 0.42, 0.10, 3.05, basalt)
        for door_panel in range(4):
            z = 0.48 + door_panel * 0.72
            box("cottage_garage_panel", cx, cy + sign * 0.105, z, width, 0.075, 0.64, bronze)
        for xoff in (-width * 0.30, 0.0, width * 0.30):
            panel("cottage_garage_window_core", cx + xoff, cy + sign * 0.1625, 2.72, 0.72, 0.28, core, face)
            panel("cottage_garage_window", cx + xoff, cy + sign * 0.1805, 2.72, 0.64, 0.22, glass, face)
        box("cottage_garage_handle", cx, cy + sign * 0.17, 1.02, 0.52, 0.045, 0.055, basalt)
        box("cottage_garage_sensor", cx + width / 2.0 + 0.34, cy + sign * 0.12, 1.25, 0.16, 0.07, 0.26, basalt)
        box("cottage_garage_sensor_light", cx + width / 2.0 + 0.34, cy + sign * 0.165, 1.30, 0.045, 0.025, 0.045, MATS["CottageLight"])
    else:
        box("cottage_garage_reveal", cx + sign * 0.035, cy, 1.62, 0.10, width + 0.42, 3.05, basalt)
        for door_panel in range(4):
            box("cottage_garage_panel", cx + sign * 0.105, cy, 0.48 + door_panel * 0.72, 0.075, width, 0.64, bronze)


def _cottage_flat_roof(cx, cy, top, width, depth, parapet_material=None, solar=False):
    bronze = MATS["CottageBronze"]
    gravel = MATS["RoofGravel"]
    basalt = MATS["CottageBasalt"]
    box("cottage_roof_slab", cx, cy, top + 0.16, width + 0.65, depth + 0.65, 0.32, bronze, bevel=0.025)
    box("cottage_roof_gravel", cx, cy, top + 0.355, max(width - 0.45, 0.4), max(depth - 0.45, 0.4), 0.07, gravel)
    if parapet_material is not None:
        for sy in (cy - depth / 2.0 + 0.13, cy + depth / 2.0 - 0.13):
            box("cottage_roof_parapet", cx, sy, top + 0.58, width - 0.18, 0.26, 0.42, parapet_material)
            box("cottage_roof_coping", cx, sy, top + 0.83, width - 0.05, 0.36, 0.08, basalt)
        for sx in (cx - width / 2.0 + 0.13, cx + width / 2.0 - 0.13):
            box("cottage_roof_parapet", sx, cy, top + 0.58, 0.26, depth - 0.18, 0.42, parapet_material)
            box("cottage_roof_coping", sx, cy, top + 0.83, 0.36, depth - 0.05, 0.08, basalt)
    if solar:
        _cottage_solar_array(cx - width * 0.18, cy, top + 0.42, 3, 2)
    _cottage_hvac(cx + width * 0.31, cy + depth * 0.24, top + 0.40)


def _cottage_solar_array(cx, cy, base_z, columns, rows):
    solar = MATS["SolarCell"]
    bronze = MATS["CottageBronze"]
    for row in range(rows):
        for column in range(columns):
            x = cx + (column - (columns - 1) / 2.0) * 1.82
            y = cy + (row - (rows - 1) / 2.0) * 1.28
            rbox("cottage_solar_panel", x, y, base_z + 0.30, 1.68, 1.08, 0.055, solar, rotation=(math.radians(-17.0), 0.0, 0.0))
            box("cottage_solar_leg", x - 0.58, y + 0.30, base_z + 0.12, 0.055, 0.055, 0.28, bronze)
            box("cottage_solar_leg", x + 0.58, y + 0.30, base_z + 0.12, 0.055, 0.055, 0.28, bronze)


def _cottage_hvac(cx, cy, base_z):
    bronze = MATS["CottageBronze"]
    basalt = MATS["CottageBasalt"]
    box("cottage_hvac_body", cx, cy, base_z + 0.42, 1.85, 0.92, 0.84, bronze, bevel=0.025)
    for index in range(5):
        box("cottage_hvac_louvre", cx, cy - 0.49, base_z + 0.18 + index * 0.14, 1.62, 0.035, 0.055, basalt)
    cyl("cottage_hvac_fan", cx, cy, base_z + 0.87, 0.34, 0.055, basalt, vertices=12)


def _cottage_pergola(cx, cy, width, depth, height=2.85, base_z=0.22):
    teak = MATS["CottageTeak"]
    bronze = MATS["CottageBronze"]
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            box("cottage_pergola_post", cx + sx * (width / 2.0 - 0.18), cy + sy * (depth / 2.0 - 0.18), base_z + height / 2.0, 0.18, 0.18, height, bronze)
    for sy in (-1.0, 1.0):
        box("cottage_pergola_beam", cx, cy + sy * (depth / 2.0 - 0.18), base_z + height + 0.10, width + 0.30, 0.20, 0.20, teak)
    slats = max(4, int(width / 0.55))
    for index in range(slats):
        x = cx - width / 2.0 + (index + 0.5) * width / slats
        box("cottage_pergola_slat", x, cy, base_z + height + 0.27, 0.13, depth + 0.25, 0.09, teak)


def _cottage_balcony(cx, cy, cz, width, face):
    basalt = MATS["CottageBasalt"]
    bronze = MATS["CottageBronze"]
    glass = MATS["CottageGlass"]
    hedge = MATS["CottageHedge"]
    sign = -1.0 if face in ("front", "left") else 1.0
    if face in ("front", "back"):
        box("cottage_balcony_slab", cx, cy + sign * 0.72, cz, width + 0.35, 1.48, 0.18, basalt)
        box("cottage_balcony_glass", cx, cy + sign * 1.38, cz + 0.58, width, 0.045, 0.92, glass)
        box("cottage_balcony_rail", cx, cy + sign * 1.38, cz + 1.08, width + 0.08, 0.09, 0.075, bronze)
        for side in (-1.0, 1.0):
            box("cottage_balcony_side_glass", cx + side * width / 2.0, cy + sign * 0.72, cz + 0.58, 0.045, 1.28, 0.92, glass)
            box("cottage_balcony_planter", cx + side * (width / 2.0 - 0.42), cy + sign * 1.05, cz + 0.22, 0.62, 0.38, 0.26, basalt)
            box("cottage_balcony_hedge", cx + side * (width / 2.0 - 0.42), cy + sign * 1.05, cz + 0.43, 0.54, 0.30, 0.20, hedge, bevel=0.06)
    else:
        box("cottage_balcony_slab", cx + sign * 0.72, cy, cz, 1.48, width + 0.35, 0.18, basalt)
        box("cottage_balcony_glass", cx + sign * 1.38, cy, cz + 0.58, 0.045, width, 0.92, glass)
        box("cottage_balcony_rail", cx + sign * 1.38, cy, cz + 1.08, 0.09, width + 0.08, 0.075, bronze)


def _cottage_pool(cx, cy, width, depth):
    basalt = MATS["CottageBasalt"]
    stone = MATS["CottageTravertine"]
    water = MATS["CottageWater"]
    box("cottage_pool_basin", cx, cy, 0.28, width + 0.55, depth + 0.55, 0.34, basalt)
    box("cottage_pool_water", cx, cy, 0.43, width, depth, 0.07, water)
    for sy in (-1.0, 1.0):
        box("cottage_pool_coping", cx, cy + sy * (depth / 2.0 + 0.16), 0.49, width + 0.70, 0.28, 0.11, stone)
    for sx in (-1.0, 1.0):
        box("cottage_pool_coping", cx + sx * (width / 2.0 + 0.16), cy, 0.49, 0.28, depth + 0.70, 0.11, stone)
    for step in range(3):
        box("cottage_pool_step", cx - width / 2.0 + 0.55 + step * 0.34, cy, 0.30 + step * 0.055, 0.30, min(depth * 0.52, 2.2), 0.09, stone)
    box("cottage_pool_bench", cx + width / 2.0 - 0.55, cy, 0.34, 0.55, max(depth - 0.7, 0.6), 0.10, stone)


def _cottage_wall_run(cx, cy, length, rotation_z=0.0):
    sand = MATS["CottageSand"]
    basalt = MATS["CottageBasalt"]
    if abs(rotation_z) < 0.001:
        box("cottage_wall_base", cx, cy, 0.27, length, 0.34, 0.54, basalt)
        box("cottage_wall_panel", cx, cy, 1.25, length, 0.26, 1.42, sand)
        box("cottage_wall_cap", cx, cy, 2.05, length + 0.04, 0.40, 0.18, basalt)
    else:
        rbox("cottage_wall_base", cx, cy, 0.27, length, 0.34, 0.54, basalt, rotation=(0.0, 0.0, rotation_z))
        rbox("cottage_wall_panel", cx, cy, 1.25, length, 0.26, 1.42, sand, rotation=(0.0, 0.0, rotation_z))
        rbox("cottage_wall_cap", cx, cy, 2.05, length + 0.04, 0.40, 0.18, basalt, rotation=(0.0, 0.0, rotation_z))


def _cottage_wall_pilaster(cx, cy, side=False):
    stone = MATS["CottageTravertine"]
    basalt = MATS["CottageBasalt"]
    light = MATS["CottageLight"]
    if side:
        box("cottage_wall_pilaster", cx, cy, 1.13, 0.46, 0.58, 2.26, stone)
        box("cottage_wall_pilaster_cap", cx, cy, 2.32, 0.56, 0.68, 0.12, basalt)
    else:
        box("cottage_wall_pilaster", cx, cy, 1.13, 0.58, 0.46, 2.26, stone)
        box("cottage_wall_pilaster_cap", cx, cy, 2.32, 0.68, 0.56, 0.12, basalt)
        box("cottage_wall_light", cx, cy - 0.26, 1.78, 0.09, 0.035, 0.34, light)


def _cottage_gate(cx, width, pedestrian=False):
    teak = MATS["CottageTeak"]
    bronze = MATS["CottageBronze"]
    basalt = MATS["CottageBasalt"]
    y = -13.20
    box("cottage_gate_frame_top", cx, y, 2.02, width, 0.11, 0.13, bronze)
    box("cottage_gate_frame_bottom", cx, y, 0.24, width, 0.11, 0.13, bronze)
    for side in (-1.0, 1.0):
        box("cottage_gate_frame_side", cx + side * (width / 2.0 - 0.055), y, 1.13, 0.11, 0.11, 1.90, bronze)
    slats = max(3, int(width / 0.34))
    for index in range(slats):
        x = cx - width / 2.0 + (index + 0.5) * width / slats
        box("cottage_gate_slat", x, y + 0.035, 1.13, 0.17, 0.055, 1.78, teak)
    if pedestrian:
        box("cottage_gate_handle", cx + width / 2.0 - 0.25, y - 0.11, 1.08, 0.045, 0.045, 0.52, bronze)
    else:
        box("cottage_gate_track", cx + 1.2, y + 0.22, 0.055, width + 4.0, 0.16, 0.055, basalt)
        box("cottage_gate_motor", cx - width / 2.0 - 0.55, y + 0.52, 0.42, 0.62, 0.52, 0.62, basalt)
        box("cottage_gate_motor_light", cx - width / 2.0 - 0.55, y + 0.24, 0.48, 0.055, 0.025, 0.055, MATS["CottageLight"])


def _cottage_planter(cx, cy, width, depth, hedge_height=0.62):
    basalt = MATS["CottageBasalt"]
    hedge = MATS["CottageHedge"]
    gravel = MATS["CottageGravel"]
    box("cottage_planter", cx, cy, 0.34, width, depth, 0.48, basalt)
    box("cottage_planter_soil", cx, cy, 0.60, width - 0.18, depth - 0.18, 0.055, gravel)
    box("cottage_planter_hedge", cx, cy, 0.66 + hedge_height / 2.0, width - 0.30, depth - 0.30, hedge_height, hedge, bevel=0.10)


def _build_cottage_site(gate_x, pedestrian_x, entrance_x, entrance_y, garage_x, pool_center, pool_size):
    paving = MATS["CottagePaving"]
    gravel = MATS["CottageGravel"]
    lawn = MATS["CottageLawn"]
    basalt = MATS["CottageBasalt"]
    teak = MATS["CottageTeak"]
    stone = MATS["CottageTravertine"]
    bronze = MATS["CottageBronze"]

    # A mineral ground plane makes the asset readable as one estate in
    # Blender and prevents terrain poking through the private garden.
    # Three slabs approximate the chamfered lot instead of leaving
    # paved rectangular corners outside the diagonal boundary walls.
    box("cottage_site_base", 0.0, 0.0, 0.055, 35.2, 19.0, 0.11, gravel)
    box("cottage_site_base_front", 0.0, -11.3, 0.055, 28.2, 3.7, 0.11, gravel)
    box("cottage_site_base_rear", 0.0, 11.3, 0.055, 28.2, 3.7, 0.11, gravel)
    # Desert-modern landscaping is mostly mineral ground with framed
    # lawn rooms, not one continuous bright-green carpet.
    for lawn_x, lawn_y, lawn_w, lawn_d in (
        (-13.9, 3.8, 5.6, 14.6),
        (13.9, 3.8, 5.6, 14.6),
        (-12.4, -9.2, 6.8, 5.2),
        (12.4, -9.2, 6.8, 5.2),
        (-5.9, -9.4, 4.6, 4.6),
        (5.9, -9.4, 4.6, 4.6),
    ):
        box("cottage_site_lawn", lawn_x, lawn_y, 0.125, lawn_w, lawn_d, 0.055, lawn)
        box("cottage_lawn_edging", lawn_x, lawn_y - lawn_d / 2.0, 0.145, lawn_w + 0.08, 0.07, 0.055, basalt)
        box("cottage_lawn_edging", lawn_x, lawn_y + lawn_d / 2.0, 0.145, lawn_w + 0.08, 0.07, 0.055, basalt)
        box("cottage_lawn_edging", lawn_x - lawn_w / 2.0, lawn_y, 0.145, 0.07, lawn_d + 0.08, 0.055, basalt)
        box("cottage_lawn_edging", lawn_x + lawn_w / 2.0, lawn_y, 0.145, 0.07, lawn_d + 0.08, 0.055, basalt)

    # Drive and turning court.  Dark expansion joints are real thin
    # geometry, so the court does not depend only on texture repetition.
    box("cottage_drive", gate_x, -8.65, 0.155, 5.6, 9.1, 0.075, paving)
    court_width = abs(garage_x - gate_x) + 8.4
    box("cottage_turning_court", (gate_x + garage_x) / 2.0, -5.15, 0.155, court_width, 4.3, 0.075, paving)
    for index in range(6):
        box("cottage_drive_joint", gate_x, -12.35 + index * 1.55, 0.198, 5.62, 0.055, 0.018, basalt)
    box("cottage_drive_centre_joint", gate_x, -8.65, 0.198, 0.055, 9.1, 0.018, basalt)
    box("cottage_gate_drain", gate_x, -12.78, 0.19, 5.35, 0.24, 0.035, basalt)
    for index in range(9):
        box("cottage_gate_drain_slot", gate_x - 2.35 + index * 0.59, -12.78, 0.212, 0.28, 0.045, 0.012, bronze)

    # Pedestrian route: gate -> entrance, with an L-turn only where the
    # architectural axis requires it.
    path_mid_y = (entrance_y + -13.0) / 2.0
    path_length = abs(entrance_y - -13.0)
    box("cottage_pedestrian_path", pedestrian_x, path_mid_y, 0.16, 1.55, path_length, 0.07, stone)
    if abs(entrance_x - pedestrian_x) > 0.25:
        box("cottage_pedestrian_path_turn", (pedestrian_x + entrance_x) / 2.0, entrance_y - 0.72, 0.16, abs(entrance_x - pedestrian_x) + 1.55, 1.45, 0.07, stone)

    # Front wall with true vehicle/pedestrian openings.  The gates are
    # closed exterior assemblies; no attempt is made to model beyond
    # the slats.
    gaps = sorted(((gate_x - 2.75, gate_x + 2.75), (pedestrian_x - 0.68, pedestrian_x + 0.68)))
    cursor = -14.0
    for gap_start, gap_end in gaps:
        if gap_start - cursor > 0.25:
            _cottage_wall_run((cursor + gap_start) / 2.0, -13.20, gap_start - cursor)
        cursor = max(cursor, gap_end)
    if 14.0 - cursor > 0.25:
        _cottage_wall_run((cursor + 14.0) / 2.0, -13.20, 14.0 - cursor)
    for px in (-13.6, -9.6, -5.6, 3.8, 7.8, 11.8, 13.6):
        if not any(start - 0.45 <= px <= end + 0.45 for start, end in gaps):
            _cottage_wall_pilaster(px, -13.20)
    for px in (gate_x - 3.12, gate_x + 3.12, pedestrian_x - 1.02, pedestrian_x + 1.02):
        _cottage_wall_pilaster(px, -13.20)
    _cottage_gate(gate_x, 5.35, pedestrian=False)
    _cottage_gate(pedestrian_x, 1.28, pedestrian=True)
    box("cottage_address_plaque", pedestrian_x + 1.45, -13.49, 1.48, 0.52, 0.035, 0.34, bronze)
    box("cottage_intercom", gate_x - 3.48, -13.43, 1.18, 0.20, 0.09, 0.34, basalt)
    box("cottage_intercom_light", gate_x - 3.48, -13.49, 1.25, 0.045, 0.020, 0.045, MATS["CottageLight"])

    # Chamfered corners suit Sail Island's curved shore and loop road.
    for sx in (-1.0, 1.0):
        _cottage_wall_run(sx * 15.85, -11.35, 5.25, math.radians(45.0 if sx > 0 else -45.0))
        _cottage_wall_run(sx * 15.85, 11.35, 5.25, math.radians(-45.0 if sx > 0 else 45.0))
        # Side wall uses a rotated run so its stacked courses follow Y.
        rbox("cottage_wall_base_side", sx * 17.70, 0.0, 0.27, 19.0, 0.34, 0.54, basalt, rotation=(0.0, 0.0, math.radians(90.0)))
        rbox("cottage_wall_panel_side", sx * 17.70, 0.0, 1.25, 19.0, 0.26, 1.42, MATS["CottageSand"], rotation=(0.0, 0.0, math.radians(90.0)))
        rbox("cottage_wall_cap_side", sx * 17.70, 0.0, 2.05, 19.04, 0.40, 0.18, basalt, rotation=(0.0, 0.0, math.radians(90.0)))
        for py in (-7.5, -2.5, 2.5, 7.5):
            _cottage_wall_pilaster(sx * 17.70, py, side=True)
    _cottage_wall_run(0.0, 13.20, 28.0)
    for px in (-12.0, -6.0, 0.0, 6.0, 12.0):
        # Rear pilasters reuse the front detail but their small light
        # remains on the garden side of the wall.
        _cottage_wall_pilaster(px, 13.20)

    # Landscape structure: clipped hedges, planters and sculptural
    # boulders.  Palms remain separate high-detail vegetation models.
    _cottage_planter(-15.6, -6.0, 2.6, 6.4, 0.72)
    _cottage_planter(15.6, -6.0, 2.6, 6.4, 0.72)
    _cottage_planter(-15.6, 7.5, 2.6, 5.2, 0.58)
    _cottage_planter(15.6, 7.5, 2.6, 5.2, 0.58)
    for bx, by, scale in ((-13.8, -10.6, 1.15), (13.8, -10.8, 0.92), (-14.4, 11.2, 0.82)):
        sphere("cottage_garden_boulder", bx, by, 0.38, 1.15 * scale, 0.82 * scale, 0.58 * scale, basalt, segments=12, ring_count=8)
    for lx in (-6.0, 6.0):
        box("cottage_path_bollard", pedestrian_x + lx * 0.18, -10.7, 0.42, 0.13, 0.13, 0.62, basalt)
        box("cottage_path_bollard_light", pedestrian_x + lx * 0.18, -10.7, 0.75, 0.095, 0.095, 0.055, MATS["CottageLight"])

    # Rear leisure terrace: teak deck boards, pool and a shaded cabana.
    pool_x, pool_y = pool_center
    pool_w, pool_d = pool_size
    deck_w = min(pool_w + (1.4 if pool_w < 5.0 else 3.2), 21.0)
    deck_d = min(pool_d + 2.6, 12.2)
    deck_x = pool_x
    box("cottage_pool_deck", deck_x, pool_y, 0.17, deck_w, deck_d, 0.09, teak)
    board_count = max(4, int(deck_w / 0.62))
    for index in range(1, board_count):
        x = deck_x - deck_w / 2.0 + index * deck_w / board_count
        box("cottage_pool_deck_joint", x, pool_y, 0.222, 0.028, deck_d - 0.08, 0.012, basalt)
    _cottage_pool(pool_x, pool_y, pool_w, pool_d)
    if pool_w >= 5.0:
        _cottage_pergola(deck_x + deck_w / 2.0 - 2.35, pool_y, 4.3, min(deck_d - 0.5, 4.8), 2.75, 0.22)
        box("cottage_outdoor_kitchen", deck_x - deck_w / 2.0 + 1.45, pool_y, 0.58, 2.25, 0.72, 0.78, basalt)
        box("cottage_outdoor_kitchen_top", deck_x - deck_w / 2.0 + 1.45, pool_y, 1.01, 2.38, 0.82, 0.09, stone)
        box("cottage_outdoor_grill", deck_x - deck_w / 2.0 + 1.45, pool_y, 1.09, 0.92, 0.52, 0.07, bronze)
    else:
        # Courtyard No.11 has a narrow side lap pool.  Its cabana sits
        # at the shallow southern end instead of over the water, and
        # the outdoor kitchen is omitted from the 3 m side garden.
        _cottage_pergola(pool_x, pool_y - pool_d / 2.0 - 0.15, 3.7, 3.4, 2.65, 0.22)
        box("cottage_lap_pool_bench", pool_x - pool_w / 2.0 - 0.55, pool_y + 1.8, 0.48, 0.55, 2.4, 0.52, stone)


def _cottage_facade_seams(cx, cy, base_z, width, height, face):
    """Fine panel shadow gaps over a solid exterior wall volume."""
    basalt = MATS["CottageBasalt"]
    sign = -1.0 if face in ("front", "left") else 1.0
    verticals = max(2, int(width / 3.1))
    horizontals = max(1, int(height / 3.4))
    centre_z = base_z + height / 2.0
    if face in ("front", "back"):
        for index in range(1, verticals):
            x = cx - width / 2.0 + width * index / verticals
            box("cottage_facade_seam_v", x, cy + sign * 0.012, centre_z, 0.045, 0.024, height - 0.18, basalt)
        for index in range(1, horizontals + 1):
            z = base_z + height * index / (horizontals + 1)
            box("cottage_facade_seam_h", cx, cy + sign * 0.012, z, width - 0.18, 0.024, 0.045, basalt)
    else:
        for index in range(1, verticals):
            y = cy - width / 2.0 + width * index / verticals
            box("cottage_facade_seam_v", cx + sign * 0.012, y, centre_z, 0.024, 0.045, height - 0.18, basalt)
        for index in range(1, horizontals + 1):
            z = base_z + height * index / (horizontals + 1)
            box("cottage_facade_seam_h", cx + sign * 0.012, cy, z, 0.024, width - 0.18, 0.045, basalt)


def _cottage_downspouts(points, top_z):
    bronze = MATS["CottageBronze"]
    for x, y in points:
        cyl("cottage_downspout", x, y, top_z / 2.0 + 0.15, 0.045, top_z - 0.25, bronze, vertices=8)
        cyl("cottage_downspout_shoe", x, y, 0.22, 0.065, 0.22, MATS["CottageBasalt"], vertices=8)


def build_cottage_dune():
    """No.10: horizontal dune pavilion with a flying roof and stone blade."""
    sand = MATS["CottageSand"]
    stone = MATS["CottageTravertine"]
    limestone = MATS["CottageLimestone"]
    basalt = MATS["CottageBasalt"]
    teak = MATS["CottageTeak"]
    _build_cottage_site(-8.5, -2.0, -1.6, -4.8, -10.2, (2.5, 10.35), (12.5, 3.7))

    box("dune_plinth", 0.8, 1.15, 0.24, 27.0, 15.4, 0.30, basalt, bevel=0.025)
    box("dune_main_volume", 3.8, 1.8, 3.95, 16.8, 10.6, 7.30, sand, bevel=0.04)
    box("dune_east_stone_volume", 10.45, 1.1, 3.55, 4.3, 9.5, 6.50, stone, bevel=0.035)
    box("dune_stone_blade", -4.9, 0.55, 4.30, 2.35, 12.1, 8.05, stone, bevel=0.03)
    box("dune_garage_volume", -10.6, -1.15, 2.02, 8.1, 7.1, 3.48, limestone, bevel=0.035)
    box("dune_entry_link", -2.2, -2.65, 1.92, 5.2, 4.35, 3.28, sand, bevel=0.03)
    box("dune_floor_band", 3.8, 1.8, 3.82, 17.02, 10.82, 0.18, basalt)
    box("dune_blade_cap", -4.9, 0.55, 8.39, 2.58, 12.35, 0.14, basalt)
    _cottage_flat_roof(3.8, 1.8, 7.60, 16.8, 10.6, None, solar=True)
    _cottage_flat_roof(-10.6, -1.15, 3.76, 8.1, 7.1, limestone, solar=False)
    box("dune_link_roof", -2.2, -2.65, 3.66, 5.65, 4.80, 0.20, MATS["CottageBronze"])
    # A perimeter bronze frame enlarges the main roof shadow without
    # burying its solar/HVAC layer under a second full slab.
    for edge_y in (-4.18, 7.78):
        box("dune_flying_roof_edge", 3.8, edge_y, 8.03, 19.4, 0.48, 0.18, MATS["CottageBronze"])
    for edge_x in (-5.72, 13.32):
        box("dune_flying_roof_edge", edge_x, 1.8, 8.03, 0.48, 12.4, 0.18, MATS["CottageBronze"])
    _cottage_facade_seams(3.8, -3.50, 0.35, 16.6, 7.15, "front")
    _cottage_facade_seams(3.8, 7.10, 0.35, 16.6, 7.15, "back")
    _cottage_facade_seams(-4.62, 1.8, 0.35, 10.4, 7.15, "left")
    _cottage_facade_seams(12.62, 1.1, 0.35, 9.3, 6.35, "right")
    _cottage_louver(-4.9, -5.51, 5.70, 1.55, 2.55, "front", teak)
    _cottage_window(-4.9, -5.51, 1.95, 1.35, 2.45, "front", 0.0)

    # Front: deep shaded glass below, a teak-screened sleeping floor
    # above and the stone blade acting as a solar fin between them.
    _cottage_window(-0.8, -3.50, 1.82, 3.1, 2.65, "front", 0.18)
    _cottage_window(3.8, -3.50, 1.82, 3.4, 2.65, "front", 0.0)
    _cottage_window(8.7, -3.65, 1.82, 3.0, 2.65, "front", 0.34)
    _cottage_window(-0.8, -3.50, 5.72, 2.7, 2.25, "front", 0.42)
    _cottage_louver(4.3, -3.50, 5.72, 5.4, 2.35, "front", teak)
    _cottage_window(9.3, -3.65, 5.72, 2.5, 2.25, "front", 0.0)
    _cottage_balcony(4.0, -3.50, 4.08, 5.8, "front")
    _cottage_door(-1.6, -4.83, "front")
    _cottage_garage_door(-10.2, -4.70, 4.9, "front")
    _cottage_window(-13.7, -4.70, 2.05, 1.35, 1.65, "front", 0.25)

    # Rear and flanks are fully composed for cars passing either way.
    _cottage_window(-0.6, 7.10, 1.90, 3.4, 2.70, "back", 0.0)
    _cottage_window(4.2, 7.10, 1.90, 3.8, 2.70, "back", 0.22)
    _cottage_window(8.9, 5.85, 1.90, 2.8, 2.70, "back", 0.0)
    _cottage_window(0.4, 7.10, 5.72, 3.0, 2.25, "back", 0.38)
    _cottage_window(6.4, 7.10, 5.72, 3.4, 2.25, "back", 0.0)
    _cottage_balcony(4.4, 7.10, 4.08, 6.4, "back")
    _cottage_window(-4.62, -1.8, 5.65, 2.4, 2.0, "left", 0.0)
    _cottage_window(-4.62, 3.4, 2.05, 2.8, 2.3, "left", 0.30)
    _cottage_window(12.62, -1.2, 2.05, 3.0, 2.45, "right", 0.18)
    _cottage_window(12.62, 3.2, 5.55, 3.2, 2.1, "right", 0.0)
    _cottage_pergola(3.8, 8.35, 9.5, 2.1, 2.85, 0.30)
    _cottage_downspouts(((12.35, -3.75), (12.35, 6.0), (-6.25, 6.75)), 7.55)


def build_cottage_courtyard():
    """No.11: U-shaped mashrabiya courtyard house with a barjeel tower."""
    sand = MATS["CottageSand"]
    stone = MATS["CottageTravertine"]
    limestone = MATS["CottageLimestone"]
    basalt = MATS["CottageBasalt"]
    _build_cottage_site(5.8, 0.0, 0.0, -4.35, 10.0, (15.05, 6.8), (3.15, 9.6))

    box("courtyard_plinth", 0.0, 1.9, 0.24, 27.5, 16.8, 0.30, basalt, bevel=0.025)
    box("courtyard_west_wing", -9.7, 2.0, 3.42, 6.7, 13.0, 6.28, sand, bevel=0.04)
    box("courtyard_east_wing", 9.7, 2.0, 3.42, 6.7, 13.0, 6.28, sand, bevel=0.04)
    box("courtyard_rear_wing", 0.0, 7.15, 3.88, 14.8, 6.1, 7.20, limestone, bevel=0.04)
    box("courtyard_front_screen_west", -4.15, -4.28, 3.22, 4.0, 0.72, 5.88, stone, bevel=0.025)
    box("courtyard_front_screen_east", 4.15, -4.28, 3.22, 4.0, 0.72, 5.88, stone, bevel=0.025)
    box("courtyard_portal_beam", 0.0, -4.28, 5.94, 4.55, 0.78, 0.58, basalt)
    for sx in (-2.10, 2.10):
        box("courtyard_portal_column", sx, -4.28, 2.92, 0.52, 0.62, 5.28, stone)
        box("courtyard_portal_light", sx, -4.65, 2.92, 0.075, 0.030, 2.25, MATS["CottageLight"])
    _cottage_mashrabiya(-4.15, -4.65, 3.35, 3.15, 4.65, "front")
    _cottage_mashrabiya(4.15, -4.65, 3.35, 3.15, 4.65, "front")
    _cottage_door(0.0, 4.08, "front")
    _cottage_flat_roof(-9.7, 2.0, 6.56, 6.7, 13.0, sand, solar=False)
    _cottage_flat_roof(9.7, 2.0, 6.56, 6.7, 13.0, sand, solar=True)
    _cottage_flat_roof(0.0, 7.15, 7.48, 14.8, 6.1, limestone, solar=False)

    # Modern cubic wind tower: screened crown, stepped cap and a narrow
    # light slot rather than a historical replica ornament.
    box("courtyard_barjeel", -7.9, 7.3, 5.55, 3.15, 3.15, 10.55, stone, bevel=0.035)
    box("courtyard_barjeel_band", -7.9, 7.3, 7.72, 3.34, 3.34, 0.20, basalt)
    _cottage_mashrabiya(-7.9, 5.71, 9.35, 2.15, 2.05, "front")
    _cottage_mashrabiya(-7.9, 8.89, 9.35, 2.15, 2.05, "back")
    _cottage_mashrabiya(-9.49, 7.3, 9.35, 2.15, 2.05, "left")
    _cottage_mashrabiya(-6.31, 7.3, 9.35, 2.15, 2.05, "right")
    box("courtyard_barjeel_cap_slab", -7.9, 7.3, 10.93, 3.52, 3.52, 0.18, MATS["CottageBronze"])
    box("courtyard_barjeel_cap_step", -7.9, 7.3, 11.17, 2.55, 2.55, 0.30, basalt)
    box("courtyard_barjeel_cap_finial", -7.9, 7.3, 11.48, 0.72, 0.72, 0.32, MATS["CottageBronze"])
    box("courtyard_barjeel_light", -7.9, 5.69, 3.65, 0.075, 0.030, 5.1, MATS["CottageLight"])
    _cottage_facade_seams(-9.7, -4.52, 0.35, 6.5, 6.1, "front")
    _cottage_facade_seams(9.7, -4.52, 0.35, 6.5, 6.1, "front")
    _cottage_facade_seams(-13.07, 2.0, 0.35, 12.8, 6.1, "left")
    _cottage_facade_seams(13.07, 2.0, 0.35, 12.8, 6.1, "right")
    _cottage_facade_seams(0.0, 10.22, 0.35, 14.6, 7.0, "back")
    _cottage_mashrabiya(-13.07, -2.4, 5.05, 2.6, 1.75, "left")
    _cottage_mashrabiya(13.07, -2.4, 5.05, 2.6, 1.75, "right")

    # Exterior courtyard room: fountain, paving medallion and pergola.
    cyl("courtyard_paving_medallion", 0.0, 1.35, 0.42, 3.05, 0.10, stone, vertices=20)
    cyl("courtyard_fountain_basin", 0.0, 1.35, 0.62, 1.52, 0.48, basalt, vertices=16)
    cyl("courtyard_fountain_water", 0.0, 1.35, 0.86, 1.32, 0.055, MATS["CottageWater"], vertices=16)
    cyl("courtyard_fountain_column", 0.0, 1.35, 1.13, 0.17, 0.62, MATS["CottageBronze"], vertices=12)
    sphere("courtyard_fountain_sphere", 0.0, 1.35, 1.55, 0.52, 0.52, 0.52, stone, segments=14, ring_count=10)
    _cottage_pergola(0.0, -1.15, 8.6, 3.2, 3.05, 0.34)
    _cottage_planter(-5.15, 3.6, 1.15, 4.4, 0.52)
    _cottage_planter(5.15, 3.6, 1.15, 4.4, 0.52)

    _cottage_window(-9.7, -4.52, 2.05, 3.1, 2.5, "front", 0.22)
    _cottage_window(-9.7, -4.52, 5.20, 2.6, 1.9, "front", 0.0)
    _cottage_garage_door(10.0, -4.52, 4.7, "front")
    _cottage_window(9.7, -4.52, 5.20, 2.6, 1.9, "front", 0.36)
    _cottage_window(-6.33, -1.2, 2.15, 3.0, 2.55, "right", 0.0)
    _cottage_window(-6.33, 2.8, 5.20, 2.7, 1.9, "right", 0.28)
    _cottage_window(6.33, -1.2, 2.15, 3.0, 2.55, "left", 0.20)
    _cottage_window(6.33, 2.8, 5.20, 2.7, 1.9, "left", 0.0)
    _cottage_window(-13.07, 0.6, 2.15, 3.4, 2.5, "left", 0.18)
    _cottage_window(-13.07, 5.0, 5.20, 2.8, 1.9, "left", 0.0)
    _cottage_window(13.07, 0.6, 2.15, 3.4, 2.5, "right", 0.0)
    _cottage_window(13.07, 5.0, 5.20, 2.8, 1.9, "right", 0.34)
    _cottage_window(-4.2, 10.22, 2.10, 3.2, 2.55, "back", 0.24)
    _cottage_window(0.4, 10.22, 2.10, 3.4, 2.55, "back", 0.0)
    _cottage_window(4.8, 10.22, 5.65, 3.2, 2.05, "back", 0.40)
    _cottage_downspouts(((-13.2, -4.3), (13.2, -4.3), (-7.6, 10.35), (7.6, 10.35)), 6.55)


def build_cottage_palm():
    """No.12: two metal-roofed resort pavilions around a shaded veranda."""
    sand = MATS["CottageSand"]
    limestone = MATS["CottageLimestone"]
    basalt = MATS["CottageBasalt"]
    bronze = MATS["CottageBronze"]
    roof_metal = MATS["CottageRoofMetal"]
    teak = MATS["CottageTeak"]
    _build_cottage_site(8.0, 1.0, 1.0, -4.05, 9.1, (-1.5, 10.25), (15.5, 3.9))

    box("palm_plinth", 0.9, 1.0, 0.24, 28.5, 15.8, 0.30, basalt, bevel=0.025)
    box("palm_west_pavilion", -6.4, 1.0, 3.00, 13.0, 10.0, 5.42, sand, bevel=0.04)
    box("palm_east_pavilion", 8.6, 0.55, 2.78, 9.2, 8.6, 4.98, limestone, bevel=0.04)
    box("palm_glass_link", 1.0, -1.05, 2.00, 5.0, 5.9, 3.42, MATS["CottageCore"], bevel=0.025)
    box("palm_chimney_blade", -13.35, 2.2, 4.45, 1.55, 4.7, 8.35, basalt, bevel=0.025)
    box("palm_chimney_cap", -13.35, 2.2, 8.72, 1.82, 4.95, 0.18, bronze)

    gable_roof("palm_west_roof", -6.4, 1.0, 6.82, 14.3, 11.7, 2.25, roof_metal, ridge_axis="x")
    box("palm_west_ridge", -6.4, 1.0, 7.99, 14.42, 0.28, 0.12, bronze)
    gable_roof("palm_east_roof", 8.6, 0.55, 6.28, 10.4, 10.1, 2.02, roof_metal, ridge_axis="x")
    box("palm_east_ridge", 8.6, 0.55, 7.34, 10.52, 0.28, 0.12, bronze)
    box("palm_link_roof", 1.0, -1.05, 3.83, 5.55, 6.45, 0.22, bronze)
    for roof_x, roof_y, roof_z, slope in ((-8.8, -1.55, 6.99, -1.0), (-3.9, 3.55, 6.99, 1.0), (8.6, -1.75, 6.43, -1.0)):
        rbox("palm_skylight", roof_x, roof_y, roof_z, 1.65, 1.10, 0.10, MATS["CottageGlass"], rotation=(math.radians(21.0 * slope), 0.0, 0.0))
        rbox("palm_skylight_frame", roof_x, roof_y, roof_z - 0.035, 1.82, 1.26, 0.055, bronze, rotation=(math.radians(21.0 * slope), 0.0, 0.0))
    # Exposed rafter tails and continuous gutters make the low roofs
    # read as construction rather than two coloured prisms.
    for x in range(-13, 1):
        box("palm_rafter_tail", float(x) + 0.2, -4.62, 5.63, 0.11, 0.72, 0.13, teak)
        box("palm_rafter_tail", float(x) + 0.2, 6.62, 5.63, 0.11, 0.72, 0.13, teak)
    for y in (-4.98, 6.98):
        cyl("palm_gutter", -6.4, y, 5.72, 0.075, 14.1, bronze, vertices=8, rotation=(0.0, math.radians(90.0), 0.0))

    # Deep front and rear verandas with slim columns and teak soffit slats.
    for vy, face in ((-5.95, "front"), (7.25, "back")):
        box("palm_veranda_floor", -3.0, vy + (0.95 if face == "front" else -0.95), 0.34, 18.5, 2.25, 0.16, teak)
        box("palm_veranda_roof", -3.0, vy, 3.42, 18.8, 2.55, 0.16, bronze)
        for vx in (-11.8, -7.4, -3.0, 1.4, 5.8):
            cyl("palm_veranda_column", vx, vy, 1.86, 0.075, 3.05, bronze, vertices=10)
        for index in range(24):
            box("palm_veranda_soffit_slat", -12.0 + index * 0.78, vy, 3.30, 0.10, 2.38, 0.035, teak)

    _cottage_facade_seams(-6.4, -4.02, 0.35, 12.8, 5.25, "front")
    _cottage_facade_seams(-6.4, 6.02, 0.35, 12.8, 5.25, "back")
    _cottage_facade_seams(8.6, -3.77, 0.35, 9.0, 4.8, "front")
    _cottage_facade_seams(8.6, 4.87, 0.35, 9.0, 4.8, "back")
    _cottage_facade_seams(-12.92, 1.0, 0.35, 9.8, 5.25, "left")
    _cottage_facade_seams(13.22, 0.55, 0.35, 8.4, 4.8, "right")
    _cottage_window(-9.8, -4.02, 2.05, 3.3, 2.65, "front", 0.0)
    _cottage_window(-4.7, -4.02, 2.05, 3.4, 2.65, "front", 0.26)
    _cottage_window(-7.2, -4.02, 4.72, 4.8, 1.35, "front", 0.42)
    _cottage_door(1.0, -4.02, "front")
    _cottage_window(5.9, -3.77, 2.00, 2.25, 2.45, "front", 0.20)
    _cottage_garage_door(9.1, -3.77, 4.65, "front")
    _cottage_window(-9.4, 6.02, 2.05, 3.5, 2.65, "back", 0.22)
    _cottage_window(-4.2, 6.02, 2.05, 3.7, 2.65, "back", 0.0)
    _cottage_window(1.0, 1.92, 2.02, 3.7, 2.72, "back", 0.34)
    _cottage_window(8.6, 4.87, 2.00, 4.4, 2.45, "back", 0.0)
    _cottage_window(-12.92, -1.4, 2.25, 3.2, 2.55, "left", 0.18)
    _cottage_window(-12.92, 3.8, 4.55, 2.6, 1.45, "left", 0.0)
    _cottage_window(13.22, 0.4, 2.15, 3.4, 2.45, "right", 0.28)
    _cottage_window(13.22, 3.6, 4.35, 2.4, 1.35, "right", 0.0)

    # Outdoor fireplace is a black firebox in the basalt blade, with a
    # bronze lintel and stacked-log niche visible from the pool terrace.
    box("palm_fireplace_opening", -13.35, 4.61, 1.32, 1.05, 0.07, 1.28, MATS["CottageCore"])
    box("palm_fireplace_lintel", -13.35, 4.66, 2.06, 1.28, 0.09, 0.16, bronze)
    box("palm_fireplace_glow", -13.35, 4.67, 0.82, 0.62, 0.025, 0.16, MATS["CottageLight"])
    for log_index in range(4):
        cyl("palm_firewood", -12.35, 4.62, 0.55 + log_index * 0.16, 0.065, 0.78, teak, vertices=8, rotation=(0.0, math.radians(90.0), 0.0))
    _cottage_downspouts(((-13.2, -5.05), (0.35, -5.05), (-13.2, 7.05), (13.0, 5.05)), 5.65)




# --------------------------------------------------------------------------- #
# 0.3.2 low-poly Blender city set (user direction 30.10.2026).
#
# Every RichTown building/structure that used to be a stretched generic
# box or a GDScript primitive assembly gets a real fixed-scale Blender
# model at a "slightly above low" geometry budget: a few hundred to a
# few thousand triangles, flat semantic materials, readable silhouettes
# and signature details (balconies, dock doors, corrugation, jet
# bridges, hyperboloid shells).  The premium Building Models No.1-12
# above stay untouched; vegetation and ground tiles are out of scope.
# Front is Blender -Y, origin at ground centre, real metres.
# --------------------------------------------------------------------------- #


def _ct_lathe(name, profile, material, segments=32, scale_x=1.0):
    """Surface of revolution around Blender Z from [(radius, z), ...]."""
    b = MeshBuilder()
    rings = []
    for radius, z in profile:
        ring = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            ring.append(b.add_vertex(Vector((math.cos(a) * radius * scale_x, math.sin(a) * radius, z))))
        rings.append(ring)
    for r in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            b.quad(rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i])
    return b.build(name, material, smooth=True)


def build_school():
    plaster = MATS["TownPlaster"]
    stone = MATS["TownStone"]
    trim = MATS["TownTrim"]
    roof = MATS["TownRoof"]
    dark_glass = MATS["WindowGlassDark"]
    metal = MATS["PropsMetal"]
    field = MATS["CityFieldGreen"]
    white = MATS["CityWhitePaint"]
    red = MATS["CityAccentRed"]

    box("school_plinth", 0, 16, 0.25, 80, 60, 0.5, stone)
    box("school_main", 0, 16, 6.35, 64, 18, 12, plaster)
    box("school_main_roof", 0, 16, 12.85, 66, 20, 1.0, MATS["RoofDark"])
    for floor_z in (3.4, 6.9, 10.2):
        panel("school_win_front", 0, 6.67, floor_z, 57, 1.7, dark_glass, "front")
        panel("school_win_back", 0, 25.33, floor_z, 57, 1.7, dark_glass, "back")
        # 0.3.4: ribbon glazing reads as real classroom windows once
        # it is broken into bays; ten schools make this nearly free.
        for mullion_x in range(-24, 25, 6):
            box("school_win_mullion", mullion_x, 6.60, floor_z, 0.26, 0.18, 1.75, trim)
            box("school_win_mullion", mullion_x, 25.40, floor_z, 0.26, 0.18, 1.75, trim)
        # 0.3.13: head/sill rails close the ribbon glazing bands so
        # the glass sits inside a frame grid, not on the plaster.
        box("school_win_rail0313", 0, 6.55, floor_z + 0.98, 57.6, 0.24, 0.20, trim)
        box("school_win_rail0313", 0, 6.55, floor_z - 0.98, 57.6, 0.24, 0.20, trim)
        box("school_win_rail0313", 0, 25.45, floor_z + 0.98, 57.6, 0.24, 0.20, trim)
        box("school_win_rail0313", 0, 25.45, floor_z - 0.98, 57.6, 0.24, 0.20, trim)
    for wx in (-29.0, 29.0):
        box("school_wing", wx, 3, 4.85, 18, 26, 9, plaster)
        gable_roof("school_wing_roof", wx, 3, 11.1, 19.4, 27.4, 3.4, roof, ridge_axis="y")
        win_recess_0312("school_wing_win", wx, -10.0, 5.4, 12, 3.6, dark_glass, trim, "front", depth=0.33, frame_w=0.18)
    box("school_gym", 0, 34, 4.85, 34, 20, 9, stone)
    box("school_gym_roof", 0, 34, 9.8, 35.5, 21.5, 0.9, MATS["RoofDark"])
    win_recess_0312("school_gym_glass", 0, 24.0, 7.6, 30, 1.8, dark_glass, trim, "front", depth=0.33, frame_w=0.16)
    box("school_portal", 0, 6.4, 3.1, 13, 1.6, 6.2, trim)
    box("school_door", 0, 5.5, 2.2, 6.4, 0.4, 4.2, MATS["TownDoorAccent"])
    box("school_canopy", 0, 2.8, 5.6, 17, 6.4, 0.55, metal)
    for cx in (-7.2, 7.2):
        cyl("school_column", cx, 0.4, 2.8, 0.32, 5.6, metal, vertices=10)
    for si in range(3):
        box("school_step", 0, 3.2 - si * 0.9, 0.18 + si * 0.17, 14 - si * 1.2, 0.9, 0.36, stone)
    cyl("school_flagpole", 16, -2, 5.5, 0.14, 11, metal, vertices=8)
    # 0.3.9: name band over the portal and roof plant.
    box("school_sign", 0, 5.42, 5.1, 10.0, 0.25, 0.8, red)
    for hvac_x in (-18.0, 18.0):
        box("school_roof_hvac", hvac_x, 16, 13.75, 4.2, 2.4, 0.8, metal)
    box("school_flag", 17.6, -2, 10.0, 3.0, 0.08, 1.8, red)
    # Sports field on the front (-Y) side.
    box("school_field", 0, -24, 0.16, 76, 40, 0.32, field)
    box("school_line_mid", 0, -24, 0.36, 0.5, 38, 0.06, white)
    box("school_line_lr", 0, -42.8, 0.36, 72, 0.5, 0.06, white)
    box("school_line_lr", 0, -5.2, 0.36, 72, 0.5, 0.06, white)
    for gx in (-34.0, 34.0):
        box("school_goal", gx, -24, 1.4, 0.35, 7.4, 2.8, white)
    for fx in range(-36, 37, 8):
        cyl("school_fence", fx, -43.5, 0.9, 0.09, 1.8, metal, vertices=6)
        cyl("school_fence", fx, -4.5, 0.9, 0.09, 1.8, metal, vertices=6)


def build_airport_terminal():
    glass = MATS["FacadeGlass"]
    main = MATS["FacadeMain"]
    metal = MATS["TowerMetal"]
    dark = MATS["RoofDark"]
    blue = MATS["CityAccentBlue"]

    box("term_hall", 0, 0, 11, 380, 64, 22, main)
    panel("term_glass_upper", 0, -32.7, 14.5, 376, 11, glass, "front")
    panel("term_glass_lower", 0, -32.7, 3.4, 376, 6.4, glass, "front")
    panel("term_glass_airside", 0, 32.7, 12, 376, 14, glass, "back")
    # 0.3.13: transom rails tie the terminal glass bands to the hall.
    box("term_glass_rail0313", 0, -32.8, 20.15, 378.0, 0.4, 0.35, metal)
    box("term_glass_rail0313", 0, -32.8, 8.85, 378.0, 0.4, 0.35, metal)
    box("term_glass_rail0313", 0, -32.8, 6.75, 378.0, 0.4, 0.35, metal)
    box("term_glass_rail0313", 0, 32.8, 19.15, 378.0, 0.4, 0.35, metal)
    box("term_glass_rail0313", 0, 32.8, 4.85, 378.0, 0.4, 0.35, metal)
    box("term_stripe", 0, -32.75, 20.6, 380, 0.7, 2.2, blue)
    for i in range(21):
        fx = -180.0 + i * 18.0
        box("term_fin", fx, -32.8, 11, 1.1, 1.4, 21, metal)
    for slab_i, (sy, sang) in enumerate(((-26.0, -0.34), (-13.0, -0.17), (0.0, 0.0), (13.0, 0.17), (26.0, 0.34))):
        slab_z = 25.2 - abs(sy) * 0.115
        rbox("term_roof_slab", 0, sy, slab_z, 386, 15.5, 1.1, metal, rotation=(sang, 0, 0))
    box("term_skylight", 0, 0, 26.0, 300, 5, 0.5, glass)
    box("term_entrance", 0, -34.5, 2.6, 130, 5, 5.2, glass)
    for door_x in range(-52, 53, 13):
        box("term_door_mullion", door_x, -37.12, 2.6, 0.45, 0.25, 5.2, metal)
    for hvac_x in range(-150, 151, 50):
        box("term_roof_hvac", hvac_x, 8, 24.6, 10, 6, 1.8, dark)
    box("term_canopy", 0, -39, 8.4, 210, 12, 0.9, metal)
    for cx in range(-96, 97, 24):
        cyl("term_column", cx, -43.5, 4.2, 0.45, 8.4, metal, vertices=8)
    for fx in (-150.0, -50.0, 50.0, 150.0):
        box("term_finger", fx, 56, 6.5, 24, 48, 13, main)
        panel("term_finger_glass", fx - 12.65, 56, 8, 44, 5, glass, "left")
        panel("term_finger_glass", fx + 12.65, 56, 8, 44, 5, glass, "right")
        box("term_finger_roof", fx, 56, 13.6, 26, 50, 1.1, dark)
        box("term_finger_hvac", fx + 5, 48, 14.9, 7, 9, 1.6, dark)
        rbox("term_jetbridge", fx - 13.8, 66, 4.6, 3.2, 11, 3.4, metal, rotation=(0, 0, 0.5))
        rbox("term_jetbridge", fx + 13.8, 66, 4.6, 3.2, 11, 3.4, metal, rotation=(0, 0, -0.5))


def build_atc_tower():
    concrete = MATS["ConcreteLight"]
    glass = MATS["FacadeGlass"]
    metal = MATS["PropsMetal"]
    box("atc_base", 0, 0, 2.5, 15, 15, 5, MATS["FacadeAccent"])
    panel("atc_base_door", 0, -7.75, 1.8, 3.4, 3.4, MATS["WindowFrame"], "front")
    cone("atc_shaft", 0, 0, 22, 4.4, 2.9, 34, concrete, vertices=16)
    cyl("atc_collar", 0, 0, 39.4, 3.6, 1.6, metal, vertices=12)
    cyl("atc_cab", 0, 0, 43.2, 6.2, 4.6, glass, vertices=18)
    for i in range(10):
        a = 2.0 * math.pi * i / 10.0
        rbox("atc_mullion", math.cos(a) * 6.25, math.sin(a) * 6.25, 43.2, 0.35, 0.35, 4.6, metal, rotation=(0, 0, a))
    cone("atc_roof", 0, 0, 46.2, 7.1, 6.2, 1.2, metal, vertices=14)
    cyl("atc_antenna", 0, 0, 50.2, 0.16, 7, metal, vertices=8)
    box("atc_beacon", 0, 0, 47.3, 0.7, 0.7, 0.7, MATS["CityAccentRed"])
    # 0.3.10: base window band (was a blank plinth face).
    panel("atc_base_windows", 0, -7.56, 3.6, 9.0, 1.1, glass, "front")


def _build_hangar(width, length, wall_h, roof_h):
    clad = MATS["PropsMetal"]
    concrete = MATS["ConcreteLight"]
    dark = MATS["RoofDark"]
    frame = MATS["WindowFrame"]
    glass = MATS["FacadeGlass"]
    box("hangar_base", 0, 0, 1.5, width, length, 3.0, concrete)
    box("hangar_walls", 0, 0, 3.0 + (wall_h - 3.0) / 2.0, width, length, wall_h - 3.0, clad)
    gable_roof("hangar_roof", 0, 0, wall_h + roof_h / 2.0, width + 1.6, length + 1.6, roof_h, dark, ridge_axis="y")
    door_y = -length / 2.0 - 0.35
    box("hangar_door", 0, door_y, wall_h * 0.42, width * 0.74, 0.6, wall_h * 0.8, frame)
    for rail_z in (0.22, 0.48, 0.74):
        panel("hangar_door_rail", 0, door_y - 0.375, wall_h * rail_z, width * 0.74, 0.35, clad, "front")
    panel("hangar_door_seam", 0, door_y - 0.42, wall_h * 0.42, 0.4, wall_h * 0.8, clad, "front")
    for seam_x in (-0.30, -0.15, 0.15, 0.30):
        panel("hangar_door_leaf", width * seam_x, door_y - 0.46, wall_h * 0.42, 0.28, wall_h * 0.8, clad, "front")
    box("hangar_skylight", 0, 0, wall_h + roof_h + 0.02, 2.2, length * 0.70, 0.18, glass)
    for sx in (-1.0, 1.0):
        panel("hangar_side_glass", sx * (width / 2.0 + 0.355), 0, wall_h * 0.72, length * 0.66, 1.7, glass, "right" if sx > 0.0 else "left")
        box("hangar_personnel", sx * (width / 2.0 + 0.2), -length * 0.3, 1.6, 0.35, 2.2, 3.2, frame)
        box("hangar_side_vent", sx * (width / 2.0 + 0.20), length * 0.28, wall_h * 0.45, 0.30, 3.2, 1.4, frame)
    for vy in (-length * 0.28, 0.0, length * 0.28):
        cyl("hangar_vent", 0, vy, wall_h + roof_h - 0.4, 1.05, 1.6, clad, vertices=8)
    # 0.3.14: portal surround around the sliding door + rails edging the
    # side glazing band so neither reads as pasted-on planes.
    for post_x in (-(width * 0.37 + 0.35), width * 0.37 + 0.35):
        box("hangar_door_post0314", post_x, door_y, wall_h * 0.42, 0.7, 0.7, wall_h * 0.84, frame)
    box("hangar_door_header0314", 0, door_y, wall_h * 0.82 + 0.35, width * 0.74 + 2.1, 0.7, 0.7, frame)
    for sx in (-1.0, 1.0):
        for rail_z in (wall_h * 0.72 - 0.95, wall_h * 0.72 + 0.95):
            box("hangar_glass_rail0314", sx * (width / 2.0 + 0.20), 0, rail_z, 0.3, length * 0.66, 0.22, clad)


def build_hangar_large():
    _build_hangar(44.0, 57.0, 9.9, 6.1)


def build_hangar_small():
    _build_hangar(30.0, 39.0, 6.8, 4.2)



def _yacht_hull(name, length, beam, freeboard, material):
    """0.3.11 lofted planing/sailing hull: five-point sections from a
    flat transom stern (+Y) to a fine bow (-Y), deck-capped.  Keel
    line at z=0 so the model origin sits on the basin floor grid and
    placement Y handles the draft."""
    sections = [
        (0.50, 0.46, 1.00),
        (0.30, 0.50, 0.97),
        (0.05, 0.50, 0.95),
        (-0.22, 0.44, 0.98),
        (-0.40, 0.28, 1.06),
        (-0.50, 0.02, 1.16),
    ]
    b = MeshBuilder()
    rings = []
    for yf, hf, sf in sections:
        y = yf * length
        hb = hf * beam
        ring = [
            b.add_vertex(Vector((-hb, y, freeboard * sf))),
            b.add_vertex(Vector((-hb * 0.88, y, freeboard * 0.38))),
            b.add_vertex(Vector((0.0, y, 0.0))),
            b.add_vertex(Vector((hb * 0.88, y, freeboard * 0.38))),
            b.add_vertex(Vector((hb, y, freeboard * sf))),
        ]
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, c = rings[i], rings[i + 1]
        for j in range(4):
            b.quad(c[j], a[j], a[j + 1], c[j + 1])
        b.quad(c[4], a[4], a[0], c[0])
    r0 = rings[0]
    b.add_face((r0[4], r0[3], r0[2], r0[1], r0[0]),
               ((0.0, 1.0), (0.2, 0.4), (0.5, 0.0), (0.8, 0.4), (1.0, 1.0)))
    return b.build(name, material, smooth=True)


def _yacht_portholes(prefix, length, beam, freeboard, ys, material):
    for sx in (-1.0, 1.0):
        for i, yf in enumerate(ys):
            hb = beam * (0.50 if abs(yf) < 0.3 else 0.44)
            box(f"{prefix}_porthole_{int(sx)}_{i}", sx * (hb * 0.995), yf * length,
                freeboard * 0.72, 0.08, 0.55, 0.28, material)


def build_yacht_sail():
    white = MATS["CityWhitePaint"]
    glass = MATS["WindowGlassDark"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]

    _yacht_hull("ys_hull", 11.5, 3.4, 1.05, white)
    box("ys_coachroof", 0, 0.4, 1.28, 1.9, 3.4, 0.5, white)
    box("ys_coachglass", 0, 0.35, 1.32, 1.98, 2.6, 0.26, glass)
    box("ys_cockpit", 0, 3.1, 1.06, 1.7, 2.2, 0.22, dark)
    box("ys_swimstep", 0, 5.95, 0.42, 2.2, 0.5, 0.12, white)
    box("ys_bowroller", 0, -5.8, 1.24, 0.3, 0.7, 0.14, metal)
    cyl("ys_mast", 0, -0.8, 7.6, 0.09, 13.2, metal, vertices=6)
    cyl("ys_boom", 0, 1.1, 2.6, 0.07, 3.9, metal, vertices=6,
        rotation=(math.radians(90), 0, 0))
    sails = MeshBuilder()
    tack = sails.add_vertex(Vector((0.0, -0.75, 2.75)))
    head = sails.add_vertex(Vector((0.0, -0.75, 13.6)))
    clew = sails.add_vertex(Vector((0.0, 3.0, 2.75)))
    sails.tri(tack, head, clew)
    sails.tri(tack, clew, head)
    jib_tack = sails.add_vertex(Vector((0.0, -5.45, 1.35)))
    jib_head = sails.add_vertex(Vector((0.0, -0.85, 12.2)))
    jib_clew = sails.add_vertex(Vector((0.0, -0.55, 2.9)))
    sails.tri(jib_tack, jib_head, jib_clew)
    sails.tri(jib_tack, jib_clew, jib_head)
    sails.build("ys_sails", white, smooth=False)
    tube_between("ys_forestay", (0.0, -5.45, 1.4), (0.0, -0.82, 13.9), 0.025, 0.025, metal, vertices=4)
    tube_between("ys_backstay", (0.0, 5.2, 1.15), (0.0, -0.82, 13.9), 0.025, 0.025, metal, vertices=4)
    _yacht_portholes("ys", 11.5, 3.4, 1.05, (-0.18, 0.02, 0.22), glass)


def build_yacht_motor():
    white = MATS["CityWhitePaint"]
    glass = MATS["WindowGlassDark"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]

    _yacht_hull("ym_hull", 13.5, 4.3, 1.35, white)
    box("ym_salon", 0, 0.7, 2.15, 3.5, 5.6, 1.5, white)
    box("ym_salon_glass", 0, 0.45, 2.35, 3.58, 4.7, 0.62, glass)
    rbox("ym_windshield", 0, -2.35, 2.5, 3.1, 0.18, 0.95, glass,
         rotation=(math.radians(-24), 0, 0))
    box("ym_flybridge", 0, 1.15, 3.35, 3.0, 3.4, 0.85, white)
    rbox("ym_fly_glass", 0, -0.55, 3.6, 2.7, 0.16, 0.7, glass,
         rotation=(math.radians(-24), 0, 0))
    box("ym_hardtop", 0, 1.3, 4.05, 3.3, 3.9, 0.16, white)
    for sx in (-1.0, 1.0):
        rbox("ym_arch_post", sx * 1.45, 2.9, 3.5, 0.22, 0.5, 1.5, white,
             rotation=(math.radians(18), 0, 0))
        box("ym_exhaust", sx * 1.6, 6.55, 0.85, 0.5, 0.4, 0.35, dark)
    box("ym_arch_top", 0, 3.35, 4.3, 3.1, 0.5, 0.22, white)
    box("ym_radar", 0, 3.35, 4.52, 0.9, 0.45, 0.22, dark)
    box("ym_sunpad", 0, -3.6, 1.5, 2.2, 2.0, 0.22, dark)
    box("ym_swimplatform", 0, 7.05, 0.55, 3.6, 0.8, 0.14, white)
    box("ym_windlass", 0, -5.6, 1.5, 0.55, 0.7, 0.3, metal)
    _yacht_portholes("ym", 13.5, 4.3, 1.35, (-0.24, -0.06, 0.12, 0.3), glass)


def build_airliner():
    white = MATS["CityWhitePaint"]
    blue = MATS["CityAccentBlue"]
    metal = MATS["PropsMetal"]
    frame = MATS["WindowFrame"]
    dark = MATS["RoofDark"]

    cyl("plane_fuselage", 0, 0.5, 4.4, 2.1, 33, white, vertices=16, rotation=(math.radians(90), 0, 0))
    nose = cone("plane_nose", 0, -19.2, 4.4, 2.1, 0.4, 6.4, white, vertices=16)
    nose.rotation_euler = (math.radians(90), 0, 0)
    tail = cone("plane_tailcone", 0, 19.6, 5.1, 0.5, 2.05, 6.0, white, vertices=16)
    tail.rotation_euler = (math.radians(90), 0, 0)
    rbox("plane_cockpit", 0, -17.6, 5.75, 2.7, 2.4, 0.8, MATS["WindowGlassDark"], rotation=(math.radians(-32), 0, 0))
    for sx in (-1.0, 1.0):
        box("plane_stripe", sx * 1.98, 0.5, 5.15, 0.1, 28, 0.85, blue)
        rbox("plane_wing", sx * 9.6, 2.4, 3.75, 19, 4.4, 0.42, metal, rotation=(0, 0, sx * 0.40))
        rbox("plane_winglet", sx * 18.4, 6.1, 4.6, 0.35, 2.2, 1.9, blue, rotation=(0, 0, sx * 0.40))
        cyl("plane_engine", sx * 6.8, -0.8, 2.65, 1.05, 4.6, white, vertices=10, rotation=(math.radians(90), 0, 0))
        cyl("plane_intake", sx * 6.8, -3.15, 2.65, 0.88, 0.35, frame, vertices=10, rotation=(math.radians(90), 0, 0))
        box("plane_pylon", sx * 6.8, -0.4, 3.6, 0.4, 2.6, 1.1, metal)
        rbox("plane_tailplane", sx * 3.4, 19.8, 6.3, 7.5, 2.6, 0.35, metal, rotation=(0, 0, sx * 0.35))
        cyl("plane_gear_leg", sx * 2.3, 2.5, 1.35, 0.3, 2.5, metal, vertices=8)
        box("plane_gear_bogie", sx * 2.3, 2.5, 0.5, 0.65, 2.4, 0.9, dark)
    box("plane_fin", 0, 18.2, 8.9, 0.45, 6.4, 6.6, blue)
    rbox("plane_fin_sweep", 0, 15.6, 7.0, 0.45, 4.4, 3.4, blue, rotation=(math.radians(-38), 0, 0))
    cyl("plane_gear_nose", 0, -13, 1.35, 0.26, 2.5, metal, vertices=8)
    box("plane_gear_nosewheel", 0, -13, 0.45, 0.5, 1.1, 0.85, dark)
    box("plane_apu", 0, 21.8, 5.4, 1.1, 1.6, 1.0, metal)


def build_cooling_tower():
    concrete = MATS["ConcreteLight"]
    profile = [
        (39.0, 8.0), (36.0, 18.0), (31.0, 36.0), (27.5, 55.0),
        (26.2, 71.0), (26.8, 83.0), (28.5, 92.5), (29.6, 95.5), (30.4, 98.0),
    ]
    _ct_lathe("cooling_shell", profile, concrete, segments=36)
    cyl("cooling_throat", 0, 0, 91.5, 26.5, 1.2, MATS["WindowFrame"], vertices=24)
    cyl("cooling_basin", 0, 0, 0.6, 42.0, 1.2, concrete, vertices=28)
    cyl("cooling_ring_beam", 0, 0, 8.6, 38.8, 1.6, concrete, vertices=28)
    for i in range(16):
        a = 2.0 * math.pi * i / 16.0
        cx = math.cos(a) * 38.2
        cy = math.sin(a) * 38.2
        rbox("cooling_column", cx, cy, 4.6, 1.1, 1.1, 7.6, concrete, rotation=(0.42, 0, a))
        rbox("cooling_column_b", cx, cy, 4.6, 1.1, 1.1, 7.6, concrete, rotation=(-0.42, 0, a))


def build_reactor():
    concrete = MATS["ConcreteLight"]
    metal = MATS["PropsMetal"]
    cyl("reactor_block", 0, 0, 15, 22, 30, concrete, vertices=22)
    cyl("reactor_ring", 0, 0, 30.4, 23, 1.8, metal, vertices=22)
    sphere("reactor_dome", 0, 0, 31.5, 44, 44, 19, MATS["CityWhitePaint"], segments=20, ring_count=12)
    cyl("reactor_vent", -15, 9, 35, 1.6, 13, metal, vertices=10)
    box("reactor_aux", 33.5, 0, 6.5, 19, 17, 13, MATS["FacadeAccent"])
    box("reactor_aux_roof", 33.5, 0, 13.5, 20, 18, 0.9, MATS["RoofDark"])
    panel("reactor_aux_glass", 33.5, -8.85, 8.5, 15, 3.4, MATS["WindowGlassDark"], "front")
    tube_between("reactor_pipe_a", (19, -3, 19), (26, -3, 12), 1.15, 1.15, metal, vertices=10)
    tube_between("reactor_pipe_b", (19, 4, 15), (26, 4, 9), 0.9, 0.9, metal, vertices=10)
    cyl("reactor_tank_small", 12, -19, 4, 4.5, 8, metal, vertices=12)


def build_chimney():
    concrete = MATS["ConcreteLight"]
    cyl("chimney_plinth", 0, 0, 1, 9.5, 2, concrete, vertices=16)
    cone("chimney_stack", 0, 0, 65, 7.2, 4.0, 130, concrete, vertices=16)
    for band_z in (78.0, 99.0, 119.0):
        band_r = 7.2 - 3.2 * (band_z / 130.0)
        cyl("chimney_band", 0, 0, band_z, band_r * 1.04, 7.5, MATS["CityAccentRed"], vertices=16)
    cyl("chimney_rim", 0, 0, 129.6, 4.35, 1.4, MATS["WindowFrame"], vertices=16)
    box("chimney_beacon", 0, 0, 131.0, 0.8, 0.8, 0.8, MATS["CityAccentRed"])


def build_radar_station():
    cyl("radar_base", 0, 0, 4, 5, 8, MATS["ConcreteLight"], vertices=16)
    sphere("radar_dome", 0, 0, 10.5, 18, 18, 15, MATS["CityWhitePaint"], segments=18, ring_count=12)
    box("radar_hut", 11.5, 0, 1.75, 9, 6, 3.5, MATS["FacadeMain"])
    box("radar_hut_roof", 11.5, 0, 3.8, 9.6, 6.6, 0.5, MATS["RoofDark"])
    panel("radar_hut_door", 11.5, -3.225, 1.5, 1.6, 2.8, MATS["WindowFrame"], "front")
    cyl("radar_mast", 13.5, 1.5, 8, 0.14, 9, MATS["PropsMetal"], vertices=8)


def build_watchtower():
    wood = MATS["PropsWood"]
    glass = MATS["FacadeGlass"]
    for sx in (-1.6, 1.6):
        for sy in (-1.6, 1.6):
            rbox("watch_leg", sx, sy, 5.3, 0.38, 0.38, 10.4, wood,
                 rotation=(0.10 * (1 if sy > 0 else -1), 0.10 * (1 if sx < 0 else -1), 0))
    for brace_z, brace_ang in ((3.4, 0.78), (7.4, -0.78)):
        rbox("watch_brace", 0, -1.85, brace_z, 0.22, 0.22, 5.4, wood, rotation=(0, brace_ang, 0))
        rbox("watch_brace", 0, 1.85, brace_z, 0.22, 0.22, 5.4, wood, rotation=(0, -brace_ang, 0))
    box("watch_platform", 0, 0, 10.3, 5.2, 5.2, 0.4, wood)
    box("watch_cab", 0, 0, 11.9, 4.6, 4.6, 2.8, wood)
    box("watch_glass", 0, 0, 12.55, 4.85, 4.85, 1.0, glass)
    gable_roof("watch_roof", 0, 0, 14.1, 5.9, 5.9, 1.7, MATS["TownRoof"], ridge_axis="x")
    for rx in (-0.55, 0.55):
        box("watch_ladder_rail", rx, -2.05, 5.1, 0.14, 0.14, 10.2, MATS["PropsMetal"])
    for rung in range(7):
        box("watch_ladder_rung", 0, -2.05, 1.2 + rung * 1.35, 1.15, 0.12, 0.12, MATS["PropsMetal"])
    # 0.3.10: platform guard railing (was an open deck edge).
    for rail_side in (-1.0, 1.0):
        box("watch_rail_top", 0, rail_side * 2.45, 11.45, 5.0, 0.09, 0.09, wood)
        box("watch_rail_top", rail_side * 2.45, 0, 11.45, 0.09, 5.0, 0.09, wood)
    for post_x in (-2.45, 2.45):
        for post_y in (-2.45, 2.45):
            box("watch_rail_post", post_x, post_y, 10.95, 0.09, 0.09, 0.95, wood)


def build_storage_tank():
    white = MATS["CityWhitePaint"]
    metal = MATS["PropsMetal"]
    cyl("tank_base", 0, 0, 0.4, 11.7, 0.8, MATS["ConcreteLight"], vertices=20)
    cyl("tank_shell", 0, 0, 6.3, 11, 11, white, vertices=20)
    sphere("tank_roof", 0, 0, 11.6, 22.4, 22.4, 5.2, metal, segments=18, ring_count=10)
    cyl("tank_hatch", 0, 0, 14.0, 1.6, 0.9, metal, vertices=10)
    cyl("tank_pipe", 11.3, 0, 5.5, 0.5, 11, metal, vertices=8)
    box("tank_valve", 11.6, 0, 1.2, 1.1, 1.1, 1.4, MATS["CityAccentRed"])
    box("tank_ladder", 0, -11.15, 5.8, 0.9, 0.25, 11, metal)


def build_silo():
    metal = MATS["PropsMetal"]
    cyl("silo_body", 0, 0, 7, 6, 14, MATS["CityWhitePaint"], vertices=12)
    cone("silo_roof", 0, 0, 15.7, 6.45, 0.7, 3.4, metal, vertices=12)
    cyl("silo_pipe", 0, 0, 17.9, 0.55, 1.2, metal, vertices=8)
    box("silo_chute", 0, -6.5, 5, 1.4, 1.2, 9, metal)
    cyl("silo_base", 0, 0, 0.35, 6.5, 0.7, MATS["ConcreteLight"], vertices=12)


def build_afv():
    green = MATS["CityArmyGreen"]
    dark = MATS["RoofDark"]
    metal = MATS["PropsMetal"]
    box("afv_hull", 0, 0, 1.55, 3.4, 7.2, 1.15, green)
    rbox("afv_glacis", 0, -3.55, 1.45, 3.3, 2.0, 0.5, green, rotation=(math.radians(52), 0, 0))
    rbox("afv_rear", 0, 3.6, 1.5, 3.3, 1.4, 0.45, green, rotation=(math.radians(-40), 0, 0))
    for sx in (-1.35, 1.35):
        box("afv_track", sx, 0, 0.62, 1.05, 7.7, 1.15, dark)
        box("afv_skirt", sx * 1.444, 0, 1.25, 0.18, 7.3, 0.75, green)
        for wy in (-2.9, -1.45, 0.0, 1.45, 2.9):
            cyl("afv_wheel", sx * 1.274, wy, 0.56, 0.53, 0.3, green, vertices=8, rotation=(0, math.radians(90), 0))
    box("afv_turret", 0, 0.55, 2.6, 2.35, 3.2, 0.95, green)
    rbox("afv_turret_front", 0, -1.15, 2.55, 2.2, 1.2, 0.8, green, rotation=(math.radians(38), 0, 0))
    cyl("afv_barrel", 0, -3.6, 2.72, 0.16, 4.8, metal, vertices=8, rotation=(math.radians(90), 0, 0))
    cyl("afv_muzzle", 0, -5.6, 2.72, 0.25, 0.8, dark, vertices=8, rotation=(math.radians(90), 0, 0))
    cyl("afv_hatch", -0.55, 0.6, 3.2, 0.55, 0.28, green, vertices=8)
    cyl("afv_antenna", 0.85, 1.9, 4.4, 0.035, 2.8, dark, vertices=6)
    box("afv_stowage", 0, 2.35, 2.45, 2.1, 0.9, 0.7, dark)
    for hx in (-1.15, 1.15):
        box("afv_headlight", hx, -4.15, 1.75, 0.42, 0.2, 0.3, MATS["LampGlow"])


def build_stadium():
    concrete = MATS["ConcreteLight"]
    metal = MATS["PropsMetal"]
    seats = MATS["CityAccentRed"]
    pitch = MATS["CityFieldGreen"]
    white = MATS["CityWhitePaint"]
    sx = 150.0 / 127.0
    profile = [
        (127.0, 0.0), (127.0, 26.0), (125.0, 34.0), (120.0, 40.0), (114.0, 42.5),
        (106.0, 41.0), (96.0, 35.0), (84.0, 29.0), (71.0, 23.0), (58.0, 17.0),
        (47.0, 11.0), (40.0, 5.0),
    ]
    _ct_lathe("stadium_bowl", profile, concrete, segments=36, scale_x=sx)
    seat_profile = [(103.0, 40.4), (93.0, 34.4), (81.0, 28.4), (68.0, 22.4), (55.0, 16.4), (44.0, 10.4)]
    _ct_lathe("stadium_seats", seat_profile, seats, segments=36, scale_x=sx)
    roof_profile = [(106.0, 43.6), (109.0, 45.6), (130.0, 43.6), (130.5, 41.2), (126.0, 40.6), (108.0, 42.2)]
    _ct_lathe("stadium_roof", roof_profile, metal, segments=36, scale_x=sx)
    for i in range(36):
        a = 2.0 * math.pi * i / 36.0
        rbox("stadium_rib", math.cos(a) * 150.2, math.sin(a) * 127.2, 17.5, 2.8, 2.4, 35.0, concrete, rotation=(0, 0, a))
    for portal_i in range(8):
        portal_a = 2.0 * math.pi * portal_i / 8.0
        rbox("stadium_portal", math.cos(portal_a) * 150.8, math.sin(portal_a) * 127.8, 5.0, 9.0, 2.5, 10.0, MATS["WindowFrame"], rotation=(0, 0, portal_a))
    box("stadium_pitch", 0, 0, 0.18, 112, 72, 0.36, pitch)
    box("stadium_line_mid", 0, 0, 0.4, 0.5, 68, 0.06, white)
    box("stadium_line_box", -44, 0, 0.4, 0.5, 40, 0.06, white)
    box("stadium_line_box", 44, 0, 0.4, 0.5, 40, 0.06, white)
    for fx, fy in ((-118.0, -98.0), (118.0, -98.0), (-118.0, 98.0), (118.0, 98.0)):
        cyl("stadium_pylon", fx, fy, 28.5, 0.9, 57, metal, vertices=8)
        head_a = math.atan2(-fy, -fx)
        rbox("stadium_flood_head", fx, fy, 57.5, 8.5, 1.4, 3.6, metal, rotation=(0, 0, head_a))
        rbox("stadium_flood_glow", fx * 0.985, fy * 0.985, 57.3, 7.8, 1.5, 3.0, MATS["LampGlow"], rotation=(0, 0, head_a))


def _build_office_tower(podium_w, shaft_w, total_h, setback_at, spire, detail_036=False):
    stone = MATS["TowerStone"]
    glass = MATS["TowerGlass"]
    spandrel = MATS["TowerSpandrel"]
    metal = MATS["TowerMetal"]
    trim = MATS["TowerTrim"]
    dark = MATS["RoofDark"]

    box("office_podium", 0, 0, 3, podium_w, podium_w, 6, stone)
    box("office_podium_roof", 0, 0, 6.3, podium_w + 0.8, podium_w + 0.8, 0.6, dark)
    box("office_entrance", 0, -(podium_w / 2.0 + 0.4), 2.4, podium_w * 0.46, 0.9, 4.6, MATS["FacadeGlass"])
    box("office_canopy", 0, -(podium_w / 2.0 + 2.2), 5.4, podium_w * 0.55, 4.6, 0.45, metal)
    for cx in (-podium_w * 0.22, podium_w * 0.22):
        cyl("office_column", cx, -(podium_w / 2.0 + 3.8), 2.7, 0.34, 5.4, metal, vertices=8)
    for mullion_frac in (-0.18, -0.09, 0.0, 0.09, 0.18):
        box("office_storefront_mullion", podium_w * mullion_frac, -(podium_w / 2.0 + 0.92), 2.4, 0.28, 0.22, 4.6, metal)
    box("office_entrance_step", 0, -(podium_w / 2.0 + 2.0), 0.18, podium_w * 0.60, 3.6, 0.36, stone)
    if detail_036:
        # 0.3.6 (low tower): podium was dressed only at the front;
        # side/rear storefront glass reuses the FacadeGlass part.
        box("office_podium_glass_back", 0, podium_w / 2.0 + 0.4, 2.4, podium_w * 0.46, 0.9, 4.6, MATS["FacadeGlass"])
        for sx in (-1.0, 1.0):
            box("office_podium_glass_side", sx * (podium_w / 2.0 + 0.4), 0, 2.4, 0.9, podium_w * 0.46, 4.6, MATS["FacadeGlass"])
    lower_top = setback_at if setback_at > 0 else total_h - 4.0
    box("office_shaft", 0, 0, 6 + (lower_top - 6) / 2.0, shaft_w, shaft_w, lower_top - 6, glass)
    ring_z = 15.0
    while ring_z < lower_top - 3.0:
        box("office_spandrel", 0, 0, ring_z, shaft_w + 0.4, shaft_w + 0.4, 1.05, spandrel)
        ring_z += 9.5 if detail_036 else 11.5
    for cx in (-shaft_w / 2.0, shaft_w / 2.0):
        for cy in (-shaft_w / 2.0, shaft_w / 2.0):
            box("office_corner_fin", cx, cy, 6 + (lower_top - 6) / 2.0, 1.15, 1.15, lower_top - 6, metal)
    # 0.3.13: vertical face fins between the corner fins, so the
    # glass shaft reads as a framed curtain wall with a bay rhythm
    # and shadow gaps instead of one smooth glass box.
    for sy in (-1.0, 1.0):
        for fin_x in (-shaft_w * 0.25, shaft_w * 0.25):
            box("office_face_fin0313", fin_x, sy * (shaft_w / 2.0 + 0.10), 6 + (lower_top - 6) / 2.0, 0.5, 0.34, lower_top - 6, metal)
    for sx in (-1.0, 1.0):
        for fin_y in (-shaft_w * 0.25, shaft_w * 0.25):
            box("office_face_fin0313", sx * (shaft_w / 2.0 + 0.10), fin_y, 6 + (lower_top - 6) / 2.0, 0.34, 0.5, lower_top - 6, metal)
    top_w = shaft_w
    if setback_at > 0:
        top_w = shaft_w - 6.0
        upper_h = total_h - 4.0 - lower_top
        box("office_upper", 0, 0, lower_top + upper_h / 2.0, top_w, top_w, upper_h, glass)
        ring_z = lower_top + 8.0
        while ring_z < total_h - 6.0:
            box("office_spandrel_up", 0, 0, ring_z, top_w + 0.4, top_w + 0.4, 1.05, spandrel)
            ring_z += 9.5 if detail_036 else 11.5
        box("office_setback_slab", 0, 0, lower_top + 0.35, shaft_w + 0.7, shaft_w + 0.7, 0.7, trim)
        if detail_036:
            # 0.3.8 (mid/high towers): the setback upper shaft keeps
            # the lower shaft's corner-fin rhythm; fins stay inside
            # the lower shaft envelope.
            for cx in (-top_w / 2.0, top_w / 2.0):
                for cy in (-top_w / 2.0, top_w / 2.0):
                    box("office_upper_corner_fin", cx, cy, lower_top + upper_h / 2.0, 1.15, 1.15, upper_h, metal)
            # 0.3.13: same face-fin rhythm on the setback shaft.
            for sy in (-1.0, 1.0):
                for fin_x in (-top_w * 0.25, top_w * 0.25):
                    box("office_upper_fin0313", fin_x, sy * (top_w / 2.0 + 0.10), lower_top + upper_h / 2.0, 0.5, 0.34, upper_h, metal)
            for sx in (-1.0, 1.0):
                for fin_y in (-top_w * 0.25, top_w * 0.25):
                    box("office_upper_fin0313", sx * (top_w / 2.0 + 0.10), fin_y, lower_top + upper_h / 2.0, 0.34, 0.5, upper_h, metal)
    box("office_crown", 0, 0, total_h - 2.9, top_w + 1.2, top_w + 1.2, 2.2, trim)
    box("office_roof_box", -top_w * 0.16, 0, total_h - 0.9, top_w * 0.42, top_w * 0.5, 1.9, dark)
    box("office_hvac", top_w * 0.22, top_w * 0.18, total_h - 1.3, 4.5, 4.0, 1.2, metal)
    if detail_036:
        box("office_hvac_second", -top_w * 0.28, -top_w * 0.20, total_h - 1.35, 3.6, 3.2, 1.1, metal)
    for rail_y in (-top_w / 2.0 - 0.3, top_w / 2.0 + 0.3):
        box("office_roof_rail", 0, rail_y, total_h - 1.45, top_w + 0.8, 0.18, 0.55, metal)
    for rail_x in (-top_w / 2.0 - 0.3, top_w / 2.0 + 0.3):
        box("office_roof_rail", rail_x, 0, total_h - 1.45, 0.18, top_w + 0.8, 0.55, metal)
    if spire:
        cone("office_spire", 0, 0, total_h + 4.6, 1.7, 0.12, 9.4, metal, vertices=10)
        cyl("office_beacon", 0, 0, total_h + 9.6, 0.32, 0.6, MATS["CityAccentRed"], vertices=8)


def build_office_tower_low():
    _build_office_tower(36.0, 31.0, 42.0, 0.0, False, detail_036=True)


def build_office_tower_mid():
    _build_office_tower(36.0, 31.0, 68.0, 46.0, False, detail_036=True)


def build_office_tower_high():
    _build_office_tower(38.0, 33.0, 96.0, 58.0, True, detail_036=True)


def _build_midrise(width, depth, floors, detail_036=False, panel_038=False):
    plaster = MATS["HeroPlaster"]
    stone = MATS["HeroStone"]
    glass = MATS["FacadeGlass"]
    dark_glass = MATS["WindowGlassDark"]
    metal = MATS["PropsMetal"]
    floor_h = 3.1
    body_h = floors * floor_h
    box("mid_plinth", 0, 0, 0.6, width + 0.5, depth + 0.5, 1.2, stone)
    box("mid_body", 0, 0, 1.2 + body_h / 2.0, width, depth, body_h, plaster)
    box("mid_stair_glass", 0, -(depth / 2.0 + 0.25), 1.2 + body_h / 2.0, 4.6, 0.5, body_h - 1.5, glass)
    box("mid_door", 0, -(depth / 2.0 + 0.3), 1.9, 2.6, 0.4, 3.4, MATS["WindowFrame"])
    box("mid_canopy", 0, -(depth / 2.0 + 1.1), 3.9, 6.4, 2.4, 0.35, metal)
    for f in range(floors):
        fz = 1.2 + f * floor_h
        for sy in (-1.0, 1.0):
            face_y = sy * (depth / 2.0)
            for bx in (-width * 0.29, width * 0.29):
                box("mid_balcony_slab", bx, face_y + sy * 0.85, fz + 0.15, 5.4, 1.7, 0.22, MATS["HeroTrim"])
                box("mid_balcony_rail", bx, face_y + sy * 1.66, fz + 0.72, 5.4, 0.14, 0.95, glass)
                if panel_038:
                    # 0.3.8 (midrise_b): flat dark-glass slabs become
                    # outward panels on the old outer face; the
                    # plaster wall behind hides the back side.
                    panel("mid_balcony_door", bx, face_y + sy * 0.22, fz + 1.45, 3.6, 2.3, dark_glass, "back" if sy > 0.0 else "front")
                else:
                    box("mid_balcony_door", bx, face_y + sy * 0.12, fz + 1.45, 3.6, 0.2, 2.3, dark_glass)
                if detail_036:
                    box("mid_balcony_toprail", bx, face_y + sy * 1.66, fz + 1.22, 5.5, 0.16, 0.09, metal)
            for wx in (-width * 0.13, width * 0.13, -width * 0.44, width * 0.44):
                if panel_038:
                    panel("mid_window", wx, face_y + sy * 0.22, fz + 1.7, 2.5, 1.6, dark_glass, "back" if sy > 0.0 else "front")
                else:
                    box("mid_window", wx, face_y + sy * 0.12, fz + 1.7, 2.5, 0.2, 1.6, dark_glass)
            if detail_036:
                box("mid_sill_band", 0, face_y + sy * 0.10, fz + 0.80, width * 0.92, 0.18, 0.16, MATS["HeroTrim"])
        for sx in (-1.0, 1.0):
            for wy in (-depth * 0.28, 0.0, depth * 0.28):
                if panel_038:
                    panel("mid_side_window", sx * (width / 2.0 + 0.22), wy, fz + 1.7, 2.2, 1.6, dark_glass, "right" if sx > 0.0 else "left")
                else:
                    box("mid_side_window", sx * (width / 2.0 + 0.12), wy, fz + 1.7, 0.2, 2.2, 1.6, dark_glass)
    # 0.3.12: full-height facade piers between the window columns,
    # proud of the glass panels, so the flat panes sit inside a real
    # structural grid with shadow lines instead of floating on the
    # plaster.  HeroTrim is already a material of this model.
    for sy in (-1.0, 1.0):
        for pier_x in (-width * 0.365, -width * 0.21, width * 0.21, width * 0.365):
            box("mid_pier0312", pier_x, sy * (depth / 2.0 + 0.13), 1.2 + body_h / 2.0, 0.55, 0.34, body_h, MATS["HeroTrim"])
    for sx in (-1.0, 1.0):
        for pier_y in (-depth * 0.14, depth * 0.14):
            box("mid_pier0312", sx * (width / 2.0 + 0.13), pier_y, 1.2 + body_h / 2.0, 0.34, 0.55, body_h, MATS["HeroTrim"])
    box("mid_parapet", 0, 0, 1.2 + body_h + 0.4, width + 0.6, depth + 0.6, 0.8, stone)
    box("mid_bulkhead", -width * 0.2, 0, 1.2 + body_h + 1.6, 7, 6, 2.4, plaster)
    box("mid_hvac", width * 0.24, depth * 0.15, 1.2 + body_h + 1.2, 4.2, 3.4, 1.1, metal)
    for light_x in (-2.0, 2.0):
        box("mid_entry_light", light_x, -(depth / 2.0 + 0.45), 3.2, 0.35, 0.18, 0.50, MATS["LampGlow"])
    for rail_y in (-depth / 2.0 - 0.15, depth / 2.0 + 0.15):
        box("mid_roof_rail", 0, rail_y, 1.2 + body_h + 1.05, width + 0.2, 0.14, 0.50, metal)
    for rail_x in (-width / 2.0 - 0.15, width / 2.0 + 0.15):
        box("mid_roof_rail", rail_x, 0, 1.2 + body_h + 1.05, 0.14, depth + 0.2, 0.50, metal)


def build_midrise_a():
    _build_midrise(34.0, 26.0, 7, detail_036=True, panel_038=True)


def build_midrise_b():
    _build_midrise(30.0, 24.0, 10, detail_036=True, panel_038=True)


def _build_warehouse(length, width, wall_h, roof_h, doors, detail_036=False):
    clad = MATS["ConcreteLight"]
    metal = MATS["PropsMetal"]
    frame = MATS["WindowFrame"]
    box("wh_walls", 0, 0, wall_h / 2.0, length, width, wall_h, clad)
    rib_step = length / 9.0
    for i in range(10):
        rx = -length / 2.0 + i * rib_step
        box("wh_rib", rx, -(width / 2.0 + 0.14), wall_h / 2.0, 0.55, 0.28, wall_h, metal)
        box("wh_rib", rx, width / 2.0 + 0.14, wall_h / 2.0, 0.55, 0.28, wall_h, metal)
    gable_roof("wh_roof", 0, 0, wall_h + roof_h / 2.0, length + 1.4, width + 1.8, roof_h, metal, ridge_axis="x")
    door_span = length * (0.62 if length > 60.0 else 0.5)
    for i in range(doors):
        dx = -door_span / 2.0 + (i + 0.5) * (door_span / doors)
        box("wh_dock_door", dx, -(width / 2.0 + 0.22), 2.4, 4.3, 0.4, 4.7, frame)
        box("wh_dock_header0312", dx, -(width / 2.0 + 0.30), 4.95, 4.7, 0.5, 0.4, metal)
        for seam_z in (1.35, 2.95):
            box("wh_dock_seam", dx, -(width / 2.0 + 0.46), seam_z, 4.0, 0.16, 0.16, MATS["RoofDark"])
        box("wh_dock_bump", dx, -(width / 2.0 + 0.5), 0.5, 4.6, 0.7, 0.9, MATS["RoofDark"])
    rbox("wh_dock_canopy", 0, -(width / 2.0 + 1.5), 5.6, door_span + 6, 3.0, 0.3, metal, rotation=(math.radians(14), 0, 0))
    box("wh_office", length / 2.0 - 6.0, -(width / 2.0 + 2.2), wall_h * 0.42, 12, 4.6, wall_h * 0.84, MATS["FacadeMain"])
    box("wh_office_glass", length / 2.0 - 6.0, -(width / 2.0 + 4.65), wall_h * 0.5, 11, 0.35, wall_h * 0.5, MATS["FacadeGlass"])
    box("wh_end_door", length / 2.0 + 0.22, 0, 2.7, 0.4, 6.4, 5.4, frame)
    box("wh_gutter", 0, -(width / 2.0 + 0.28), wall_h - 0.25, length * 0.98, 0.35, 0.30, metal)
    for downspout_x in (-length * 0.38, 0.0, length * 0.38):
        box("wh_downspout", downspout_x, -(width / 2.0 + 0.30), wall_h / 2.0, 0.18, 0.18, wall_h, metal)
    if detail_036:
        # 0.3.6 (large warehouse): rear gutter/downspouts, clerestory
        # daylight strips and a ridge cap -- existing materials only.
        box("wh_gutter_back", 0, width / 2.0 + 0.28, wall_h - 0.25, length * 0.98, 0.35, 0.30, metal)
        for downspout_x in (-length * 0.38, 0.0, length * 0.38):
            box("wh_downspout_back", downspout_x, width / 2.0 + 0.30, wall_h / 2.0, 0.18, 0.18, wall_h, metal)
        for sy in (-1.0, 1.0):
            box("wh_clerestory", 0, sy * (width / 2.0 + 0.10), wall_h - 1.35, length * 0.8, 0.2, 1.1, MATS["FacadeGlass"])
        box("wh_ridge_cap", 0, 0, wall_h + roof_h + 0.02, length + 1.5, 0.5, 0.16, metal)
    for vx in (-length * 0.3, 0.0, length * 0.3):
        cyl("wh_vent", vx, 0, wall_h + roof_h - 0.3, 0.85, 1.5, metal, vertices=10)


def build_warehouse_large():
    _build_warehouse(76.0, 32.0, 8.0, 5.0, 6, detail_036=True)


def build_warehouse_small():
    _build_warehouse(46.0, 24.0, 6.5, 3.5, 4, detail_036=True)


def build_shopping_mall():
    """RichTown Mall: the exact 230 x 130 x 18 m rt-mall parcel.

    0.3.5 closes the last generic massing box in the exported city.
    Two retail levels with continuous storefront glass, a finned stone
    upper gallery, four entrance pavilions, roof atria and a rear
    loading dock -- nine shared materials, no new runtime material.
    Everything stays inside the parcel envelope (canopies included).
    """
    main_mat = MATS["FacadeMain"]
    accent = MATS["FacadeAccent"]
    glass = MATS["FacadeGlass"]
    concrete = MATS["ConcreteLight"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    blue = MATS["CityAccentBlue"]
    red = MATS["CityAccentRed"]
    glow = MATS["LampGlow"]

    box("mall_plinth", 0, 0, 0.5, 230.0, 130.0, 1.0, concrete)
    box("mall_ground_mass", 0, 0, 3.8, 226.0, 126.0, 5.6, main_mat)
    # Ground-floor storefront glass on all four faces.
    for sy in (-63.10, 63.10):
        panel("mall_storefront", 0, sy + (0.25 if sy > 0.0 else -0.25), 3.6, 200.0, 4.2, glass, "back" if sy > 0.0 else "front")
    for sx in (-113.10, 113.10):
        panel("mall_storefront", sx + (0.25 if sx > 0.0 else -0.25), 0, 3.6, 104.0, 4.2, glass, "right" if sx > 0.0 else "left")
    mx = -87.5
    while mx <= 87.6:
        for sy in (-63.38, 63.38):
            box("mall_storefront_mullion", mx, sy, 3.6, 0.35, 0.3, 4.2, metal)
        mx += 12.5
    my = -48.0
    while my <= 48.1:
        for sx in (-113.38, 113.38):
            box("mall_storefront_mullion", sx, my, 3.6, 0.3, 0.35, 4.2, metal)
        my += 12.0
    # 0.3.13: head/sill transom rails frame the storefront glass
    # (the panels floated proud of the massing with only vertical
    # mullions tying them back to the facade).
    for sy in (-63.38, 63.38):
        box("mall_storefront_rail0313", 0, sy, 5.82, 202.0, 0.34, 0.30, metal)
        box("mall_storefront_rail0313", 0, sy, 1.38, 202.0, 0.34, 0.30, metal)
    for sx in (-113.38, 113.38):
        box("mall_storefront_rail0313", sx, 0, 5.82, 0.34, 106.0, 0.30, metal)
        box("mall_storefront_rail0313", sx, 0, 1.38, 0.34, 106.0, 0.30, metal)
    box("mall_mid_cornice", 0, 0, 7.05, 228.0, 128.0, 0.9, accent)
    box("mall_upper_mass", 0, 0, 11.3, 224.0, 124.0, 7.6, main_mat)
    for sy in (-62.10, 62.10):
        panel("mall_clerestory", 0, sy + (0.25 if sy > 0.0 else -0.25), 13.4, 180.0, 2.6, glass, "back" if sy > 0.0 else "front")
    for sx in (-112.10, 112.10):
        panel("mall_clerestory", sx + (0.25 if sx > 0.0 else -0.25), 0, 13.4, 96.0, 2.6, glass, "right" if sx > 0.0 else "left")
    # 0.3.13: same transom treatment for the clerestory band.
    for sy in (-62.38, 62.38):
        box("mall_clerestory_rail0313", 0, sy, 14.82, 182.0, 0.32, 0.26, metal)
        box("mall_clerestory_rail0313", 0, sy, 11.98, 182.0, 0.32, 0.26, metal)
    for sx in (-112.38, 112.38):
        box("mall_clerestory_rail0313", sx, 0, 14.82, 0.32, 98.0, 0.26, metal)
        box("mall_clerestory_rail0313", sx, 0, 11.98, 0.32, 98.0, 0.26, metal)
    fx = -104.0
    while fx <= 104.1:
        for sy in (-62.45, 62.45):
            box("mall_fin", fx, sy, 11.3, 1.2, 0.9, 7.6, accent)
        fx += 16.0
    fy = -48.0
    while fy <= 48.1:
        for sx in (-112.45, 112.45):
            box("mall_fin", sx, fy, 11.3, 0.9, 1.2, 7.6, accent)
        fy += 16.0
    for cx in (-112.0, 112.0):
        for cy in (-62.0, 62.0):
            box("mall_corner_pier", cx, cy, 8.55, 3.0, 3.0, 15.1, accent)
    box("mall_roof_slab", 0, 0, 15.6, 229.0, 129.0, 1.0, concrete)
    for sy in (-63.9, 63.9):
        box("mall_parapet", 0, sy, 16.85, 229.0, 1.2, 1.5, accent)
    for sx in (-113.9, 113.9):
        box("mall_parapet", sx, 0, 16.85, 1.2, 129.0, 1.5, accent)

    def entrance(sign, along_y):
        if along_y:
            box("mall_entrance_glass", 0, sign * 63.6, 3.4, 34.0, 1.2, 4.8, glass)
            box("mall_entrance_canopy", 0, sign * 62.75, 5.9, 38.0, 4.5, 0.5, metal)
            box("mall_entrance_light", 0, sign * 63.9, 5.55, 30.0, 0.3, 0.15, glow)
            box("mall_entrance_sign", 0, sign * 63.8, 6.9, 30.0, 0.5, 0.9, blue)
            for cx in (-14.0, 14.0):
                cyl("mall_entrance_column", cx, sign * 64.2, 3.3, 0.35, 5.6, metal, vertices=8)
        else:
            box("mall_entrance_glass", sign * 113.6, 0, 3.4, 1.2, 34.0, 4.8, glass)
            box("mall_entrance_canopy", sign * 112.75, 0, 5.9, 4.5, 38.0, 0.5, metal)
            box("mall_entrance_light", sign * 113.9, 0, 5.55, 0.3, 30.0, 0.15, glow)
            box("mall_entrance_sign", sign * 113.8, 0, 6.9, 0.5, 30.0, 0.9, blue)
            for cy in (-14.0, 14.0):
                cyl("mall_entrance_column", sign * 114.2, cy, 3.3, 0.35, 5.6, metal, vertices=8)

    entrance(-1.0, True)
    entrance(1.0, True)
    entrance(-1.0, False)
    entrance(1.0, False)
    # Tenant sign bands high on the long south face and east face.
    box("mall_sign_band", 0, -62.4, 14.8, 60.0, 0.6, 1.6, blue)
    box("mall_sign_band", 112.4, 0, 14.8, 0.6, 44.0, 1.6, red)
    # Rear loading dock (north face, clear of the centre entrance).
    for dx in (-80.0, -58.0, 58.0, 80.0):
        box("mall_dock_door", dx, 63.3, 3.0, 6.0, 0.6, 4.0, dark)
        box("mall_dock_leveler", dx, 63.7, 0.65, 5.2, 0.5, 0.5, metal)
    # Roof atria, HVAC and exhaust vents (hard cap z = 18.0).
    for ax in (-70.0, 0.0, 70.0):
        box("mall_atrium", ax, 0, 17.0, 36.0, 24.0, 1.8, glass)
        box("mall_atrium_frame", ax, 0, 17.95, 36.0, 0.5, 0.1, metal)
        box("mall_atrium_frame", ax, 0, 17.95, 0.5, 24.0, 0.1, metal)
    for hx, hy in ((-100.0, -40.0), (-35.0, 42.0), (35.0, -42.0), (100.0, 40.0), (-100.0, 38.0), (100.0, -38.0)):
        box("mall_hvac", hx, hy, 16.8, 10.0, 6.0, 1.4, dark)
    for vx, vy in ((-52.0, -30.0), (52.0, 30.0), (-52.0, 30.0), (52.0, -30.0)):
        cyl("mall_roof_vent", vx, vy, 16.9, 1.2, 1.6, metal, vertices=10)


def _build_turbine_hall(length, height):
    """NPP turbine hall: 42 m wide, `length` long (Blender Y), `height` high.

    0.3.5 replaces the last two generic warehouse boxes on the NPP
    apron with ribbed industrial halls: high ribbon glazing, louver
    bands, end doors, a glazed roof monitor and exhaust stacks.
    """
    main_mat = MATS["FacadeMain"]
    accent = MATS["FacadeAccent"]
    glass = MATS["FacadeGlass"]
    concrete = MATS["ConcreteLight"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    blue = MATS["CityAccentBlue"]
    red = MATS["CityAccentRed"]
    wall_h = height - 3.5
    half = length / 2.0

    box("turbine_plinth", 0, 0, 0.5, 42.0, length, 1.0, concrete)
    box("turbine_hall", 0, 0, 1.0 + wall_h / 2.0, 40.0, length - 2.0, wall_h, main_mat)
    box("turbine_roof", 0, 0, height - 2.0, 42.0, length, 1.0, dark)
    box("turbine_monitor", 0, 0, height - 0.85, 12.0, length * 0.62, 1.3, glass)
    box("turbine_monitor_cap", 0, 0, height - 0.10, 13.0, length * 0.62, 0.2, metal)
    # Structural ribs + louver segments along both long walls.
    ry = -half + 8.0
    while ry < half - 4.0:
        for sx in (-20.45, 20.45):
            box("turbine_rib", sx, ry, 1.0 + wall_h / 2.0, 0.9, 1.4, wall_h, accent)
        if ry + 5.0 < half - 4.0:
            for sx in (-20.06, 20.06):
                panel("turbine_louver", sx + (0.15 if sx > 0.0 else -0.15), ry + 5.0, 3.2, 7.0, 2.2, metal, "right" if sx > 0.0 else "left")
        ry += 10.0
    for sy in (-(half - 0.55), half - 0.55):
        for ex in (-12.0, 0.0, 12.0):
            box("turbine_end_rib", ex, sy, 1.0 + wall_h / 2.0, 1.4, 0.9, wall_h, accent)
    # High ribbon glazing and the plant-blue stripe.
    for sx in (-20.05, 20.05):
        panel("turbine_ribbon", sx + (0.175 if sx > 0.0 else -0.175), 0, height - 6.0, length - 10.0, 3.0, glass, "right" if sx > 0.0 else "left")
        for rail_dz in (-1.65, 1.65):
            box("turbine_ribbon_rail0314", sx + (0.28 if sx > 0.0 else -0.28), 0, height - 6.0 + rail_dz, 0.25, length - 10.0, 0.3, metal)
        panel("turbine_stripe", sx + (0.15 if sx > 0.0 else -0.15), 0, 7.5, length - 6.0, 1.0, blue, "right" if sx > 0.0 else "left")
    for sy in (-(half - 0.95), half - 0.95):
        panel("turbine_stripe", 0, sy + (0.15 if sy > 0.0 else -0.15), 7.5, 36.0, 1.0, blue, "back" if sy > 0.0 else "front")
    # End doors: one wide equipment door + personnel door per gable.
    for sy in (-(half - 0.8), half - 0.8):
        box("turbine_door", -4.0, sy, 4.5, 14.0, 0.5, 7.0, dark)
        panel("turbine_door_split", -4.0, sy + (0.45 if sy > 0 else -0.45), 4.5, 0.4, 7.0, metal, "back" if sy > 0 else "front")
        box("turbine_personnel_door", 10.0, sy, 2.6, 2.4, 0.5, 3.2, blue)
    # Roof exhaust stacks, vents and corner safety lights.
    stack_ys = (-60.0, -20.0, 20.0, 60.0) if length > 140.0 else (-32.0, 0.0, 32.0)
    for i, sy in enumerate(stack_ys):
        cyl("turbine_stack", -10.0 if i % 2 == 0 else 10.0, sy, height - 1.1, 1.1, 1.8, metal, vertices=8)
    for vx, vy in ((-14.0, -half * 0.45), (14.0, half * 0.45), (14.0, -half * 0.15), (-14.0, half * 0.15)):
        box("turbine_roof_vent", vx, vy, height - 1.05, 5.0, 4.0, 0.9, dark)
    for cx in (-19.5, 19.5):
        for cy in (-(half - 1.5), half - 1.5):
            box("turbine_safety_light", cx, cy, height - 0.3, 0.5, 0.5, 0.5, red)


def build_turbine_hall_long():
    _build_turbine_hall(170.0, 26.0)


def build_turbine_hall_short():
    _build_turbine_hall(110.0, 20.0)


def _build_container(material):
    dark = MATS["RoofDark"]
    metal = MATS["PropsMetal"]
    box("cont_body", 0, 0, 1.42, 12.2, 2.44, 2.59, material)
    for sy in (-0.92, 0.92):
        box("cont_rail", 0, sy, 0.12, 12.2, 0.32, 0.24, dark)
    for i in range(12):
        rx = -5.7 + i * (11.4 / 11.0)
        box("cont_rib", rx, -1.26, 1.42, 0.34, 0.13, 2.3, material)
        box("cont_rib", rx, 1.26, 1.42, 0.34, 0.13, 2.3, material)
    for i in range(6):
        rx = -5.25 + i * 2.1
        box("cont_roof_rib", rx, 0, 2.76, 0.36, 2.2, 0.12, material)
    for cx in (-6.02, 6.02):
        for cy in (-1.14, 1.14):
            box("cont_corner", cx, cy, 1.42, 0.3, 0.3, 2.59, dark)
    box("cont_door_a", 6.18, -0.6, 1.42, 0.16, 1.12, 2.3, material)
    box("cont_door_b", 6.18, 0.6, 1.42, 0.16, 1.12, 2.3, material)
    for lx in (-0.95, -0.25, 0.25, 0.95):
        cyl("cont_lockrod", 6.3, lx, 1.42, 0.07, 2.2, metal, vertices=6)
    for hinge_z in (0.65, 2.2):
        for hinge_y in (-1.12, 1.12):
            box("cont_hinge", 6.25, hinge_y, hinge_z, 0.18, 0.28, 0.42, metal)
    for ry in (-0.6, 0.0, 0.6):
        box("cont_rear_rib0314", -6.16, ry, 1.42, 0.14, 0.4, 2.3, material)
    panel("cont_data_plate", 6.315, -0.6, 1.95, 0.75, 0.50, MATS["CityWhitePaint"], "right")


def build_container_red():
    _build_container(MATS["CityAccentRed"])


def build_container_blue():
    _build_container(MATS["CityAccentBlue"])


def build_villa_b():
    plaster = MATS["VillaPlaster"]
    stone = MATS["VillaStone"]
    wood = MATS["VillaWood"]
    glass = MATS["VillaGlass"]
    granite = MATS["VillaGranite"]
    dark = MATS["RoofDark"]

    box("villab_plinth", 0, 0, 0.18, 19.2, 15.24, 0.36, granite)
    box("villab_main", -2.4, -1.2, 3.55, 12.5, 9.5, 6.4, plaster)
    box("villab_main_roof", -2.4, -1.2, 6.95, 13.1, 10.1, 0.45, dark)
    box("villab_upper", -4.0, -2.3, 7.95, 9.5, 7.4, 1.9, stone)
    box("villab_upper_roof", -4.0, -2.3, 8.95, 10.0, 7.9, 0.3, dark)
    win_recess_0312("villab_glass", -2.4, -5.95, 2.9, 9.2, 4.4, glass, wood, "front", depth=0.24, frame_w=0.18)
    for i in range(6):
        box("villab_screen", -6.6 + i * 1.7, -6.35, 3.1, 0.28, 0.28, 5.2, wood)
    win_recess_0312("villab_side_win", -8.65, -1.2, 4.4, 5.5, 2.0, glass, wood, "left", depth=0.24, frame_w=0.16)
    win_recess_0312("villab_upper_win", -4.0, -6.0, 7.95, 7.6, 1.3, glass, wood, "front", depth=0.19, frame_w=0.14)
    box("villab_garage", 6.4, -2.6, 1.95, 5.6, 6.5, 3.2, stone)
    box("villab_garage_roof", 6.4, -2.6, 3.7, 6.1, 7.0, 0.35, dark)
    box("villab_garage_door", 6.4, -5.95, 1.55, 4.4, 0.25, 2.5, MATS["TownGarage"])
    box("villab_door", 2.6, -6.05, 1.6, 1.5, 0.25, 2.9, wood)
    for mullion_x in (-5.9, -2.4, 1.1):
        box("villab_glass_mullion", mullion_x, -6.22, 2.9, 0.22, 0.16, 4.4, wood)
    panel("villab_glass_rail", -2.4, -6.30, 2.9, 9.2, 0.22, wood, "front")
    for garage_seam_z in (0.80, 1.55, 2.30):
        panel("villab_garage_seam", 6.4, -6.16, garage_seam_z, 4.3, 0.12, dark, "front")
    box("villab_step", 2.6, -6.55, 0.16, 2.2, 0.9, 0.32, granite)
    box("villab_porch_light", 3.65, -6.20, 2.8, 0.28, 0.16, 0.42, MATS["LampGlow"])
    for downspout_x in (-8.55, 3.75):
        box("villab_downspout", downspout_x, -6.03, 3.65, 0.16, 0.16, 6.6, dark)
    for px in (3.4, 8.6):
        for py in (1.2, 5.6):
            box("villab_pergola_post", px, py, 1.6, 0.24, 0.24, 3.2, wood)
    for i in range(5):
        box("villab_pergola_beam", 3.2 + i * 1.4, 3.4, 3.3, 0.24, 5.6, 0.28, wood)
    # 0.3.6: rear elevation (was blank), pergola cross beams, roof vent.
    win_recess_0312("villab_rear_gloss", -2.4, 3.55, 2.9, 8.0, 3.6, glass, wood, "back", depth=0.20, frame_w=0.18)
    win_recess_0312("villab_rear_upper_win", -4.0, 1.4, 7.95, 6.5, 1.2, glass, wood, "back", depth=0.195, frame_w=0.14)
    box("villab_rear_door", 2.6, 3.62, 1.6, 1.4, 0.25, 2.8, wood)
    box("villab_rear_step", 2.6, 4.05, 0.16, 2.0, 0.8, 0.32, granite)
    for rear_mullion_x in (-4.9, -0.1):
        box("villab_rear_mullion", rear_mullion_x, 3.80, 2.9, 0.22, 0.16, 3.6, wood)
    for py in (1.2, 5.6):
        box("villab_pergola_cross", 6.0, py, 3.52, 6.4, 0.24, 0.22, wood)
    box("villab_roof_vent", 2.2, 2.2, 7.42, 1.6, 1.2, 0.5, dark)
    # 0.3.14 lived-in detail (TZ stage 5): tilted solar array on the garage
    # roof, AC outdoor units on the side/rear walls and a satellite dish
    # on the upper roof slab (top z=9.1).
    rbox("villab_solar0314", 6.4, -2.6, 4.42, 4.6, 2.6, 0.10, dark, rotation=(math.radians(20), 0, 0))
    box("villab_solar_post0314", 6.4, -1.45, 4.35, 4.4, 0.12, 0.7, wood)
    box("villab_ac0314", 4.07, 1.5, 0.55, 0.38, 0.95, 0.7, MATS["TownGarage"])
    panel("villab_acfan0314", 4.27, 1.5, 0.55, 0.7, 0.5, dark, "right")
    box("villab_ac0314", -5.0, 3.77, 0.55, 0.95, 0.38, 0.7, MATS["TownGarage"])
    panel("villab_acfan0314", -5.0, 3.97, 0.55, 0.7, 0.5, dark, "back")


def build_townhouse_b():
    plaster = MATS["TownPlaster"]
    stone = MATS["TownStone"]
    trim = MATS["TownTrim"]
    roof = MATS["TownRoof"]
    glass = MATS["WindowGlassDark"]

    box("townb_slab", 0, 0, 0.15, 18.87, 16.37, 0.3, stone)
    for ux in (-4.65, 4.65):
        box("townb_ground", ux, -1.0, 1.95, 8.9, 10.6, 3.3, stone)
        box("townb_upper", ux, -1.0, 5.25, 8.9, 10.6, 3.3, plaster)
        box("townb_band", ux, -1.0, 3.7, 9.1, 10.8, 0.35, trim)
        gable_roof("townb_roof", ux, -1.0, 9.05, 9.5, 11.4, 4.3, roof, ridge_axis="y")
        box("townb_bay", ux - 1.9, -6.9, 2.7, 3.6, 1.3, 5.2, plaster)
        win_recess_0312("townb_bay_glass", ux - 1.9, -7.55, 2.9, 3.0, 4.2, glass, trim, "front", depth=0.18, frame_w=0.14)
        box("townb_bay_roof", ux - 1.9, -6.9, 5.5, 4.0, 1.7, 0.3, roof)
        box("townb_garage", ux + 2.2, -6.45, 1.45, 3.3, 0.3, 2.4, MATS["TownGarage"])
        box("townb_bay_mullion_v", ux - 1.9, -7.76, 2.9, 0.18, 0.14, 4.2, trim)
        box("townb_bay_mullion_h", ux - 1.9, -7.76, 2.9, 3.0, 0.14, 0.18, trim)
        box("townb_garage_seam", ux + 2.2, -6.64, 1.45, 3.2, 0.10, 0.12, trim)
        box("townb_downspout", ux + (-4.55 if ux < 0 else 4.55), -6.35, 3.4, 0.16, 0.16, 6.8, roof)
        for wx in (-2.6, 0.2, 3.0):
            win_recess_0312("townb_window", ux + wx, -6.30, 5.5, 1.5, 1.7, glass, trim, "front", depth=0.22, frame_w=0.12)
        box("townb_chimney", ux + 2.8, 1.8, 10.4, 1.1, 1.1, 2.6, stone)
        box("townb_chimney_band", ux + 2.8, 1.8, 11.55, 1.35, 1.35, 0.20, trim)
        # 0.3.6: rear elevation (was blank): door + upper windows.
        box("townb_rear_door", ux + 2.0, 4.42, 1.55, 1.3, 0.25, 2.7, MATS["TownDoor"] if ux < 0 else MATS["TownDoorAccent"])
        for rear_wx in (-2.4, 0.4):
            win_recess_0312("townb_rear_win", ux + rear_wx, 4.30, 5.5, 1.5, 1.7, glass, trim, "back", depth=0.22, frame_w=0.12)
        # 0.3.14 lived-in detail (TZ stage 5): wheelie bins against the front
        # wall (free strip + beside the bay) and a side-wall AC outdoor unit.
        for _bin_x in (ux + 0.22, ux - 4.05):
            box("townb_bin0314", _bin_x, -6.65, 0.5, 0.55, 0.6, 1.0, MATS["TownGarage"])
            box("townb_bin_lid0314", _bin_x, -6.65, 1.04, 0.6, 0.65, 0.08, trim)
        _side0314 = -1.0 if ux < 0.0 else 1.0
        box("townb_ac0314", _side0314 * 9.3, -2.0, 0.5, 0.35, 0.9, 0.65, MATS["TownGarage"])
        panel("townb_ac_grille0314", _side0314 * 9.49, -2.0, 0.5, 0.7, 0.45, glass, "right" if _side0314 > 0.0 else "left")
    box("townb_door_l", -1.15, -6.42, 1.55, 1.3, 0.25, 2.7, MATS["TownDoor"])
    box("townb_door_r", 1.15, -6.42, 1.55, 1.3, 0.25, 2.7, MATS["TownDoorAccent"])
    for porch_light_x in (-1.95, 1.95):
        box("townb_porch_light", porch_light_x, -6.58, 2.9, 0.25, 0.14, 0.40, MATS["LampGlow"])
    box("townb_porch_roof", 0, -7.0, 3.35, 5.4, 1.6, 0.28, roof)
    for px in (-2.4, 2.4):
        box("townb_porch_post", px, -7.6, 1.65, 0.22, 0.22, 3.3, trim)


def build_barn():
    red = MATS["CityBarnRed"]
    white = MATS["CityWhitePaint"]
    dark = MATS["RoofDark"]
    box("barn_walls", 0, 0, 3.5, 30, 14, 7, red)
    gable_roof("barn_roof", 0, 0, 8.7, 31.4, 15.8, 3.4, dark, ridge_axis="x")
    box("barn_door", -15.15, 0, 2.6, 0.35, 6.6, 5.2, white)
    box("barn_door_in", -15.32, 0, 2.6, 0.2, 5.8, 4.5, red)
    rbox("barn_brace_a", -15.45, 0, 2.6, 0.16, 6.4, 0.5, white, rotation=(math.radians(48), 0, 0))
    rbox("barn_brace_b", -15.45, 0, 2.6, 0.16, 6.4, 0.5, white, rotation=(math.radians(-48), 0, 0))
    box("barn_loft", -15.25, 0, 7.6, 0.3, 2.2, 2.0, white)
    panel("barn_loft_glass", -15.5, 0, 7.6, 1.7, 1.5, MATS["WindowGlassDark"], "left")
    for wx in (-9.0, -3.0, 3.0, 9.0):
        win_recess_0312("barn_win", wx, -7.0, 4.2, 1.5, 1.6, MATS["WindowGlassDark"], white, "front", depth=0.24, frame_w=0.15)
    box("barn_leanto", -2, 8.4, 1.7, 17, 3.4, 3.4, red)
    rbox("barn_leanto_roof", -2, 8.6, 3.6, 17.6, 4.4, 0.3, dark, rotation=(math.radians(10), 0, 0))
    box("barn_ridge_cap", 0, 0, 10.42, 31.6, 0.5, 0.25, dark)
    for gutter_y in (-7.95, 7.95):
        box("barn_gutter", 0, gutter_y, 6.95, 30.5, 0.25, 0.25, dark)
    for hinge_y in (-2.9, 2.9):
        box("barn_door_hinge", -15.56, hinge_y, 2.6, 0.14, 0.35, 0.8, MATS["PropsMetal"])
    box("barn_cupola", 0, 0, 11.1, 2.2, 2.2, 1.6, white)
    cupola_roof = cone("barn_cupola_roof", 0, 0, 12.5, 1.9, 0.15, 1.4, dark, vertices=4)
    cupola_roof.rotation_euler = (0, 0, math.radians(45))


def build_greenhouse():
    glass = MATS["PropsGlass"]
    metal = MATS["PropsMetal"]
    green = MATS["CityFieldGreen"]
    box("gh_base", 0, 0, 0.4, 44, 14, 0.8, MATS["ConcreteLight"])
    angles = (-1.02, -0.51, 0.0, 0.51, 1.02)
    for a in angles:
        gy = math.sin(a) * 6.9
        gz = 0.8 + math.cos(a) * 5.1
        rbox("gh_glass", 0, gy, gz, 43.6, 3.6, 0.1, glass, rotation=(a, 0, 0))
    for rib_x in range(-21, 22, 7):
        for a in angles:
            gy = math.sin(a) * 7.0
            gz = 0.8 + math.cos(a) * 5.2
            rbox("gh_rib", rib_x, gy, gz, 0.32, 3.7, 0.22, metal, rotation=(a, 0, 0))
    for sy in (-6.9, 6.9):
        box("gh_side_wall", 0, sy, 1.8, 43.6, 0.12, 2.0, glass)
    for ex in (-21.9, 21.9):
        box("gh_end", ex, 0, 2.4, 0.3, 12.6, 3.4, glass)
        box("gh_end_peak", ex, 0, 5.3, 0.3, 8.6, 2.6, glass)
        box("gh_end_frame", ex, 0, 4.4, 0.35, 9.0, 0.5, metal)
    box("gh_door", -22.1, 0, 1.7, 0.3, 2.4, 3.0, MATS["WindowFrame"])
    box("gh_ridge_vent", 0, 0, 6.05, 40, 1.2, 0.25, metal)
    for fan_x in (-22.12, 22.12):
        box("gh_fan", fan_x, 4.2, 2.6, 0.18, 2.2, 2.2, MATS["WindowFrame"])
    for row_y in (-4.4, -1.5, 1.5, 4.4):
        box("gh_crops", 0, row_y, 1.25, 40, 1.7, 0.95, green)


def build_barge():
    """0.3.15 (TZ stage 6): 55 m canal cargo barge for the port quay.

    Flat-bottom hull with raked ends (keel line z=0 like the yachts,
    placement Y carries the 1.55 m draft), one open hold with a cargo
    mound, three closed hatch covers aft and a raised wheelhouse.
    Five merged parts, all in the 0.3.12 world-density UV set except
    the glass band.
    """
    dark = MATS["RoofDark"]
    metal = MATS["PropsMetal"]
    white = MATS["CityWhitePaint"]
    glass = MATS["WindowGlassDark"]
    red = MATS["CityAccentRed"]
    deck = 2.6
    # Hull loft: (y, top half-beam, bottom half-beam, bottom z).
    sections = [
        (-27.5, 3.1, 0.8, 1.55),
        (-24.0, 4.3, 3.6, 0.55),
        (-19.0, 4.3, 4.1, 0.0),
        (19.0, 4.3, 4.1, 0.0),
        (24.0, 4.3, 3.6, 0.55),
        (27.5, 3.4, 1.2, 1.45),
    ]
    b = MeshBuilder()
    rings = []
    for y, thb, bhb, bz in sections:
        rings.append([
            b.add_vertex(Vector((-thb, y, deck))),
            b.add_vertex(Vector((-bhb, y, bz))),
            b.add_vertex(Vector((bhb, y, bz))),
            b.add_vertex(Vector((thb, y, deck))),
        ])
    for i in range(len(rings) - 1):
        a, c = rings[i], rings[i + 1]
        for j in range(3):
            b.quad(c[j], a[j], a[j + 1], c[j + 1])
        b.quad(c[3], a[3], a[0], c[0])
    r0 = rings[0]
    b.quad(r0[0], r0[1], r0[2], r0[3])
    r1 = rings[-1]
    b.quad(r1[3], r1[2], r1[1], r1[0])
    b.build("barge_hull0315", dark, smooth=False)
    # Red sheer stripe along the parallel mid-body (ends stay clear
    # of the raked sections where the hull narrows).
    box("barge_stripe0315", 0, 0, 2.18, 8.74, 38.0, 0.34, red)
    # Open forward hold: coaming rim + stepped cargo mound.
    box("barge_coaming0315", 0, -10.5, deck + 0.25, 7.6, 17.0, 0.5, metal)
    box("barge_cargo0315", 0, -10.5, deck + 0.55, 7.0, 16.0, 0.7, dark)
    box("barge_cargo0315", 0, -10.5, deck + 1.05, 6.0, 14.0, 0.5, dark)
    # Three closed hatch covers aft of the hold.
    for hy in (1.5, 7.6, 13.7):
        box("barge_hatch0315", 0, hy, deck + 0.28, 7.5, 5.6, 0.55, metal)
    # Raised wheelhouse on the stern deck.
    box("barge_wheelhouse0315", 0, 22.6, deck + 1.05, 5.5, 4.6, 2.1, white)
    box("barge_wh_glass0315", 0, 22.6, deck + 1.55, 5.68, 4.78, 0.75, glass)
    box("barge_wh_roof0315", 0, 22.6, deck + 2.22, 5.9, 5.0, 0.24, dark)
    for stack_x in (-1.7, 1.7):
        cyl("barge_stack0315", stack_x, 24.9, deck + 1.5, 0.17, 1.7, metal, vertices=8)
    cyl("barge_mast0315", 0, 19.8, deck + 2.1, 0.08, 4.2, metal, vertices=6)
    box("barge_mast_bar0315", 0, 19.8, deck + 3.6, 2.2, 0.1, 0.1, metal)
    # Forecastle gear + mooring bollards.
    box("barge_windlass0315", 0, -23.6, deck + 0.35, 1.8, 1.1, 0.7, metal)
    for bx in (-3.7, 3.7):
        for by in (-25.4, 25.8):
            cyl("barge_bollard0315", bx, by, deck + 0.25, 0.15, 0.5, metal, vertices=6)


def build_port_crane():
    yellow = MATS["CitySignYellow"]
    metal = MATS["PropsMetal"]
    dark = MATS["RoofDark"]
    for ry in (-7.0, 7.0):
        box("crane_rail", 0, ry, 0.25, 26, 1.3, 0.5, dark)
    for lx in (-9.0, 9.0):
        for ly in (-7.0, 7.0):
            box("crane_leg", lx, ly, 15, 1.7, 1.7, 30, yellow)
    for ly in (-7.0, 7.0):
        box("crane_beam", 0, ly, 30.6, 20.5, 1.5, 1.8, yellow)
    for lx in (-9.0, 9.0):
        box("crane_cross", lx, 0, 30.6, 1.5, 15.5, 1.8, yellow)
    box("crane_deck", 0, 0, 32.2, 15, 11, 1.6, metal)
    box("crane_machine", -3.5, 2.5, 34.4, 6.5, 5.5, 3.0, yellow)
    for ax in (-2.6, 2.6):
        rbox("crane_aframe", ax, 0, 40.5, 1.1, 1.1, 16.5, yellow, rotation=(0.30, 0, 0))
        rbox("crane_aframe_b", ax, 0, 40.5, 1.1, 1.1, 16.5, yellow, rotation=(-0.30, 0, 0))
    rbox("crane_jib", 0, -20.7, 45.0, 1.7, 44, 1.9, yellow, rotation=(math.radians(-30), 0, 0))
    rbox("crane_counterjib", 0, 8.5, 35.2, 1.5, 17, 1.7, yellow, rotation=(math.radians(6), 0, 0))
    box("crane_counterweight", 0, 15.5, 33.4, 4.2, 3.2, 4.6, dark)
    tube_between("crane_tie_a", (0, 0, 48.6), (0, -38.5, 55.6), 0.22, 0.22, metal, vertices=6)
    tube_between("crane_tie_b", (0, 0, 48.6), (0, 16.4, 36.2), 0.22, 0.22, metal, vertices=6)
    box("crane_cab", 3.1, -4.5, 30.2, 3.0, 3.4, 3.0, MATS["FacadeGlass"])
    tube_between("crane_cable", (0, -38.5, 55.2), (0, -38.5, 21.0), 0.09, 0.09, MATS["WindowFrame"], vertices=6)
    box("crane_spreader", 0, -38.5, 20.4, 6.2, 2.4, 1.1, MATS["CityAccentRed"])
    box("crane_load", 0, -38.5, 18.2, 12.0, 2.4, 2.5, MATS["CityAccentBlue"])
    # 0.3.10: leg cross-bracing and a cab window band.
    for lx in (-9.0, 9.0):
        rbox("crane_brace_a", lx, 0, 15, 0.8, 17.5, 0.8, yellow, rotation=(0.55, 0, 0))
        rbox("crane_brace_b", lx, 0, 15, 0.8, 17.5, 0.8, yellow, rotation=(-0.55, 0, 0))
    panel("crane_cab_glass", 3.1, -6.28, 30.9, 2.6, 1.1, MATS["FacadeGlass"], "front")


main()
