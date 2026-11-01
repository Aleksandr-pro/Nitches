#!/usr/bin/env python3
"""Build the detailed human character GLB for the native Godot game.

0.3.29: full procedural rewrite for close-range realism (~64k tris):
skull-deformation face, one-piece swept hair cap, shaped jacket loft
with a closed muted zipper, fingered hands, lofted shoes.

0.3.30: photoreal texture pass.  Every surface now carries
procedurally synthesised PBR maps (albedo / tangent normal /
roughness): a face painted in world space over the deformed skull
(pores, freckles, moles, stubble, forehead lines, crow's feet),
radial-fibre irises behind real pupil holes, veined sclera, strand
hair, fabric weaves, denim twill, cell-grain leather, treaded
soles - plus fingernails, ear helices and an Adam's apple.
Requires numpy + Pillow (no CI workflow executes this script; the
committed GLB is the artefact).  Output is seed-deterministic.

Joint layout, material order (append-only) and the translation-only
node hierarchy are unchanged from 0.3.28 so player_character.gd can
pose the same 12 joints procedurally.
"""
from __future__ import annotations

import io
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/assets/models/characters/nitches_player.glb"

# 0.3.30: textured materials carry white factors - the synthesised
# maps below own the colour/roughness (authored to match the old
# factor hues, converted linear -> sRGB in the texture builders).
MATERIALS = [
    ("Skin", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Jacket - deep teal", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Shirt - warm ivory", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Trousers - charcoal blue", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Hair - dark brown", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Shoes - dark leather", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Warm metal details", (0.40, 0.39, 0.37, 1.0), 0.62, 0.38),
    ("Eyes", (1.0, 1.0, 1.0, 1.0), 0.0, 0.12),
    ("Iris", (1.0, 1.0, 1.0, 1.0), 0.0, 0.30),
    ("Mouth", (0.20, 0.075, 0.055, 1.0), 0.0, 0.8),
    # 0.3.29 append-only additions; existing indices must never move.
    ("Lips", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Pupil", (0.012, 0.010, 0.009, 1.0), 0.0, 0.18),
    ("Shoe sole - rubber", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    # 0.3.30 append-only additions (textured photoreal pass).
    ("Skin - face", (1.0, 1.0, 1.0, 1.0), 0.0, 1.0),
    ("Fingernails", (0.52, 0.33, 0.27, 1.0), 0.0, 0.42),
]
SKIN, JACKET, SHIRT, TROUSERS, HAIR, SHOES, METAL, EYES, IRIS, MOUTH, LIPS, PUPIL, SOLE, FACE_SKIN, NAILS = range(len(MATERIALS))
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


def add_mesh(material: int, positions, indices, colors=None, uvs=None) -> None:
    joint_x, joint_y, joint_z = LIMBS[CURRENT_LIMB][1]
    bucket = LIMB_BUCKETS.setdefault((CURRENT_LIMB, material), {"positions": [], "indices": [], "colors": [], "uvs": []})
    offset = len(bucket["positions"])
    bucket["positions"].extend((x - joint_x, y - joint_y, z - joint_z) for x, y, z in positions)
    bucket["indices"].extend(offset + index for index in indices)
    if colors is None:
        colors = [(1.0, 1.0, 1.0)] * len(positions)
    bucket["colors"].extend(colors)
    if uvs is None:
        uvs = [(0.0, 0.0)] * len(positions)
    bucket["uvs"].extend(uvs)


# ---------------------------------------------------------------------------
# Deterministic value noise for surface grain (no random module: the GLB
# must be byte-reproducible so the Blender/CI bots never churn).
# ---------------------------------------------------------------------------

def _hash3(ix: int, iy: int, iz: int) -> float:
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


def value_noise(x: float, y: float, z: float) -> float:
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = _smooth(x - ix), _smooth(y - iy), _smooth(z - iz)

    def mix(a, b, t):
        return a + (b - a) * t

    c000 = _hash3(ix, iy, iz)
    c100 = _hash3(ix + 1, iy, iz)
    c010 = _hash3(ix, iy + 1, iz)
    c110 = _hash3(ix + 1, iy + 1, iz)
    c001 = _hash3(ix, iy, iz + 1)
    c101 = _hash3(ix + 1, iy, iz + 1)
    c011 = _hash3(ix, iy + 1, iz + 1)
    c111 = _hash3(ix + 1, iy + 1, iz + 1)
    return mix(mix(mix(c000, c100, fx), mix(c010, c110, fx), fy),
               mix(mix(c001, c101, fx), mix(c011, c111, fx), fy), fz)


def fbm(x: float, y: float, z: float) -> float:
    return (value_noise(x, y, z) + 0.5 * value_noise(x * 2.13 + 7.0, y * 2.13 + 3.0, z * 2.13 + 11.0)) / 1.5


def grain(p, scale: float, amp: float) -> float:
    return 1.0 + amp * (fbm(p[0] * scale, p[1] * scale, p[2] * scale) * 2.0 - 1.0)


def gauss(p, centre, sigma) -> float:
    d2 = ((p[0] - centre[0]) / sigma[0]) ** 2 + ((p[1] - centre[1]) / sigma[1]) ** 2 + ((p[2] - centre[2]) / sigma[2]) ** 2
    return math.exp(-d2)


def bump(p, centre, sigma, direction, amp):
    w = gauss(p, centre, sigma) * amp
    return (p[0] + direction[0] * w, p[1] + direction[1] * w, p[2] + direction[2] * w)


def ang_diff(a: float, b: float) -> float:
    d = (a - b) % (2.0 * math.pi)
    return d - 2.0 * math.pi if d > math.pi else d


def ang_gauss(a: float, centre: float, width: float) -> float:
    d = ang_diff(a, centre) / width
    return math.exp(-d * d)


def paint(positions, fn):
    return [fn(x, y, z) for x, y, z in positions]


def mul3(c, s):
    return (c[0] * s, c[1] * s, c[2] * s)


# ---------------------------------------------------------------------------
# Geometry primitives.  Winding mirrors the 0.3.25/0.3.28 helpers exactly
# ((a, b, c), (a, c, d)) because make_normals' inward-flip heuristic was
# calibrated against it.
# ---------------------------------------------------------------------------

def add_ellipsoid(material, center, radii, segments=32, rings=20, deformation=None, color_fn=None, uv_scale=(1.0, 1.0)) -> None:
    cx, cy, cz = center
    rx, ry, rz = radii
    positions = []
    indices = []
    uvs = []
    for row in range(rings + 1):
        theta = math.pi * row / rings
        y_unit = math.cos(theta)
        ring_radius = math.sin(theta)
        for col in range(segments + 1):  # +1: duplicated UV seam column
            phi = 2.0 * math.pi * col / segments
            x_unit = math.cos(phi) * ring_radius
            z_unit = math.sin(phi) * ring_radius
            x = cx + rx * x_unit
            y = cy + ry * y_unit
            z = cz + rz * z_unit
            if deformation:
                x, y, z = deformation(x, y, z, x_unit, y_unit, z_unit)
            positions.append((x, y, z))
            uvs.append((col / segments * uv_scale[0], row / rings * uv_scale[1]))
    stride = segments + 1
    for row in range(rings):
        for col in range(segments):
            a = row * stride + col
            b = row * stride + col + 1
            c = (row + 1) * stride + col + 1
            d = (row + 1) * stride + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None, uvs)


def add_grid(material, rows, closed_loop=True, color_fn=None, uv_scale=(1.0, 1.0)) -> None:
    """Triangulate a list of equal-length vertex rings."""
    positions = []
    indices = []
    uvs = []
    segments = len(rows[0])
    stride = segments + 1 if closed_loop else segments
    for ri, ring in enumerate(rows):
        v = ri / max(len(rows) - 1, 1) * uv_scale[1]
        ring_ext = list(ring) + [ring[0]] if closed_loop else list(ring)
        for ci, pnt in enumerate(ring_ext):
            positions.append(pnt)
            uvs.append((ci / segments * uv_scale[0], v))
    for row in range(len(rows) - 1):
        for col in range(stride - 1):
            a = row * stride + col
            b = row * stride + col + 1
            c = (row + 1) * stride + col + 1
            d = (row + 1) * stride + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None, uvs)


def add_loft(material, stations, segments=32, power=1.0, cap_start=True, cap_end=True,
             shape_fn=None, vertex_fn=None, color_fn=None, uv_scale=(1.0, 1.0)) -> None:
    """Ring loft.  Each station is (origin, u_vec, v_vec); a ring point is
    origin + u*spow(cos phi) + v*spow(sin phi), so power < 1 squares the
    section (flat chest/front, shoe last) and power 1 keeps it elliptical."""
    def spow(v):
        return math.copysign(abs(v) ** power, v) if power != 1.0 else v

    positions = []
    indices = []
    uvs = []
    stride = segments + 1
    for si, (origin, u_vec, v_vec) in enumerate(stations):
        vv = si / max(len(stations) - 1, 1) * uv_scale[1]
        for col in range(stride):
            phi = 2.0 * math.pi * col / segments
            cu, cv = spow(math.cos(phi)), spow(math.sin(phi))
            mult = shape_fn(phi) if shape_fn else 1.0
            p = (origin[0] + (u_vec[0] * cu + v_vec[0] * cv) * mult,
                 origin[1] + (u_vec[1] * cu + v_vec[1] * cv) * mult,
                 origin[2] + (u_vec[2] * cu + v_vec[2] * cv) * mult)
            if vertex_fn:
                p = vertex_fn(p)
            positions.append(p)
            uvs.append((col / segments * uv_scale[0], vv))
    for row in range(len(stations) - 1):
        for col in range(segments):
            a = row * stride + col
            b = row * stride + col + 1
            c = (row + 1) * stride + col + 1
            d = (row + 1) * stride + col
            indices.extend((a, b, c, a, c, d))
    if cap_start:
        positions.append(stations[0][0])
        uvs.append((0.5 * uv_scale[0], 0.0))
        start_center = len(positions) - 1
        for col in range(segments):
            indices.extend((start_center, col + 1, col))
    if cap_end:
        positions.append(stations[-1][0])
        uvs.append((0.5 * uv_scale[0], uv_scale[1]))
        end_center = len(positions) - 1
        end_row = (len(stations) - 1) * stride
        for col in range(segments):
            indices.extend((end_center, end_row + col, end_row + col + 1))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None, uvs)


def _catmull_rom(points, samples):
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    spans = len(points) - 1
    for i in range(samples + 1):
        t = i / samples * spans
        seg = min(int(t), spans - 1)
        lt = t - seg
        p0, p1, p2, p3 = pts[seg], pts[seg + 1], pts[seg + 2], pts[seg + 3]
        out.append(tuple(
            0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * lt +
                   (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * lt * lt +
                   (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * lt * lt * lt)
            for k in range(3)))
    return out


def _profile_value(profile, t):
    if t <= profile[0][0]:
        return profile[0][1]
    for (t0, v0), (t1, v1) in zip(profile, profile[1:]):
        if t <= t1:
            lt = (t - t0) / max(t1 - t0, 1e-9)
            return v0 + (v1 - v0) * _smooth(lt)
    return profile[-1][1]


def add_tube_path(material, points, radius_profile, segments=20, samples=12, depth_ratio=0.92,
                  rounded_caps=True, offset_fn=None, color_fn=None, uv_scale=(1.0, 1.0)) -> None:
    """Swept tube along a Catmull-Rom path with a (t, radius) profile."""
    centres = _catmull_rom(points, samples)
    # Frames: seed with the 0.3.28 helper choice, then parallel-transport.
    def sub(a, b):
        return (a[0] - b[0], a[1] - b[1], a[2] - b[2])

    def norm(v):
        ln = math.sqrt(sum(c * c for c in v)) or 1.0
        return tuple(c / ln for c in v)

    def cross(a, b):
        return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

    def dot(a, b):
        return sum(x * y for x, y in zip(a, b))

    tangents = []
    for i, c in enumerate(centres):
        a = centres[max(i - 1, 0)]
        b = centres[min(i + 1, len(centres) - 1)]
        tangents.append(norm(sub(b, a)))
    t0 = tangents[0]
    helper = (0.0, 0.0, 1.0) if abs(t0[2]) < 0.88 else (1.0, 0.0, 0.0)
    normal = norm(cross(t0, helper))
    frames = []
    for t in tangents:
        d = dot(normal, t)
        normal = norm((normal[0] - t[0] * d, normal[1] - t[1] * d, normal[2] - t[2] * d))
        frames.append((normal, norm(cross(t, normal))))

    rings = []  # (centre, tangent, n, b, radius)
    if rounded_caps:
        r0 = _profile_value(radius_profile, 0.0)
        c0, tg0 = centres[0], tangents[0]
        rings.append(((c0[0] - tg0[0] * r0 * 0.62, c0[1] - tg0[1] * r0 * 0.62, c0[2] - tg0[2] * r0 * 0.62),
                      tg0, frames[0][0], frames[0][1], r0 * 0.66))
    for i, c in enumerate(centres):
        t = i / samples
        off = offset_fn(t) if offset_fn else (0.0, 0.0, 0.0)
        rings.append(((c[0] + off[0], c[1] + off[1], c[2] + off[2]), tangents[i],
                      frames[i][0], frames[i][1], _profile_value(radius_profile, t)))
    if rounded_caps:
        r1 = _profile_value(radius_profile, 1.0)
        ce, tge = centres[-1], tangents[-1]
        rings.append(((ce[0] + tge[0] * r1 * 0.62, ce[1] + tge[1] * r1 * 0.62, ce[2] + tge[2] * r1 * 0.62),
                      tge, frames[-1][0], frames[-1][1], r1 * 0.66))

    rows = []
    for centre, _tg, n, b, radius in rings:
        ring = []
        for col in range(segments + 1):
            angle = 2.0 * math.pi * col / segments
            ca, sa = math.cos(angle), math.sin(angle)
            ring.append((centre[0] + radius * ca * n[0] + radius * depth_ratio * sa * b[0],
                         centre[1] + radius * ca * n[1] + radius * depth_ratio * sa * b[1],
                         centre[2] + radius * ca * n[2] + radius * depth_ratio * sa * b[2]))
        rows.append(ring)

    positions = []
    indices = []
    uvs = []
    stride = segments + 1
    for ri, ring in enumerate(rows):
        positions.extend(ring)
        vv = ri / max(len(rows) - 1, 1) * uv_scale[1]
        uvs.extend((col / segments * uv_scale[0], vv) for col in range(stride))
    for row in range(len(rows) - 1):
        for col in range(segments):
            a = row * stride + col
            bb = row * stride + col + 1
            c = (row + 1) * stride + col + 1
            d = (row + 1) * stride + col
            indices.extend((a, bb, c, a, c, d))
    positions.extend((rings[0][0], rings[-1][0]))
    uvs.extend(((0.5 * uv_scale[0], 0.0), (0.5 * uv_scale[0], uv_scale[1])))
    start_center = len(positions) - 2
    end_center = len(positions) - 1
    end_row = (len(rows) - 1) * stride
    for col in range(segments):
        indices.extend((start_center, col + 1, col))
        indices.extend((end_center, end_row + col, end_row + col + 1))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None, uvs)


def add_box(material, center, size, color_fn=None) -> None:
    cx, cy, cz = center
    sx, sy, sz = (v * 0.5 for v in size)
    positions = [(cx + x * sx, cy + y * sy, cz + z * sz) for x, y, z in (
        (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
        (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
    )]
    indices = [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 3, 7, 6, 3, 6, 2, 0, 4, 7, 0, 7, 3, 1, 2, 6, 1, 6, 5]
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None)


def make_normals(positions, indices):
    normals = [[0.0, 0.0, 0.0] for _ in positions]
    model_centre = tuple(sum(p[k] for p in positions) / max(len(positions), 1) for k in range(3))
    for i in range(0, len(indices), 3):
        ia, ib, ic = indices[i:i + 3]
        a, b, c = positions[ia], positions[ib], positions[ic]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
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
        length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        out.append((n[0] / length, n[1] / length, n[2] / length) if length > 1e-8 else (0.0, 1.0, 0.0))
    return out


# ---------------------------------------------------------------------------
# Paint jobs (tint x grain).  COLOR_0 multiplies the material base colour,
# so 1.0 is neutral; essential contrast stays in separate materials and
# paint only adds variation, seams and soft occlusion.
# ---------------------------------------------------------------------------

def skin_paint(x, y, z):
    p = (x, y, z)
    base = grain(p, 130.0, 0.06) * grain(p, 26.0, 0.03)
    r, g, b = base, base, base
    # Cheek / nose-tip warmth.
    for centre in ((-0.068, 1.662, -0.070), (0.068, 1.662, -0.070), (0.0, 1.650, -0.118)):
        w = gauss(p, centre, (0.032, 0.026, 0.030))
        r *= 1.0 + 0.07 * w
        g *= 1.0 - 0.05 * w
        b *= 1.0 - 0.06 * w
    # Socket shading and nostril shadow (dents read through colour too).
    for centre in ((-0.045, 1.694, -0.102), (0.045, 1.694, -0.102)):
        shade = 1.0 - 0.10 * gauss(p, centre, (0.021, 0.015, 0.018))
        r, g, b = r * shade, g * shade, b * shade
    for centre in ((-0.0115, 1.639, -0.116), (0.0115, 1.639, -0.116)):
        shade = 1.0 - 0.55 * gauss(p, centre, (0.008, 0.006, 0.009))
        r, g, b = r * shade, g * shade, b * shade
    # Under-jaw / neck occlusion.
    if y < 1.60:
        shade = 1.0 - 0.10 * min(max((1.60 - y) / 0.08, 0.0), 1.0)
        r, g, b = r * shade, g * shade, b * shade
    return (r, g, b)


def hair_paint(x, y, z):
    p = (x, y, z)
    phi = math.atan2(z - 0.004, x)
    streak = 1.0 + 0.16 * (value_noise(phi * 22.0, y * 6.0, 3.0) * 2.0 - 1.0)
    base = grain(p, 90.0, 0.06) * streak
    warm = 1.0 + 0.05 * gauss(p, (0.0, 1.80, 0.02), (0.09, 0.06, 0.09))
    return (base * warm, base, base * 0.97)


def jacket_paint(x, y, z):
    p = (x, y, z)
    base = grain(p, 70.0, 0.055) * grain(p, 16.0, 0.03)
    phi = math.atan2(z, x)
    # Side seams + sleeve fold shading on the inner arm.
    for seam in (0.0, math.pi):
        base *= 1.0 - 0.09 * ang_gauss(phi, seam, 0.07)
    if z < -0.05:  # front yoke seam
        base *= 1.0 - 0.07 * math.exp(-(((y - 1.365) / 0.006) ** 2))
    if y < 0.905:  # hem band
        base *= 0.93
    if 1.50 < y < 1.575:  # collar band
        base *= 0.95
    return (base, base, base * 1.01)


def trousers_paint(x, y, z):
    p = (x, y, z)
    base = grain(p, 85.0, 0.05) * grain(p, 18.0, 0.025)
    phi = math.atan2(z, x - math.copysign(0.145, x) if abs(x) > 0.05 else x)
    # Front crease line and inner-leg occlusion.
    base *= 1.0 - 0.10 * ang_gauss(phi, -math.pi / 2.0, 0.06)
    if abs(x) < 0.06 and y < 0.95:
        base *= 0.9
    if y > 0.975:  # waistband
        base *= 0.9
    if 0.155 < y < 0.205:  # ankle cuff
        base *= 0.93
    return (base, base, base * 1.02)


def leather_paint(x, y, z):
    p = (x, y, z)
    base = grain(p, 160.0, 0.07) * grain(p, 40.0, 0.04)
    if z < -0.15:  # polished toe cap
        base *= 1.06
    if z > 0.045:  # heel counter
        base *= 0.92
    return (base, base, base)


def sole_paint(x, y, z):
    base = grain((x, y, z), 120.0, 0.08)
    if y < 0.012:  # ground-worn bottom
        base *= 0.85
    return mul3((1.0, 1.0, 1.0), base)


def shirt_paint(x, y, z):
    base = grain((x, y, z), 90.0, 0.04)
    return (base, base, base * 0.99)


# ---------------------------------------------------------------------------
# Face: skull-carried form (0.3.29 core lesson: never glued-on balls;
# additive volumes sit deeply sunk so only a soft cap reads).
# ---------------------------------------------------------------------------

HEAD_C = (0.0, 1.678, 0.002)
HEAD_R = (0.114, 0.146, 0.120)


def head_deform(x, y, z, x_unit, y_unit, z_unit):
    p = (x, y, z)
    # Cranium: fuller back-top, slight forehead slope.
    p = bump(p, (0.0, 1.720, 0.095), (0.085, 0.075, 0.045), (0.0, 0.1, 1.0), 0.0075)
    p = bump(p, (0.0, 1.765, -0.075), (0.070, 0.045, 0.040), (0.0, 0.0, 1.0), -0.0035)
    # Brow ridge, then eye sockets sunk under it.
    p = bump(p, (0.0, 1.713, -0.100), (0.078, 0.015, 0.030), (0.0, 0.0, -1.0), 0.0042)
    for s in (-1.0, 1.0):
        p = bump(p, (s * 0.045, 1.693, -0.098), (0.020, 0.0135, 0.018), (0.0, 0.0, -1.0), -0.0045)
    # Nose: bridge, tip, nostril wings (tip must project ~20mm in profile).
    p = bump(p, (0.0, 1.688, -0.104), (0.0082, 0.027, 0.012), (0.0, 0.0, -1.0), 0.0075)
    p = bump(p, (0.0, 1.652, -0.106), (0.0095, 0.0085, 0.0105), (0.0, -0.18, -1.0), 0.0152)
    for s in (-1.0, 1.0):
        p = bump(p, (s * 0.0145, 1.643, -0.104), (0.0085, 0.0075, 0.009), (s * 0.35, 0.0, -1.0), 0.0050)
        # Cheekbones and the hollow beneath them.
        p = bump(p, (s * 0.077, 1.676, -0.058), (0.030, 0.021, 0.028), (s * 0.75, 0.0, -0.66), 0.0045)
        p = bump(p, (s * 0.073, 1.640, -0.052), (0.026, 0.018, 0.024), (s * 0.75, 0.0, -0.66), -0.0032)
        # Nasolabial fold running from the nose wing to the mouth corner.
        p = bump(p, (s * 0.027, 1.626, -0.096), (0.0075, 0.019, 0.011), (0.0, 0.0, -1.0), -0.0017)
        # Jaw corners.
        p = bump(p, (s * 0.056, 1.602, -0.008), (0.020, 0.024, 0.035), (s * 1.0, 0.0, 0.0), 0.0028)
    # Philtrum dip, lip bed, chin.
    p = bump(p, (0.0, 1.627, -0.098), (0.009, 0.008, 0.012), (0.0, 0.0, -1.0), -0.0014)
    p = bump(p, (0.0, 1.609, -0.094), (0.030, 0.011, 0.016), (0.0, 0.0, -1.0), 0.0022)
    p = bump(p, (0.0, 1.570, -0.080), (0.020, 0.013, 0.014), (0.0, -0.3, -1.0), 0.0062)
    x, y, z = p
    # Jaw taper + slimming toward the neck (multiplicative, after bumps).
    t = min(max((1.662 - y) / 0.115, 0.0), 1.0)
    ts = _smooth(t)
    x *= 1.0 - 0.20 * ts
    z = HEAD_C[2] + (z - HEAD_C[2]) * (1.0 - 0.08 * ts) + 0.004 * ts
    if y < 1.556:
        tuck = min(max((1.556 - y) / 0.03, 0.0), 1.0)
        x *= 1.0 - 0.22 * tuck
        z = HEAD_C[2] + (z - HEAD_C[2]) * (1.0 - 0.20 * tuck)
    # Lightly flattened crown.
    if y_unit > 0.72:
        y -= 0.005 * (y_unit - 0.72) / 0.28
    return x, y, z


def hair_rim_theta(phi: float) -> float:
    """Polar rim angle of the hair cap by azimuth (front is -pi/2)."""
    rim = 1.30
    rim += 0.44 * ang_gauss(phi, math.pi / 2.0, 0.95)        # nape low at back
    rim += -0.10 * ang_gauss(phi, -math.pi / 2.0, 0.85)      # forehead hairline
    rim += -0.11 * ang_gauss(phi, -math.pi / 2.0 - 0.95, 0.34)  # temple recession L
    rim += -0.11 * ang_gauss(phi, -math.pi / 2.0 + 0.95, 0.34)  # temple recession R
    rim += 0.19 * ang_gauss(phi, -0.18, 0.30)                # sideburn R (just front of ear)
    rim += 0.19 * ang_gauss(phi, -2.96, 0.30)                # sideburn L
    rim += 0.09 * ang_gauss(phi, -2.30, 0.55)                # swept fringe falls left
    rim += -0.05 * ang_gauss(phi, -0.80, 0.55)               # parting side sits higher
    rim += -0.055 * ang_gauss(phi, -1.05, 0.26)              # temple recession R
    rim += -0.055 * ang_gauss(phi, -2.09, 0.26)              # temple recession L
    return min(rim, 1.88)


def add_hair_cap() -> None:
    segments, rows = 96, 34
    cx, cy, cz = 0.0, HEAD_C[1] + 0.0025, HEAD_C[2] + 0.0045
    rx, ry, rz = HEAD_R[0] + 0.0085, HEAD_R[1] + 0.0125, HEAD_R[2] + 0.0090
    grid = []
    for row in range(rows + 1):
        v = row / rows
        ring = []
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            # atan2 azimuth (front -pi/2) from param phi (x=cos, z=sin).
            az = math.atan2(math.sin(phi), math.cos(phi))
            theta = v * hair_rim_theta(az)
            inflate = 1.0 + 0.10 * math.sin(min(v, 1.0) * math.pi) * 0.12  # gentle mid-volume
            # Strand grooves: fine wavy ridges running crown -> rim.
            strand = math.sin(phi * 130.0 + 7.0 * value_noise(math.cos(phi) * 4.0 + 9.0, math.sin(phi) * 4.0, v * 3.0))
            inflate *= 1.0 + 0.0015 * strand
            x = cx + rx * math.sin(theta) * math.cos(phi) * inflate
            y = cy + ry * math.cos(theta)
            z = cz + rz * math.sin(theta) * math.sin(phi) * inflate
            # Fringe overhang: front rim rows lean forward slightly.
            front = ang_gauss(az, -math.pi / 2.0, 0.8)
            z -= 0.0035 * front * (v ** 3)
            y -= 0.0020 * front * (v ** 3)
            # Rim tuck for fake thickness on the last row.
            if row == rows:
                x = cx + (x - cx) * 0.985
                z = cz + (z - cz) * 0.985
            ring.append((x, y, z))
        grid.append(ring)
    add_grid(HAIR, grid, True)


def add_iris(ex: float) -> None:
    """Domed iris annulus hugging the eyeball sphere, with a real pupil
    hole and a black disc just behind it (true parallax at glancing
    angles).  Planar UVs feed the radial-fibre iris texture."""
    ec = (ex, 1.6935, -0.0942)
    ball_r = 0.0128
    segments = 28
    radii = (0.0025, 0.0036, 0.0046, 0.0053, 0.0059)
    positions, indices, uvs = [], [], []
    for r in radii:
        z = ec[2] - math.sqrt(ball_r * ball_r - r * r) - 0.00035
        for col in range(segments + 1):
            a = 2.0 * math.pi * col / segments
            positions.append((ex + r * math.cos(a), 1.6935 + r * math.sin(a), z))
            uvs.append((0.5 + 0.5 * math.cos(a) * r / 0.0059, 0.5 - 0.5 * math.sin(a) * r / 0.0059))
    stride = segments + 1
    for row in range(len(radii) - 1):
        for col in range(segments):
            a = row * stride + col
            b = row * stride + col + 1
            c = (row + 1) * stride + col + 1
            d = (row + 1) * stride + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(IRIS, positions, indices, None, uvs)
    # Pupil: black disc between the iris plane and the ball surface.
    positions = [(ex, 1.6935, -0.1072)]
    indices = []
    uvs = [(0.5, 0.5)]
    for col in range(segments + 1):
        a = 2.0 * math.pi * col / segments
        positions.append((ex + 0.0027 * math.cos(a), 1.6935 + 0.0027 * math.sin(a), -0.1072))
        uvs.append((0.5 + 0.5 * math.cos(a), 0.5 - 0.5 * math.sin(a)))
    for col in range(segments):
        indices.extend((0, col + 2, col + 1))
    add_mesh(PUPIL, positions, indices, None, uvs)


def add_lips() -> None:
    def deform(x, y, z, _xu, _yu, _zu):
        # Pinch the meeting line, taper the corners, cupid's bow on top.
        pinch = 1.0 - 0.38 * math.exp(-(((y - 1.6115) / 0.0016) ** 2))
        taper = 1.0 - 0.45 * _smooth(min(max((abs(x) - 0.014) / 0.010, 0.0), 1.0))
        z = -0.0990 + (z + 0.0990) * pinch
        y = 1.6115 + (y - 1.6115) * taper
        if y > 1.6145:
            y -= 0.0016 * math.exp(-((x / 0.006) ** 2))
        return x, y, z

    def lip_paint(x, y, z):
        base = grain((x, y, z), 160.0, 0.04)
        line = 1.0 - 0.55 * math.exp(-(((y - 1.6115) / 0.0016) ** 2)) if z < -0.1005 else 1.0
        lower = 1.07 if y < 1.608 else 1.0
        return mul3((1.0, 0.98, 0.97), base * line * lower)

    add_ellipsoid(LIPS, (0.0, 1.6115, -0.0990), (0.0245, 0.0078, 0.0088), 40, 22, deform, lip_paint)


def add_face() -> None:
    set_limb("Head")
    add_ellipsoid(FACE_SKIN, HEAD_C, HEAD_R, 96, 64, head_deform)
    # Ears: flattened, half-sunk into the skull.
    for s in (-1.0, 1.0):
        def ear_deform(x, y, z, _xu, _yu, _zu, s=s):
            zz = z + 0.006 * _smooth(min(max((y - 1.685) / 0.03, 0.0), 1.0))
            return x, y, zz

        def ear_paint(x, y, z, s=s):
            base = skin_paint(x, y, z)
            w = gauss((x, y, z), (s * 0.120, 1.688, 0.002), (0.010, 0.016, 0.012))
            return (base[0] * (1.0 - 0.18 * w) * 1.04, base[1] * (1.0 - 0.22 * w), base[2] * (1.0 - 0.22 * w))

        add_ellipsoid(SKIN, (s * 0.1115, 1.685, 0.002), (0.0140, 0.033, 0.021), 28, 18, ear_deform, ear_paint)
        # Helix rim: a C-curve half-sunk into the ear's outer face.
        add_tube_path(SKIN, [(s * 0.1235, 1.702, 0.012), (s * 0.1245, 1.697, -0.006),
                             (s * 0.1240, 1.685, -0.014), (s * 0.1225, 1.672, -0.010)],
                      [(0.0, 0.0022), (0.5, 0.0028), (1.0, 0.0020)], 10, 10, 0.9, True, None, ear_paint)
    # Eyeballs (deeply sunk) behind skin eyelid caps, so only an almond
    # of sclera/iris shows; iris and pupil sit flush on the ball front.
    for s in (-1.0, 1.0):
        ex = s * 0.045
        add_ellipsoid(EYES, (ex, 1.6935, -0.0942), (0.0128, 0.0128, 0.0128), 28, 18)
        add_iris(ex)

        def upper_lid_deform(x, y, z, _xu, yu, _zu):
            if yu < 0.15:
                z += 0.015 * (0.15 - yu)
            return x, y, z

        def lower_lid_deform(x, y, z, _xu, yu, _zu):
            if yu > -0.10:
                z += 0.015 * (yu + 0.10)
            return x, y, z

        add_ellipsoid(SKIN, (ex, 1.7008, -0.0975), (0.0170, 0.0105, 0.0115), 30, 16, upper_lid_deform, skin_paint)
        add_ellipsoid(SKIN, (ex, 1.6872, -0.0975), (0.0164, 0.0080, 0.0112), 30, 14, lower_lid_deform, skin_paint)
        # Brow: tapered curved bar following the ridge.
        add_tube_path(HAIR, [(s * 0.016, 1.7115, -0.1065), (s * 0.044, 1.7175, -0.1075), (s * 0.069, 1.7125, -0.0985)],
                      [(0.0, 0.0036), (0.5, 0.0043), (1.0, 0.0020)], 12, 10, 0.6, True, None,
                      lambda x, y, z: mul3(hair_paint(x, y, z), 0.85))
    add_lips()
    add_hair_cap()


# ---------------------------------------------------------------------------
# Torso, clothing detail, limbs, shoes.
# ---------------------------------------------------------------------------

# (y, x-radius, z-radius, z-centre) - the z-centre gives the torso a
# subtle chest-forward S instead of a straight column in profile.
TORSO_SECTIONS = [
    (0.843, 0.216, 0.136, 0.004), (0.895, 0.246, 0.154, 0.003),
    (0.975, 0.241, 0.151, 0.001), (1.075, 0.251, 0.157, -0.001),
    (1.175, 0.274, 0.167, -0.003), (1.275, 0.291, 0.171, -0.004),
    (1.375, 0.316, 0.169, -0.003), (1.455, 0.350, 0.160, -0.001),
    (1.495, 0.318, 0.141, 0.000), (1.520, 0.248, 0.119, 0.001),
    (1.538, 0.172, 0.101, 0.001),
]


def _interp_sections(y: float, idx: int) -> float:
    secs = TORSO_SECTIONS
    if y <= secs[0][0]:
        return secs[0][idx]
    for a, b in zip(secs, secs[1:]):
        if y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return a[idx] + (b[idx] - a[idx]) * _smooth(t)
    return secs[-1][idx]


def add_torso() -> None:
    set_limb("Torso")
    stations = []
    steps = 26
    for i in range(steps + 1):
        y = TORSO_SECTIONS[0][0] + (TORSO_SECTIONS[-1][0] - TORSO_SECTIONS[0][0]) * i / steps
        stations.append(((0.0, y, _interp_sections(y, 3)), (_interp_sections(y, 1), 0.0, 0.0), (0.0, 0.0, _interp_sections(y, 2))))

    def groove(phi):
        return 1.0 - 0.030 * ang_gauss(phi, -math.pi / 2.0, 0.10)

    add_loft(JACKET, stations, 64, 0.78, True, True, groove, None, jacket_paint, (6.0, 3.0))
    # Standing collar band (hugs the narrowed torso top, no tray ring).
    collar = [((0.0, 1.505, 0.001), (0.160, 0.0, 0.0), (0.0, 0.0, 0.102)),
              ((0.0, 1.536, 0.001), (0.150, 0.0, 0.0), (0.0, 0.0, 0.096)),
              ((0.0, 1.562, 0.001), (0.138, 0.0, 0.0), (0.0, 0.0, 0.089))]
    add_loft(JACKET, collar, 48, 0.85, False, False, None, None, lambda x, y, z: mul3(jacket_paint(x, y, z), 0.94), (4.0, 0.4))
    # Shirt triangle at the throat (jacket stays closed).
    add_ellipsoid(SHIRT, (0.0, 1.516, -0.0765), (0.032, 0.037, 0.021), 24, 16, None, shirt_paint)
    # Neck with trapezius flare (Torso limb: stays with the body).
    add_tube_path(SKIN, [(0.0, 1.462, 0.006), (0.0, 1.540, 0.002), (0.0, 1.612, -0.001)],
                  [(0.0, 0.078), (0.45, 0.057), (1.0, 0.053)], 28, 10, 0.9, True, None,
                  lambda x, y, z: mul3(skin_paint(x, y, z), 0.97), (2.0, 1.5))
    add_ellipsoid(SKIN, (0.0, 1.576, -0.0435), (0.0155, 0.0135, 0.0115), 20, 14, None,
                  lambda x, y, z: mul3(skin_paint(x, y, z), 0.97))
    add_zipper()
    # Chest pocket flaps with muted mini-zips.
    for s in (-1.0, 1.0):
        add_ellipsoid(JACKET, (s * 0.187, 1.098, -0.128), (0.056, 0.026, 0.007), 24, 14, None,
                      lambda x, y, z: mul3(jacket_paint(x, y, z), 0.96))
        add_box(METAL, (s * 0.187, 1.138, -0.132), (0.052, 0.0045, 0.004),
                lambda x, y, z: (0.36, 0.36, 0.36))


def add_zipper() -> None:
    """Closed centre zipper following the torso front; muted steel teeth."""
    rows = []
    y = 0.878
    while y <= 1.498:
        z_surface = _interp_sections(y, 3) - _interp_sections(y, 2) * 0.970
        rows.append([(-0.0064, y, z_surface - 0.0011), (0.0, y, z_surface - 0.0021), (0.0064, y, z_surface - 0.0011)])
        y += 0.0165

    def teeth(x, yy, z):
        tooth = 0.40 + (0.12 if int(yy / 0.011) % 2 == 0 else 0.0)
        if abs(x) < 0.001:
            tooth *= 0.82
        return (tooth, tooth, tooth)

    positions = []
    indices = []
    for ring in rows:
        positions.extend(ring)
    for row in range(len(rows) - 1):
        for col in range(2):
            a = row * 3 + col
            b = row * 3 + col + 1
            c = (row + 1) * 3 + col + 1
            d = (row + 1) * 3 + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(METAL, positions, indices, paint(positions, teeth))
    add_box(METAL, (0.0, 1.468, _interp_sections(1.468, 3) - _interp_sections(1.468, 2) * 0.97 - 0.004), (0.008, 0.022, 0.003),
            lambda x, y, z: (0.48, 0.48, 0.48))


def add_arm(side: float) -> None:
    suffix = "L" if side < 0 else "R"
    shoulder = (side * 0.333, 1.455, 0.0)
    elbow = (side * 0.423, 1.155, -0.006)
    wrist = (side * 0.414, 0.865, -0.028)

    def fold(t, side=side):
        return (0.0, 0.0, 0.0035 * math.sin(t * math.pi))

    set_limb("UpperArm" + suffix)
    add_ellipsoid(JACKET, (side * 0.326, 1.447, 0.0), (0.087, 0.089, 0.094), 32, 22, None, jacket_paint, (2.0, 1.0))
    add_tube_path(JACKET, [(side * 0.318, 1.478, 0.0), shoulder, (side * 0.392, 1.300, -0.004), elbow],
                  [(0.0, 0.096), (0.3, 0.085), (0.75, 0.072), (1.0, 0.064)], 28, 14, 0.92, True, fold, jacket_paint, (2.0, 1.3))
    set_limb("Forearm" + suffix)
    add_ellipsoid(JACKET, elbow, (0.064, 0.068, 0.064), 26, 18, None, jacket_paint, (2.0, 1.0))
    add_tube_path(JACKET, [elbow, (side * 0.426, 1.010, -0.018), wrist],
                  [(0.0, 0.064), (0.35, 0.057), (0.85, 0.047), (1.0, 0.046)], 26, 12, 0.94, True, fold, jacket_paint, (2.0, 1.2))
    # Cuff band at the wrist (loft ring standing around the forearm axis).
    add_loft(JACKET, [((wrist[0], 0.906, wrist[2]), (0.0545, 0.0, 0.0), (0.0, 0.0, 0.0515)),
                      ((wrist[0], 0.882, wrist[2]), (0.0535, 0.0, 0.0), (0.0, 0.0, 0.0505)),
                      ((wrist[0], 0.858, wrist[2]), (0.0475, 0.0, 0.0), (0.0, 0.0, 0.0450))],
             26, 1.0, False, False, None, None, lambda x, y, z: mul3(jacket_paint(x, y, z), 0.90), (2.0, 0.3))
    add_hand(side, wrist)


def add_hand(side: float, wrist) -> None:
    palm_c = (wrist[0], 0.798, -0.034)

    def palm_deform(x, y, z, _xu, _yu, _zu):
        # Wider at the knuckles, narrower at the wrist; slight cup.
        t = min(max((0.845 - y) / 0.10, 0.0), 1.0)
        x = palm_c[0] + (x - palm_c[0]) * (0.82 + 0.30 * _smooth(t))
        z = z + 0.004 * ((x - palm_c[0]) / 0.04) ** 2 * 0.4
        return x, y, z

    add_ellipsoid(SKIN, palm_c, (0.040, 0.054, 0.0175), 28, 20, palm_deform, skin_paint)
    # Fingers: two-point curl toward the palm (+Z), relaxed.
    fingers = [  # (x offset from palm centre, length)
        (-0.0285, 0.066), (-0.0095, 0.074), (0.0095, 0.068), (0.0275, 0.054),
    ]
    for off, length in fingers:
        bx = palm_c[0] + side * off * -1.0  # keep index on the thumb side
        by, bz = 0.756, -0.036
        mid = (bx, by - length * 0.55, bz + 0.004)
        tip = (bx, by - length, bz + 0.014)
        add_tube_path(SKIN, [(bx, by + 0.012, bz), mid, tip],
                      [(0.0, 0.0088), (0.35, 0.0080), (0.42, 0.0074), (0.55, 0.0079), (0.62, 0.0072), (0.8, 0.0068), (1.0, 0.0062)],
                      14, 10, 0.95, True, None, skin_paint)
        # Fingernail: sheared cap on the dorsal (-Z) side of the fingertip.
        nail_c = (bx, tip[1] + 0.009, tip[2] - 0.0040)

        def nail_deform(x, y, z, _xu, _yu, _zu, nail_c=nail_c):
            return x, y, z + 0.30 * (y - nail_c[1])

        add_ellipsoid(NAILS, nail_c, (0.0058, 0.0078, 0.0024), 16, 10, nail_deform)
    # Thumb on the body's inner-front side of the palm.
    tx = palm_c[0] - side * 0.034
    add_tube_path(SKIN, [(tx, 0.820, -0.040), (tx - side * 0.010, 0.786, -0.047), (tx - side * 0.013, 0.756, -0.044)],
                  [(0.0, 0.0102), (0.6, 0.0088), (1.0, 0.0070)], 14, 7, 0.95, True, None, skin_paint)
    thumb_nail_c = (tx - side * 0.012, 0.765, -0.0488)

    def thumb_nail_deform(x, y, z, _xu, _yu, _zu, c=thumb_nail_c):
        return x, y, z + 0.25 * (y - c[1])

    add_ellipsoid(NAILS, thumb_nail_c, (0.0074, 0.0084, 0.0026), 16, 10, thumb_nail_deform)


def add_leg(side: float) -> None:
    suffix = "L" if side < 0 else "R"
    hip = (side * 0.135, 0.83, 0.0)
    knee = (side * 0.145, 0.48, 0.018)
    ankle = (side * 0.155, 0.115, -0.005)
    set_limb("Thigh" + suffix)
    add_tube_path(TROUSERS, [(side * 0.132, 0.878, 0.0), hip, (side * 0.141, 0.650, 0.010), knee],
                  [(0.0, 0.126), (0.3, 0.112), (0.75, 0.095), (1.0, 0.089)], 30, 16, 0.90, True, None, trousers_paint, (3.0, 1.6))
    set_limb("Shin" + suffix)
    add_ellipsoid(TROUSERS, knee, (0.086, 0.089, 0.087), 28, 20, None, trousers_paint, (2.0, 1.0))

    def calf(t):
        return (0.0, 0.0, 0.011 * math.sin(math.pi * min(max(t * 1.25, 0.0), 1.0)) ** 1.5)

    add_tube_path(TROUSERS, [knee, (side * 0.150, 0.300, 0.008), ankle],
                  [(0.0, 0.089), (0.25, 0.083), (0.7, 0.065), (1.0, 0.057)], 28, 14, 0.92, True, calf, trousers_paint, (3.0, 1.5))
    set_limb("Foot" + suffix)
    add_shoe(side)


def add_shoe(side: float) -> None:
    cx = side * 0.155
    # Upper last: (z, width, top height above sole line y=0.026).
    last = [
        (0.088, 0.052, 0.050), (0.068, 0.079, 0.080), (0.030, 0.086, 0.090),
        (-0.020, 0.086, 0.077), (-0.080, 0.089, 0.061), (-0.135, 0.087, 0.048),
        (-0.175, 0.078, 0.034), (-0.198, 0.059, 0.020), (-0.211, 0.032, 0.010),
    ]
    stations = [((cx, 0.026 + h / 2.0, z), (w / 2.0, 0.0, 0.0), (0.0, h / 2.0, 0.0)) for z, w, h in last]
    add_loft(SHOES, stations, 40, 0.82, True, True, None,
             lambda p: (p[0], max(p[1], 0.022), p[2]), leather_paint, (1.0, 1.2))
    # Sole: slim slab with a mild toe spring and a real heel block.
    sole = [  # (z, width, bottom y, top y)
        (0.092, 0.058, 0.006, 0.034), (0.070, 0.087, 0.004, 0.035),
        (0.020, 0.094, 0.004, 0.029), (-0.060, 0.096, 0.004, 0.027),
        (-0.130, 0.094, 0.005, 0.027), (-0.180, 0.084, 0.007, 0.027),
        (-0.205, 0.066, 0.011, 0.028), (-0.214, 0.038, 0.016, 0.028),
    ]
    stations = [((cx, (tb + tp) / 2.0, z), (w / 2.0, 0.0, 0.0), (0.0, (tp - tb) / 2.0, 0.0)) for z, w, tb, tp in sole]
    add_loft(SOLE, stations, 36, 0.80, True, True, None, None, sole_paint, (1.0, 1.0))
    # Tongue + ivory laces across the instep.
    tongue = [((cx, 0.026 + hh + 0.0012, zz), (0.023, 0.0, 0.0), (0.0, 0.0035, 0.0)) for zz, hh in
              ((-0.012, 0.0805), (-0.055, 0.069), (-0.100, 0.0555), (-0.138, 0.0475))]
    add_loft(SHOES, tongue, 20, 0.9, True, True, None, None,
             lambda x, y, z: mul3(leather_paint(x, y, z), 1.18), (1.0, 1.0))
    for i in range(5):
        lz = -0.030 - i * 0.023
        top = 0.026 + (0.0744 - i * 0.0055)
        add_tube_path(SHIRT, [(cx - 0.030, top - 0.007, lz), (cx, top + 0.0015, lz - 0.002), (cx + 0.030, top - 0.007, lz)],
                      [(0.0, 0.0034), (1.0, 0.0034)], 10, 5, 0.8, True, None, lambda x, y, z: mul3(shirt_paint(x, y, z), 0.60))


def build_character() -> None:
    add_torso()
    # Hips (trousers) bridging torso and thighs.
    set_limb("Torso")

    def hip_deform(x, y, z, _xu, y_unit, _zu):
        # Slight seat shaping: fuller behind, flatter in front.
        if z > 0.02:
            z += 0.006
        return x, y, z

    add_ellipsoid(TROUSERS, (0.0, 0.870, 0.004), (0.258, 0.158, 0.154), 48, 32, hip_deform, trousers_paint, (5.0, 2.0))
    for side in (-1.0, 1.0):
        add_arm(side)
        add_leg(side)
    add_face()
    set_limb("Torso")


# ---------------------------------------------------------------------------
# 0.3.30 photoreal texture synthesis (numpy + Pillow, seed-deterministic).
# All maps are authored in sRGB byte terms for albedo / linear for
# normal+roughness, matching the hues the flat factors had pre-0.3.30.
# Face maps are painted in world space over the *deformed* skull so
# freckles/stubble/wrinkles land exactly on the sculpted features.
# ---------------------------------------------------------------------------

def _tile_noise(h, w, cells_x, cells_y, rng, wrap_y=False):
    """Value noise sampled on an h x w grid; always tiles in x."""
    rows = cells_y if wrap_y else cells_y + 1
    lat = rng.random((rows, cells_x))
    xs = np.linspace(0.0, cells_x, w, endpoint=False)
    ys = np.linspace(0.0, cells_y, h, endpoint=False) if wrap_y else np.linspace(0.0, cells_y, h, endpoint=True)
    x0 = np.floor(xs).astype(np.int64)
    fx = xs - x0
    y0 = np.floor(ys).astype(np.int64)
    fy = ys - y0
    x1 = (x0 + 1) % cells_x
    y1 = (y0 + 1) % cells_y if wrap_y else np.minimum(y0 + 1, cells_y)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    top = lat[y0][:, x0] * (1.0 - fx) + lat[y0][:, x1] * fx
    bot = lat[y1][:, x0] * (1.0 - fx) + lat[y1][:, x1] * fx
    return top * (1.0 - fy[:, None]) + bot * fy[:, None]


def _fbm_tile(h, w, cells_x, cells_y, rng, octaves=4, wrap_y=False):
    total = np.zeros((h, w))
    weight_sum = 0.0
    amp = 1.0
    cx, cy = cells_x, cells_y
    for _ in range(octaves):
        total += amp * _tile_noise(h, w, cx, cy, rng, wrap_y)
        weight_sum += amp
        amp *= 0.5
        cx *= 2
        cy *= 2
    return total / weight_sum


def _smooth_np(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _gauss_np(X, Y, Z, c, sgm):
    return np.exp(-(((X - c[0]) / sgm[0]) ** 2 + ((Y - c[1]) / sgm[1]) ** 2 + ((Z - c[2]) / sgm[2]) ** 2))


def _normal_from_height(hgt, strength):
    gx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * strength
    gy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * strength
    nx, ny, nz = -gx, -gy, np.ones_like(hgt)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx * inv * 0.5 + 0.5, ny * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5], axis=-1)


def _pack_rough(gray):
    return np.stack([np.ones_like(gray), np.clip(gray, 0.0, 1.0), np.zeros_like(gray)], axis=-1)


def _encode_image(rgb, kind):
    arr = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGB")
    buf = io.BytesIO()
    if kind == "jpeg":
        img.save(buf, "JPEG", quality=90)
        return buf.getvalue(), "image/jpeg"
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue(), "image/png"


def _down2(a):
    h, w = a.shape
    return a.reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))


def _bump_np(X, Y, Z, c, sgm, d, amp):
    w = _gauss_np(X, Y, Z, c, sgm) * amp
    return X + d[0] * w, Y + d[1] * w, Z + d[2] * w


def head_deform_np(X, Y, Z, Yu):
    """Vectorised twin of head_deform() so face textures painted in
    world space land on the sculpted surface texel-exactly."""
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.720, 0.095), (0.085, 0.075, 0.045), (0.0, 0.1, 1.0), 0.0075)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.765, -0.075), (0.070, 0.045, 0.040), (0.0, 0.0, 1.0), -0.0035)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.713, -0.100), (0.078, 0.015, 0.030), (0.0, 0.0, -1.0), 0.0042)
    for s in (-1.0, 1.0):
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.045, 1.693, -0.098), (0.020, 0.0135, 0.018), (0.0, 0.0, -1.0), -0.0045)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.688, -0.104), (0.0082, 0.027, 0.012), (0.0, 0.0, -1.0), 0.0075)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.652, -0.106), (0.0095, 0.0085, 0.0105), (0.0, -0.18, -1.0), 0.0152)
    for s in (-1.0, 1.0):
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.0145, 1.643, -0.104), (0.0085, 0.0075, 0.009), (s * 0.35, 0.0, -1.0), 0.0050)
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.077, 1.676, -0.058), (0.030, 0.021, 0.028), (s * 0.75, 0.0, -0.66), 0.0045)
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.073, 1.640, -0.052), (0.026, 0.018, 0.024), (s * 0.75, 0.0, -0.66), -0.0032)
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.027, 1.626, -0.096), (0.0075, 0.019, 0.011), (0.0, 0.0, -1.0), -0.0017)
        X, Y, Z = _bump_np(X, Y, Z, (s * 0.056, 1.602, -0.008), (0.020, 0.024, 0.035), (s * 1.0, 0.0, 0.0), 0.0028)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.627, -0.098), (0.009, 0.008, 0.012), (0.0, 0.0, -1.0), -0.0014)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.609, -0.094), (0.030, 0.011, 0.016), (0.0, 0.0, -1.0), 0.0022)
    X, Y, Z = _bump_np(X, Y, Z, (0.0, 1.570, -0.080), (0.020, 0.013, 0.014), (0.0, -0.3, -1.0), 0.0062)
    t = np.clip((1.662 - Y) / 0.115, 0.0, 1.0)
    ts = t * t * (3.0 - 2.0 * t)
    X = X * (1.0 - 0.20 * ts)
    Z = HEAD_C[2] + (Z - HEAD_C[2]) * (1.0 - 0.08 * ts) + 0.004 * ts
    tuck = np.clip((1.556 - Y) / 0.03, 0.0, 1.0)
    X = X * (1.0 - 0.22 * tuck)
    Z = HEAD_C[2] + (Z - HEAD_C[2]) * (1.0 - 0.20 * tuck)
    Y = Y - 0.005 * np.where(Yu > 0.72, (Yu - 0.72) / 0.28, 0.0)
    return X, Y, Z


def _make_face_textures():
    H = W = 1024
    rng = np.random.default_rng(20261101)
    uu = np.linspace(0.0, 1.0, W, endpoint=False)[None, :].repeat(H, axis=0)
    vv = np.linspace(0.0, 1.0, H)[:, None].repeat(W, axis=1)
    theta = vv * np.pi
    phi = uu * 2.0 * np.pi
    st, ct = np.sin(theta), np.cos(theta)
    Xu = np.cos(phi) * st
    Yu = ct
    Zu = np.sin(phi) * st
    X = HEAD_C[0] + HEAD_R[0] * Xu
    Y = HEAD_C[1] + HEAD_R[1] * Yu
    Z = HEAD_C[2] + HEAD_R[2] * Zu
    X, Y, Z = head_deform_np(X, Y, Z, Yu)

    def G(c, sgm):
        return _gauss_np(X, Y, Z, c, sgm)

    front = _smooth_np((-Z - 0.015) / 0.055)
    base = np.array([0.795, 0.592, 0.464])
    tone = 0.93 + 0.14 * _fbm_tile(H, W, 4, 3, rng)
    tone *= 0.965 + 0.07 * _fbm_tile(H, W, 18, 14, rng)
    alb = np.ones((H, W, 3)) * base[None, None, :] * tone[:, :, None]

    # Warm blood-flow zones: cheeks, nose, eye corners, chin.
    warm = (G((-0.066, 1.660, -0.072), (0.034, 0.027, 0.032)) + G((0.066, 1.660, -0.072), (0.034, 0.027, 0.032))
            + G((0.0, 1.652, -0.120), (0.020, 0.018, 0.016)) + 0.6 * G((0.0, 1.575, -0.088), (0.022, 0.016, 0.018)))
    warm = np.clip(warm, 0.0, 1.2)
    alb[:, :, 0] *= 1.0 + 0.09 * warm
    alb[:, :, 1] *= 1.0 - 0.06 * warm
    alb[:, :, 2] *= 1.0 - 0.07 * warm
    # Eye-socket soft shadow so lids blend into the skull.
    sock = G((-0.045, 1.693, -0.100), (0.023, 0.016, 0.020)) + G((0.045, 1.693, -0.100), (0.023, 0.016, 0.020))
    alb *= (1.0 - 0.10 * np.clip(sock, 0.0, 1.0))[:, :, None]
    # Nostril shadow.
    nos = G((-0.0115, 1.639, -0.118), (0.008, 0.006, 0.009)) + G((0.0115, 1.639, -0.118), (0.008, 0.006, 0.009))
    alb *= (1.0 - 0.55 * np.clip(nos, 0.0, 1.0))[:, :, None]
    # Freckles across the nose band and cheeks.
    freck_n = _tile_noise(H, W, 90, 90, rng)
    freck = _smooth_np((freck_n - 0.80) / 0.16)
    band = _smooth_np((0.030 - np.abs(Y - 1.666)) / 0.018) * _smooth_np((0.085 - np.abs(X)) / 0.02) * front
    k = (freck * band * 0.40)[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.52, 0.35, 0.24])[None, None, :] * k
    # Moles (asymmetry sells a real face).
    for c, sg, dark in (((0.058, 1.649, -0.089), 0.0017, 0.62), ((-0.037, 1.603, -0.091), 0.0014, 0.55),
                        ((0.021, 1.716, -0.105), 0.0012, 0.5)):
        alb *= (1.0 - dark * G(c, (sg, sg, sg)))[:, :, None]
    # Five-o'clock shadow: jaw, chin, jawline sides, light moustache zone.
    jaw = _smooth_np((1.640 - Y) / 0.02) * _smooth_np((Y - 1.546) / 0.012)
    sides = _smooth_np((np.abs(X) - 0.052) / 0.02) * _smooth_np((1.676 - Y) / 0.02) * _smooth_np((Y - 1.596) / 0.02)
    mous = _smooth_np((1.634 - Y) / 0.004) * _smooth_np((Y - 1.6195) / 0.004) * _smooth_np((0.032 - np.abs(X)) / 0.007)
    lip_metric = (X / 0.033) ** 2 + ((Y - 1.6115) / 0.0145) ** 2
    lip_clear = _smooth_np((lip_metric - 1.1) / 0.7)
    stub_mask = np.clip(jaw + sides + 0.7 * mous, 0.0, 1.0) * front * lip_clear
    speck = rng.random((H, W))
    dots = _smooth_np((speck - 0.72) / 0.20)
    dots = 0.5 * dots + 0.125 * (np.roll(dots, 1, 0) + np.roll(dots, -1, 0) + np.roll(dots, 1, 1) + np.roll(dots, -1, 1))
    k = (stub_mask * (0.10 + 0.40 * dots))[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.38, 0.35, 0.34])[None, None, :] * k
    # Pores: fine grain + sparse 1-2px dots (value-noise blobs read as craters).
    grain_f = _fbm_tile(H, W, 170, 170, rng, octaves=2)
    alb *= (0.982 + 0.036 * grain_f)[:, :, None]
    wht = rng.random((H, W))
    draw = _smooth_np((wht - 0.90) / 0.08)
    pore = (2.0 * draw + np.roll(draw, 1, 0) + np.roll(draw, -1, 0) + np.roll(draw, 1, 1) + np.roll(draw, -1, 1)) / 6.0
    pore_zone = 0.45 + 0.55 * np.clip(G((0.0, 1.67, -0.11), (0.045, 0.07, 0.03)) + G((0.0, 1.75, -0.08), (0.07, 0.035, 0.04)), 0.0, 1.0)
    alb *= (1.0 - 0.20 * pore * pore_zone)[:, :, None]
    # Forehead lines (albedo shade; grooves go to the height field too).
    fl = np.zeros((H, W))
    for ly in (1.7435, 1.7565):
        fl += np.exp(-(((Y - ly) / 0.0016) ** 2))
    fl *= front * (1.0 - _smooth_np((np.abs(X) - 0.052) / 0.03))
    alb *= (1.0 - 0.05 * np.clip(fl, 0.0, 1.0))[:, :, None]

    # Height field -> normal map (pores, lines, stubble, crow's feet).
    height = -0.55 * pore * pore_zone + 0.12 * dots * stub_mask - 0.5 * np.clip(fl, 0.0, 1.0) + 0.10 * (grain_f - 0.5)
    height += 0.10 * (_fbm_tile(H, W, 60, 48, rng) - 0.5)
    for (ux, vx, sgn) in ((0.8175, 0.4661, 1.0), (0.6825, 0.4661, -1.0)):
        for ang in (-0.5, -0.05, 0.4):
            du = (uu - (ux + sgn * 0.016)) * 0.64
            dv = vv - vx
            along = sgn * du * np.cos(ang) - dv * np.sin(ang)
            perp = sgn * du * np.sin(ang) + dv * np.cos(ang)
            line = np.exp(-((perp / 0.0016) ** 2)) * np.exp(-(((along - 0.011) / 0.009) ** 2)) * (along > 0)
            height -= 0.40 * line
            alb *= (1.0 - 0.04 * line)[:, :, None]
    # Roughness: shiny T-zone, matte stubble.
    tzone = np.clip(G((0.0, 1.748, -0.085), (0.075, 0.038, 0.045)) + G((0.0, 1.668, -0.112), (0.022, 0.055, 0.020)), 0.0, 1.0)
    rough = 0.58 - 0.18 * tzone + 0.10 * stub_mask + 0.06 * (_fbm_tile(H, W, 24, 18, rng) - 0.5)

    return {
        "albedo": _encode_image(alb, "jpeg"),
        "normal": _encode_image(_normal_from_height(_down2(height), 1.0), "png"),
        "rough": _encode_image(_pack_rough(_down2(rough)), "png"),
    }


def _make_skin_textures():
    H = W = 512
    rng = np.random.default_rng(20261102)
    base = np.array([0.795, 0.592, 0.464])
    tone = 0.94 + 0.12 * _fbm_tile(H, W, 5, 5, rng, wrap_y=True)
    alb = np.ones((H, W, 3)) * base[None, None, :] * tone[:, :, None]
    grain_f = _fbm_tile(H, W, 150, 150, rng, octaves=2, wrap_y=True)
    wht = rng.random((H, W))
    draw = _smooth_np((wht - 0.90) / 0.08)
    pore = (2.0 * draw + np.roll(draw, 1, 0) + np.roll(draw, -1, 0) + np.roll(draw, 1, 1) + np.roll(draw, -1, 1)) / 6.0
    alb *= (0.985 + 0.03 * grain_f)[:, :, None]
    alb *= (1.0 - 0.16 * pore)[:, :, None]
    fine = _fbm_tile(H, W, 40, 40, rng, wrap_y=True)
    alb *= (0.98 + 0.04 * fine)[:, :, None]
    height = -0.45 * pore + 0.14 * (grain_f - 0.5) + 0.10 * (fine - 0.5)
    rough = 0.60 + 0.07 * (_fbm_tile(H, W, 12, 12, rng, wrap_y=True) - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(height, 0.9), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def _make_hair_textures():
    H, W = 512, 1024
    rng = np.random.default_rng(20261103)
    base = np.array([0.225, 0.160, 0.118])
    # Fine ~1px strands: smoothed 1D column noise resampled through a
    # slow flow warp (value-noise streaks read as wide metal flutes).
    def _strand_field(scale, warp_amp, smooth_passes):
        n1d = rng.random(4096)
        for _ in range(smooth_passes):
            n1d = 0.25 * np.roll(n1d, 1) + 0.5 * n1d + 0.25 * np.roll(n1d, -1)
        warp = (_fbm_tile(H, W, 20, 5, rng) - 0.5) * warp_amp
        sx = (np.arange(W)[None, :] * scale + warp) % 4096.0
        i0 = np.floor(sx).astype(int)
        frac = sx - i0
        return n1d[i0] * (1.0 - frac) + n1d[(i0 + 1) % 4096] * frac

    strand_mix = 0.68 * _strand_field(2.0, 90.0, 2) + 0.32 * _strand_field(5.0, 150.0, 1)
    clumps = _tile_noise(H, W, 60, 3, rng)
    bright = (0.68 + 0.48 * strand_mix) * (0.86 + 0.28 * clumps)
    alb = np.ones((H, W, 3)) * base[None, None, :] * bright[:, :, None]
    light_strands = _smooth_np((strand_mix - 0.90) / 0.08)
    k = (light_strands * 0.22)[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.44, 0.33, 0.22])[None, None, :] * k
    vv = np.linspace(0.0, 1.0, H)[:, None]
    alb *= (1.0 - 0.22 * _smooth_np((vv - 0.88) / 0.1))[:, :, None]  # darker hairline rim
    height = strand_mix * 0.55 + clumps * 0.2
    rough = 0.65 - 0.09 * strand_mix + 0.04 * (_fbm_tile(H, W, 16, 4, rng) - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(height, 0.9), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def _make_fabric_textures(base_rgb, seed, twill=False, rough_base=0.8):
    H = W = 512
    rng = np.random.default_rng(seed)
    uu = np.linspace(0.0, 1.0, W, endpoint=False)[None, :].repeat(H, axis=0)
    vv = np.linspace(0.0, 1.0, H, endpoint=False)[:, None].repeat(W, axis=1)
    if twill:
        weave = 0.5 + 0.5 * np.sin(2.0 * np.pi * ((uu + vv) * 55.0))
        weave = weave * 0.65 + 0.35 * (0.5 + 0.5 * np.sin(2.0 * np.pi * vv * 110.0))
    else:
        weave = (0.5 + 0.5 * np.sin(2.0 * np.pi * uu * 80.0)) * (0.5 + 0.5 * np.sin(2.0 * np.pi * vv * 80.0))
    tone = 0.92 + 0.16 * _fbm_tile(H, W, 6, 6, rng, wrap_y=True)
    alb = np.ones((H, W, 3)) * np.array(base_rgb)[None, None, :] * tone[:, :, None] * (0.95 + 0.09 * weave)[:, :, None]
    if twill:  # denim flecks
        fleck = _smooth_np((_tile_noise(H, W, 260, 260, rng, wrap_y=True) - 0.93) / 0.06)
        alb *= (1.0 + 0.25 * fleck)[:, :, None]
    height = 0.55 * weave + 0.2 * (_fbm_tile(H, W, 30, 30, rng, wrap_y=True) - 0.5)
    rough = rough_base + 0.08 * (_fbm_tile(H, W, 10, 10, rng, wrap_y=True) - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(height, 0.55), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def _make_leather_textures():
    H = W = 512
    rng = np.random.default_rng(20261104)
    base = np.array([0.172, 0.160, 0.150])
    r1 = 1.0 - np.abs(2.0 * _fbm_tile(H, W, 10, 10, rng, octaves=3, wrap_y=True) - 1.0)
    r2 = 1.0 - np.abs(2.0 * _fbm_tile(H, W, 26, 26, rng, octaves=3, wrap_y=True) - 1.0)
    cells = 0.62 * r1 + 0.38 * r2
    alb = np.ones((H, W, 3)) * base[None, None, :] * (0.80 + 0.38 * cells)[:, :, None]
    scuff = _smooth_np((_tile_noise(H, W, 90, 90, rng, wrap_y=True) - 0.90) / 0.08)
    alb *= (1.0 + 0.20 * scuff)[:, :, None]
    rough = 0.46 + 0.22 * (1.0 - cells) + 0.05 * (_fbm_tile(H, W, 14, 14, rng, wrap_y=True) - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(cells, 1.1), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def _make_sole_textures():
    H = W = 512
    rng = np.random.default_rng(20261105)
    base = np.array([0.228, 0.218, 0.207])
    uu = np.linspace(0.0, 1.0, W, endpoint=False)[None, :].repeat(H, axis=0)
    vv = np.linspace(0.0, 1.0, H)[:, None].repeat(W, axis=1)
    tone = 0.9 + 0.2 * _fbm_tile(H, W, 10, 10, rng, wrap_y=True)
    alb = np.ones((H, W, 3)) * base[None, None, :] * tone[:, :, None]
    du = np.abs(((uu - 0.75 + 0.5) % 1.0) - 0.5)
    band = _smooth_np((0.17 - du) / 0.045)
    bars = _smooth_np((np.sin(2.0 * np.pi * vv * 9.0) - 0.25) / 0.4)
    alb *= (1.0 - 0.35 * band * bars)[:, :, None]
    speck = _tile_noise(H, W, 240, 240, rng, wrap_y=True)
    alb *= (0.92 + 0.16 * speck)[:, :, None]
    height = -1.2 * band * bars + 0.3 * (speck - 0.5)
    rough = 0.92 + 0.05 * (_fbm_tile(H, W, 8, 8, rng, wrap_y=True) - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(height, 1.3), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def _make_sclera_texture():
    H = W = 256
    rng = np.random.default_rng(20261106)
    base = np.array([0.930, 0.905, 0.862])
    alb = np.ones((H, W, 3)) * base[None, None, :]
    uu = np.linspace(0.0, 1.0, W, endpoint=False)[None, :].repeat(H, axis=0)
    vv = np.linspace(0.0, 1.0, H)[:, None].repeat(W, axis=1)
    du = np.abs(((uu - 0.75 + 0.5) % 1.0) - 0.5)
    dist = np.sqrt((du * 0.8) ** 2 + ((vv - 0.5) * 1.2) ** 2)
    veins = _smooth_np((1.0 - np.abs(2.0 * _fbm_tile(H, W, 5, 4, rng, octaves=3) - 1.0) - 0.90) / 0.08)
    vein_mask = _smooth_np((dist - 0.05) / 0.10) * (1.0 - _smooth_np((dist - 0.30) / 0.12))
    k = (veins * vein_mask * 0.75)[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.66, 0.30, 0.26])[None, None, :] * k
    alb *= (1.0 - 0.05 * _smooth_np((dist - 0.18) / 0.15))[:, :, None]
    return {"albedo": _encode_image(alb, "jpeg")}


def _make_iris_texture():
    H = W = 256
    rng = np.random.default_rng(20261107)
    yy, xx = np.mgrid[0:H, 0:W]
    dx = (xx / (W - 1) - 0.5) * 2.0
    dy = (yy / (H - 1) - 0.5) * 2.0
    R = np.sqrt(dx * dx + dy * dy)
    A = (np.arctan2(dy, dx) / (2.0 * np.pi)) % 1.0
    fibre_tex = _tile_noise(256, 256, 110, 3, rng)
    fibres = fibre_tex[np.clip((R * 255).astype(int), 0, 255), np.clip((A * 255).astype(int), 0, 255)]
    fleck_tex = _tile_noise(256, 256, 46, 4, rng)
    flecks = fleck_tex[np.clip((R * 255).astype(int), 0, 255), np.clip((A * 255).astype(int), 0, 255)]
    inner = np.array([0.155, 0.088, 0.038])
    mid = np.array([0.265, 0.158, 0.068])
    outer = np.array([0.185, 0.108, 0.048])
    grad = np.ones((H, W, 3)) * inner[None, None, :]
    m1 = _smooth_np((R - 0.45) / 0.25)[:, :, None]
    grad = grad * (1.0 - m1) + mid[None, None, :] * m1
    m2 = _smooth_np((R - 0.75) / 0.2)[:, :, None]
    grad = grad * (1.0 - m2) + outer[None, None, :] * m2
    alb = grad * (0.72 + 0.50 * fibres)[:, :, None]
    amber = _smooth_np((flecks - 0.80) / 0.15) * _smooth_np((0.85 - np.abs(R - 0.62)) / 0.3)
    k = (amber * 0.35)[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.46, 0.31, 0.115])[None, None, :] * k
    collar = np.exp(-(((R - (0.62 + 0.045 * np.sin(A * 2.0 * np.pi * 36.0))) / 0.035) ** 2))
    alb *= (1.0 - 0.30 * collar)[:, :, None]
    alb *= (1.0 - 0.75 * _smooth_np((R - 0.90) / 0.08))[:, :, None]  # limbal ring
    alb = np.where((R < 0.424)[:, :, None], np.array([0.008, 0.008, 0.008])[None, None, :], alb)
    alb = np.where((R > 1.0)[:, :, None], np.array([0.185, 0.108, 0.048])[None, None, :], alb)
    return {"albedo": _encode_image(alb, "jpeg")}


def _make_lips_textures():
    H = W = 256
    rng = np.random.default_rng(20261108)
    base = np.array([0.660, 0.450, 0.392])
    lines = _tile_noise(H, W, 190, 26, rng)
    alb = np.ones((H, W, 3)) * base[None, None, :] * (0.94 + 0.10 * lines)[:, :, None]
    uu = np.linspace(0.0, 1.0, W, endpoint=False)[None, :].repeat(H, axis=0)
    vv = np.linspace(0.0, 1.0, H)[:, None].repeat(W, axis=1)
    du = np.abs(((uu - 0.75 + 0.5) % 1.0) - 0.5)
    centre = np.exp(-((du / 0.16) ** 2 + ((vv - 0.5) / 0.30) ** 2))
    k = (centre * 0.35)[:, :, None]
    alb = alb * (1.0 - k) + np.array([0.575, 0.330, 0.275])[None, None, :] * k
    rough = 0.60 - 0.22 * centre + 0.05 * (lines - 0.5)
    return {"albedo": _encode_image(alb, "jpeg"), "normal": _encode_image(_normal_from_height(lines, 0.7), "png"),
            "rough": _encode_image(_pack_rough(rough), "png")}


def build_material_textures():
    """material index -> {'albedo'|'normal'|'rough': (bytes, mime)}"""
    return {
        SKIN: _make_skin_textures(),
        FACE_SKIN: _make_face_textures(),
        JACKET: _make_fabric_textures((0.255, 0.435, 0.421), 20261110, twill=False, rough_base=0.78),
        SHIRT: _make_fabric_textures((0.892, 0.847, 0.763), 20261111, twill=False, rough_base=0.85),
        TROUSERS: _make_fabric_textures((0.308, 0.359, 0.409), 20261112, twill=True, rough_base=0.90),
        HAIR: _make_hair_textures(),
        SHOES: _make_leather_textures(),
        SOLE: _make_sole_textures(),
        EYES: _make_sclera_texture(),
        IRIS: _make_iris_texture(),
        LIPS: _make_lips_textures(),
    }


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

    def append_accessor(raw: bytes, component_type: int, count: int, accessor_type: str, target: int,
                        minimum=None, maximum=None, normalized=False) -> int:
        align4(binary)
        offset = len(binary)
        binary.extend(raw)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(raw), "target": target})
        accessor = {"bufferView": len(buffer_views) - 1, "componentType": component_type, "count": count, "type": accessor_type}
        if normalized:
            accessor["normalized"] = True
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
        colors = bucket["colors"]
        uvs = bucket["uvs"]
        if not positions or not indices:
            continue
        normals = make_normals(positions, indices)
        # Weld normals of coincident vertices (duplicated UV-seam columns)
        # so texture seams never shade as creases.
        _groups = {}
        for _i, _p in enumerate(positions):
            _groups.setdefault((round(_p[0], 6), round(_p[1], 6), round(_p[2], 6)), []).append(_i)
        for _idxs in _groups.values():
            if len(_idxs) > 1:
                _sx = sum(normals[_i][0] for _i in _idxs)
                _sy = sum(normals[_i][1] for _i in _idxs)
                _sz = sum(normals[_i][2] for _i in _idxs)
                _ln = math.sqrt(_sx * _sx + _sy * _sy + _sz * _sz)
                if _ln > 1e-8:
                    for _i in _idxs:
                        normals[_i] = (_sx / _ln, _sy / _ln, _sz / _ln)
        pflat = [v for p in positions for v in p]
        nflat = [v for n in normals for v in n]
        pos_raw = struct.pack("<%sf" % len(pflat), *pflat)
        norm_raw = struct.pack("<%sf" % len(nflat), *nflat)
        color_bytes = bytearray()
        for r, g, b in colors:
            color_bytes.extend((max(0, min(255, round(r * 255))), max(0, min(255, round(g * 255))),
                                max(0, min(255, round(b * 255))), 255))
        if max(indices) > 65535:
            index_raw = struct.pack("<%sI" % len(indices), *indices)
            index_component = 5125
        else:
            index_raw = struct.pack("<%sH" % len(indices), *indices)
            index_component = 5123
        mins = [min(p[k] for p in positions) for k in range(3)]
        maxs = [max(p[k] for p in positions) for k in range(3)]
        position_accessor = append_accessor(pos_raw, 5126, len(positions), "VEC3", 34962, mins, maxs)
        normal_accessor = append_accessor(norm_raw, 5126, len(normals), "VEC3", 34962)
        color_accessor = append_accessor(bytes(color_bytes), 5121, len(colors), "VEC4", 34962, normalized=True)
        uvflat = [component for uv in uvs for component in uv]
        uv_raw = struct.pack("<%sf" % len(uvflat), *uvflat)
        uv_accessor = append_accessor(uv_raw, 5126, len(uvs), "VEC2", 34962)
        index_accessor = append_accessor(index_raw, index_component, len(indices), "SCALAR", 34963)
        meshes.append({"name": limb + "_" + MATERIALS[material_index][0], "primitives": [{
            "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor, "COLOR_0": color_accessor, "TEXCOORD_0": uv_accessor},
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

    # 0.3.30: synthesised PBR maps (image bufferViews carry no target).
    tex_by_mat = build_material_textures()
    images, textures = [], []
    samplers = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]

    def append_image(data: bytes, mime: str) -> int:
        align4(binary)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data)})
        images.append({"bufferView": len(buffer_views) - 1, "mimeType": mime})
        textures.append({"sampler": 0, "source": len(images) - 1})
        return len(textures) - 1

    mat_textures = {}
    for mat_index, maps in sorted(tex_by_mat.items()):
        entry = {}
        if "albedo" in maps:
            entry["baseColorTexture"] = {"index": append_image(*maps["albedo"])}
        if "rough" in maps:
            entry["metallicRoughnessTexture"] = {"index": append_image(*maps["rough"])}
        if "normal" in maps:
            entry["normalTexture"] = {"index": append_image(*maps["normal"])}
        mat_textures[mat_index] = entry

    def material_json(index, name, color, metallic, roughness):
        pbr = {"baseColorFactor": color, "metallicFactor": metallic, "roughnessFactor": roughness}
        extra = mat_textures.get(index, {})
        if "baseColorTexture" in extra:
            pbr["baseColorTexture"] = extra["baseColorTexture"]
        if "metallicRoughnessTexture" in extra:
            pbr["metallicRoughnessTexture"] = extra["metallicRoughnessTexture"]
        mat = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": True}
        if "normalTexture" in extra:
            mat["normalTexture"] = extra["normalTexture"]
        return mat

    gltf = {
        "asset": {"version": "2.0", "generator": "Nitches procedural human character builder (0.3.30 textured)", "copyright": "Original Nitches character asset"},
        "scene": 0,
        "scenes": [{"name": "Nitches Player Character", "nodes": [len(nodes)]}],
        "nodes": nodes + [{"name": "NitchesPlayerCharacter", "children": children}],
        "meshes": meshes,
        "materials": [material_json(i, *mat) for i, mat in enumerate(MATERIALS)],
        "images": images,
        "textures": textures,
        "samplers": samplers,
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
