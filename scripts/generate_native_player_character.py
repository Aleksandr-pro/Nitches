#!/usr/bin/env python3
"""Build the detailed human character GLB for the native Godot game.

0.3.29: full procedural rewrite for close-range realism.  Still uses
only Python's standard library (CI regenerates without Blender), but
the single-instance avatar now spends ~60k triangles: the face is
carried by skull deformation (nose/brow/cheek/chin gaussian bumps,
eye-socket dimples) instead of glued-on balls, the hair is one cap
with a smooth swept hairline, the jacket is a shaped loft with a
closed muted-metal zipper, hands have curled fingers, and shoes are
lofted over a real side profile with a separate rubber sole.
COLOR_0 (normalized ubyte VEC4) carries tint x procedural grain so
surfaces have variation and roughness read without textures.

Joint layout, material order (append-only) and the translation-only
node hierarchy are unchanged from 0.3.28 so player_character.gd can
pose the same 12 joints procedurally.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/assets/models/characters/nitches_player.glb"

MATERIALS = [
    ("Skin", (0.63, 0.37, 0.25, 1.0), 0.0, 0.62),
    ("Jacket - deep teal", (0.055, 0.16, 0.15, 1.0), 0.0, 0.74),
    ("Shirt - warm ivory", (0.78, 0.70, 0.55, 1.0), 0.0, 0.84),
    ("Trousers - charcoal blue", (0.075, 0.105, 0.14, 1.0), 0.0, 0.9),
    ("Hair - dark brown", (0.072, 0.050, 0.038, 1.0), 0.0, 0.82),
    ("Shoes - dark leather", (0.045, 0.039, 0.034, 1.0), 0.0, 0.38),
    ("Warm metal details", (0.54, 0.31, 0.095, 1.0), 0.38, 0.42),
    ("Eyes", (0.93, 0.89, 0.82, 1.0), 0.0, 0.22),
    ("Iris", (0.12, 0.065, 0.035, 1.0), 0.0, 0.25),
    ("Mouth", (0.20, 0.075, 0.055, 1.0), 0.0, 0.8),
    # 0.3.29 append-only additions; existing indices must never move.
    ("Lips", (0.46, 0.225, 0.175, 1.0), 0.0, 0.48),
    ("Pupil", (0.012, 0.010, 0.009, 1.0), 0.0, 0.18),
    ("Shoe sole - rubber", (0.115, 0.105, 0.095, 1.0), 0.0, 0.92),
]
SKIN, JACKET, SHIRT, TROUSERS, HAIR, SHOES, METAL, EYES, IRIS, MOUTH, LIPS, PUPIL, SOLE = range(len(MATERIALS))
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


def add_mesh(material: int, positions, indices, colors=None) -> None:
    joint_x, joint_y, joint_z = LIMBS[CURRENT_LIMB][1]
    bucket = LIMB_BUCKETS.setdefault((CURRENT_LIMB, material), {"positions": [], "indices": [], "colors": []})
    offset = len(bucket["positions"])
    bucket["positions"].extend((x - joint_x, y - joint_y, z - joint_z) for x, y, z in positions)
    bucket["indices"].extend(offset + index for index in indices)
    if colors is None:
        colors = [(1.0, 1.0, 1.0)] * len(positions)
    bucket["colors"].extend(colors)


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

def add_ellipsoid(material, center, radii, segments=32, rings=20, deformation=None, color_fn=None) -> None:
    cx, cy, cz = center
    rx, ry, rz = radii
    positions = []
    indices = []
    for row in range(rings + 1):
        theta = math.pi * row / rings
        y_unit = math.cos(theta)
        ring_radius = math.sin(theta)
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            x_unit = math.cos(phi) * ring_radius
            z_unit = math.sin(phi) * ring_radius
            x = cx + rx * x_unit
            y = cy + ry * y_unit
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
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None)


def add_grid(material, rows, closed_loop=True, color_fn=None) -> None:
    """Triangulate a list of equal-length vertex rings."""
    positions = []
    indices = []
    segments = len(rows[0])
    for ring in rows:
        positions.extend(ring)
    col_range = range(segments) if closed_loop else range(segments - 1)
    for row in range(len(rows) - 1):
        for col in col_range:
            nxt = (col + 1) % segments
            a = row * segments + col
            b = row * segments + nxt
            c = (row + 1) * segments + nxt
            d = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None)


def add_loft(material, stations, segments=32, power=1.0, cap_start=True, cap_end=True,
             shape_fn=None, vertex_fn=None, color_fn=None) -> None:
    """Ring loft.  Each station is (origin, u_vec, v_vec); a ring point is
    origin + u*spow(cos phi) + v*spow(sin phi), so power < 1 squares the
    section (flat chest/front, shoe last) and power 1 keeps it elliptical."""
    def spow(v):
        return math.copysign(abs(v) ** power, v) if power != 1.0 else v

    positions = []
    indices = []
    for origin, u_vec, v_vec in stations:
        for col in range(segments):
            phi = 2.0 * math.pi * col / segments
            cu, cv = spow(math.cos(phi)), spow(math.sin(phi))
            mult = shape_fn(phi) if shape_fn else 1.0
            p = (origin[0] + (u_vec[0] * cu + v_vec[0] * cv) * mult,
                 origin[1] + (u_vec[1] * cu + v_vec[1] * cv) * mult,
                 origin[2] + (u_vec[2] * cu + v_vec[2] * cv) * mult)
            if vertex_fn:
                p = vertex_fn(p)
            positions.append(p)
    for row in range(len(stations) - 1):
        for col in range(segments):
            a = row * segments + col
            b = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d = (row + 1) * segments + col
            indices.extend((a, b, c, a, c, d))
    if cap_start:
        positions.append(stations[0][0])
        start_center = len(positions) - 1
        for col in range(segments):
            indices.extend((start_center, (col + 1) % segments, col))
    if cap_end:
        positions.append(stations[-1][0])
        end_center = len(positions) - 1
        end_row = (len(stations) - 1) * segments
        for col in range(segments):
            indices.extend((end_center, end_row + col, end_row + (col + 1) % segments))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None)


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
                  rounded_caps=True, offset_fn=None, color_fn=None) -> None:
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
        for col in range(segments):
            angle = 2.0 * math.pi * col / segments
            ca, sa = math.cos(angle), math.sin(angle)
            ring.append((centre[0] + radius * ca * n[0] + radius * depth_ratio * sa * b[0],
                         centre[1] + radius * ca * n[1] + radius * depth_ratio * sa * b[1],
                         centre[2] + radius * ca * n[2] + radius * depth_ratio * sa * b[2]))
        rows.append(ring)

    positions = []
    indices = []
    for ring in rows:
        positions.extend(ring)
    for row in range(len(rows) - 1):
        for col in range(segments):
            a = row * segments + col
            bb = row * segments + (col + 1) % segments
            c = (row + 1) * segments + (col + 1) % segments
            d = (row + 1) * segments + col
            indices.extend((a, bb, c, a, c, d))
    positions.extend((rings[0][0], rings[-1][0]))
    start_center = len(positions) - 2
    end_center = len(positions) - 1
    end_row = (len(rows) - 1) * segments
    for col in range(segments):
        indices.extend((start_center, (col + 1) % segments, col))
        indices.extend((end_center, end_row + col, end_row + (col + 1) % segments))
    add_mesh(material, positions, indices, paint(positions, color_fn) if color_fn else None)


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
    add_grid(HAIR, grid, True, hair_paint)


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
    add_ellipsoid(SKIN, HEAD_C, HEAD_R, 96, 64, head_deform, skin_paint)
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
    # Eyeballs (deeply sunk) behind skin eyelid caps, so only an almond
    # of sclera/iris shows; iris and pupil sit flush on the ball front.
    for s in (-1.0, 1.0):
        ex = s * 0.045
        add_ellipsoid(EYES, (ex, 1.6935, -0.0960), (0.0128, 0.0128, 0.0128), 28, 18)
        add_ellipsoid(IRIS, (ex, 1.6935, -0.1060), (0.0062, 0.0062, 0.0030), 20, 12)
        add_ellipsoid(PUPIL, (ex, 1.6935, -0.1078), (0.0030, 0.0030, 0.0016), 14, 9)

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

    add_loft(JACKET, stations, 64, 0.78, True, True, groove, None, jacket_paint)
    # Standing collar band (hugs the narrowed torso top, no tray ring).
    collar = [((0.0, 1.505, 0.001), (0.160, 0.0, 0.0), (0.0, 0.0, 0.102)),
              ((0.0, 1.536, 0.001), (0.150, 0.0, 0.0), (0.0, 0.0, 0.096)),
              ((0.0, 1.562, 0.001), (0.138, 0.0, 0.0), (0.0, 0.0, 0.089))]
    add_loft(JACKET, collar, 48, 0.85, False, False, None, None, lambda x, y, z: mul3(jacket_paint(x, y, z), 0.94))
    # Shirt triangle at the throat (jacket stays closed).
    add_ellipsoid(SHIRT, (0.0, 1.516, -0.0765), (0.032, 0.037, 0.021), 24, 16, None, shirt_paint)
    # Neck with trapezius flare (Torso limb: stays with the body).
    add_tube_path(SKIN, [(0.0, 1.462, 0.006), (0.0, 1.540, 0.002), (0.0, 1.612, -0.001)],
                  [(0.0, 0.078), (0.45, 0.057), (1.0, 0.053)], 28, 10, 0.9, True, None,
                  lambda x, y, z: mul3(skin_paint(x, y, z), 0.97))
    add_zipper()
    # Chest pocket flaps with muted mini-zips.
    for s in (-1.0, 1.0):
        add_ellipsoid(JACKET, (s * 0.187, 1.098, -0.137), (0.049, 0.031, 0.011), 24, 14, None,
                      lambda x, y, z: mul3(jacket_paint(x, y, z), 0.96))
        add_box(METAL, (s * 0.187, 1.142, -0.140), (0.078, 0.005, 0.005),
                lambda x, y, z: (0.5, 0.5, 0.5))


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
    add_ellipsoid(JACKET, (side * 0.326, 1.447, 0.0), (0.090, 0.094, 0.100), 32, 22, None, jacket_paint)
    add_tube_path(JACKET, [(side * 0.318, 1.478, 0.0), shoulder, (side * 0.392, 1.300, -0.004), elbow],
                  [(0.0, 0.096), (0.3, 0.085), (0.75, 0.072), (1.0, 0.064)], 28, 14, 0.92, True, fold, jacket_paint)
    set_limb("Forearm" + suffix)
    add_ellipsoid(JACKET, elbow, (0.068, 0.072, 0.068), 26, 18, None, jacket_paint)
    add_tube_path(JACKET, [elbow, (side * 0.426, 1.010, -0.018), wrist],
                  [(0.0, 0.064), (0.35, 0.057), (0.85, 0.047), (1.0, 0.046)], 26, 12, 0.94, True, fold, jacket_paint)
    # Cuff band at the wrist (loft ring standing around the forearm axis).
    add_loft(JACKET, [((wrist[0], 0.904, wrist[2]), (0.054, 0.0, 0.0), (0.0, 0.0, 0.051)),
                      ((wrist[0], 0.864, wrist[2]), (0.052, 0.0, 0.0), (0.0, 0.0, 0.049))],
             26, 1.0, False, False, None, None, lambda x, y, z: mul3(jacket_paint(x, y, z), 0.90))
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
                      [(0.0, 0.0088), (0.6, 0.0078), (1.0, 0.0062)], 14, 7, 0.95, True, None, skin_paint)
    # Thumb on the body's inner-front side of the palm.
    tx = palm_c[0] - side * 0.034
    add_tube_path(SKIN, [(tx, 0.820, -0.040), (tx - side * 0.010, 0.786, -0.047), (tx - side * 0.013, 0.756, -0.044)],
                  [(0.0, 0.0102), (0.6, 0.0088), (1.0, 0.0070)], 14, 7, 0.95, True, None, skin_paint)


def add_leg(side: float) -> None:
    suffix = "L" if side < 0 else "R"
    hip = (side * 0.135, 0.83, 0.0)
    knee = (side * 0.145, 0.48, 0.018)
    ankle = (side * 0.155, 0.115, -0.005)
    set_limb("Thigh" + suffix)
    add_tube_path(TROUSERS, [(side * 0.132, 0.878, 0.0), hip, (side * 0.141, 0.650, 0.010), knee],
                  [(0.0, 0.122), (0.3, 0.110), (0.75, 0.095), (1.0, 0.089)], 30, 16, 0.90, True, None, trousers_paint)
    set_limb("Shin" + suffix)
    add_ellipsoid(TROUSERS, knee, (0.091, 0.094, 0.093), 28, 20, None, trousers_paint)

    def calf(t):
        return (0.0, 0.0, 0.011 * math.sin(math.pi * min(max(t * 1.25, 0.0), 1.0)) ** 1.5)

    add_tube_path(TROUSERS, [knee, (side * 0.150, 0.300, 0.008), ankle],
                  [(0.0, 0.089), (0.25, 0.083), (0.7, 0.065), (1.0, 0.057)], 28, 14, 0.92, True, calf, trousers_paint)
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
             lambda p: (p[0], max(p[1], 0.022), p[2]), leather_paint)
    # Sole: slim slab with a mild toe spring and a real heel block.
    sole = [  # (z, width, bottom y, top y)
        (0.092, 0.058, 0.006, 0.034), (0.070, 0.087, 0.004, 0.035),
        (0.020, 0.094, 0.004, 0.029), (-0.060, 0.096, 0.004, 0.027),
        (-0.130, 0.094, 0.005, 0.027), (-0.180, 0.084, 0.007, 0.027),
        (-0.205, 0.066, 0.011, 0.028), (-0.214, 0.038, 0.016, 0.028),
    ]
    stations = [((cx, (tb + tp) / 2.0, z), (w / 2.0, 0.0, 0.0), (0.0, (tp - tb) / 2.0, 0.0)) for z, w, tb, tp in sole]
    add_loft(SOLE, stations, 36, 0.80, True, True, None, None, sole_paint)
    # Tongue + ivory laces across the instep.
    tongue = [((cx, 0.026 + hh + 0.0012, zz), (0.023, 0.0, 0.0), (0.0, 0.0035, 0.0)) for zz, hh in
              ((-0.012, 0.0805), (-0.055, 0.069), (-0.100, 0.0555), (-0.138, 0.0475))]
    add_loft(SHOES, tongue, 20, 0.9, True, True, None, None,
             lambda x, y, z: mul3(leather_paint(x, y, z), 1.18))
    for i in range(5):
        lz = -0.030 - i * 0.023
        top = 0.026 + (0.0744 - i * 0.0055)
        add_tube_path(SHIRT, [(cx - 0.030, top - 0.007, lz), (cx, top + 0.0015, lz - 0.002), (cx + 0.030, top - 0.007, lz)],
                      [(0.0, 0.0034), (1.0, 0.0034)], 10, 5, 0.8, True, None, shirt_paint)


def build_character() -> None:
    add_torso()
    # Hips (trousers) bridging torso and thighs.
    set_limb("Torso")

    def hip_deform(x, y, z, _xu, y_unit, _zu):
        # Slight seat shaping: fuller behind, flatter in front.
        if z > 0.02:
            z += 0.006
        return x, y, z

    add_ellipsoid(TROUSERS, (0.0, 0.875, 0.004), (0.258, 0.147, 0.154), 48, 32, hip_deform, trousers_paint)
    for side in (-1.0, 1.0):
        add_arm(side)
        add_leg(side)
    add_face()
    set_limb("Torso")


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
        if not positions or not indices:
            continue
        normals = make_normals(positions, indices)
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
        index_accessor = append_accessor(index_raw, index_component, len(indices), "SCALAR", 34963)
        meshes.append({"name": limb + "_" + MATERIALS[material_index][0], "primitives": [{
            "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor, "COLOR_0": color_accessor},
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
