"""Dev-only Blender render harness for the procedural player character.

Usage (headless bpy venv):
    python scripts/dev_render_character.py [glb_path] [out_dir]

Renders a fixed review set (full body, face close-ups, shoes, hand,
stride pose) with Cycles CPU so character iterations can be judged
visually before integrating.  Not used by CI or the game build.

Blender frame after glTF import: character front = +Y, up = +Z
(glTF (x, y, z) -> Blender (x, -z, y)).
"""
import math
import sys
from pathlib import Path

sys.setdlopenflags(0x1 | 0x100)  # RTLD_LAZY | RTLD_GLOBAL (stub lib symbols)
import bpy
from mathutils import Vector

GLB = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("src/assets/models/characters/nitches_player.glb")
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/home/user/nitches-char")
FILTER = [f for f in sys.argv[3].split(",") if f] if len(sys.argv) > 3 else []
OUT.mkdir(parents=True, exist_ok=True)

# --- clean scene ------------------------------------------------------------
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for coll in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
    pass

bpy.ops.import_scene.gltf(filepath=str(GLB.resolve()))

# --- world / lights / ground -------------------------------------------------
world = bpy.data.worlds["World"]
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.32, 0.34, 0.38, 1.0)
bg.inputs[1].default_value = 0.55


def add_sun(location, energy, rot_deg):
    data = bpy.data.lights.new("Sun", "SUN")
    data.energy = energy
    obj = bpy.data.objects.new("Sun", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    return obj


def add_area(location, energy, size, target):
    data = bpy.data.lights.new("Area", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new("Area", data)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return obj


add_sun((2.5, 3.0, 4.0), 3.2, (52, 0, 35))
add_area((-2.2, 2.6, 1.6), 260, 2.5, (0, 0, 1.0))   # soft front-left fill
add_area((0.5, -2.4, 2.2), 320, 2.0, (0, 0, 1.2))   # rim from behind

bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
ground = bpy.context.object
gmat = bpy.data.materials.new("Ground")
gmat.use_nodes = True
bsdf = gmat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.42, 0.43, 0.45, 1.0)
bsdf.inputs["Roughness"].default_value = 0.95
ground.data.materials.append(gmat)

# --- render setup --------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.cycles.device = "CPU"
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Base Contrast"

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
scene.camera = cam


def shoot(name, location, target, lens=42, res=(900, 1350)):
    if FILTER and not any(name.startswith(f) for f in FILTER):
        return
    cam.location = location
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = lens
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = str(OUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("SHOT", name)


JOINTS = ["Torso", "Head", "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR",
          "UpperArmL", "ForearmL", "UpperArmR", "ForearmR"]


def set_pose(pose_deg):
    for name in JOINTS:
        obj = bpy.data.objects.get(name)
        if obj:
            obj.rotation_mode = "XYZ"  # glTF import leaves QUATERNION mode
            obj.rotation_euler = (math.radians(pose_deg.get(name, 0.0)), 0.0, 0.0)
    bpy.context.view_layer.update()


shoot("01_full_front", (0, 3.5, 1.05), (0, 0, 0.94))
shoot("02_full_34", (2.4, 2.7, 1.25), (0, 0, 0.92))
shoot("03_profile", (3.3, 0.1, 1.05), (0, 0, 0.94))
shoot("04_face_front", (0, 0.60, 1.70), (0, 0.03, 1.660), lens=58, res=(1100, 1100))
shoot("05_face_34", (0.40, 0.46, 1.75), (0, 0.03, 1.655), lens=58, res=(1100, 1100))
shoot("06_back", (0.7, -3.2, 1.25), (0, 0, 0.94))
shoot("07_shoes", (0.55, 0.80, 0.30), (0.10, 0.05, 0.07), lens=46, res=(1000, 800))
shoot("08_hand", (-0.78, 0.52, 0.98), (-0.47, 0.03, 0.80), lens=50, res=(1000, 1000))
shoot("10_torso", (0.32, 1.12, 1.38), (0, 0, 1.22), lens=48, res=(1000, 1100))

set_pose({"ThighL": 30, "ShinL": -16, "FootL": -8, "ThighR": -24, "ShinR": -30, "FootR": 18,
          "UpperArmL": -20, "ForearmL": -14, "UpperArmR": 22, "ForearmR": -18, "Torso": 4, "Head": -3})
shoot("09_stride", (2.4, 2.7, 1.25), (0, 0, 0.92))
set_pose({})

print("RENDER_DONE")
