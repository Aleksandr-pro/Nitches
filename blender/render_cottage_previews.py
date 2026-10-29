#!/usr/bin/env python3
"""Render four review views of each Sail Island cottage GLB.

Run with Blender:
    blender -b -noaudio --python blender/render_cottage_previews.py -- \
        /path/to/glb_dir /path/to/output_dir

The GLBs carry semantic materials only.  For a meaningful architectural
review this script temporarily binds the matching cottage albedo,
normal and roughness maps with world-space box projection, approximating
the world-triplanar assignment used by Godot.  It does not modify GLBs.
"""

import math
import os
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
TEXTURE_DIR = ROOT / "src" / "assets" / "textures" / "realworld"

TEXTURE_SETS = {
    "CottageSand": ("cottage_rammed_sand", 0.20),
    "CottageTravertine": ("cottage_travertine_coarse", 0.24),
    "CottageLimestone": ("cottage_limestone_blocks", 0.20),
    "CottageBasalt": ("cottage_basalt", 0.28),
    "CottageTeak": ("cottage_teak_weathered", 0.34),
    "CottageRoofMetal": ("cottage_roof_metal", 0.42),
    "CottageBronze": ("cottage_roof_metal", 0.50),
    "CottagePaving": ("cottage_paving", 0.17),
    "CottageGravel": ("cottage_paving", 0.24),
}


def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def bind_textures(frame):
    for material in bpy.data.materials:
        if not material.use_nodes or material.name not in TEXTURE_SETS:
            continue
        texture_name, scale = TEXTURE_SETS[material.name]
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        principled = nodes.get("Principled BSDF")
        if principled is None:
            continue
        coordinates = nodes.new("ShaderNodeTexCoord")
        coordinates.object = frame
        coordinates.location = (-900, 0)
        mapping = nodes.new("ShaderNodeMapping")
        mapping.location = (-720, 0)
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        links.new(coordinates.outputs["Object"], mapping.inputs["Vector"])

        def image_node(filename, y, non_color=False):
            node = nodes.new("ShaderNodeTexImage")
            node.location = (-520, y)
            node.projection = "BOX"
            node.projection_blend = 0.35
            image_path = TEXTURE_DIR / filename
            if image_path.exists():
                node.image = bpy.data.images.load(str(image_path), check_existing=True)
                if non_color:
                    node.image.colorspace_settings.name = "Non-Color"
            links.new(mapping.outputs["Vector"], node.inputs["Vector"])
            return node

        albedo = image_node(f"{texture_name}.jpg", 180)
        links.new(albedo.outputs["Color"], principled.inputs["Base Color"])
        roughness = image_node(f"{texture_name}_roughness.jpg", -40, True)
        links.new(roughness.outputs["Color"], principled.inputs["Roughness"])
        normal = image_node(f"{texture_name}_normal.jpg", -280, True)
        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.location = (-260, -280)
        normal_map.inputs["Strength"].default_value = 0.85
        links.new(normal.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])


def prepare_scene(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 18
    scene.cycles.use_denoising = False
    scene.cycles.device = "CPU"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 620
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = 0.15

    world = bpy.data.worlds.new("CottagePreviewWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.52, 0.69, 0.94, 1.0)
    background.inputs["Strength"].default_value = 0.72

    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    frame = bpy.data.objects.new("PBRFrame", None)
    scene.collection.objects.link(frame)
    bind_textures(frame)

    # Neutral sand apron outside the estate wall.
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, -0.06))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    ground.dimensions = (110, 85, 0.08)
    ground_material = bpy.data.materials.new("PreviewSand")
    ground_material.use_nodes = True
    ground_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.72, 0.63, 0.47, 1)
    ground_material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(ground_material)

    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(1.2)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(48), math.radians(8), math.radians(38))
    scene.collection.objects.link(sun)

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera_data.lens = 34
    camera_data.clip_end = 300
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    glb_dir = Path(argv[0]) if len(argv) > 0 else Path("/tmp/cottage_props_out")
    output_dir = Path(argv[1]) if len(argv) > 1 else Path("/tmp/cottage_previews")
    output_dir.mkdir(parents=True, exist_ok=True)
    views = (
        ("front34", (-28, -31, 17), (0, 0, 2.6)),
        ("rear34", (28, 31, 17), (0, 0, 2.6)),
        ("side", (36, -7, 10), (0, 0, 2.8)),
        ("aerial", (-4, -20, 49), (0, 1, 0)),
    )
    for name in ("cottage_dune", "cottage_courtyard", "cottage_palm"):
        glb_path = glb_dir / f"{name}.glb"
        if not glb_path.exists():
            print(f"[preview] missing {glb_path}")
            continue
        scene, camera = prepare_scene(glb_path)
        for view_name, location, target in views:
            camera.location = location
            look_at(camera, target)
            scene.render.filepath = str(output_dir / f"{name}_{view_name}.png")
            bpy.ops.render.render(write_still=True)
            print(f"[preview] {scene.render.filepath}")


main()
