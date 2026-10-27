#!/usr/bin/env python3
"""Generate a reusable, metre-scale Dubai-inspired premium cafe GLB.

Requirements: Python 3, numpy, trimesh, Pillow. The exported mesh uses a ground-centred
origin and faces local +X, so NativeWorldBuilder can place it with make_transform.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/assets/models/props/dubai_premium_cafe.glb"

# Material names mirror NativeWorldBuilder._prop_material(). Albedo and normal
# maps are embedded in the GLB as well, so the model remains textured when an
# agent imports it outside this project's custom material remapping.
MATERIALS = {
    "CafeTravertine": {"color": [245, 238, 222, 255], "metallic": 0.0, "roughness": 0.78, "base": "user_travertine.jpg", "normal": "user_travertine_normal.jpg", "uv_scale": 0.22},
    "CafeLimestone": {"color": [248, 242, 229, 255], "metallic": 0.0, "roughness": 0.88, "base": "user_stone_tiles_beige.jpg", "normal": None, "uv_scale": 0.24},
    "CafeBronze": {"color": [184, 137, 78, 255], "metallic": 0.72, "roughness": 0.36, "base": "user_brushed_metal.jpg", "normal": "user_brushed_metal_normal.jpg", "uv_scale": 0.40},
    "CafeSteel": {"color": [194, 204, 207, 255], "metallic": 0.82, "roughness": 0.34, "base": "user_brushed_metal.jpg", "normal": "user_brushed_metal_normal.jpg", "uv_scale": 0.44},
    "CafeGlass": {"color": [154, 190, 202, 78], "metallic": 0.18, "roughness": 0.055, "base": None, "normal": None, "uv_scale": 1.0, "alpha": "BLEND"},
    "CafeOak": {"color": [222, 193, 157, 255], "metallic": 0.0, "roughness": 0.78, "base": "user_wood_slats_dark.jpg", "normal": "user_wood_slats_dark_normal.jpg", "uv_scale": 0.32},
    "CafeWarmLight": {"color": [255, 221, 165, 255], "metallic": 0.0, "roughness": 0.35, "base": None, "normal": None, "uv_scale": 1.0, "emissive": [0.8, 0.34, 0.08]},
    "CafeCream": {"color": [248, 241, 225, 255], "metallic": 0.0, "roughness": 0.80, "base": "user_travertine.jpg", "normal": "user_travertine_normal.jpg", "uv_scale": 0.36},
    "CafeFabric": {"color": [248, 239, 219, 255], "metallic": 0.0, "roughness": 0.92, "base": "cafe_linen.jpg", "normal": "cafe_linen_normal.png", "uv_scale": 8.0},
    "CafeCounter": {"color": [210, 211, 207, 255], "metallic": 0.10, "roughness": 0.28, "base": "user_black_granite.jpg", "normal": "user_black_granite_normal.jpg", "uv_scale": 0.34},
    "CafeGreen": {"color": [224, 233, 211, 255], "metallic": 0.0, "roughness": 0.94, "base": "foliage.jpg", "normal": "foliage_normal.jpg", "uv_scale": 0.72},
    "CafeCeramic": {"color": [245, 239, 226, 255], "metallic": 0.08, "roughness": 0.36, "base": "user_marble_tiles.jpg", "normal": "user_marble_tiles_normal.jpg", "uv_scale": 0.22},
}
TEXTURE_ROOT = ROOT / "src/assets/textures/realworld"
_TEXTURE_CACHE = {}


def _generate_linen_textures():
    """Create a subtle, tileable linen albedo + normal pair for the parasols."""
    from PIL import Image

    TEXTURE_ROOT.mkdir(parents=True, exist_ok=True)
    size = 512
    yy, xx = np.mgrid[0:size, 0:size].astype(float)
    rng = np.random.default_rng(271828)
    warp = np.cos(math.tau * xx / 4.0)
    weft = np.cos(math.tau * yy / 4.0)
    broad = 1.2 * np.sin(math.tau * xx / size * 3.0) + 0.9 * np.sin(math.tau * yy / size * 2.0)
    # Integer-frequency Fourier noise wraps seamlessly at all four edges.
    noise = np.zeros((size, size), dtype=float)
    for _ in range(28):
        fx, fy = rng.integers(1, 90, size=2)
        phase = rng.uniform(0.0, math.tau)
        noise += rng.normal(0.0, 1.0) * np.cos(math.tau * (fx * xx + fy * yy) / size + phase)
    noise = noise / max(float(noise.std()), 1e-8) * 1.1
    luminance = 223.0 + 1.15 * warp + 1.05 * weft + broad + noise
    rgb = np.stack((luminance * 1.035, luminance, luminance * 0.925), axis=-1)
    albedo = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB")
    albedo_path = TEXTURE_ROOT / "cafe_linen.jpg"
    albedo.save(albedo_path, format="JPEG", quality=94, subsampling=0, optimize=True)

    height = 0.08 * warp + 0.08 * weft
    grad_y, grad_x = np.gradient(height)
    normal = np.stack((128.0 - grad_x * 28.0, 128.0 - grad_y * 28.0, np.full_like(height, 252.0)), axis=-1)
    normal_image = Image.fromarray(np.clip(normal, 0, 255).astype(np.uint8), mode="RGB")
    normal_path = TEXTURE_ROOT / "cafe_linen_normal.png"
    normal_image.save(normal_path, format="PNG", optimize=True)


def _load_texture(filename):
    if filename is None:
        return None
    if filename not in _TEXTURE_CACHE:
        from PIL import Image

        with Image.open(TEXTURE_ROOT / filename) as image:
            cached = image.copy()
            cached.format = image.format
            _TEXTURE_CACHE[filename] = cached
    return _TEXTURE_CACHE[filename]

parts: dict[str, list[trimesh.Trimesh]] = {name: [] for name in MATERIALS}


def _transform(center, rotations=()):
    matrix = np.eye(4)
    for angle, axis in rotations:
        matrix = matrix @ trimesh.transformations.rotation_matrix(angle, axis)
    matrix[:3, 3] = np.asarray(center, dtype=float)
    return matrix


def box(material, center, size, rotations=()):
    mesh = trimesh.creation.box(extents=np.asarray(size, dtype=float))
    mesh.apply_transform(_transform(center, rotations))
    mesh.metadata["smooth_normals"] = False
    parts[material].append(mesh)


def cylinder(material, center, radius, height, sections=16, axis="y", top_radius=None):
    if top_radius is None or abs(top_radius - radius) < 1e-6:
        mesh = trimesh.creation.cylinder(radius=radius, height=height, sections=sections)
    else:
        mesh = trimesh.creation.cone(radius=radius, height=height, sections=sections)
    if axis == "y":
        rotation = ((-math.pi / 2.0, (1.0, 0.0, 0.0)),)
    elif axis == "x":
        rotation = ((math.pi / 2.0, (0.0, 1.0, 0.0)),)
    else:
        rotation = ()
    mesh.apply_transform(_transform(center, rotation))
    mesh.metadata["smooth_normals"] = True
    parts[material].append(mesh)


def sphere(material, center, scale, subdivisions=2):
    mesh = trimesh.creation.icosphere(subdivisions=subdivisions, radius=1.0)
    mesh.apply_scale(np.asarray(scale, dtype=float))
    mesh.apply_translation(np.asarray(center, dtype=float))
    mesh.metadata["smooth_normals"] = True
    parts[material].append(mesh)


def leaf(material, base, direction, length, width, segments=10):
    """A thin, curved lanceolate leaf with a softly folded midrib."""
    origin = np.asarray(base, dtype=float)
    direction = np.asarray(direction, dtype=float)
    direction /= max(np.linalg.norm(direction), 1e-8)
    horizontal = np.array((direction[2], 0.0, -direction[0]), dtype=float)
    if np.linalg.norm(horizontal) < 1e-5:
        horizontal = np.array((1.0, 0.0, 0.0))
    horizontal /= np.linalg.norm(horizontal)
    across = np.linspace(-1.0, 1.0, 5)
    vertices = []
    for step in range(segments + 1):
        t = step / segments
        center = origin + direction * (length * t)
        center[1] += 0.10 * math.sin(math.pi * t)
        profile = max(0.015, math.sin(math.pi * t) ** 0.78)
        for u in across:
            camber = (1.0 - abs(u)) * width * 0.13
            point = center + horizontal * (u * width * profile * 0.5)
            point[1] += camber
            vertices.append(point)
    faces = []
    for row in range(segments):
        for column in range(4):
            a = row * 5 + column
            b = a + 1
            c = a + 5
            d = c + 1
            faces.extend(((a, c, b), (b, c, d)))
    mesh = trimesh.Trimesh(vertices=np.asarray(vertices), faces=np.asarray(faces), process=False)
    mesh.metadata["smooth_normals"] = True
    parts[material].append(mesh)


def beam(material, start, end, width, depth=None):
    """Box beam between two 3D points, primarily for the gold screen lattice."""
    a, b = np.asarray(start, dtype=float), np.asarray(end, dtype=float)
    delta = b - a
    length = float(np.linalg.norm(delta))
    if length < 1e-5:
        return
    direction = delta / length
    # Local beam length is X; rotate X onto the required direction.
    axis = np.cross((1.0, 0.0, 0.0), direction)
    dot = float(np.clip(np.dot((1.0, 0.0, 0.0), direction), -1.0, 1.0))
    if np.linalg.norm(axis) < 1e-8:
        rotations = ((math.pi, (0.0, 1.0, 0.0)),) if dot < 0 else ()
    else:
        rotations = ((math.acos(dot), axis / np.linalg.norm(axis)),)
    box(material, (a + b) * 0.5, (length, width, depth or width), rotations)


def _unwrap_for_pbr(mesh, uv_scale, smooth_normals):
    """Build per-face planar UVs with explicit hard or smooth shading normals."""
    faces = mesh.faces.copy()
    triangles = mesh.vertices[faces]
    cross = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    face_normals = trimesh.util.unitize(cross)
    if smooth_normals:
        vertex_normals = np.zeros_like(mesh.vertices)
        for corner in range(3):
            np.add.at(vertex_normals, faces[:, corner], face_normals)
        vertex_normals = trimesh.util.unitize(vertex_normals)
        split_normals = vertex_normals[faces].reshape(-1, 3)
    else:
        split_normals = np.repeat(face_normals, 3, axis=0)

    # Dominant-axis projection avoids stretching texture detail on boxes, bars,
    # furniture and frame members. Orient each face's UV basis consistently.
    uv = np.empty((len(faces), 3, 2), dtype=float)
    for face_index, normal in enumerate(face_normals):
        axis = int(np.argmax(np.abs(normal)))
        points = triangles[face_index]
        if axis == 0:
            uv[face_index, :, 0] = points[:, 2]
            uv[face_index, :, 1] = -np.sign(normal[0]) * points[:, 1]
        elif axis == 1:
            uv[face_index, :, 0] = points[:, 0]
            uv[face_index, :, 1] = -np.sign(normal[1]) * points[:, 2]
        else:
            uv[face_index, :, 0] = points[:, 0]
            uv[face_index, :, 1] = np.sign(normal[2]) * points[:, 1]
    uv *= uv_scale

    # Duplicate triangle vertices at UV seams and copy the original smooth
    # normals, keeping the stone, glass and curved metal surfaces clean.
    split_vertices = triangles.reshape(-1, 3)
    split_uv = uv.reshape(-1, 2)
    split_faces = np.arange(len(split_vertices), dtype=np.int64).reshape(-1, 3)
    unwrapped = trimesh.Trimesh(vertices=split_vertices, faces=split_faces, process=False)
    unwrapped.vertex_normals = split_normals
    unwrapped.visual = TextureVisuals(uv=split_uv)
    return unwrapped


def mashrabiya_panel(x, z, width, height, facing="x"):
    """Fine but low-poly mashrabiya diamond lattice in a framed panel."""
    y0, y1 = 0.62, 3.35
    if facing == "x":
        box("CafeBronze", (x, (y0 + y1) * 0.5, z), (0.075, height, width))
        lo, hi = z - width * 0.44, z + width * 0.44
        pitch = 0.34
        for base in np.arange(lo - height, hi + height, pitch):
            # Intersect long diagonals with the rectangular panel boundaries.
            p0 = max(0.0, (lo - base))
            p1 = min(height, (hi - base))
            if p1 > p0:
                beam("CafeBronze", (x + 0.055, y0 + p0, base + p0), (x + 0.055, y0 + p1, base + p1), 0.035, 0.035)
            p0 = max(0.0, (base - hi))
            p1 = min(height, (base - lo))
            if p1 > p0:
                beam("CafeBronze", (x + 0.055, y0 + p0, base - p0), (x + 0.055, y0 + p1, base - p1), 0.035, 0.035)
        box("CafeBronze", (x + 0.08, y0 + 0.04, z), (0.12, 0.08, width + 0.16))
        box("CafeBronze", (x + 0.08, y1 - 0.04, z), (0.12, 0.08, width + 0.16))
    else:
        # Plane parallel to the X/Y façade at fixed Z.
        box("CafeBronze", (x, (y0 + y1) * 0.5, z), (width, height, 0.075))
        lo, hi = x - width * 0.44, x + width * 0.44
        pitch = 0.34
        for base in np.arange(lo - height, hi + height, pitch):
            p0 = max(0.0, lo - base)
            p1 = min(height, hi - base)
            if p1 > p0:
                beam("CafeBronze", (base + p0, y0 + p0, z + 0.055), (base + p1, y0 + p1, z + 0.055), 0.035)
            p0 = max(0.0, base - hi)
            p1 = min(height, base - lo)
            if p1 > p0:
                beam("CafeBronze", (base - p0, y0 + p0, z + 0.055), (base - p1, y0 + p1, z + 0.055), 0.035)
        box("CafeBronze", (x, y0 + 0.04, z + 0.08), (width + 0.16, 0.08, 0.12))
        box("CafeBronze", (x, y1 - 0.04, z + 0.08), (width + 0.16, 0.08, 0.12))


# Floor / podium: the origin is the pavement plane at the cafe centre.
box("CafeTravertine", (-1.94, 0.08, 0.0), (6.95, 0.16, 8.15))
box("CafeTravertine", (3.15, 0.055, 0.0), (5.05, 0.11, 8.55))
# Fine brass floor inlays and a broad, welcoming threshold.
for z in (-3.55, -2.95, 2.95, 3.55):
    box("CafeBronze", (-1.93, 0.166, z), (6.7, 0.018, 0.025))
box("CafeLimestone", (1.15, 0.17, 0.0), (0.48, 0.06, 7.7))

# Interior shell, glazing and bronze frame. Main entrance and service side face +X.
box("CafeLimestone", (-5.18, 1.98, 0.0), (0.34, 3.58, 7.85))
box("CafeLimestone", (-1.95, 0.42, -3.80), (6.45, 0.46, 0.32))
box("CafeLimestone", (-1.95, 0.42, 3.80), (6.45, 0.46, 0.32))
# Full-height smoked glass elevations.
box("CafeGlass", (-5.00, 2.02, 0.0), (0.055, 2.95, 6.70))
box("CafeGlass", (-1.95, 2.00, -3.60), (5.95, 2.95, 0.055))
box("CafeGlass", (-1.95, 2.00, 3.60), (5.95, 2.95, 0.055))
# Street-facing glass facade with a pair of sliding doors and bronze transom.
for z0, z1 in ((-3.34, -1.30), (1.30, 3.34)):
    box("CafeGlass", (1.10, 2.00, (z0 + z1) * 0.5), (0.055, 2.95, z1 - z0))
box("CafeGlass", (1.10, 2.78, 0.0), (0.055, 1.40, 2.48))
for z in (-1.26, -0.42, 0.42, 1.26):
    box("CafeGlass", (1.16, 1.94, z), (0.025, 2.82, 0.025))
# Dark bronze structural mullions, corner piers and a deep entry portal.
for x in (-4.90, -3.40, -1.90, -0.40, 1.03):
    for z in (-3.62, 3.62):
        box("CafeBronze", (x, 2.04, z), (0.105, 3.30, 0.105))
for z in (-3.50, -1.24, 1.24, 3.50):
    box("CafeBronze", (1.19, 2.02, z), (0.11, 3.28, 0.11))
box("CafeBronze", (1.18, 3.55, 0.0), (0.18, 0.15, 7.25))
# Tall limestone piers and polished bronze door pulls.
for z in (-3.96, 3.96):
    box("CafeLimestone", (1.06, 2.07, z), (0.40, 3.78, 0.34))
for z in (-0.07, 0.07):
    box("CafeBronze", (1.23, 1.85, z), (0.08, 0.62, 0.035))

# A dramatic floating canopy: warm limestone top, bronze soffit and crisp fascia.
box("CafeLimestone", (-1.85, 4.06, 0.0), (7.75, 0.30, 8.55))
box("CafeBronze", (-1.70, 3.88, 0.0), (7.55, 0.09, 8.33))
box("CafeCream", (-1.72, 4.24, 0.0), (7.82, 0.12, 8.62))
# Canopy cantilever on the terrace side, carried on slender bronze blades.
box("CafeCream", (2.15, 4.05, 0.0), (1.50, 0.22, 8.40))
box("CafeBronze", (2.16, 3.91, 0.0), (1.48, 0.07, 8.22))
for z in (-3.88, -2.58, -1.29, 0.0, 1.29, 2.58, 3.88):
    box("CafeBronze", (1.18, 3.30, z), (0.10, 1.28, 0.10))
    box("CafeBronze", (2.24, 3.26, z), (0.08, 1.36, 0.08))
# Layered perimeter fascia and recessed linear lighting.
for z in (-4.28, 4.28):
    box("CafeBronze", (-1.84, 4.08, z), (7.80, 0.34, 0.10))
    box("CafeWarmLight", (-1.82, 3.86, z - (0.065 if z > 0 else -0.065)), (7.40, 0.035, 0.035))
for x in (-5.64, 2.92):
    box("CafeBronze", (x, 4.08, 0.0), (0.10, 0.34, 8.35))
# Slender fins and a recessed rooflight give the canopy a sculpted skyline.
for z in (-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0):
    box("CafeLimestone", (-1.10, 4.37, z), (6.0, 0.08, 0.08))
box("CafeGlass", (-1.9, 4.335, 0.0), (2.8, 0.025, 1.55))

# Mashrabiya screens: geometric bronze lattice adds a restrained Gulf reference.
mashrabiya_panel(-4.76, 0.0, 5.85, 2.73, "x")
mashrabiya_panel(-2.00, -3.72, 3.30, 2.73, "z")
# A discreet eight-point star emblem above the entrance, built as real geometry.
for sign_x, sign_y, sign_z in ((1.29, 3.13, 0.0),):
    for angle in range(8):
        theta = math.pi * angle / 8.0
        beam(
            "CafeBronze",
            (sign_x, sign_y + math.sin(theta) * 0.30, sign_z + math.cos(theta) * 0.30),
            (sign_x, sign_y - math.sin(theta) * 0.30, sign_z - math.cos(theta) * 0.30),
            0.045,
            0.045,
        )
    sphere("CafeWarmLight", (sign_x + 0.025, sign_y, sign_z), (0.07, 0.07, 0.07), 1)

# Interior stone-and-wood coffee bar, shelving, seating and small equipment.
box("CafeOak", (-0.68, 0.62, 0.0), (2.15, 0.14, 4.65))
box("CafeCounter", (-0.68, 1.08, 0.0), (2.00, 0.80, 4.45))
box("CafeTravertine", (0.34, 1.51, 0.0), (0.18, 0.07, 4.55))
box("CafeOak", (-3.00, 0.56, -2.74), (3.05, 0.26, 1.15))
box("CafeFabric", (-3.00, 0.91, -2.74), (3.00, 0.42, 0.94))
box("CafeOak", (-3.00, 1.28, -3.28), (3.00, 0.72, 0.12))
# Backbar shelving and bronze-edged display niches.
for y in (1.92, 2.50, 3.05):
    box("CafeOak", (-4.52, y, 0.0), (0.28, 0.075, 3.25))
for z in (-1.58, -0.53, 0.53, 1.58):
    box("CafeBronze", (-4.34, 2.50, z), (0.08, 1.12, 0.065))
# Coffee equipment, cups and brushed brass taps.
for z in (-1.36, -0.68, 0.0, 0.68, 1.36):
    cylinder("CafeSteel", (-0.80, 1.82, z), 0.16, 0.46, 12, "y")
    cylinder("CafeCeramic", (-0.76, 2.075, z), 0.09, 0.08, 12, "y")
for z in (-1.62, -0.54, 0.54, 1.62):
    cylinder("CafeBronze", (-0.52, 1.70, z), 0.028, 0.44, 8, "y")
# Commercial espresso station: polished machine body, group heads, gauges,
# portafilters and twin grinders make the open bar read as a real cafe interior.
box("CafeSteel", (-0.64, 1.95, 0.0), (1.08, 0.58, 2.74))
box("CafeBronze", (-0.075, 2.02, 0.0), (0.035, 0.43, 2.50))
for z in (-0.82, 0.0, 0.82):
    cylinder("CafeSteel", (0.01, 1.76, z), 0.105, 0.17, 20, "x")
    beam("CafeSteel", (0.10, 1.70, z), (0.34, 1.63, z + 0.12), 0.035)
    sphere("CafeBronze", (-0.045, 2.22, z), (0.055, 0.055, 0.055), 2)
    # Small pressure gauge rim and ivory dial.
    cylinder("CafeBronze", (-0.035, 2.34, z), 0.075, 0.035, 20, "x")
    cylinder("CafeCream", (-0.012, 2.34, z), 0.055, 0.012, 20, "x")
for z in (-1.90, 1.90):
    box("CafeSteel", (-1.14, 1.77, z), (0.54, 0.66, 0.54))
    cylinder("CafeGlass", (-1.14, 2.23, z), 0.16, 0.32, 18, "y")
    cylinder("CafeCream", (-1.14, 2.40, z), 0.14, 0.055, 18, "y")
    cylinder("CafeBronze", (-1.14, 2.46, z), 0.06, 0.075, 14, "y")
# A lit pastry display case at the end of the bar, with individually modelled pastries.
box("CafeBronze", (-0.20, 1.55, 1.72), (0.86, 0.07, 1.05))
box("CafeGlass", (-0.20, 1.92, 1.72), (0.76, 0.62, 0.94))
for y in (1.70, 1.94):
    box("CafeSteel", (-0.20, y, 1.72), (0.67, 0.025, 0.82))
for z in (1.42, 1.70, 1.98):
    sphere("CafeCeramic", (-0.17, 1.78, z), (0.10, 0.075, 0.09), 2)
    sphere("CafeCream", (-0.17, 2.02, z), (0.09, 0.065, 0.08), 2)

# Pendant lights, warm downlights and ceiling trim.
for z in (-2.5, -1.25, 0.0, 1.25, 2.5):
    cylinder("CafeBronze", (-1.85, 3.43, z), 0.025, 0.55, 8, "y")
    cylinder("CafeWarmLight", (-1.85, 3.16, z), 0.15, 0.10, 16, "y")
for x in (-4.55, -3.10, -1.65, -0.20):
    for z in (-3.12, 3.12):
        sphere("CafeWarmLight", (x, 3.39, z), (0.07, 0.055, 0.07), 1)
# Two high bar stools with bronze stems and upholstered seats.
for z in (-1.72, 1.72):
    cylinder("CafeBronze", (0.64, 0.55, z), 0.045, 0.88, 10, "y")
    cylinder("CafeBronze", (0.64, 0.14, z), 0.24, 0.045, 12, "y")
    box("CafeFabric", (0.64, 1.02, z), (0.48, 0.12, 0.48))
    box("CafeOak", (0.83, 1.25, z), (0.08, 0.48, 0.46))

# Private terrace with three compact marble tables and sculpted ivory parasols.
for table_index, z in enumerate((-2.72, 0.0, 2.72)):
    x = 3.72
    cylinder("CafeCeramic", (x, 0.81, z), 0.53, 0.12, 24, "y")
    cylinder("CafeBronze", (x, 0.43, z), 0.07, 0.72, 12, "y")
    cylinder("CafeBronze", (x, 0.10, z), 0.28, 0.055, 16, "y")
    # Four understated bronze chairs, aligned to the table and kept in footprint.
    for side in (-1.0, 1.0):
        chair_x = x + side * 0.92
        box("CafeBronze", (chair_x, 0.49, z), (0.54, 0.085, 0.48))
        box("CafeFabric", (chair_x, 0.55, z), (0.49, 0.055, 0.43))
        box("CafeBronze", (chair_x + side * 0.22, 0.82, z), (0.075, 0.64, 0.46))
        for dx in (-0.20, 0.20):
            for dz in (-0.17, 0.17):
                cylinder("CafeBronze", (chair_x + dx, 0.24, z + dz), 0.028, 0.46, 8, "y")
    # Offset parasol mast, low conical canopy and slim radial ribs.
    umbrella_x = 3.74
    cylinder("CafeBronze", (umbrella_x, 2.10, z), 0.035, 2.55, 10, "y")
    cylinder("CafeFabric", (umbrella_x, 3.30, z), 1.30, 0.40, 24, "y", top_radius=0.10)
    for rib in range(12):
        angle = math.tau * rib / 12.0
        beam(
            "CafeBronze",
            (umbrella_x + math.cos(angle) * 0.12, 3.16, z + math.sin(angle) * 0.12),
            (umbrella_x + math.cos(angle) * 1.22, 3.20, z + math.sin(angle) * 1.22),
            0.025,
            0.025,
        )

# Low linear planters around the terrace edges; leaves remain within the asset bounds.
for z in (-3.70, 3.70):
    box("CafeTravertine", (2.72, 0.29, z), (1.32, 0.48, 0.72))
    box("CafeBronze", (2.72, 0.54, z), (1.28, 0.045, 0.68))
    for frond in range(10):
        angle = math.tau * frond / 10.0
        direction = (0.46 * math.cos(angle), 0.90 + 0.12 * (frond % 3), 0.46 * math.sin(angle))
        leaf("CafeGreen", (2.70, 0.67, z), direction, 0.65 + 0.07 * (frond % 4), 0.18 + 0.025 * (frond % 3), 10)
# Warm bollard lights and bronze edge detailing finish the entrance route.
for z in (-3.30, 3.30):
    cylinder("CafeBronze", (2.02, 0.34, z), 0.11, 0.56, 12, "y")
    cylinder("CafeWarmLight", (2.02, 0.64, z), 0.09, 0.10, 12, "y")
for z in (-3.45, 3.45):
    box("CafeBronze", (3.24, 0.13, z), (4.30, 0.045, 0.055))

# Ensure the procedural, deterministic close-up linen maps are checked in with
# the source assets so native synchronization and standalone GLB export agree.
_generate_linen_textures()

# Merge by material into a compact set of photoreal PBR surfaces.
scene = trimesh.Scene()
for material_name, meshes in parts.items():
    meshes = [mesh for mesh in meshes if len(mesh.faces) > 0]
    if not meshes:
        continue
    spec = MATERIALS[material_name]
    prepared_meshes = [
        _unwrap_for_pbr(mesh, spec["uv_scale"], mesh.metadata.get("smooth_normals", False))
        for mesh in meshes
    ]
    merged = trimesh.util.concatenate(prepared_meshes)
    material = PBRMaterial(
        name=material_name,
        baseColorFactor=spec["color"],
        baseColorTexture=_load_texture(spec.get("base")),
        normalTexture=_load_texture(spec.get("normal")),
        metallicFactor=spec["metallic"],
        roughnessFactor=spec["roughness"],
        emissiveFactor=spec.get("emissive"),
        alphaMode=spec.get("alpha", "OPAQUE"),
        doubleSided=(material_name in ("CafeGlass", "CafeGreen")),
    )
    merged.visual.material = material
    merged.metadata["name"] = material_name
    scene.add_geometry(merged, geom_name=material_name, node_name=material_name)

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_bytes(trimesh.exchange.gltf.export_glb(scene, include_normals=True))

bounds = scene.bounds
size = bounds[1] - bounds[0]
if not (10.8 <= size[0] <= 11.5 and 4.3 <= size[1] <= 4.6 and 8.5 <= size[2] <= 9.1):
    raise RuntimeError(f"Unexpected Dubai cafe dimensions: {size.tolist()}")
print(f"Wrote {OUTPUT}: {OUTPUT.stat().st_size:,} bytes")
print(f"AABB min={bounds[0].round(3).tolist()} max={bounds[1].round(3).tolist()} size={size.round(3).tolist()}")
print(f"Parts={len(scene.geometry)} triangles={sum(len(mesh.faces) for mesh in scene.geometry.values()):,}")
