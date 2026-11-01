#!/usr/bin/env python3
"""Dev-only review renders of a converted car GLB (not shipped).

Imports the exported GLB into a fresh Blender scene and renders studio
orbit shots for eyeballing proportions, materials, lights and wheels
before a car is wired into the catalog.  Mirrors dev_render_character.py.

    python scripts/dev_render_car.py -- \
        --glb src/assets/models/cars/bugatti_chiron_super_sport.glb \
        --out /tmp/car_review
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> dict[str, str]:
    args: dict[str, str] = {}
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            args[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    return args


def look_at(cam, target: Vector) -> None:
    direction = Vector(target) - cam.location
    cam.rotation_mode = "XYZ"
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    args = parse_args()
    glb = Path(args["glb"]).resolve()
    out = Path(args["out"]).resolve()
    out.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"  # EEVEE needs libEGL (absent headless)
    scene.cycles.samples = 48
    scene.cycles.use_denoising = False
    scene.cycles.device = "CPU"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 800
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Base Contrast"
    except Exception:
        pass
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.32, 0.34, 0.38, 1.0)
    bg.inputs[1].default_value = 0.9

    # Ground plane at the car's floor.
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    mins = Vector((math.inf,) * 3)
    maxs = Vector((-math.inf,) * 3)
    for obj in meshes:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            for a in range(3):
                mins[a] = min(mins[a], p[a])
                maxs[a] = max(maxs[a], p[a])
    centre = (mins + maxs) * 0.5
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, mins.z - 0.001))
    ground = bpy.context.object
    gmat = bpy.data.materials.new("Ground")
    gmat.use_nodes = True
    bsdf = gmat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.16, 0.17, 0.19, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
    ground.data.materials.append(gmat)

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.2
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_mode = "XYZ"
    sun.rotation_euler = (math.radians(52), math.radians(8),
                          math.radians(38))
    fill_data = bpy.data.lights.new("Fill", "SUN")
    fill_data.energy = 0.9
    fill = bpy.data.objects.new("Fill", fill_data)
    scene.collection.objects.link(fill)
    fill.rotation_mode = "XYZ"
    fill.rotation_euler = (math.radians(65), math.radians(-6),
                           math.radians(215))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 42
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    target = Vector((centre.x, centre.y, mins.z + 0.55))
    # Blender after glTF import: nose faces -Y.
    shots = [
        ("01_front34", Vector((4.4, -4.8, 1.35)), target),
        ("02_rear34", Vector((-4.4, 4.8, 1.45)), target),
        ("03_side", Vector((6.8, centre.y, 0.75)), target),
        ("04_front", Vector((0.0, -6.4, 0.85)), target),
        ("05_rear", Vector((0.0, 6.4, 0.95)), target),
        ("06_top", Vector((0.4, centre.y - 0.4, 8.6)),
         Vector((centre.x, centre.y, mins.z))),
        ("07_wheel", Vector((2.1, -2.3, 0.55)),
         Vector((0.86, -1.36, mins.z + 0.34))),
        ("08_low_front", Vector((-2.6, -4.6, 0.45)), target),
    ]
    for name, location, look in shots:
        cam.location = location + Vector((0, 0, mins.z)) \
            if name != "06_top" else location
        look_at(cam, look)
        scene.render.filepath = str(out / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", name)
    print("DONE", out)


if __name__ == "__main__":
    main()
