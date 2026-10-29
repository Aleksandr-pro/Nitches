#!/usr/bin/env python3
"""Desert ("Пустынный каньон") world generator for Nitches Horizon Native.

Implements the owner's spec (docs/DESERT_MAP.md): 4x4 km desert basin,
north mesas + 2 canyons, NE quarry, east oil field, central salt flat,
west town "Дюны", SW wind farm, southern dune sea, SE oasis, ring
highway + secondary asphalt + dirt network, density rules (250 m grid,
70/30 along roads, per-zone budgets) and the required density heatmap
report.

Output: native/data/desert_native.json in the same schema as
richtown_native.json (terrain heights, roads with samples, districts,
zones, landmarks, spawn, stats) plus a "desert" section with scatter
placements, structures and game content consumed by the Godot desert
build path in world_builder.gd.

Coordinates: Godot metres, X east 0..4000, Z south 0..4000 (the spec's
km-from-NW-corner maps 1:1 with y -> Z).  Terrain grid 501x501 @ 8 m.

Run:  PYTHONPATH=<numpy+pillow> python3 scripts/generate_desert_world.py
"""

import json
import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "native/data/desert_native.json")
OUT_REPORT = os.path.join(ROOT, "docs/desert-density-report.txt")
OUT_HEATMAP = os.path.join(ROOT, "docs/desert-density-heatmap.png")
OUT_PREVIEW = os.path.join(ROOT, "docs/desert-design-preview.png")
PREVIEW_DIR = "/tmp/desert_prev"

SEED = 20261029
rng = np.random.default_rng(SEED)

SIZE = 4000.0
STEP = 8.0
N = int(SIZE / STEP) + 1  # 501

xs = np.linspace(0.0, SIZE, N)
zs = np.linspace(0.0, SIZE, N)
GX, GZ = np.meshgrid(xs, zs)  # [iz, ix]


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- noise
def value_noise(cells, seed):
    r = np.random.default_rng(seed)
    coarse = r.random((cells + 1, cells + 1)).astype(np.float32)
    # bilinear upsample to N x N
    idx = np.linspace(0, cells, N)
    i0 = np.floor(idx).astype(int)
    frac = (idx - i0).astype(np.float32)
    i1 = np.minimum(i0 + 1, cells)
    top = coarse[i0][:, i0] * (1 - frac) + coarse[i0][:, i1] * frac
    bot = coarse[i1][:, i0] * (1 - frac) + coarse[i1][:, i1] * frac
    out = top * (1 - frac)[:, None] + bot * frac[:, None]
    return out * 2.0 - 1.0


def fbm(cells_list, seed0):
    total = np.zeros((N, N), dtype=np.float32)
    amp_sum = 0.0
    amp = 1.0
    for i, cells in enumerate(cells_list):
        total += value_noise(cells, seed0 + i * 131) * amp
        amp_sum += amp
        amp *= 0.5
    return total / amp_sum


# ---------------------------------------------------------------- helpers
def catmull_rom(points, closed=False, step=4.0):
    """Resample a polyline through control points at ~step metres."""
    pts = [np.array(p, dtype=np.float64) for p in points]
    if closed:
        ext = [pts[-1]] + pts + [pts[0], pts[1]]
    else:
        ext = [pts[0]] + pts + [pts[-1]]
    dense = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        seg_len = float(np.linalg.norm(p2 - p1))
        n_sub = max(2, int(seg_len / step))
        for j in range(n_sub):
            t = j / n_sub
            t2, t3 = t * t, t * t * t
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t +
                                (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                                (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    dense.append(pts[0].copy() if closed else pts[-1].copy())
    return np.array(dense)


def resample_even(dense, step):
    """Pick points roughly every `step` metres along a dense polyline."""
    if len(dense) < 2:
        return dense
    out = [dense[0]]
    acc = 0.0
    for i in range(1, len(dense)):
        acc += float(np.linalg.norm(dense[i] - dense[i - 1]))
        if acc >= step:
            out.append(dense[i])
            acc = 0.0
    if np.linalg.norm(out[-1] - dense[-1]) > 1.0:
        out.append(dense[-1])
    return np.array(out)


def bilinear(grid, x, z):
    fx = np.clip(x / STEP, 0, N - 1.001)
    fz = np.clip(z / STEP, 0, N - 1.001)
    ix, iz = int(fx), int(fz)
    tx, tz = fx - ix, fz - iz
    return float(
        grid[iz, ix] * (1 - tx) * (1 - tz) + grid[iz, ix + 1] * tx * (1 - tz) +
        grid[iz + 1, ix] * (1 - tx) * tz + grid[iz + 1, ix + 1] * tx * tz)


def polyline_local_op(grid, dense, radius, fn):
    """Apply fn(dist_array, s_array) -> new heights on cells near polyline.

    fn receives, per local bbox: distance to the current segment and the
    along-polyline distance s of the closest point; it must return the
    modified height sub-grid.  Segments process in order.
    """
    # cumulative s
    seg_lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_cum = np.concatenate([[0.0], np.cumsum(seg_lens)])
    return _polyline_local_op_s(grid, dense, radius, fn, s_cum)


def _polyline_local_op_s(grid, dense, radius, fn, s_cum):
    for i in range(len(dense) - 1):
        a, b = dense[i], dense[i + 1]
        minx = max(0, int((min(a[0], b[0]) - radius) / STEP))
        maxx = min(N - 1, int((max(a[0], b[0]) + radius) / STEP) + 1)
        minz = max(0, int((min(a[1], b[1]) - radius) / STEP))
        maxz = min(N - 1, int((max(a[1], b[1]) + radius) / STEP) + 1)
        if maxx <= minx or maxz <= minz:
            continue
        lx = xs[minx:maxx + 1][None, :]
        lz = zs[minz:maxz + 1][:, None]
        ab = b - a
        lab = float(ab @ ab)
        if lab < 1e-9:
            continue
        t = np.clip(((lx - a[0]) * ab[0] + (lz - a[1]) * ab[1]) / lab, 0, 1)
        px = a[0] + ab[0] * t
        pz = a[1] + ab[1] * t
        dist = np.hypot(lx - px, lz - pz)
        s = s_cum[i] + t * math.sqrt(lab)
        sub = grid[minz:maxz + 1, minx:maxx + 1]
        grid[minz:maxz + 1, minx:maxx + 1] = fn(sub, dist, s)
    return grid


# ---------------------------------------------------------------- zones
SALT_RECT = (1200.0, 1500.0, 2800.0, 2700.0)      # minx, minz, maxx, maxz
TOWN_RECT = (400.0, 1600.0, 1200.0, 2400.0)
QUARRY_RECT = (2800.0, 500.0, 3800.0, 1500.0)
OIL_RECT = (3000.0, 1800.0, 4000.0, 2800.0)
OASIS_CENTRE = np.array([3350.0, 3500.0])
LAKE_R = 78.0
LAKE_Y = 26.2
SALT_Y = 34.0


def in_rect(x, z, r):
    return r[0] <= x <= r[2] and r[1] <= z <= r[3]


# ---------------------------------------------------------------- height
print("[desert] base heightfield ...")
basin = 32.0 + fbm([5, 11, 23], 101) * 4.6 + fbm([47], 7331) * 1.0
H = basin.astype(np.float64)

# North plateau massif (z 0..1200), falling to the basin by z ~1500.
plateau_mask = smoothstep(1550.0, 950.0, GZ)
plateau = 48.0 + fbm([6, 13], 202) * 8.0 + fbm([13, 29], 909) * 3.2
H += plateau_mask * plateau

# Mesa / butte blobs: (x, z, rx, rz, top_height_over_basin, name)
MESAS = [
    (420, 300, 330, 240, 58, "Западная меза"),
    (1050, 210, 300, 200, 62, "Северная меза"),
    (1650, 420, 360, 260, 56, "Меза Серпантина"),
    (1850, 330, 200, 160, 62, "Меза Радиовышки"),
    (2300, 260, 320, 210, 58, "Восточная меза"),
    (2900, 330, 300, 220, 54, "Меза Карьера"),
    (3520, 260, 340, 230, 52, "Крайняя меза"),
    (800, 780, 260, 200, 48, "Южный столп"),
    (1750, 1150, 240, 185, 58, "Столовая гора"),
    (2750, 690, 210, 170, 52, "Тоннельная меза"),
    (3350, 1550, 200, 150, 34, "Холм Нефтяников"),
    (1350, 2950, 230, 160, 32, "Южная меза"),
]


def mesa_profile(mx, mz, rx, rz, phase):
    """Flat-topped butte factor 0..1 with an irregular, rotated outline."""
    rot = phase * 0.7
    dx0, dz0 = GX - mx, GZ - mz
    dx = dx0 * math.cos(rot) + dz0 * math.sin(rot)
    dz = -dx0 * math.sin(rot) + dz0 * math.cos(rot)
    theta = np.arctan2(dz0, dx0)
    wobble = 1.0 + 0.20 * np.sin(3.0 * theta + phase) + 0.12 * np.sin(7.0 * theta + phase * 2.3)
    d = np.sqrt((dx / rx) ** 2 + (dz / rz) ** 2) / wobble
    return (1.0 - smoothstep(0.50, 1.0, d)) ** 0.8


mesa_field = np.zeros_like(H)
for mi, (mx, mz, rx, rz, top, _name) in enumerate(MESAS):
    mesa_field = np.maximum(mesa_field, top * mesa_profile(mx, mz, rx, rz, 0.9 + mi * 1.37))
H += mesa_field * (0.35 + 0.65 * np.maximum(plateau_mask, smoothstep(1.15, 0.55, np.sqrt(((GX - 1750) / 900.0) ** 2 + ((GZ - 1150) / 700.0) ** 2))))
# isolated buttes outside the plateau keep (most of) their height:
for mi, (mx, mz, rx, rz, top, _name) in enumerate(MESAS):
    if mz > 1000:
        H = np.maximum(H, 32.0 + top * mesa_profile(mx, mz, rx, rz, 0.9 + mi * 1.37))

# SW wind-farm ridge: elongated E-W crest.
ridge_d = np.abs(GZ - 2820.0) / 190.0 + np.maximum(0.0, (np.abs(GX - 700.0) - 430.0)) / 260.0
H += 40.0 * np.clip(1.0 - ridge_d, 0.0, 1.0) ** 1.4

# Dune sea (south band): sharp-crested ridge noise, anisotropic.
dune_mask = smoothstep(2620.0, 2920.0, GZ) * (1.0 - smoothstep(3520.0, 3780.0, GZ))
# fade dunes around the oasis and the wind ridge
oasis_dist = np.hypot(GX - OASIS_CENTRE[0], GZ - OASIS_CENTRE[1])
dune_mask *= smoothstep(320.0, 620.0, oasis_dist)
dune_mask *= 1.0 - 0.85 * np.clip(1.0 - ridge_d, 0.0, 1.0)
wind = math.radians(24.0)
du_m = GX * math.cos(wind) + GZ * math.sin(wind)          # metres across the wind
dune_warp = fbm([6, 12], 917) * 150.0
crest_break = smoothstep(-0.55, 0.35, fbm([5, 9], 31337))
dune_ridge = (1.0 - np.abs(np.sin(math.pi * (du_m + dune_warp) / 175.0))) ** 2.4
dune_ripple = (1.0 - np.abs(np.sin(math.pi * (du_m + dune_warp * 0.5) / 39.0))) ** 1.5
dune_amp = 12.0 + 21.0 * (0.5 + 0.5 * fbm([7], 555))
H += dune_mask * (dune_ridge * dune_amp * (0.30 + 0.70 * crest_break) + dune_ripple * 1.9)

# Salt flat: absolutely flat.
_salt_cx, _salt_cz = 2000.0, 2100.0
_salt_sdf = np.maximum(np.abs(GX - _salt_cx) - 780.0, np.abs(GZ - _salt_cz) - 580.0) + fbm([11], 4711) * 65.0
salt_mask = 1.0 - smoothstep(-30.0, 210.0, _salt_sdf)
H = H * (1.0 - salt_mask) + SALT_Y * salt_mask

# Oasis bowl + lake bed.
oasis_dist_eff = oasis_dist * (1.0 + 0.16 * fbm([8], 6161))
bowl = smoothstep(600.0, 150.0, oasis_dist_eff)
H = H * (1.0 - bowl * 0.85) + (27.6 + fbm([9], 88) * 0.7) * (bowl * 0.85)
lake_bed = smoothstep(LAKE_R + 26.0, LAKE_R - 24.0, oasis_dist)
H = H * (1.0 - lake_bed) + 23.6 * lake_bed

# Quarry pit: terraced benches down to a floor.
q_c = np.array([3300.0, 1000.0])
q_d = np.sqrt(((GX - q_c[0]) / 430.0) ** 2 + ((GZ - q_c[1]) / 390.0) ** 2) * (1.0 + 0.22 * fbm([13], 2718))
q_target = 48.0 + np.clip(q_d - 0.18, 0.0, 1.0) * 40.0
q_target = np.floor(q_target / 6.0) * 6.0 + (q_target - np.floor(q_target / 6.0) * 6.0) * 0.22 + fbm([17], 1414) * 1.6
q_mask = 1.0 - smoothstep(0.92, 1.12, q_d)
H = H * (1.0 - q_mask) + np.maximum(q_target, 48.0) * q_mask

# Canyons: carved polylines with descending floor profiles.
CANYON_A = [(560, 150), (700, 330), (640, 520), (800, 700), (760, 900), (920, 1080), (1040, 1260), (1030, 1440)]
CANYON_B = [(2380, 190), (2520, 380), (2440, 580), (2600, 780), (2540, 980), (2660, 1160), (2640, 1360)]


def carve_canyon(ctrl, floor_top, floor_bottom, half_floor=17.0, wall_run=30.0):
    dense = catmull_rom(ctrl, step=6.0)
    total = float(np.sum(np.linalg.norm(np.diff(dense, axis=0), axis=1)))

    def fn(sub, dist, s):
        floor_h = floor_top + (floor_bottom - floor_top) * np.clip(s / total, 0, 1)
        wall = smoothstep(half_floor, half_floor + wall_run, dist) * 70.0
        carved = floor_h + wall
        return np.minimum(sub, carved)

    polyline_local_op(H, dense, half_floor + wall_run + STEP, fn)
    return dense


print("[desert] carving canyons and wadis ...")
canyon_a_dense = carve_canyon(CANYON_A, 64.0, 36.0)
canyon_b_dense = carve_canyon(CANYON_B, 66.0, 38.0)

# Wadis (dry riverbeds) that the ring highway bridges.
WADI_EAST = [(3050, 1500), (3220, 1900), (3380, 2350), (3560, 2750), (3680, 3100)]
WADI_SOUTH = [(1350, 2720), (1580, 2880), (1820, 2980), (2050, 3120), (2240, 3290), (2400, 3400), (2520, 3560), (2620, 3720)]
# Oasis stream: shallow channel west from the lake.
STREAM = [(2960, 3560), (3100, 3520), (3220, 3505), (3290, 3500)]


def carve_channel(ctrl, depth, half_w, base_drop=0.0):
    dense = catmull_rom(ctrl, step=6.0)

    def fn(sub, dist, s):
        k = 1.0 - smoothstep(half_w * 0.45, half_w, dist)
        return sub - (depth + base_drop) * k

    polyline_local_op(H, dense, half_w + STEP, fn)
    return dense


wadi_east_dense = carve_channel(WADI_EAST, 7.5, 26.0)
wadi_south_dense = carve_channel(WADI_SOUTH, 7.0, 24.0)
stream_dense = carve_channel(STREAM, 2.2, 9.0)

# Light thermal erosion on steep rock (a few relaxation passes).
for _ in range(3):
    avg = 0.25 * (np.roll(H, 1, 0) + np.roll(H, -1, 0) + np.roll(H, 1, 1) + np.roll(H, -1, 1))
    slope = np.abs(H - avg)
    k = np.clip((slope - 1.8) / 6.0, 0.0, 0.35) * (plateau_mask * 0.8 + 0.2)
    H = H * (1.0 - k) + avg * k
# re-assert salt flat + lake after smoothing
H = H * (1.0 - salt_mask) + SALT_Y * salt_mask
H = H * (1.0 - lake_bed) + 23.6 * lake_bed

# ---------------------------------------------------------------- roads
print("[desert] roads: layout + flattening ...")
RING = [
    (1160, 2050), (980, 1620), (920, 1180), (1050, 880), (1500, 770),
    (2050, 730), (2480, 700), (2740, 760), (3050, 780), (3320, 980),
    (3460, 1350), (3500, 1750), (3480, 2150), (3400, 2520), (3220, 2880),
    (2850, 3080), (2350, 3180), (1850, 3140), (1400, 3050), (1000, 2880),
    (830, 2520), (900, 2220),
]
SERPENTINE = [
    (1720, 770), (1560, 640), (1780, 560), (1580, 470), (1820, 420), (1850, 345),
]
QUARRY_RD = [(3320, 980), (3400, 1060), (3300, 1140), (3220, 1180)]
OASIS_RD = [(3220, 2880), (3300, 3150), (3260, 3380), (3310, 3470), (3380, 3560)]
TOWN_MAIN = [(470, 2050), (800, 2050), (1160, 2050)]
TOWN_CROSS1 = [(640, 1900), (640, 2050), (640, 2210)]
TOWN_CROSS2 = [(925, 1880), (925, 2050), (925, 2220)]
TOWN_NORTH = [(520, 1965), (800, 1965), (1100, 1965)]

D_SALT_EW = [(1160, 2100), (1700, 2080), (2300, 2120), (2900, 2200), (3480, 2300)]
D_SALT_NS = [(2640, 1360), (2500, 1700), (2380, 2120), (2420, 2500), (2380, 2880)]
D_CANYON_A = [(560, 150), (700, 330), (640, 520), (800, 700), (760, 900), (920, 1080), (1040, 1260), (1030, 1440), (1000, 1630), (1020, 1820), (1050, 1960)]
D_CANYON_B = [(2380, 190), (2520, 380), (2440, 580), (2600, 780), (2540, 980), (2660, 1160), (2640, 1360)]
D_OIL_LOOP = [(3480, 2150), (3660, 2280), (3720, 2520), (3580, 2700), (3410, 2540), (3400, 2320)]
D_WIND = [(860, 2480), (760, 2680), (700, 2800), (900, 2840), (1100, 2860)]
D_WEST = [(1000, 1630), (760, 1250), (520, 950), (480, 600), (560, 280), (560, 150)]
D_PLATEAU = [(3320, 980), (3000, 720), (2660, 560), (2400, 300), (2380, 190)]
D_QUARRY_PIT = [(3220, 1180), (3060, 1080), (3080, 900), (3260, 800), (3440, 880), (3400, 1060)]
D_OASIS_WEST = [(3380, 3560), (3150, 3520), (2900, 3350), (2700, 3160)]
D_STATION = [(640, 1965), (520, 1680), (420, 1420)]
D_PLATEAU_TOP = [(560, 160), (1150, 260), (1700, 380), (1830, 360), (2150, 280), (2380, 220)]
D_FOOTHILLS = [(1000, 1500), (1450, 1380), (1950, 1420), (2400, 1380), (2640, 1360)]
D_MID = [(430, 1660), (900, 1600), (1500, 1560), (2100, 1500), (2700, 1540), (3200, 1470)]
D_WEST_BORDER = [(560, 300), (430, 800), (400, 1396), (470, 1900), (640, 1965)]
D_EAST_SERVICE = [(3460, 1350), (3820, 1500), (3880, 2000), (3840, 2500), (3560, 2750), (3410, 2540)]
D_OIL_EW1 = [(3160, 2080), (3500, 2120), (3840, 2080)]
D_OIL_EW2 = [(3180, 2620), (3520, 2580), (3820, 2520)]
D_QUARRY_RIM = [(3050, 780), (2950, 1050), (3060, 1250), (3220, 1180)]
D_RIM_A = [(560, 160), (480, 500), (560, 850), (820, 1150), (1000, 1500)]
D_RIM_B = [(2380, 200), (2680, 500), (2720, 850), (2800, 1200), (2750, 1450)]
D_SALT_SOUTH = [(1230, 2640), (2000, 2600), (2770, 2640)]
D_MESA_FOOT = [(1950, 1420), (1830, 1310)]
T_DUNE_1 = [(1100, 2860), (1180, 3120), (1280, 3380), (1350, 3620)]
T_DUNE_2 = [(2380, 2880), (2320, 3150), (2380, 3420), (2300, 3680)]
T_DUNE_3 = [(3220, 2880), (3050, 3150), (2980, 3400), (3100, 3520)]
T_SOUTH_BORDER = [(700, 3550), (1500, 3650), (2300, 3680), (3100, 3600)]
D_RANCH_SPURS = [
    [(1030, 1440), (1250, 1220)],
    [(2050, 730), (2080, 1020)],
    [(3480, 2150), (3180, 1980)],
    [(1400, 3050), (1520, 2900)],
    [(2350, 3180), (2580, 3000)],
    [(1000, 2880), (760, 3020)],
]

ROAD_DEFS = [
    # id, name, control points, width, lanes, surface, closed, speed
    ("ring", "Кольцевое шоссе", RING, 15.0, 4, "asphalt", True, 110),
    ("serpentine", "Серпантин на плато", SERPENTINE, 9.0, 2, "asphalt", False, 60),
    ("quarry_road", "Дорога к карьеру", QUARRY_RD, 10.0, 2, "asphalt", False, 50),
    ("oasis_road", "Дорога к оазису", OASIS_RD, 9.0, 2, "asphalt", False, 70),
    ("town_main", "Главная улица Дюны", TOWN_MAIN, 11.0, 2, "asphalt", False, 40),
    ("town_cross1", "Западный переулок", TOWN_CROSS1, 8.0, 2, "asphalt", False, 40),
    ("town_cross2", "Восточный переулок", TOWN_CROSS2, 8.0, 2, "asphalt", False, 40),
    ("town_north", "Северная улица", TOWN_NORTH, 8.0, 2, "asphalt", False, 40),
    ("dirt_salt_ew", "Солончаковая грунтовка", D_SALT_EW, 7.5, 2, "gravel", False, 80),
    ("dirt_salt_ns", "Грунтовка через солончак", D_SALT_NS, 7.5, 2, "gravel", False, 80),
    ("dirt_canyon_a", "Западный каньон", D_CANYON_A, 8.0, 2, "gravel", False, 60),
    ("dirt_canyon_b", "Восточный каньон", D_CANYON_B, 8.0, 2, "gravel", False, 60),
    ("dirt_oil_loop", "Кольцо нефтяного поля", D_OIL_LOOP, 8.0, 2, "gravel", True, 70),
    ("dirt_wind", "Дорога ветряной фермы", D_WIND, 7.0, 2, "gravel", False, 50),
    ("dirt_west", "Западная тропа", D_WEST, 7.0, 2, "gravel", False, 60),
    ("dirt_plateau", "Плато-восточная грунтовка", D_PLATEAU, 7.5, 2, "gravel", False, 60),
    ("dirt_quarry_pit", "Карьерный круг", D_QUARRY_PIT, 9.0, 2, "gravel", True, 40),
    ("dirt_oasis_west", "Западный путь к оазису", D_OASIS_WEST, 7.0, 2, "gravel", False, 60),
    ("dirt_station", "Дорога к старой станции", D_STATION, 6.5, 2, "gravel", False, 50),
    ("dirt_plateau_top", "Верхняя дорога плато", D_PLATEAU_TOP, 7.0, 2, "gravel", False, 60),
    ("dirt_foothills", "Предгорная грунтовка", D_FOOTHILLS, 7.5, 2, "gravel", False, 70),
    ("dirt_mid", "Срединный траверс", D_MID, 7.5, 2, "gravel", False, 70),
    ("dirt_west_border", "Западная приграничная тропа", D_WEST_BORDER, 6.5, 2, "gravel", False, 50),
    ("dirt_east_service", "Восточная служебная дорога", D_EAST_SERVICE, 7.0, 2, "gravel", False, 60),
    ("dirt_oil_ew1", "Нефтяная широтная I", D_OIL_EW1, 7.0, 2, "gravel", False, 60),
    ("dirt_oil_ew2", "Нефтяная широтная II", D_OIL_EW2, 7.0, 2, "gravel", False, 60),
    ("dirt_quarry_rim", "Западный борт карьера", D_QUARRY_RIM, 7.0, 2, "gravel", False, 40),
    ("dirt_rim_a", "Бровка Западного каньона", D_RIM_A, 6.5, 2, "gravel", False, 50),
    ("dirt_rim_b", "Бровка Восточного каньона", D_RIM_B, 6.5, 2, "gravel", False, 50),
    ("dirt_salt_south", "Южный край солончака", D_SALT_SOUTH, 7.0, 2, "gravel", False, 70),
    ("dirt_mesa_foot", "К Столовой горе", D_MESA_FOOT, 6.0, 2, "gravel", False, 40),
    ("trail_dune_1", "Дюнная тропа Запад", T_DUNE_1, 6.0, 2, "gravel", False, 60),
    ("trail_dune_2", "Дюнная тропа Центр", T_DUNE_2, 6.0, 2, "gravel", False, 60),
    ("trail_dune_3", "Дюнная тропа Восток", T_DUNE_3, 6.0, 2, "gravel", False, 60),
    ("trail_wadi_east", "Русло Восточного оуэда", WADI_EAST, 6.5, 2, "gravel", False, 60),
    ("trail_wadi_south", "Русло Южного оуэда", WADI_SOUTH, 6.5, 2, "gravel", False, 60),
    ("trail_south_border", "Южная приграничная тропа", T_SOUTH_BORDER, 6.5, 2, "gravel", False, 60),
]
ROAD_DEFS += [
    ("dirt_graveyard", "К кладбищу машин", [(925, 2220), (945, 2350), (962, 2452)], 6.0, 2, "gravel", False, 40),
    ("dirt_plane", "К самолёту-развалине", [(2920, 1510), (2952, 1576)], 5.5, 2, "gravel", False, 40),
    ("dirt_oasis_south", "Южный берег оазиса", [(3380, 3560), (3320, 3660), (3100, 3600)], 6.0, 2, "gravel", False, 40),
]
for i, spur in enumerate(D_RANCH_SPURS):
    ROAD_DEFS.append((f"dirt_ranch_{i}", f"Подъезд к ранчо {i+1}", spur, 6.0, 2, "gravel", False, 40))

roads_dense = {}
for (rid, _name, ctrl, _w, _lanes, _surf, closed, _spd) in ROAD_DEFS:
    roads_dense[rid] = catmull_rom(ctrl, closed=closed, step=5.0)

# Bridge spans: (road_id, centre point approx, half-length m).  The deck
# profile is kept from the smoothed road profile; terrain there is NOT
# flattened (the wadi bed stays below).
BRIDGES = [
    ("ring", np.array([3435.0, 2430.0]), 46.0),
    ("ring", np.array([2110.0, 3165.0]), 42.0),
    ("oasis_road", np.array([3300.0, 3495.0]), 20.0),
]
TUNNEL = ("ring", np.array([2740.0, 755.0]), 55.0)  # half-length


def road_profile(dense, max_grade, closed, follow=False):
    """Smooth, grade-limited target heights along a road centreline."""
    hs = np.array([bilinear(H, p[0], p[1]) for p in dense])
    # wide smoothing (two box passes); trails mostly follow the terrain
    for win in ((9,) if follow else (61, 31)):
        k = np.ones(win) / win
        if closed:
            ext = np.concatenate([hs[-win:], hs, hs[:win]])
            hs = np.convolve(ext, k, mode="same")[win:-win]
        else:
            hs = np.convolve(np.pad(hs, win // 2, mode="edge"), k, mode="valid")
    ds = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    for _ in range(3):
        for i in range(len(ds)):
            lim = max_grade * max(ds[i], 0.5)
            d = hs[i + 1] - hs[i]
            if d > lim:
                hs[i + 1] = hs[i] + lim
            elif d < -lim:
                hs[i + 1] = hs[i] - lim
        for i in range(len(ds) - 1, -1, -1):
            lim = max_grade * max(ds[i], 0.5)
            d = hs[i] - hs[i + 1]
            if d > lim:
                hs[i] = hs[i + 1] + lim
            elif d < -lim:
                hs[i] = hs[i + 1] - lim
    return hs


road_profiles = {}
bridge_s_ranges = {}   # road_id -> list of (s0, s1)
tunnel_s_range = None

for (rid, _name, _ctrl, width, _lanes, surf, closed, _spd) in ROAD_DEFS:
    dense = roads_dense[rid]
    follow = rid.startswith("trail_")
    max_grade = 0.075 if surf == "asphalt" else (0.24 if follow else 0.11)
    prof = road_profile(dense, max_grade, closed, follow=follow)
    road_profiles[rid] = prof
    seg_lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_cum = np.concatenate([[0.0], np.cumsum(seg_lens)])

    skip_ranges = []
    for (brid, centre, half_len) in BRIDGES:
        if brid != rid:
            continue
        d = np.linalg.norm(dense - centre, axis=1)
        s0 = float(s_cum[int(np.argmin(d))])
        skip_ranges.append((s0 - half_len, s0 + half_len))
    if skip_ranges:
        bridge_s_ranges[rid] = skip_ranges
    if TUNNEL[0] == rid:
        d = np.linalg.norm(dense - TUNNEL[1], axis=1)
        s0 = float(s_cum[int(np.argmin(d))])
        tunnel_s_range = (s0 - TUNNEL[2], s0 + TUNNEL[2])

    half_w = width * 0.5
    falloff = 8.0 if follow else 16.0

    def make_fn(prof=prof, dense=dense, s_cum=s_cum, half_w=half_w,
                falloff=falloff, skip_ranges=skip_ranges):
        def fn(sub, dist, s):
            target_h = np.interp(s, s_cum, prof)
            w = 1.0 - smoothstep(half_w + 1.5, half_w + falloff, dist)
            for (a, b) in skip_ranges:
                w = np.where((s > a) & (s < b), 0.0, w)
            return sub * (1.0 - w) + target_h * w
        return fn

    _polyline_local_op_s(H, dense, half_w + falloff + STEP, make_fn(), s_cum)

# Final road samples (~14 m) with heights: terrain after flattening,
# except bridge spans which follow the deck profile.
roads_out = []
road_samples_by_id = {}
for (rid, name, _ctrl, width, lanes, surf, closed, spd) in ROAD_DEFS:
    dense = roads_dense[rid]
    samples_pts = resample_even(dense, 14.0)
    seg_lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_cum = np.concatenate([[0.0], np.cumsum(seg_lens)])
    prof = road_profiles[rid]
    samples = []
    for p in samples_pts:
        d = np.linalg.norm(dense - p, axis=1)
        s_here = float(s_cum[int(np.argmin(d))])
        y = bilinear(H, p[0], p[1])
        for (a, b) in bridge_s_ranges.get(rid, []):
            if a <= s_here <= b:
                y = float(np.interp(s_here, s_cum, prof))
        samples.append([round(float(p[0]), 2), round(float(y), 3), round(float(p[1]), 2)])
    road_samples_by_id[rid] = samples
    roads_out.append({
        "id": "dz-" + rid, "name": name, "widthM": width, "lanes": lanes,
        "speedLimitKmh": spd, "surface": surf, "closed": bool(closed),
        "samples": samples,
    })

road_length_total = 0.0
for r in roads_out:
    pts = np.array([[s[0], s[2]] for s in r["samples"]])
    road_length_total += float(np.sum(np.linalg.norm(np.diff(pts, axis=0), axis=1)))
print(f"[desert] roads total length: {road_length_total/1000.0:.1f} km")

# Road-distance raster (capped 260 m) for scatter + gap analysis.
print("[desert] road distance raster ...")
road_dist = np.full((N, N), 260.0)
for rid, dense in roads_dense.items():
    def d_fn(sub, dist, s, _w=0.0):
        return np.minimum(sub, dist)
    polyline_local_op(road_dist, dense, 260.0, d_fn)

# slope raster
gy, gx = np.gradient(H, STEP)
slope_grid = np.hypot(gx, gy)


def height_at(x, z):
    return bilinear(H, x, z)


def slope_at(x, z):
    return bilinear(slope_grid, x, z)


def road_dist_at(x, z):
    return bilinear(road_dist, x, z)


def zone_of(x, z):
    if in_rect(x, z, TOWN_RECT):
        return "town"
    if in_rect(x, z, SALT_RECT) and height_at(x, z) < 35.2:
        return "salt"
    if in_rect(x, z, QUARRY_RECT) and np.hypot((x - 3300) / 430.0, (z - 1000) / 390.0) < 1.25:
        return "quarry"
    d_oasis = math.hypot(x - OASIS_CENTRE[0], z - OASIS_CENTRE[1])
    if d_oasis < 580.0:
        return "oasis"
    if in_rect(x, z, OIL_RECT):
        return "oil"
    if 150.0 < x < 1300.0 and 2500.0 < z < 3120.0:
        return "wind"
    if z < 1250.0:
        return "canyon"
    if z > 2780.0:
        return "dunes"
    return "desert"


# ---------------------------------------------------------------- scatter
print("[desert] scatter placement ...")
# cumulative lengths of every road for along-road sampling
road_pick = []
for rid, dense in roads_dense.items():
    lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    road_pick.append((rid, dense, np.concatenate([[0.0], np.cumsum(lens)])))
road_pick_total = sum(float(c[-1]) for _r, _d, c in road_pick)


def random_road_point():
    pick = rng.random() * road_pick_total
    for _rid, dense, cum in road_pick:
        if pick <= cum[-1]:
            i = int(np.searchsorted(cum, pick))
            i = min(max(i, 1), len(dense) - 1)
            a, b = dense[i - 1], dense[i]
            t = 0.0 if cum[i] == cum[i - 1] else (pick - cum[i - 1]) / (cum[i] - cum[i - 1])
            p = a + (b - a) * t
            d = b - a
            n = np.linalg.norm(d)
            perp = np.array([-d[1], d[0]]) / n if n > 1e-6 else np.array([1.0, 0.0])
            return p, perp
    p = road_pick[0][1][0]
    return p, np.array([1.0, 0.0])


def scatter(count, accept, along_ratio=0.7, min_road_dist=7.0, max_attempts_factor=30):
    out = []
    attempts = 0
    max_attempts = count * max_attempts_factor
    while len(out) < count and attempts < max_attempts:
        attempts += 1
        if rng.random() < along_ratio:
            p, perp = random_road_point()
            off = (min_road_dist + float(rng.exponential(55.0))) * (1 if rng.random() < 0.5 else -1)
            off = float(np.clip(off, -150.0, 150.0))
            x, z = float(p[0] + perp[0] * off), float(p[1] + perp[1] * off)
        else:
            x, z = float(rng.random() * SIZE), float(rng.random() * SIZE)
        if not (30.0 < x < SIZE - 30.0 and 30.0 < z < SIZE - 30.0):
            continue
        if road_dist_at(x, z) < min_road_dist:
            continue
        if accept(x, z):
            out.append((x, z))
    return out


def mk_instances(points, smin, smax):
    return [[round(x, 1), round(z, 1), round(float(rng.uniform(smin, smax)), 2),
             round(float(rng.random() * math.tau), 2)] for (x, z) in points]


def not_in_water_or_town_core(x, z):
    if math.hypot(x - OASIS_CENTRE[0], z - OASIS_CENTRE[1]) < LAKE_R + 6.0:
        return False
    return True


scatter_data = {}

def cactus_ok(x, z):
    zn = zone_of(x, z)
    if zn in ("salt", "town", "quarry"):
        return False
    if zn == "dunes" and rng.random() > 0.06:
        return False
    if zn == "oasis":
        return False
    return slope_at(x, z) < 0.38 and not_in_water_or_town_core(x, z)


cacti = scatter(6000, cactus_ok)
n1 = int(len(cacti) * 0.50)
n2 = int(len(cacti) * 0.35)
scatter_data["cactus_saguaro"] = mk_instances(cacti[:n1], 0.8, 1.5)
scatter_data["cactus_barrel"] = mk_instances(cacti[n1:n1 + n2], 0.7, 1.4)
scatter_data["cactus_prickly"] = mk_instances(cacti[n1 + n2:], 0.7, 1.3)


def shrub_ok(x, z):
    zn = zone_of(x, z)
    if zn == "salt":
        return rng.random() < 0.02
    if zn == "town":
        return rng.random() < 0.25
    if zn == "dunes":
        return rng.random() < 0.18
    return slope_at(x, z) < 0.55 and not_in_water_or_town_core(x, z)


scatter_data["shrub"] = mk_instances(scatter(12000, shrub_ok, min_road_dist=5.0), 0.6, 1.6)


def rock_weighted_ok_factory(max_slope):
    def ok(x, z):
        zn = zone_of(x, z)
        if zn == "salt":
            return False
        if zn == "dunes":
            return rng.random() < 0.06
        if zn == "town":
            return rng.random() < 0.06
        s = slope_at(x, z)
        rocky = 0.22 + min(s, 1.2) * 0.85 + max(0.0, height_at(x, z) - 60.0) / 150.0
        if zn == "oil":
            rocky *= 0.45
        elif zn == "wind":
            rocky *= 0.30
        elif zn == "canyon":
            rocky *= 0.50
        elif zn == "oasis":
            rocky *= 0.4
        return rng.random() < rocky and s < max_slope and not_in_water_or_town_core(x, z)
    return ok


scatter_data["rock_small"] = mk_instances(
    scatter(15000, rock_weighted_ok_factory(1.4), min_road_dist=4.5), 0.5, 1.6)
scatter_data["rock_medium"] = mk_instances(
    scatter(2500, rock_weighted_ok_factory(1.1), min_road_dist=6.0), 0.7, 1.8)
scatter_data["rock_large"] = mk_instances(
    scatter(300, rock_weighted_ok_factory(0.9), min_road_dist=9.0), 0.8, 2.0)


def dead_tree_ok(x, z):
    zn = zone_of(x, z)
    if zn in ("salt", "town", "quarry", "oasis"):
        return False
    if zn == "dunes":
        return rng.random() < 0.15
    if zn == "wind":
        return rng.random() < 0.30
    return slope_at(x, z) < 0.4 and not_in_water_or_town_core(x, z)


scatter_data["dead_tree"] = mk_instances(scatter(400, dead_tree_ok), 0.8, 1.5)
scatter_data["bones"] = mk_instances(
    scatter(200, lambda x, z: zone_of(x, z) not in ("town",) and not_in_water_or_town_core(x, z),
            min_road_dist=6.0), 0.8, 1.3)
scatter_data["tumbleweed"] = mk_instances(
    scatter(150, lambda x, z: slope_at(x, z) < 0.25 and zone_of(x, z) in ("desert", "salt", "oil", "dunes"),
            min_road_dist=5.0), 0.8, 1.4)

# Oasis palms + reeds
palms = []
tries = 0
while len(palms) < 250 and tries < 20000:
    tries += 1
    ang = rng.random() * math.tau
    r = LAKE_R + 14.0 + float(rng.exponential(85.0))
    if r > 330.0:
        continue
    x = float(OASIS_CENTRE[0] + math.cos(ang) * r)
    z = float(OASIS_CENTRE[1] + math.sin(ang) * r)
    if road_dist_at(x, z) < 8.0 or slope_at(x, z) > 0.4:
        continue
    palms.append((x, z))
scatter_data["oasis_palm"] = mk_instances(palms, 0.85, 1.25)

reeds = []
tries = 0
while len(reeds) < 600 and tries < 30000:
    tries += 1
    ang = rng.random() * math.tau
    r = LAKE_R + float(rng.uniform(-2.0, 16.0))
    x = float(OASIS_CENTRE[0] + math.cos(ang) * r)
    z = float(OASIS_CENTRE[1] + math.sin(ang) * r)
    reeds.append((x, z))
scatter_data["oasis_reed"] = mk_instances(reeds, 0.7, 1.4)

# Quarry gravel piles
piles = []
tries = 0
while len(piles) < 40 and tries < 8000:
    tries += 1
    ang = rng.random() * math.tau
    rr = float(rng.uniform(40.0, 330.0))
    x = 3300.0 + math.cos(ang) * rr
    z = 1000.0 + math.sin(ang) * rr * 0.9
    if road_dist_at(x, z) < 13.0:
        continue
    piles.append((x, z))
scatter_data["gravel_pile"] = mk_instances(piles, 0.8, 2.2)

print("[desert] scatter totals:", {k: len(v) for k, v in scatter_data.items()})

# ---------------------------------------------------------------- structures
print("[desert] structures ...")
structures = []   # {kind,x,z,yaw,w,d,h, name?} ; linear kinds add x2,z2
buildings = []    # minimap/POI-compatible subset


def add_structure(kind, x, z, yaw=0.0, w=6.0, d=6.0, h=4.0, name="", building=True, x2=None, z2=None):
    s = {"kind": kind, "x": round(float(x), 1), "z": round(float(z), 1),
         "yaw": round(float(yaw), 3), "w": w, "d": d, "h": h}
    if name:
        s["name"] = name
    if x2 is not None:
        s["x2"] = round(float(x2), 1)
        s["z2"] = round(float(z2), 1)
    structures.append(s)
    if building:
        buildings.append({"x": s["x"], "z": s["z"], "rotY": s["yaw"], "w": w, "d": d,
                          "h": h, "kind": "dz-" + kind})
    return s


# --- Town "Дюны"
add_structure("gas_station", 520, 2092, 0.0, 18, 12, 5, "Заправка «Дюны»")
add_structure("garage", 604, 2094, 0.0, 20, 13, 5.5, "Гараж «Дюны»")
add_structure("motel", 566, 2012, math.pi, 30, 12, 7, "Мотель «Мираж»")
add_structure("diner", 648, 2014, math.pi, 17, 10, 4.2, "Закусочная «Кактус»")
add_structure("warehouse", 982, 2010, math.pi, 26, 15, 6.5, "Склад")
add_structure("warehouse", 1075, 2092, 0.0, 22, 13, 6.0, "")
add_structure("church", 1082, 2014, math.pi, 12, 19, 8.5, "Церквушка")
add_structure("water_tower", 862, 1982, 0.0, 7, 7, 21, "Водокачка")
house_spots = [
    (726, 2014, math.pi), (806, 2014, math.pi), (886, 2014, math.pi),
    (706, 2092, 0.0), (1004, 2092, 0.0),
    (622, 1932, math.pi / 2), (622, 1978, math.pi / 2), (660, 2148, math.pi / 2),
    (660, 2192, math.pi / 2), (907, 1930, -math.pi / 2), (907, 1976, -math.pi / 2),
    (945, 2146, -math.pi / 2), (945, 2192, -math.pi / 2),
    (560, 1944, math.pi), (760, 1944, math.pi), (1020, 1944, math.pi),
    (740, 2170, 0.0),
]
for (hx, hz, hyaw) in house_spots:
    add_structure("house", hx, hz, hyaw, float(rng.uniform(9, 12)), float(rng.uniform(8, 10)),
                  float(rng.uniform(3.6, 6.2)))
# fairground stalls on the plaza (x 700..880, z 2100..2210)
for i in range(12):
    add_structure("stall", 712 + (i % 6) * 30, 2122 + (i // 6) * 46,
                  float(rng.uniform(-0.2, 0.2)), 5, 4, 3.2, building=False)
add_structure("stage", 790, 2196, math.pi, 16, 8, 5, building=False)
# town small props: fences, crates, barrels, tanks (~200 notable objects)
for i in range(70):
    fx = float(rng.uniform(470, 1150))
    fz = float(rng.choice([rng.uniform(1920, 1995), rng.uniform(2115, 2225)]))
    if road_dist_at(fx, fz) < 5.0:
        continue
    add_structure("fence", fx, fz, float(rng.choice([0.0, math.pi / 2])),
                  float(rng.uniform(6, 14)), 0.3, 1.1, building=False)
for i in range(80):
    fx = float(rng.uniform(480, 1140))
    fz = float(rng.choice([rng.uniform(1990, 2035), rng.uniform(2070, 2115),
                            rng.uniform(1925, 1960), rng.uniform(2135, 2215)]))
    if road_dist_at(fx, fz) < 4.5:
        continue
    add_structure(str(rng.choice(["crate", "barrel_group", "tank_small"])), fx, fz,
                  float(rng.random() * math.pi), 1.6, 1.6, 1.2, building=False)
for i in range(26):
    add_structure("town_pole", 490 + i * 26, 2036 if i % 2 == 0 else 2064, 0.0, 0.4, 0.4, 7.5, building=False)

# --- Quarry
add_structure("crusher", 3250, 1185, 0.3, 12, 12, 17, "Бетонный завод")
for i in range(3):
    add_structure("silo", 3284 + i * 13, 1196, 0.0, 7, 7, 13)
add_structure("office", 3200, 1210, -0.2, 15, 8, 4)
add_structure("conveyor", 3250, 1185, 0.0, 2.2, 2.2, 6, building=False, x2=3150, z2=1080)
machines = [("excavator", 3120, 1020, 0.7), ("excavator", 3380, 950, -0.4), ("excavator", 3240, 860, 2.1),
            ("dumptruck", 3180, 1120, 1.2), ("dumptruck", 3340, 1040, -1.0), ("dumptruck", 3100, 930, 0.2),
            ("loader", 3290, 1130, 2.8), ("loader", 3420, 1100, -2.2)]
for (mk, mx, mz, myaw) in machines:
    add_structure(mk, mx, mz, myaw, 9, 4, 4.5, building=False)
for i in range(10):
    add_structure("container", 3170 + (i % 5) * 8.5, 1232 + (i // 5) * 5, 0.05, 6, 2.6, 2.6, building=False)

# --- Oil field
pumpjacks = []
tries = 0
while len(pumpjacks) < 25 and tries < 6000:
    tries += 1
    x = float(rng.uniform(3120, 3880))
    z = float(rng.uniform(1880, 2740))
    if road_dist_at(x, z) < 20.0 or slope_at(x, z) > 0.3:
        continue
    if any(math.hypot(x - px, z - pz) < 85.0 for (px, pz) in pumpjacks):
        continue
    pumpjacks.append((x, z))
for (px, pz) in pumpjacks:
    add_structure("pumpjack", px, pz, float(rng.random() * math.tau), 11, 3.5, 6, building=False)
    if rng.random() < 0.42:
        add_structure("shed", px + float(rng.uniform(-14, 14)), pz + float(rng.uniform(-14, 14)),
                      float(rng.random() * math.pi), 5, 4, 3)
for i in range(8):
    add_structure("oil_tank", 3560 + (i % 4) * 17, 2340 + (i // 4) * 17, 0.0, 12, 12, 7)
add_structure("flare", 3725, 2035, 0.0, 3, 3, 26, "Факел нефтяного поля")
pipes = []
for _pipe_rid in ("dirt_oil_ew1", "dirt_oil_ew2"):
    _pd = roads_dense[_pipe_rid]
    for i in range(0, len(_pd) - 8, 8):
        a, b = _pd[i], _pd[i + 8]
        d = b - a
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        perp = np.array([-d[1], d[0]]) / n * -6.0
        pipes.append([round(float(a[0] + perp[0]), 1), round(float(a[1] + perp[1]), 1),
                      round(float(b[0] + perp[0]), 1), round(float(b[1] + perp[1]), 1)])
oil_dense = roads_dense["dirt_oil_loop"]
for i in range(0, len(oil_dense) - 8, 8):
    a, b = oil_dense[i], oil_dense[i + 8]
    d = b - a
    n = np.linalg.norm(d)
    if n < 1e-6:
        continue
    perp = np.array([-d[1], d[0]]) / n * 7.0
    pipes.append([round(float(a[0] + perp[0]), 1), round(float(a[1] + perp[1]), 1),
                  round(float(b[0] + perp[0]), 1), round(float(b[1] + perp[1]), 1)])

# --- Wind farm
turbines = []
for i in range(14):
    tx = 300.0 + i * 58.0 + float(rng.uniform(-9, 9))
    tz = 2800.0 + math.sin(i * 0.55) * 38.0 + float(rng.uniform(-8, 8))
    turbines.append((tx, tz))
    add_structure("wind_turbine", tx, tz, float(rng.uniform(-0.4, 0.4)), 4, 4, 42, building=False)
add_structure("viewpoint", 1120, 2868, 2.6, 10, 8, 3.2, "Обзорная точка ветряков")

# --- Landmark structures
add_structure("radio_tower", 1850, 322, 0.0, 12, 12, 62, "Радиовышка")
arch_pt = canyon_a_dense[int(len(canyon_a_dense) * 0.46)]
arch_dir = canyon_a_dense[int(len(canyon_a_dense) * 0.46) + 4] - arch_pt
add_structure("stone_arch", float(arch_pt[0]), float(arch_pt[1]),
              math.atan2(float(arch_dir[0]), float(arch_dir[1])), 44, 7, 16, "Каменная арка", building=False)
add_structure("plane_wreck", 2952, 1576, 0.7, 34, 30, 6, "Самолёт-развалина")
add_structure("station_ruin", 392, 1396, 0.12, 20, 9, 5.5, "Старая станция")
add_structure("rail_stub", 404, 1280, 0.0, 3, 260, 0.4, building=False, x2=404, z2=1540)
add_structure("station_sign", 420, 1410, 1.2, 4, 0.3, 3.4, building=False)

# car graveyard + scattered wrecks (static rusty shells — decor per spec's
# "заброшенное"; the game ships no AI/parked traffic by owner's rule)
wrecks = []
for r in range(4):
    for c in range(6):
        wx = 940.0 + c * 7.5 + float(rng.uniform(-1.2, 1.2))
        wz = 2452.0 + r * 9.0 + float(rng.uniform(-1.2, 1.2))
        wrecks.append((wx, wz))
for i in range(36):
    p, perp = random_road_point()
    off = float(rng.uniform(14, 90)) * (1 if rng.random() < 0.5 else -1)
    wx, wz = float(p[0] + perp[0] * off), float(p[1] + perp[1] * off)
    if 40 < wx < SIZE - 40 and 40 < wz < SIZE - 40 and slope_at(wx, wz) < 0.4:
        wrecks.append((wx, wz))
for (wx, wz) in wrecks:
    add_structure("car_wreck", wx, wz, float(rng.random() * math.tau), 4.4, 1.9, 1.5, building=False)
for i in range(6):
    add_structure("container", 928 + i * 3.2, 2440, 0.03 * i, 6, 2.6, 2.6, building=False)

# ranches (6)
RANCHES = [(1270, 1205), (2100, 1045), (3160, 1960), (1540, 2875), (2600, 2975), (740, 3045)]
for i, (rx, rz) in enumerate(RANCHES):
    add_structure("ranch_house", rx, rz, float(rng.random() * math.pi), 11, 9, 4.5, f"Ранчо {i+1}")
    add_structure("barn", rx + 16, rz + 7, float(rng.random() * math.pi), 13, 8, 5.5)
    add_structure("windmill", rx - 13, rz + 10, 0.0, 3, 3, 11, building=False)
    add_structure("ranch_tank", rx + 6, rz - 12, 0.0, 4, 4, 4.5, building=False)
    add_structure("fence", rx, rz - 18, 0.0, 44, 0.3, 1.1, building=False)
    add_structure("fence", rx, rz + 18, 0.0, 44, 0.3, 1.1, building=False)

# Salt-flat furniture (Bonneville vibe): drag markers + crossing poles
for (mx, mz) in [(1500, 2268), (1500, 2292), (2300, 2268), (2300, 2292),
                 (1500, 2408), (1500, 2432), (2300, 2408), (2300, 2432)]:
    add_structure("salt_gate", mx, mz, 0.0, 0.4, 0.4, 3.4, building=False)
for (mx, mz) in [(1400, 2128), (1850, 2072), (2300, 2148), (2620, 2090),
                 (2100, 1680), (2500, 1600), (1600, 2560), (2350, 2520)]:
    add_structure("salt_marker", mx, mz, float(rng.random() * math.pi), 0.35, 0.35, 2.6, building=False)
add_structure("salt_pylon", 2000, 2350, 0.4, 2.2, 2.2, 9.0, "Соляной обелиск", building=False)
add_structure("tent", 1652, 1622, 0.7, 5, 4, 2.8, building=False)
add_structure("tank_small", 1662, 1628, 0.0, 1.8, 1.8, 2.2, building=False)

# Oasis houses + pier
oasis_houses = 0
tries = 0
while oasis_houses < 15 and tries < 6000:
    tries += 1
    ang = float(rng.uniform(-0.9, 1.9))  # east/south shore bias
    r = float(rng.uniform(120.0, 250.0))
    x = float(OASIS_CENTRE[0] + math.cos(ang) * r)
    z = float(OASIS_CENTRE[1] + math.sin(ang) * r)
    if road_dist_at(x, z) < 12.0:
        continue
    add_structure("oasis_house", x, z, ang + math.pi / 2, float(rng.uniform(8, 12)),
                  float(rng.uniform(7, 10)), float(rng.uniform(3.2, 5.0)))
    oasis_houses += 1
add_structure("pier", 3285, 3462, -0.5, 18, 3.2, 1.0, "Пирс оазиса", building=False)

# Roadside stops on the ring (4) + town gas already placed = 5 per spec
for (sx, sz, syaw, sname) in [
        (1690, 820, 2.8, "Придорожное кафе «Север»"), (3535, 2090, -1.4, "Заправка «Восток»"),
        (2620, 3115, 0.4, "Кафе «Юг»"), (900, 1020, 1.1, "Заправка «Каньон»")]:
    add_structure("roadstop", sx, sz, syaw, 16, 11, 4.6, sname)

# --- Along-road infrastructure from the ring polyline
ring_dense = roads_dense["ring"]
ring_lens = np.linalg.norm(np.diff(ring_dense, axis=0), axis=1)
ring_cum = np.concatenate([[0.0], np.cumsum(ring_lens)])


def walk_polyline(dense, cum, spacing, offset, jitter=0.0):
    out = []
    s = spacing * 0.5
    while s < cum[-1]:
        i = int(np.searchsorted(cum, s))
        i = min(max(i, 1), len(dense) - 1)
        a, b = dense[i - 1], dense[i]
        t = 0.0 if cum[i] == cum[i - 1] else (s - cum[i - 1]) / (cum[i] - cum[i - 1])
        p = a + (b - a) * t
        d = b - a
        n = np.linalg.norm(d)
        perp = np.array([-d[1], d[0]]) / n if n > 1e-6 else np.array([1.0, 0.0])
        side = 1.0
        q = p + perp * offset * side
        yaw = math.atan2(float(d[0]), float(d[1]))
        out.append((float(q[0]), float(q[1]), yaw, float(p[0]), float(p[1]), s))
        s += spacing * float(rng.uniform(1.0 - jitter, 1.0 + jitter))
    return out


poles = walk_polyline(ring_dense, ring_cum, 54.0, 11.0, jitter=0.08)
for (px, pz, pyaw, _cx, _cz, _s) in poles:
    if tunnel_s_range and _s and tunnel_s_range[0] - 20 < _s < tunnel_s_range[1] + 20:
        continue
    add_structure("power_pole", px, pz, pyaw, 0.5, 0.5, 11.5, building=False)
pole_points = [[round(s["x"], 1), round(s["z"], 1)] for s in structures if s["kind"] == "power_pole"]

billboards = walk_polyline(ring_dense, ring_cum, 585.0, 15.0, jitter=0.25)
for (bx, bz, byaw, _cx, _cz, _s) in billboards[:20]:
    add_structure("billboard", bx, bz, byaw + math.pi / 2, 11, 0.6, 7.5, building=False)

# signs along all roads ~150
signs = []
for rid, dense in roads_dense.items():
    lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(lens)])
    for (sx, sz, syaw, _cx, _cz, _s) in walk_polyline(dense, cum, 340.0, 6.8, jitter=0.4):
        signs.append((sx, sz, syaw))
rng.shuffle(signs)
signs = signs[:150]
smash_idx = set(int(v) for v in rng.choice(len(signs), size=min(15, len(signs)), replace=False))
smash_signs = []
for i, (sx, sz, syaw) in enumerate(signs):
    kind = "sign_smash" if i in smash_idx else "sign"
    add_structure(kind, sx, sz, syaw, 1.1, 0.25, 2.9, building=False)
    if i in smash_idx:
        smash_signs.append([round(sx, 1), round(sz, 1)])

# guardrail sections: high-curvature ring stretches + bridges + serpentine
guardrails = []


def add_guardrails(dense, cum, s_ranges, offset=9.2, section=12.0):
    for (a_s, b_s) in s_ranges:
        s = a_s
        while s < b_s:
            pts = []
            for ss in (s, s + section):
                i = int(np.searchsorted(cum, ss))
                i = min(max(i, 1), len(dense) - 1)
                a, b = dense[i - 1], dense[i]
                t = 0.0 if cum[i] == cum[i - 1] else (ss - cum[i - 1]) / (cum[i] - cum[i - 1])
                p = a + (b - a) * t
                d = b - a
                n = np.linalg.norm(d)
                perp = np.array([-d[1], d[0]]) / n if n > 1e-6 else np.array([1.0, 0.0])
                pts.append(p + perp * offset)
            guardrails.append([round(float(pts[0][0]), 1), round(float(pts[0][1]), 1),
                               round(float(pts[1][0]), 1), round(float(pts[1][1]), 1)])
            s += section


# curvature-based ranges on the ring
curv_ranges = []
in_range = None
for i in range(10, len(ring_dense) - 10):
    v1 = ring_dense[i] - ring_dense[i - 10]
    v2 = ring_dense[i + 10] - ring_dense[i]
    a1 = math.atan2(v1[1], v1[0])
    a2 = math.atan2(v2[1], v2[0])
    da = abs((a2 - a1 + math.pi) % (2 * math.pi) - math.pi)
    if da > 0.16 and in_range is None:
        in_range = ring_cum[i]
    elif da <= 0.16 and in_range is not None:
        if ring_cum[i] - in_range > 40.0:
            curv_ranges.append((float(in_range), float(ring_cum[i])))
        in_range = None
add_guardrails(ring_dense, ring_cum, curv_ranges)
for (a, b) in bridge_s_ranges.get("ring", []):
    add_guardrails(ring_dense, ring_cum, [(a - 14, b + 14)], offset=8.0)
    add_guardrails(ring_dense, ring_cum, [(a - 14, b + 14)], offset=-8.0)
serp_dense = roads_dense["serpentine"]
serp_lens = np.linalg.norm(np.diff(serp_dense, axis=0), axis=1)
serp_cum = np.concatenate([[0.0], np.cumsum(serp_lens)])
add_guardrails(serp_dense, serp_cum, [(80.0, float(serp_cum[-1] - 60.0))], offset=6.4)

print(f"[desert] structures: {len(structures)} (poles {len(pole_points)}, "
      f"guardrail sections {len(guardrails)}, pipe segments {len(pipes)})")

# ---------------------------------------------------------------- game content
print("[desert] game content ...")


def route_points(road_ids, step=25.0):
    pts = []
    for rid in road_ids:
        for s in road_samples_by_id[rid]:
            pts.append([s[0], s[2]])
    # dedupe close points
    out = []
    for p in pts:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 6.0:
            out.append(p)
    return out


def route_length(pts):
    return round(float(sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
                             for i in range(len(pts) - 1))), 1)


circuits = []
for (cid, cname, rids) in [
        ("circuit_canyon", "Каньон", ["dirt_canyon_a", "dirt_west"]),
        ("circuit_quarry", "Карьер", ["quarry_road", "dirt_quarry_pit"]),
        ("circuit_oil", "Нефтяное поле", ["dirt_oil_loop"]),
        ("circuit_town", "Городок Дюны", ["town_main", "town_cross2", "town_north", "town_cross1"])]:
    pts = route_points(rids)
    circuits.append({"id": cid, "name": cname, "points": pts, "lengthM": route_length(pts),
                     "start": pts[0] if pts else [0, 0]})

sprints = []
for (sid, sname, rid, frac) in [
        ("sprint_highway", "Шоссе", "ring", (0.30, 0.475)),
        ("sprint_salt", "Солончак", "dirt_salt_ew", (0.05, 0.95)),
        ("sprint_serpentine", "Серпантин", "serpentine", (0.0, 1.0))]:
    all_pts = road_samples_by_id[rid]
    a = int(len(all_pts) * frac[0])
    b = max(a + 2, int(len(all_pts) * frac[1]))
    pts = [[s[0], s[2]] for s in all_pts[a:b]]
    sprints.append({"id": sid, "name": sname, "points": pts, "lengthM": route_length(pts),
                    "start": pts[0], "finish": pts[-1]})

drags = [
    {"id": "drag_salt_1", "name": "Драг Солончак-800 A", "start": [1500.0, 2280.0], "finish": [2300.0, 2280.0], "lengthM": 800.0},
    {"id": "drag_salt_2", "name": "Драг Солончак-800 B", "start": [1500, 2420.0], "finish": [2300.0, 2420.0], "lengthM": 800.0},
]

jumps = [
    {"name": "Прыжок карьера I", "x": 3140.0, "z": 990.0, "yaw": 0.8},
    {"name": "Прыжок карьера II", "x": 3385.0, "z": 1010.0, "yaw": -2.2},
    {"name": "Прыжок каньона", "x": float(arch_pt[0]) + 30.0, "z": float(arch_pt[1]) + 46.0, "yaw": 2.9},
    {"name": "Прыжок дюн I", "x": 1750.0, "z": 3180.0, "yaw": -0.4},
    {"name": "Прыжок дюн II", "x": 2250.0, "z": 3320.0, "yaw": 0.5},
    {"name": "Прыжок дюн III", "x": 1350.0, "z": 3300.0, "yaw": -1.1},
    {"name": "Прыжок оуэда Восток", "x": 3380.0, "z": 2385.0, "yaw": 2.4},
    {"name": "Прыжок оуэда Юг", "x": 2060.0, "z": 3090.0, "yaw": -2.6},
    {"name": "Трамплин ярмарки", "x": 790.0, "z": 2165.0, "yaw": 3.1},
    {"name": "Прыжок нефтяного поля", "x": 3630.0, "z": 2420.0, "yaw": 1.4},
    {"name": "Прыжок станции", "x": 430.0, "z": 1370.0, "yaw": 0.2},
    {"name": "Прыжок мезы", "x": 1680.0, "z": 1240.0, "yaw": -1.8},
]

speed_traps = []
for frac in (0.08, 0.24, 0.41, 0.58, 0.74, 0.90):
    i = int(len(ring_dense) * frac) % len(ring_dense)
    p = ring_dense[i]
    d = ring_dense[min(i + 3, len(ring_dense) - 1)] - p
    speed_traps.append({"x": round(float(p[0]), 1), "z": round(float(p[1]), 1),
                         "yaw": round(math.atan2(float(d[0]), float(d[1])), 2)})

drift_zones = [
    {"name": "Дрифт: площадь Дюны", "x": 790.0, "z": 2155.0, "radius": 55.0},
    {"name": "Дрифт: дно карьера", "x": 3250.0, "z": 1080.0, "radius": 85.0},
    {"name": "Дрифт: солончак", "x": 2000.0, "z": 2100.0, "radius": 110.0},
    {"name": "Дрифт: шпилька серпантина", "x": 1660.0, "z": 540.0, "radius": 45.0},
    {"name": "Дрифт: кольцо нефтяников", "x": 3560.0, "z": 2430.0, "radius": 70.0},
]
speed_zones = [
    {"name": "Скорость: солончак", "from": [1350.0, 2100.0], "to": [2650.0, 2140.0]},
    {"name": "Скорость: юг кольца", "from": [2850.0, 3080.0], "to": [1850.0, 3140.0]},
    {"name": "Скорость: нефтяное кольцо", "from": [3480.0, 2150.0], "to": [3720.0, 2520.0]},
]
photo_spots = [
    {"name": "Фото: радиовышка", "x": 1832.0, "z": 360.0, "yaw": 2.6},
    {"name": "Фото: каменная арка", "x": float(arch_pt[0]) - 24.0, "z": float(arch_pt[1]) + 30.0, "yaw": -0.6},
    {"name": "Фото: оазис", "x": 3265.0, "z": 3435.0, "yaw": -2.2},
    {"name": "Фото: ветряная ферма", "x": 1120.0, "z": 2875.0, "yaw": 1.9},
    {"name": "Фото: Столовая гора", "x": 1620.0, "z": 1280.0, "yaw": -0.4},
    {"name": "Фото: самолёт", "x": 2925.0, "z": 1605.0, "yaw": -2.6},
    {"name": "Фото: сердце солончака", "x": 2000.0, "z": 2350.0, "yaw": 0.8},
    {"name": "Фото: устье каньона", "x": 1035.0, "z": 1330.0, "yaw": 3.0},
    {"name": "Фото: край карьера", "x": 3050.0, "z": 800.0, "yaw": -2.4},
    {"name": "Фото: водокачка Дюны", "x": 845.0, "z": 2010.0, "yaw": -1.2},
]
treasures = [
    {"x": 470.0, "z": 640.0}, {"x": 2520.0, "z": 900.0}, {"x": 3450.0, "z": 640.0},
    {"x": 1900.0, "z": 1750.0}, {"x": 2750.0, "z": 2450.0}, {"x": 900.0, "z": 3350.0},
    {"x": 2250.0, "z": 3500.0}, {"x": 3600.0, "z": 3050.0},
]
fast_travel = [
    {"name": "Гараж «Дюны»", "x": 604.0, "z": 2075.0},
    {"name": "Карьер", "x": 3260.0, "z": 1160.0},
    {"name": "Нефтяное поле", "x": 3560.0, "z": 2400.0},
    {"name": "Оазис", "x": 3310.0, "z": 3470.0},
    {"name": "Ветряная ферма", "x": 1100.0, "z": 2860.0},
    {"name": "Радиовышка", "x": 1850.0, "z": 345.0},
    {"name": "Перекрёсток солончака", "x": 2390.0, "z": 2120.0},
    {"name": "Старая станция", "x": 420.0, "z": 1410.0},
]

landmarks = []
for (mx, mz, _rx, _rz, top, name) in MESAS:
    landmarks.append({"x": float(mx), "z": float(mz), "rotY": 0.0, "kind": "dz-mesa",
                      "h": float(top), "name": name})
for (lx, lz, lkind, lname) in [
        (1850, 322, "dz-radio-tower", "Радиовышка"),
        (float(arch_pt[0]), float(arch_pt[1]), "dz-arch", "Каменная арка"),
        (862, 1982, "dz-water-tower", "Водокачка «Дюны»"),
        (3250, 1185, "dz-quarry", "Бетонный завод карьера"),
        (3725, 2035, "dz-flare", "Факел нефтяного поля"),
        (700, 2820, "dz-wind-farm", "Ветряная ферма"),
        (3350, 3500, "dz-oasis", "Озеро оазиса"),
        (2952, 1576, "dz-plane", "Самолёт-развалина"),
        (392, 1396, "dz-station", "Старая ж/д станция"),
        (962, 2470, "dz-graveyard", "Кладбище машин"),
        (1082, 2014, "dz-church", "Церквушка городка Дюны"),
        (1040, 1260, "dz-canyon-a", "Устье Западного каньона"),
        (2660, 1160, "dz-canyon-b", "Устье Восточного каньона"),
        (2000, 2100, "dz-salt", "Солончак"),
        (1850, 345, "dz-viewpoint", "Обзорная точка плато"),
        (800, 2050, "dz-town", "Городок Дюны"),
        (2740, 755, "dz-tunnel", "Тоннель в мезе"),
        (3435, 2430, "dz-bridge-e", "Мост Восточного оуэда"),
        (2110, 3165, "dz-bridge-s", "Мост Южного оуэда"),
]:
    landmarks.append({"x": float(lx), "z": float(lz), "rotY": 0.0, "kind": lkind, "name": lname})

districts = [
    {"id": "dz-canyons", "name": "Скалы и каньоны", "x": 1600, "z": 650, "radiusM": 1500, "biome": "rock"},
    {"id": "dz-quarry", "name": "Карьер и рудник", "x": 3300, "z": 1000, "radiusM": 620, "biome": "industry"},
    {"id": "dz-oil", "name": "Нефтяное поле", "x": 3500, "z": 2300, "radiusM": 700, "biome": "industry"},
    {"id": "dz-salt", "name": "Солончак", "x": 2000, "z": 2100, "radiusM": 950, "biome": "salt"},
    {"id": "dz-town", "name": "Городок Дюны", "x": 800, "z": 2050, "radiusM": 520, "biome": "town"},
    {"id": "dz-wind", "name": "Ветряная ферма", "x": 700, "z": 2820, "radiusM": 620, "biome": "ridge"},
    {"id": "dz-dunes", "name": "Море дюн", "x": 1900, "z": 3250, "radiusM": 1300, "biome": "dunes"},
    {"id": "dz-oasis", "name": "Оазис", "x": 3350, "z": 3500, "radiusM": 520, "biome": "oasis"},
    {"id": "dz-desert", "name": "Открытая пустыня", "x": 2000, "z": 1700, "radiusM": 2600, "biome": "desert"},
]

zones = {
    "salt": {"minX": SALT_RECT[0], "minZ": SALT_RECT[1], "maxX": SALT_RECT[2], "maxZ": SALT_RECT[3]},
    "town": {"minX": TOWN_RECT[0], "minZ": TOWN_RECT[1], "maxX": TOWN_RECT[2], "maxZ": TOWN_RECT[3]},
    "quarry": {"minX": QUARRY_RECT[0], "minZ": QUARRY_RECT[1], "maxX": QUARRY_RECT[2], "maxZ": QUARRY_RECT[3]},
    "oilField": {"minX": OIL_RECT[0], "minZ": OIL_RECT[1], "maxX": OIL_RECT[2], "maxZ": OIL_RECT[3]},
    "dunes": {"minX": 0, "minZ": 2780, "maxX": 4000, "maxZ": 3680},
    "oasisLake": {"minX": 3272, "minZ": 3422, "maxX": 3428, "maxZ": 3578},
    "plateau": {"minX": 0, "minZ": 0, "maxX": 4000, "maxZ": 1250},
}

spawn = {"x": 612.0, "y": round(height_at(612.0, 2052.0) + 0.6, 3), "z": 2052.0, "yaw": -1.5708}

stats = {
    "terrainVertices": int(N * N),
    "roadEdges": len(roads_out),
    "roadSamples": int(sum(len(r["samples"]) for r in roads_out)),
    "roadLengthKm": round(road_length_total / 1000.0, 1),
    "buildings": len(buildings),
    "landmarks": len(landmarks),
    "structures": len(structures),
    "scatterInstances": int(sum(len(v) for v in scatter_data.values())),
    "pools": 1,
    "trees": len(scatter_data.get("dead_tree", [])),
    "bushes": len(scatter_data.get("shrub", [])),
    "palms": len(scatter_data.get("oasis_palm", [])),
    "lamps": len(pole_points),
    "benches": 0,
}

desert_extra = {
    "lake": {"x": float(OASIS_CENTRE[0]), "z": float(OASIS_CENTRE[1]), "radius": LAKE_R, "y": LAKE_Y},
    "saltY": SALT_Y,
    "stream": [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in resample_even(stream_dense, 20.0)],
    "structures": structures,
    "scatter": scatter_data,
    "pipes": pipes,
    "guardrails": guardrails,
    "poleLine": pole_points,
    "bridges": [
        {"road": "dz-" + brid, "x": float(c[0]), "z": float(c[1]), "halfLength": hl}
        for (brid, c, hl) in BRIDGES],
    "tunnel": {"road": "dz-" + TUNNEL[0], "x": float(TUNNEL[1][0]), "z": float(TUNNEL[1][1]),
               "halfLength": TUNNEL[2]},
    "game": {
        "circuits": circuits, "sprints": sprints, "drags": drags, "jumps": jumps,
        "speedTraps": speed_traps, "driftZones": drift_zones, "speedZones": speed_zones,
        "photoSpots": photo_spots, "treasures": treasures, "fastTravel": fast_travel,
        "smashSigns": smash_signs,
    },
}

data = {
    "schemaVersion": 1,
    "name": "Desert",
    "units": "metres",
    "seed": SEED,
    "bounds": {"minX": 0, "minZ": 0, "maxX": SIZE, "maxZ": SIZE},
    "spawn": spawn,
    "terrain": {
        "minX": 0, "maxX": SIZE, "minZ": 0, "maxZ": SIZE, "stepM": STEP,
        "cols": N, "rows": N,
        "heights": [round(float(v), 2) for v in H.flatten()],
    },
    "zones": zones,
    "districts": districts,
    "roads": roads_out,
    "buildings": buildings,
    "landmarks": landmarks,
    "pools": [{"x": float(OASIS_CENTRE[0]), "z": float(OASIS_CENTRE[1]), "y": LAKE_Y,
               "w": LAKE_R * 2.0, "d": LAKE_R * 2.0, "rotY": 0.0}],
    "trees": [], "bushes": [], "palms": [], "lamps": [], "benches": [],
    "stats": stats,
    "desert": desert_extra,
}

with open(OUT_JSON, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
print(f"[desert] wrote {OUT_JSON} ({os.path.getsize(OUT_JSON)/1e6:.1f} MB)")

# ---------------------------------------------------------------- density report
print("[desert] density analysis ...")
CELL = 250.0
ncells = int(SIZE / CELL)
notable_points = []
for s in structures:
    notable_points.append((s["x"], s["z"]))
for kind in ("rock_medium", "rock_large", "dead_tree", "oasis_palm", "gravel_pile"):
    for inst in scatter_data[kind]:
        notable_points.append((inst[0], inst[1]))
for lm in landmarks:
    notable_points.append((lm["x"], lm["z"]))
for j in jumps:
    notable_points.append((j["x"], j["z"]))
# cactus groups: cells with >=3 cacti count as one notable group point
cactus_cells = {}
for kind in ("cactus_saguaro", "cactus_barrel", "cactus_prickly"):
    for inst in scatter_data[kind]:
        key = (int(inst[0] // CELL), int(inst[1] // CELL))
        cactus_cells[key] = cactus_cells.get(key, 0) + 1
for (cx, cz), cnt in cactus_cells.items():
    if cnt >= 3:
        notable_points.append(((cx + 0.5) * CELL, (cz + 0.5) * CELL))

cell_counts = np.zeros((ncells, ncells), dtype=int)
for (x, z) in notable_points:
    cx = min(max(int(x // CELL), 0), ncells - 1)
    cz = min(max(int(z // CELL), 0), ncells - 1)
    cell_counts[cz, cx] += 1
empty_cells = [(int(x), int(z)) for z in range(ncells) for x in range(ncells) if cell_counts[z, x] == 0]
empty_zones = {}
for (cx, cz) in empty_cells:
    zn = zone_of((cx + 0.5) * CELL, (cz + 0.5) * CELL)
    empty_zones[zn] = empty_zones.get(zn, 0) + 1

# distance-to-notable raster for road gap analysis (cap 520 m)
notable_dist = np.full((N, N), 520.0)
for (x, z) in notable_points:
    cx, cz = int(x / STEP), int(z / STEP)
    r = int(520.0 / STEP)
    x0, x1 = max(0, cx - r), min(N - 1, cx + r)
    z0, z1 = max(0, cz - r), min(N - 1, cz + r)
    lx = xs[x0:x1 + 1][None, :]
    lz = zs[z0:z1 + 1][:, None]
    d = np.hypot(lx - x, lz - z)
    sub = notable_dist[z0:z1 + 1, x0:x1 + 1]
    notable_dist[z0:z1 + 1, x0:x1 + 1] = np.minimum(sub, d)

gap_report = []
for rid, dense in roads_dense.items():
    samples = resample_even(dense, 25.0)
    run = 0.0
    worst = 0.0
    worst_at = None
    prev = None
    for p in samples:
        if bilinear(notable_dist, p[0], p[1]) > 150.0:
            run += 25.0
            if run > worst:
                worst = run
                worst_at = (float(p[0]), float(p[1]))
        else:
            run = 0.0
        prev = p
    if worst > 400.0:
        gap_report.append((rid, worst, worst_at))

# zone densities (notable objects per km^2, zone area from raster)
ZONE_AREAS = {}
zone_notable = {}
for iz in range(0, N, 4):
    for ix in range(0, N, 4):
        zn = zone_of(xs[ix], zs[iz])
        ZONE_AREAS[zn] = ZONE_AREAS.get(zn, 0) + (STEP * 4) ** 2
for (x, z) in notable_points:
    zn = zone_of(x, z)
    zone_notable[zn] = zone_notable.get(zn, 0) + 1

SPEC_DENSITY = {
    "town": (400, 500), "quarry": (250, 300), "oil": (150, 200), "oasis": (300, 300),
    "canyon": (150, 200), "wind": (80, 100), "desert": (100, 150), "dunes": (30, 50), "salt": (5, 10),
}
lines = []
lines.append("DESERT — отчёт плотности объектов (генератор generate_desert_world.py)")
lines.append("=" * 72)
lines.append(f"Сетка 250x250 м: {ncells}x{ncells} = {ncells*ncells} клеток; заметных объектов: {len(notable_points)}")
lines.append(f"Пустых клеток: {len(empty_cells)} ({100.0*len(empty_cells)/(ncells*ncells):.1f}% при лимите 5%)")
lines.append(f"Пустые клетки по зонам: {empty_zones}")
lines.append("")
lines.append("Плотность заметных объектов по зонам (объектов/км², цель по спеке):")
for zn in ("town", "quarry", "oil", "oasis", "canyon", "wind", "desert", "dunes", "salt"):
    area_km2 = ZONE_AREAS.get(zn, 0) / 1e6
    dens = zone_notable.get(zn, 0) / area_km2 if area_km2 > 0 else 0.0
    lo, hi = SPEC_DENSITY.get(zn, (0, 0))
    flag = "OK" if lo * 0.55 <= dens <= hi * 1.9 else "ВНЕ ДИАПАЗОНА"
    lines.append(f"  {zn:8s}: {dens:6.0f} /км² (цель {lo}-{hi}) [{flag}]  объектов={zone_notable.get(zn,0)}, площадь={area_km2:.2f} км²")
salt_far = sum(1 for (x, z) in notable_points if zone_of(x, z) == "salt" and road_dist_at(x, z) > 30.0)
salt_area = ZONE_AREAS.get("salt", 1) / 1e6
lines.append(f"  (солончак без дорожной мебели, >30 м от дорог: {salt_far / salt_area:.0f} /км² — цель 5-10)")
lines.append("")
if gap_report:
    lines.append("Разрывы >400 м без заметных объектов в пределах 150 м от дороги:")
    for (rid, worst, at) in sorted(gap_report, key=lambda g: -g[1]):
        lines.append(f"  {rid}: {worst:.0f} м около ({at[0]:.0f}, {at[1]:.0f})")
else:
    lines.append("Разрывов >400 м вдоль дорог не найдено.")
lines.append("")
lines.append(f"Дороги: {len(roads_out)} шт., суммарно {road_length_total/1000.0:.1f} км (цель 55-65)")
lines.append(f"Scatter-экземпляров всего: {stats['scatterInstances']}")
for k, v in sorted(scatter_data.items()):
    lines.append(f"  {k}: {len(v)}")
lines.append(f"Структур: {len(structures)}, зданий (POI/миникарта): {len(buildings)}, ориентиров: {len(landmarks)}")
lines.append(f"Ограждений: {len(guardrails)} секций, труб: {len(pipes)} сегментов, столбов ЛЭП: {len(pole_points)}")
report = "\n".join(lines) + "\n"
with open(OUT_REPORT, "w", encoding="utf-8") as f:
    f.write(report)
print(report)

# ---------------------------------------------------------------- previews
try:
    from PIL import Image, ImageDraw

    os.makedirs(PREVIEW_DIR, exist_ok=True)
    # hillshade design preview
    gy2, gx2 = np.gradient(H, STEP)
    shade = np.clip(0.55 + (-gx2 * 0.55 - gy2 * 0.75) * 1.4, 0.05, 1.2)
    base = np.zeros((N, N, 3), dtype=np.float32)
    hn = np.clip((H - 20.0) / 130.0, 0, 1)
    base[..., 0] = 0.72 + hn * 0.20
    base[..., 1] = 0.55 + hn * 0.08
    base[..., 2] = 0.36 - hn * 0.08
    rocky = np.clip(slope_grid * 1.1, 0, 1)
    base[..., 0] = base[..., 0] * (1 - rocky * 0.30) + 0.60 * rocky * 0.30
    base[..., 1] = base[..., 1] * (1 - rocky * 0.30) + 0.38 * rocky * 0.30
    base[..., 2] = base[..., 2] * (1 - rocky * 0.30) + 0.29 * rocky * 0.30
    salt_px = (np.abs(H - SALT_Y) < 0.05) & (GX >= SALT_RECT[0]) & (GX <= SALT_RECT[2]) & (GZ >= SALT_RECT[1]) & (GZ <= SALT_RECT[3])
    base[salt_px] = np.array([0.95, 0.94, 0.90])
    lake_px = oasis_dist < LAKE_R
    base[lake_px] = np.array([0.15, 0.45, 0.65])
    green_px = (oasis_dist < 330.0) & ~lake_px
    base[green_px] = base[green_px] * 0.55 + np.array([0.20, 0.45, 0.20]) * 0.45
    img = np.clip(base * shade[..., None], 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8)).resize((1000, 1000), Image.BILINEAR)
    dr = ImageDraw.Draw(im)
    scale = 1000.0 / SIZE
    for r in roads_out:
        pts = [(s[0] * scale, s[2] * scale) for s in r["samples"]]
        col = (35, 35, 40) if r["surface"] == "asphalt" else (150, 120, 85)
        wdt = 3 if r["surface"] == "asphalt" else 2
        if r.get("closed"):
            pts = pts + [pts[0]]
        dr.line(pts, fill=col, width=wdt)
    for (lx, lz, label) in [
            (1500, 500, "CANYONS / MESAS"), (3300, 1000, "QUARRY"), (800, 2050, "TOWN DUNY"),
            (2000, 2100, "SALT FLAT"), (3550, 2350, "OIL FIELD"), (700, 2820, "WIND FARM"),
            (1900, 3250, "DUNE SEA"), (3350, 3500, "OASIS"), (1850, 330, "RADIO TOWER")]:
        dr.text((lx * scale - 40, lz * scale - 6), label, fill=(20, 20, 20))
    im.save(OUT_PREVIEW)
    im.save(os.path.join(PREVIEW_DIR, "design.png"))

    # density heatmap
    heat = np.zeros((ncells, ncells, 3), dtype=np.float32)
    vmax = max(1.0, float(np.percentile(cell_counts, 92)))
    t = np.clip(cell_counts / vmax, 0, 1)
    heat[..., 0] = np.clip(0.25 + t * 1.1, 0, 1)
    heat[..., 1] = np.clip(0.25 + t * 0.55 - np.clip(t - 0.6, 0, 1) * 0.8, 0, 1)
    heat[..., 2] = np.clip(0.55 - t * 0.55, 0, 1)
    heat[cell_counts == 0] = np.array([0.08, 0.08, 0.10])
    him = Image.fromarray((heat * 255).astype(np.uint8)).resize((1000, 1000), Image.NEAREST)
    dr = ImageDraw.Draw(him)
    for r in roads_out:
        pts = [(s[0] * scale, s[2] * scale) for s in r["samples"]]
        if r.get("closed"):
            pts = pts + [pts[0]]
        dr.line(pts, fill=(15, 15, 15), width=2)
    him.save(OUT_HEATMAP)
    him.save(os.path.join(PREVIEW_DIR, "heatmap.png"))
    print(f"[desert] previews: {OUT_PREVIEW}, {OUT_HEATMAP}")
except Exception as exc:  # previews are diagnostics, never fatal
    print("[desert] preview failed:", exc)

print("[desert] done")
