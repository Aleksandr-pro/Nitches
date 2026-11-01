#!/usr/bin/env python3
"""Build a lightweight, original human character GLB for the native Godot game.

Uses only Python's standard library so CI and other agents can regenerate the
asset without Blender or external downloads. The model is a stylized, smooth-
shaded, medium-low-poly adult in everyday street clothes (about 1.84 m tall).
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/assets/models/characters/nitches_player.glb"

MATERIALS = [
    ("Skin", (0.63, 0.37, 0.25, 1.0), 0.0, 0.78),
    ("Jacket - deep teal", (0.055, 0.16, 0.15, 1.0), 0.0, 0.78),
    ("Shirt - warm ivory", (0.78, 0.70, 0.55, 1.0), 0.0, 0.84),
    ("Trousers - charcoal blue", (0.075, 0.105, 0.14, 1.0), 0.0, 0.9),
    ("Hair - dark brown", (0.045, 0.028, 0.022, 1.0), 0.0, 0.88),
    ("Shoes - dark leather", (0.045, 0.039, 0.034, 1.0), 0.0, 0.42),
    ("Warm metal details", (0.54, 0.31, 0.095, 1.0), 0.38, 0.42),
    ("Eyes", (0.89, 0.82, 0.69, 1.0), 0.0, 0.34),
    ("Iris", (0.12, 0.065, 0.035, 1.0), 0.0, 0.32),
    ("Mouth", (0.20, 0.075, 0.055, 1.0), 0.0, 0.8),
]
SKIN, JACKET, SHIRT, TROUSERS, HAIR, SHOES, METAL, EYES, IRIS, MOUTH = range(len(MATERIALS))
# 0.3.28: jointed limb hierarchy for procedural walk animation.
# Geometry is still authored in body space by the add_* helpers;
# add_mesh files it into the current limb bucket with positions
# shifted into that limb's joint-local space.  The writer emits a
# translation-only node hierarchy (bind rotations zero) so Godot
# can pose limbs without a skeleton or skinning cost.  Limb
# origins sit exactly on the joints used to author the limbs:
# hips (+-0.135, 0.83), knees (+-0.145, 0.48), ankles
# (+-0.155, 0.115), shoulders (+-0.333, 1.455), elbows
# (+-0.423, 1.155).  The torso anchor is the hip-ellipsoid
# centre (0, 0.875); the head pivots at the neck top (0, 1.595).
LIMBS = {
    "Torso": ("", (0.0, 0.875, 0.0)),
    "Head": ("Torso", (0.0, 1.595, 0.0)),
    "ThighL": ("Torso", (-0.135, 0.83, 0.0)),
    "ShinL": ("ThighL", (-0.145, 0.48, 0.018)),
    "FootL": ("ShinL", (-0.155, 0.115, -0.005)),
    "ThighR": ("Torso", (0.135, 0.83, 0.0)),
    "ShinR": ("ThighR", (0.145, 0.48, 0.018)),
    "FootR": ("ShinR", (0.155, 0.115, -0.005)),
    "UpperArmL": ("Torso", (-0.333, 1.455, 0.0)),
    "ForearmL": ("UpperArmL", (-0.423, 1.155, -0.006)),
    "UpperArmR": ("Torso", (0.333, 1.455, 0.0)),
    "ForearmR": ("UpperArmR", (0.423, 1.155, -0.006)),
}
CURRENT_LIMB = "Torso"
LIMB_BUCKETS = {}


def set_limb(name: str) -> None:
    global CURRENT_LIMB
    CURRENT_LIMB = name


def add_mesh(material: int, positions: list[tuple[float, float, float]], indices: list[int]) -> None:
    joint_x, joint_y, joint_z = LIMBS[CURRENT_LIMB][1]
    bucket = LIMB_BUCKETS.setdefault((CURRENT_LIMB, material), {"positions": [], "indices": []})
    offset = len(bucket["positions"])
    bucket["positions"].extend((x - joint_x, y - joint_y, z - joint_z) for x, y, z in positions)
    bucket["indices"].extend(offset + index for index in indices)


def add_ellipsoid(material: int, center: tuple[float, float, float], radii: tuple[float, float, float], segments: int = 16, rings: int = 10, deformation=None) -> None:
    cx, cy, cz = center
    rx, ry, rz = radii
    positions: list[tuple[float, float, float]] = []
    indices: list[int] = []
    for row in range(rings + 1):
        theta = math.pi * row / rings
        y_unit = math.cos(theta)
        ring_radius = math.sin(theta)
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            x_unit = math.cos(phi) * ring_radius
            z_unit = math.sin(phi) * ring_radius
            y = cy + ry * y_unit
            x = cx + rx * x_unit
            z = cz + rz * z_unit
            if deformation:
                x, y, z = deformation(x, y, z, x_unit, y_unit, z_unit)
            positions.append((x, y, z))
    for row in range(rings):
        for col in range(segments):
            a = row * segments + col
            b = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices)


def add_hemisphere_cap(center: tuple[float, float, float], radii: tuple[float, float, float], material: int) -> None:
    cx, cy, cz = center
    rx, ry, rz = radii
    segments, rows = 20, 8
    positions: list[tuple[float, float, float]] = []
    indices: list[int] = []
    low_angle = -0.12
    for row in range(rows + 1):
        theta = low_angle + (math.pi * 0.5 - low_angle) * row / rows
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            radial = math.cos(theta)
            positions.append((cx + rx * radial * math.cos(phi), cy + ry * math.sin(theta), cz + rz * radial * math.sin(phi)))
    for row in range(rows):
        for col in range(segments):
            a = row * segments + col
            b = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices)


def add_tube(material: int, start: tuple[float, float, float], end: tuple[float, float, float], radius_start: float, radius_end: float, depth_ratio: float = 0.92, segments: int = 12, caps: bool = True) -> None:
    ax, ay, az = start
    bx, by, bz = end
    direction = (bx - ax, by - ay, bz - az)
    length = math.sqrt(sum(v * v for v in direction))
    if length < 1e-6:
        return
    d = tuple(v / length for v in direction)
    helper = (0.0, 0.0, 1.0) if abs(d[2]) < 0.88 else (1.0, 0.0, 0.0)
    u = (d[1] * helper[2] - d[2] * helper[1], d[2] * helper[0] - d[0] * helper[2], d[0] * helper[1] - d[1] * helper[0])
    u_len = math.sqrt(sum(v * v for v in u))
    u = tuple(v / u_len for v in u)
    v = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    # Rounded shoulders and cuffs are made by overlapping soft end ellipsoids;
    # the tube itself has gently tapered, smooth cross-sections.
    ring_t = (0.05, 0.24, 0.76, 0.95)
    positions: list[tuple[float, float, float]] = []
    indices: list[int] = []
    for row, t in enumerate(ring_t):
        smooth_t = t * t * (3.0 - 2.0 * t)
        radius = radius_start + (radius_end - radius_start) * smooth_t
        cx, cy, cz = (ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t)
        for col in range(segments):
            angle = 2.0 * math.pi * col / segments
            ca, sa = math.cos(angle), math.sin(angle)
            positions.append((cx + radius * ca * u[0] + radius * depth_ratio * sa * v[0], cy + radius * ca * u[1] + radius * depth_ratio * sa * v[1], cz + radius * ca * u[2] + radius * depth_ratio * sa * v[2]))
    for row in range(len(ring_t) - 1):
        for col in range(segments):
            a = row * segments + col
            b = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d_idx = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d_idx))
    if caps:
        positions.extend((start, end))
        start_center = len(positions) - 2
        end_center = len(positions) - 1
        for col in range(segments):
            indices.extend((start_center, (col + 1) % segments, col))
            end_row = (len(ring_t) - 1) * segments
            indices.extend((end_center, end_row + col, end_row + (col + 1) % segments))
    add_mesh(material, positions, indices)


def add_rings(material: int, sections: list[tuple[float, float, float, float]], segments: int = 16) -> None:
    """Y-oriented tapered body. Each section is (y, x-radius, z-radius, x-centre)."""
    positions: list[tuple[float, float, float]] = []
    indices: list[int] = []
    for y, rx, rz, cx in sections:
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            positions.append((cx + rx * math.cos(phi), y, rz * math.sin(phi)))
    for row in range(len(sections) - 1):
        for col in range(segments):
            a = row * segments + col
            b = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices)


def add_box(material: int, center: tuple[float, float, float], size: tuple[float, float, float]) -> None:
    cx, cy, cz = center
    sx, sy, sz = (v * 0.5 for v in size)
    positions = [(cx + x * sx, cy + y * sy, cz + z * sz) for x, y, z in (
        (-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
        (-1,-1,1), (1,-1,1), (1,1,1), (-1,1,1),
    )]
    # Double-sided PBR materials keep tiny flat accents readable from either face.
    indices = [0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 3,7,6, 3,6,2, 0,4,7, 0,7,3, 1,2,6, 1,6,5]
    add_mesh(material, positions, indices)


def add_triangle(material: int, points: list[tuple[float, float, float]]) -> None:
    add_mesh(material, points, [0, 1, 2])


def make_normals(positions: list[tuple[float, float, float]], indices: list[int]) -> list[tuple[float, float, float]]:
    normals = [[0.0, 0.0, 0.0] for _ in positions]
    model_centre = tuple(sum(p[k] for p in positions) / max(len(positions), 1) for k in range(3))
    for i in range(0, len(indices), 3):
        ia, ib, ic = indices[i:i + 3]
        a, b, c = positions[ia], positions[ib], positions[ic]
        ab = (b[0]-a[0], b[1]-a[1], b[2]-a[2])
        ac = (c[0]-a[0], c[1]-a[1], c[2]-a[2])
        n = (ab[1]*ac[2]-ab[2]*ac[1], ab[2]*ac[0]-ab[0]*ac[2], ab[0]*ac[1]-ab[1]*ac[0])
        # Flip triangles facing inward relative to this component's centre.
        centre = tuple((a[k] + b[k] + c[k]) / 3.0 for k in range(3))
        if sum(n[k] * (centre[k] - model_centre[k]) for k in range(3)) < 0.0:
            ib, ic = ic, ib
            indices[i + 1], indices[i + 2] = ib, ic
            n = (-n[0], -n[1], -n[2])
        for index in (ia, ib, ic):
            normals[index][0] += n[0]
            normals[index][1] += n[1]
            normals[index][2] += n[2]
    out = []
    for n in normals:
        length = math.sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2])
        out.append((n[0]/length, n[1]/length, n[2]/length) if length > 1e-8 else (0.0, 1.0, 0.0))
    return out


def ellipsoid_deform(x, y, z, x_unit, y_unit, z_unit):
    # Subtle jaw taper and a forward cheek/nose plane make the head read as a face,
    # rather than a featureless sphere, at the intended third-person camera range.
    jaw = 0.92 + 0.08 * max(0.0, y_unit)
    cheek = 1.0 + 0.035 * (1.0 - abs(x_unit)) * (1.0 - abs(y_unit))
    return x * jaw, y, z * cheek


def build_character() -> None:
    # Core torso: articulated-looking proportions with a shaped waist and shoulders.
    add_rings(JACKET, [
        (0.83, 0.225, 0.145, 0.0), (0.91, 0.270, 0.165, 0.0),
        (1.06, 0.268, 0.165, 0.0), (1.22, 0.300, 0.175, 0.0),
        (1.38, 0.350, 0.175, 0.0), (1.49, 0.372, 0.150, 0.0),
        (1.54, 0.285, 0.115, 0.0),
    ], 20)
    # Hips and two separately modelled trouser legs leave a clear human silhouette.
    add_ellipsoid(TROUSERS, (0.0, 0.875, 0.0), (0.265, 0.15, 0.158), 16, 10)
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        hip = (side * 0.135, 0.83, 0.0)
        knee = (side * 0.145, 0.48, 0.018)
        ankle = (side * 0.155, 0.115, -0.005)
        set_limb("Thigh" + suffix)
        add_tube(TROUSERS, hip, knee, 0.125, 0.105, 0.88, 14)
        set_limb("Shin" + suffix)
        add_ellipsoid(TROUSERS, knee, (0.108, 0.105, 0.105), 12, 8)
        add_tube(TROUSERS, knee, ankle, 0.101, 0.071, 0.90, 14)
        set_limb("Foot" + suffix)
        add_ellipsoid(SHOES, (side * 0.155, 0.084, -0.074), (0.112, 0.072, 0.178), 14, 8)
        add_box(SHOES, (side * 0.155, 0.045, -0.075), (0.205, 0.024, 0.31))
        # A warm seam and understated pocket keep the outfit readable without textures.
        set_limb("Thigh" + suffix)
        add_box(METAL, (side * 0.145, 0.842, -0.164), (0.10, 0.014, 0.009))
    set_limb("Torso")

    # Shirt insert and folded lapels on the front of the jacket (front is -Z).
    add_box(SHIRT, (0.0, 1.295, -0.175), (0.145, 0.34, 0.025))
    add_triangle(SHIRT, [(-0.088,1.50,-0.176), (-0.012,1.405,-0.198), (-0.038,1.51,-0.18)])
    add_triangle(SHIRT, [(0.088,1.50,-0.176), (0.012,1.405,-0.198), (0.038,1.51,-0.18)])
    add_box(METAL, (0.0, 1.19, -0.198), (0.008, 0.32, 0.008))
    for button_y in (1.35, 1.28, 1.21):
        add_ellipsoid(METAL, (0.0, button_y, -0.204), (0.009, 0.009, 0.005), 8, 5)

    # Collar and neck sit above the jacket, separated enough to read clearly.
    add_tube(SKIN, (0.0, 1.465, 0.0), (0.0, 1.595, 0.0), 0.061, 0.056, 0.94, 12)
    add_triangle(JACKET, [(-0.095,1.53,-0.13), (-0.018,1.46,-0.17), (-0.014,1.545,-0.155)])
    add_triangle(JACKET, [(0.095,1.53,-0.13), (0.018,1.46,-0.17), (0.014,1.545,-0.155)])

    # Relaxed arms angle slightly away from the body; hand and wrist are distinct.
    for side in (-1.0, 1.0):
        suffix = "L" if side < 0 else "R"
        shoulder = (side * 0.333, 1.455, 0.0)
        elbow = (side * 0.423, 1.155, -0.006)
        wrist = (side * 0.414, 0.865, -0.028)
        set_limb("UpperArm" + suffix)
        add_ellipsoid(JACKET, shoulder, (0.115, 0.128, 0.135), 12, 8)
        add_tube(JACKET, shoulder, elbow, 0.112, 0.082, 0.92, 14)
        set_limb("Forearm" + suffix)
        add_ellipsoid(JACKET, elbow, (0.083, 0.088, 0.082), 12, 8)
        add_tube(JACKET, elbow, wrist, 0.081, 0.062, 0.94, 14)
        add_box(SHIRT, (side * 0.414, 0.891, -0.027), (0.136, 0.042, 0.13))
        hand = (side * 0.414, 0.792, -0.04)
        add_ellipsoid(SKIN, hand, (0.061, 0.085, 0.05), 12, 8)
        add_ellipsoid(SKIN, (side * 0.365, 0.802, -0.055), (0.026, 0.052, 0.031), 10, 7)

    # Head: a tapered jaw, ears, eyes, brow, nose and mouth establish an unmistakably human face.
    set_limb("Head")
    add_ellipsoid(SKIN, (0.0, 1.675, 0.0), (0.125, 0.148, 0.115), 20, 14, ellipsoid_deform)
    add_ellipsoid(SKIN, (-0.124, 1.671, 0.0), (0.024, 0.042, 0.026), 12, 8)
    add_ellipsoid(SKIN, (0.124, 1.671, 0.0), (0.024, 0.042, 0.026), 12, 8)
    for side in (-1.0, 1.0):
        x = side * 0.044
        add_ellipsoid(EYES, (x, 1.696, -0.104), (0.019, 0.013, 0.010), 12, 8)
        add_ellipsoid(IRIS, (x, 1.696, -0.113), (0.008, 0.009, 0.0045), 10, 6)
        add_tube(HAIR, (x - 0.022, 1.719, -0.102), (x + 0.021, 1.723, -0.101), 0.007, 0.0055, 0.65, 8)
    add_ellipsoid(SKIN, (0.0, 1.659, -0.124), (0.023, 0.033, 0.031), 12, 8)
    add_tube(MOUTH, (-0.026, 1.614, -0.109), (0.026, 1.614, -0.109), 0.0045, 0.0045, 0.75, 8)

    # Hair cap and two soft side locks; the low-poly hairline is part of the mesh, not a texture.
    add_hemisphere_cap((0.0, 1.748, 0.006), (0.132, 0.093, 0.123), HAIR)
    add_ellipsoid(HAIR, (-0.119, 1.704, -0.005), (0.022, 0.074, 0.057), 12, 8)
    add_ellipsoid(HAIR, (0.119, 1.704, -0.005), (0.022, 0.074, 0.057), 12, 8)
    # A short side-swept fringe breaks the helmet-like cap silhouette.
    add_triangle(HAIR, [(-0.096,1.754,-0.083), (-0.015,1.712,-0.116), (0.002,1.767,-0.104)])
    add_triangle(HAIR, [(-0.015,1.712,-0.116), (0.063,1.744,-0.101), (0.002,1.767,-0.104)])

    # Fine waist, cuff and pocket details; all remain sub-pixel at driving range.
    set_limb("Torso")
    add_box(METAL, (0.0, 0.933, -0.17), (0.43, 0.026, 0.014))
    add_box(METAL, (0.0, 0.932, -0.181), (0.042, 0.034, 0.012))
    for side in (-1.0, 1.0):
        add_box(JACKET, (side * 0.205, 1.115, -0.177), (0.105, 0.092, 0.014))
        add_box(METAL, (side * 0.205, 1.158, -0.187), (0.082, 0.006, 0.006))


def align4(data: bytearray) -> None:
    while len(data) % 4:
        data.append(0)


def write_glb() -> None:
    build_character()
    binary = bytearray()
    buffer_views = []
    accessors = []
    meshes = []
    nodes = []

    def append_accessor(raw: bytes, component_type: int, count: int, accessor_type: str, target: int, minimum=None, maximum=None) -> int:
        align4(binary)
        offset = len(binary)
        binary.extend(raw)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": target})
        accessor = {"bufferView": len(buffer_views) - 1, "componentType": component_type, "count": count, "type": accessor_type}
        if minimum is not None:
            accessor["min"] = minimum
        if maximum is not None:
            accessor["max"] = maximum
        accessors.append(accessor)
        return len(accessors) - 1

    limb_mesh_nodes = {limb: [] for limb in LIMBS}
    for (limb, material_index), bucket in sorted(LIMB_BUCKETS.items()):
        positions = bucket["positions"]
        indices = bucket["indices"]
        if not positions or not indices:
            continue
        normals = make_normals(positions, indices)
        pflat = [v for p in positions for v in p]
        nflat = [v for n in normals for v in n]
        pos_raw = struct.pack("<%sf" % len(pflat), *pflat)
        norm_raw = struct.pack("<%sf" % len(nflat), *nflat)
        index_raw = struct.pack("<%sH" % len(indices), *indices)
        mins = [min(p[k] for p in positions) for k in range(3)]
        maxs = [max(p[k] for p in positions) for k in range(3)]
        position_accessor = append_accessor(pos_raw, 5126, len(positions), "VEC3", 34962, mins, maxs)
        normal_accessor = append_accessor(norm_raw, 5126, len(normals), "VEC3", 34962)
        index_accessor = append_accessor(index_raw, 5123, len(indices), "SCALAR", 34963)
        meshes.append({"name": limb + "_" + MATERIALS[material_index][0], "primitives": [{
            "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor},
            "indices": index_accessor,
            "material": material_index,
            "mode": 4,
        }]})
        mesh_index = len(meshes) - 1
        nodes.append({"name": limb + "_" + MATERIALS[material_index][0], "mesh": mesh_index})
        limb_mesh_nodes[limb].append(len(nodes) - 1)

    # Limb nodes carry only the joint translation relative to their
    # parent; rotations stay zero at bind so Godot poses them live.
    limb_node_index = {}
    for limb, (parent, joint) in LIMBS.items():
        if parent:
            parent_joint = LIMBS[parent][1]
            relative = [joint[k] - parent_joint[k] for k in range(3)]
        else:
            relative = list(joint)
        nodes.append({"name": limb, "translation": relative, "children": list(limb_mesh_nodes[limb])})
        limb_node_index[limb] = len(nodes) - 1
    for limb, (parent, _joint) in LIMBS.items():
        if parent:
            nodes[limb_node_index[parent]]["children"].append(limb_node_index[limb])
    children = [limb_node_index["Torso"]]

    gltf = {
        "asset": {"version": "2.0", "generator": "Nitches procedural human character builder", "copyright": "Original Nitches character asset"},
        "scene": 0,
        "scenes": [{"name": "Nitches Player Character", "nodes": [len(nodes)]}],
        "nodes": nodes + [{"name": "NitchesPlayerCharacter", "children": children}],
        "meshes": meshes,
        "materials": [{
            "name": name,
            "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": metallic, "roughnessFactor": roughness},
            "doubleSided": True,
        } for name, color, metallic, roughness in MATERIALS],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
        "extras": {"purpose": "Native player avatar, spawned only when exiting a parked car", "heightMeters": 1.84, "triangleBudget": sum(len(b["indices"]) // 3 for b in LIMB_BUCKETS.values()), "joints": list(LIMBS)},
    }
    json_bytes = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    align4(binary)
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_length))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(binary), 0x004E4942))
        f.write(binary)
    print("Wrote %s (%d bytes), %d triangles, %d material meshes" % (OUTPUT.relative_to(ROOT), OUTPUT.stat().st_size, gltf["extras"]["triangleBudget"], len(meshes)))


if __name__ == "__main__":
    write_glb()
