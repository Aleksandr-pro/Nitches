#!/usr/bin/env python3
"""GreenForest ("Зелёный лес") world generator for Nitches Horizon Native.

Third world, built to the owner's GreenForest spec on the same proven
pipeline as the Desert (4x4 km, 501x501 height grid @ 8 m, Catmull-Rom
roads flattened into the heightfield, exact road-edge audits):

  north conifer hills with a serpentine and summit viewpoint, a dark
  mixed forest in the west, central open meadows, a 0.9x0.8 km lake
  with an island and a dam, a river flowing from the NW hills into
  the lake and out to the SE corner (plus a waterfall tributary in
  the NE cliff), a southern farm valley with crop fields, a birch
  grove village by the lake, a SW sawmill with clearings, a swamp
  with a causeway, ~55-60 km of roads, 8 bridges, 2 tunnels.

Output: native/data/greenforest_native.json in the desert schema
(terrain, roads, districts, zones, landmarks, spawn, stats) plus a
"forest" section with scatter, structures, fields and game content
consumed by the forest build path in world_builder.gd.

Coordinates: Godot metres, X east 0..4000, Z south 0..4000 (the
spec's km-from-NW-corner maps 1:1 with y -> Z).

Run:  python3 scripts/generate_greenforest_world.py
"""

import json
import math
import os

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "native/data/greenforest_native.json")
OUT_REPORT = os.path.join(ROOT, "docs/greenforest-density-report.txt")
OUT_HEATMAP = os.path.join(ROOT, "docs/greenforest-density-heatmap.png")
OUT_PREVIEW = os.path.join(ROOT, "docs/greenforest-design-preview.png")

SEED = 20261101
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
LAKE_X, LAKE_Z = 3050.0, 2200.0
LAKE_RX, LAKE_RZ = 450.0, 400.0
LAKE_Y = 14.0
ISLAND_X, ISLAND_Z = 2920.0, 2120.0
SWAMP_X, SWAMP_Z, SWAMP_RX, SWAMP_RZ, SWAMP_Y = 1100.0, 2850.0, 370.0, 285.0, 8.9
SUMMIT = (1850.0, 300.0)
WATERFALL = (3385.0, 655.0)

HILLS_RECT = (0.0, 0.0, 4000.0, 1250.0)
DARK_RECT = (0.0, 1150.0, 1250.0, 3250.0)
MEADOW_RECT = (1150.0, 1250.0, 2550.0, 2550.0)
FARM_RECT = (1150.0, 2850.0, 2850.0, 3850.0)
BIRCH_RECT = (3250.0, 1150.0, 4000.0, 2450.0)
SAWMILL_RECT = (450.0, 3150.0, 1350.0, 3850.0)

# Crop fields (axis-aligned, centre + size): filled with crop scatter
# and rendered as plowed-soil terrain by the builder.
FIELDS = [
    {"x": 1580.0, "z": 3120.0, "w": 300.0, "d": 180.0, "crop": "crop_wheat"},
    {"x": 1980.0, "z": 3100.0, "w": 260.0, "d": 200.0, "crop": "crop_sunflower"},
    {"x": 2380.0, "z": 3120.0, "w": 280.0, "d": 170.0, "crop": "crop_corn"},
    {"x": 1600.0, "z": 3560.0, "w": 320.0, "d": 190.0, "crop": "crop_corn"},
    {"x": 2050.0, "z": 3620.0, "w": 300.0, "d": 220.0, "crop": "crop_wheat"},
    {"x": 2480.0, "z": 3560.0, "w": 260.0, "d": 180.0, "crop": "crop_sunflower"},
    {"x": 2620.0, "z": 3320.0, "w": 150.0, "d": 150.0, "crop": "crop_wheat"},
    {"x": 1380.0, "z": 3320.0, "w": 140.0, "d": 160.0, "crop": "crop_sunflower"},
]
# Sawmill clear-cut patches (ellipses): stumps/logs, almost no trees.
CLEARCUTS = [(760.0, 3380.0, 150.0, 110.0), (1080.0, 3620.0, 170.0, 120.0),
             (560.0, 3620.0, 130.0, 100.0), (950.0, 3280.0, 120.0, 90.0)]


def in_rect(x, z, r):
    return r[0] <= x <= r[2] and r[1] <= z <= r[3]


def lake_d(x, z):
    return math.hypot((x - LAKE_X) / LAKE_RX, (z - LAKE_Z) / LAKE_RZ)


def swamp_d(x, z):
    return math.hypot((x - SWAMP_X) / SWAMP_RX, (z - SWAMP_Z) / SWAMP_RZ)


def in_fields(x, z, pad=0.0):
    for f in FIELDS:
        if abs(x - f["x"]) <= f["w"] * 0.5 + pad and abs(z - f["z"]) <= f["d"] * 0.5 + pad:
            return True
    return False


def in_clearcut(x, z):
    for (cx, cz, rx, rz) in CLEARCUTS:
        if math.hypot((x - cx) / rx, (z - cz) / rz) < 1.0:
            return True
    return False


def zone_of(x, z):
    if lake_d(x, z) < 1.02:
        return "lake"
    if swamp_d(x, z) < 1.0:
        return "swamp"
    if in_rect(x, z, SAWMILL_RECT):
        return "sawmill"
    if in_rect(x, z, FARM_RECT):
        return "farm"
    if z < 1250.0:
        return "hills"
    if in_rect(x, z, DARK_RECT):
        return "dark"
    if in_rect(x, z, BIRCH_RECT):
        return "birch"
    if in_rect(x, z, MEADOW_RECT):
        return "meadow"
    return "grove"


# ---------------------------------------------------------------- height
print("[forest] base heightfield ...")
H = (16.0 + fbm([6, 12, 24], 401) * 6.5 + fbm([48], 733) * 1.4).astype(np.float64)

# North conifer hills: ridged massif up to ~160 m.
hill_mask = smoothstep(1500.0, 750.0, GZ)
ridge = 1.0 - np.abs(fbm([5, 10, 20], 502))
hills = 26.0 + np.clip(ridge, 0.0, 1.0) * 86.0 + fbm([16, 32], 603) * 9.0
H += hill_mask * hills
# Summit knob under the viewpoint.
H += np.exp(-(np.hypot(GX - SUMMIT[0], GZ - SUMMIT[1]) / 330.0) ** 2) * 24.0
# NE cliff plateau with a steep rim.
d_cliff = np.hypot((GX - 3550.0) / 640.0, (GZ - 520.0) / 470.0)
cliff_target = 132.0 + fbm([8, 16], 704) * 8.0
cm = smoothstep(1.18, 0.72, d_cliff)
H = H * (1.0 - cm) + cliff_target * cm
# Gallery hill the ring road tunnels through.
H += np.exp(-(np.hypot(GX - 2550.0, GZ - 760.0) / 200.0) ** 2) * 38.0
# Central meadows: gentle open waves.
meadow_mask = (smoothstep(1050.0, 1300.0, GX) * (1.0 - smoothstep(2400.0, 2650.0, GX)) *
               smoothstep(1150.0, 1400.0, GZ) * (1.0 - smoothstep(2400.0, 2650.0, GZ)))
meadow_t = 13.0 + fbm([7, 14], 805) * 4.0
H = H * (1.0 - meadow_mask * 0.55) + meadow_t * (meadow_mask * 0.55)
# Southern farm plain.
farm_mask = smoothstep(2750.0, 3050.0, GZ) * smoothstep(1000.0, 1250.0, GX) * (1.0 - smoothstep(2750.0, 3000.0, GX))
farm_t = 12.5 + fbm([6, 12], 906) * 2.2
H = H * (1.0 - farm_mask * 0.8) + farm_t * (farm_mask * 0.8)
# Swamp: low and nearly flat.
d_sw = np.hypot((GX - SWAMP_X) / SWAMP_RX, (GZ - SWAMP_Z) / SWAMP_RZ)
swm = smoothstep(1.25, 0.8, d_sw)
sw_t = 8.6 + fbm([10, 20], 1007) * 0.8
H = H * (1.0 - swm * 0.85) + sw_t * (swm * 0.85)
# Lake bowl + island with its single pine (scatter adds the tree).
d_lake_g = np.hypot((GX - LAKE_X) / LAKE_RX, (GZ - LAKE_Z) / LAKE_RZ)
bed = (LAKE_Y - 4.4) + np.clip(d_lake_g, 0.0, 1.3) ** 2 * 4.0
lm = smoothstep(1.28, 0.94, d_lake_g)
H = H * (1.0 - lm) + bed * lm
H += np.exp(-(np.hypot(GX - ISLAND_X, GZ - ISLAND_Z) / 85.0) ** 2) * 8.5
H = np.maximum(H, 2.0)

# ---------------------------------------------------------------- river
print("[forest] carving river ...")
RIVER_UP_CTRL = [(420, 240), (700, 420), (620, 700), (900, 900), (820, 1180),
                 (1150, 1350), (1080, 1600), (1450, 1750), (1750, 1680),
                 (2050, 1850), (2350, 1980), (2620, 2080)]
RIVER_LOW_CTRL = [(3180, 2580), (3050, 2850), (3300, 3050), (3220, 3320),
                  (3500, 3550), (3750, 3780), (3960, 3960)]
TRIB_CTRL = [(3385, 675), (3280, 950), (3380, 1250), (3250, 1550), (3180, 1820)]


def make_river(ctrl, end_is_lake):
    """Carve a descending channel; return (dense, water_y array)."""
    dense = catmull_rom(ctrl, closed=False, step=6.0)
    hs = np.array([bilinear(H, p[0], p[1]) for p in dense])
    for win in (61, 31):
        k = np.ones(win) / win
        hs = np.convolve(np.pad(hs, win // 2, mode="edge"), k, mode="valid")
    bed = hs - 3.6
    if end_is_lake:
        bed[-1] = min(bed[-1], LAKE_Y - 3.2)
    else:
        bed[0] = min(bed[0], LAKE_Y - 3.0)
    for i in range(len(bed) - 2, -1, -1):
        bed[i] = max(bed[i], bed[i + 1])
    seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_cum = np.concatenate([[0.0], np.cumsum(seg)])

    def carve_fn(sub, dist, s, _bed=bed, _s=s_cum):
        b = np.interp(s, _s, _bed)
        carved = b + smoothstep(5.0, 17.0, dist) * 5.0
        w = 1.0 - smoothstep(14.0, 30.0, dist)
        return sub * (1.0 - w) + np.minimum(sub, carved) * w

    _polyline_local_op_s(H, dense, 34.0, carve_fn, s_cum)
    wy = np.array([bilinear(H, p[0], p[1]) for p in dense]) + 1.55
    for win in (31, 15):
        k = np.ones(win) / win
        wy = np.convolve(np.pad(wy, win // 2, mode="edge"), k, mode="valid")
    for i in range(len(wy) - 2, -1, -1):
        wy[i] = max(wy[i], wy[i + 1])
    if end_is_lake:
        wy[-1] = LAKE_Y
        for i in range(len(wy) - 2, -1, -1):
            wy[i] = max(wy[i], wy[i + 1])
    else:
        wy[0] = LAKE_Y
        for i in range(1, len(wy)):
            wy[i] = min(wy[i], wy[i - 1])
    return dense, wy


river_up_dense, river_up_wy = make_river(RIVER_UP_CTRL, True)
river_low_dense, river_low_wy = make_river(RIVER_LOW_CTRL, False)
trib_dense, trib_wy = make_river(TRIB_CTRL, True)
RIVERS = [(river_up_dense, river_up_wy), (river_low_dense, river_low_wy), (trib_dense, trib_wy)]

# Dam embankment: a low land strip under the south-bay causeway chord.
DAM_CTRL = [(2620, 2280), (2790, 2470), (3060, 2535), (3340, 2510), (3500, 2380)]
_dam_dense = catmull_rom(DAM_CTRL, closed=False, step=6.0)


def _dam_fn(sub, dist, s):
    target = LAKE_Y + 0.8 - smoothstep(6.0, 17.0, dist) * 2.4
    w = 1.0 - smoothstep(12.0, 20.0, dist)
    return sub * (1.0 - w) + np.maximum(sub, target) * w


polyline_local_op(H, _dam_dense, 24.0, _dam_fn)

# ---------------------------------------------------------------- roads
print("[forest] roads: layout + flattening ...")
RING = [(620, 980), (1250, 760), (1900, 820), (2550, 760), (3150, 900),
        (3500, 1300), (3380, 1520), (3600, 1850), (3580, 2250), (3380, 2780),
        (2850, 3220), (2100, 3480), (1350, 3520), (760, 3220), (560, 2620),
        (520, 1950), (560, 1400)]
SERPENTINE = [(1900, 820), (1650, 700), (2050, 600), (1700, 480), (2100, 400), (1850, 300)]
RIDGE = [(1850, 300), (2300, 360), (2700, 520), (3000, 700), (3150, 900)]
CLIFF_RD = [(3150, 900), (3350, 700), (3550, 560), (3800, 430), (3920, 300)]
MEADOW_STRAIGHT = [(1250, 1900), (1900, 1920), (2520, 1950)]
LAKE_LOOP = [(2600, 2000), (2900, 1780), (3350, 1850), (3600, 2200),
             (3450, 2550), (3050, 2680), (2680, 2400)]
DAM_RD = DAM_CTRL
VILLAGE_MAIN = [(3520, 1950), (3650, 2150), (3580, 2400)]
VILLAGE_CROSS = [(3450, 2150), (3600, 2180), (3750, 2200)]
FARM_STRAIGHT = [(1300, 3350), (2000, 3380), (2680, 3350)]
FARM_LOOP = [(1450, 3080), (2200, 3050), (2280, 3300), (1500, 3320)]
FOREST_LOOP = [(500, 1500), (950, 1400), (1100, 1750), (1000, 2150), (600, 2250), (420, 1850)]
RIVERBANK = [(700, 520), (950, 980), (1150, 1250), (1200, 1520), (1550, 1680), (1900, 1760), (2200, 1900), (2520, 1950)]
SWAMP_CAUSEWAY = [(620, 2900), (900, 2840), (1150, 2860), (1420, 2920), (1600, 3050)]
SAWMILL_A = [(1350, 3520), (900, 3650), (500, 3500)]
SAWMILL_B = [(900, 3650), (850, 3300), (760, 3220)]
SAWMILL_C = [(500, 3500), (350, 3150), (520, 2800)]
TRAIL_FORD = [(1250, 1580), (1450, 1740), (1700, 1820), (1900, 1920)]
TRAIL_WATERFALL = [(3350, 700), (3410, 645)]
D_DARK_A = [(420, 1850), (300, 1450), (450, 1100), (620, 980)]
D_DARK_B = [(1000, 2150), (1150, 2450), (1100, 2750)]
D_BIRCH = [(3600, 1850), (3800, 1600), (3750, 1300), (3500, 1300)]
D_FIELD_A = [(1500, 3320), (1480, 3560), (1500, 3800)]
D_FIELD_B = [(2280, 3300), (2300, 3580), (2260, 3820)]
D_SOUTH = [(700, 3800), (1500, 3820), (2260, 3820), (2850, 3680), (3380, 3300)]
D_HILLS_W = [(620, 980), (500, 700), (650, 450), (900, 300)]
D_HILLS_E = [(3150, 900), (2950, 650), (2700, 520)]
D_MEADOW_NS = [(1900, 1920), (1850, 2300), (1950, 2680), (2100, 3050)]
D_LAKE_WEST = [(2520, 1950), (2580, 2150), (2620, 2280)]
D_VILLAGE_S = [(3580, 2400), (3500, 2600), (3380, 2780)]
D_LAKE_SOUTH = [(2680, 2400), (2900, 2620), (3200, 2700), (3450, 2550)]
D_DARK_EW = [(420, 1850), (800, 1750), (1100, 1850), (1450, 1750)]
D_HILLS_LINK = [(900, 300), (1500, 420), (1850, 300)]
D_NORTH_RIM = [(900, 300), (1600, 180), (2400, 240), (3000, 360)]
D_MEADOW_W = [(1250, 1900), (1150, 2200), (1250, 2500), (1600, 2680)]
D_FARM_MID = [(1350, 3260), (2000, 3270), (2680, 3260)]
D_BIRCH_N = [(3500, 1300), (3650, 1000), (3550, 700)]
D_SWAMP_N = [(1100, 2750), (1250, 2500), (1600, 2300)]
D_SAWMILL_S = [(900, 3650), (1100, 3800), (1500, 3820)]
D_CLIFF_TOP = [(3920, 300), (3700, 180), (3400, 250), (3150, 420), (3000, 700)]
D_WEST_BORDER = [(560, 1400), (350, 1100), (260, 700), (500, 450)]

ROAD_DEFS = [
    # id, name, control points, width, lanes, surface, closed, speed
    ("ring", "Главная кольцевая", RING, 11.0, 2, "asphalt", True, 90),
    ("serpentine", "Серпантин на вершину", SERPENTINE, 8.0, 2, "asphalt", False, 60),
    ("ridge", "Хребтовая дорога", RIDGE, 7.5, 2, "gravel", False, 70),
    ("cliff_road", "Дорога к утёсу", CLIFF_RD, 9.0, 2, "asphalt", False, 70),
    ("meadow_straight", "Луговая прямая", MEADOW_STRAIGHT, 10.0, 2, "asphalt", False, 110),
    ("lake_loop", "Вокруг озера", LAKE_LOOP, 8.0, 2, "asphalt", True, 70),
    ("dam_road", "Дамба", DAM_RD, 8.0, 2, "asphalt", False, 60),
    ("village_main", "Главная улица посёлка", VILLAGE_MAIN, 8.0, 2, "asphalt", False, 40),
    ("village_cross", "Прибрежный переулок", VILLAGE_CROSS, 7.0, 2, "asphalt", False, 40),
    ("farm_straight", "Полевая прямая", FARM_STRAIGHT, 9.0, 2, "asphalt", False, 100),
    ("farm_loop", "Фермерское кольцо", FARM_LOOP, 7.5, 2, "gravel", True, 70),
    ("forest_loop", "Лесное кольцо", FOREST_LOOP, 7.5, 2, "gravel", True, 60),
    ("riverbank", "Вдоль реки", RIVERBANK, 7.0, 2, "gravel", False, 60),
    ("swamp_causeway", "Гать через болото", SWAMP_CAUSEWAY, 6.5, 2, "gravel", False, 40),
    ("sawmill_a", "Лесовозная западная", SAWMILL_A, 7.5, 2, "gravel", False, 50),
    ("sawmill_b", "Лесовозная северная", SAWMILL_B, 7.0, 2, "gravel", False, 50),
    ("sawmill_c", "Лесовозная дальняя", SAWMILL_C, 6.5, 2, "gravel", False, 50),
    ("trail_ford", "Тропа к броду", TRAIL_FORD, 6.0, 2, "gravel", False, 40),
    ("trail_waterfall", "К водопаду", TRAIL_WATERFALL, 5.5, 2, "gravel", False, 30),
    ("dirt_dark_a", "Глухой просёлок", D_DARK_A, 6.5, 2, "gravel", False, 50),
    ("dirt_dark_b", "К болоту", D_DARK_B, 6.5, 2, "gravel", False, 50),
    ("dirt_birch", "Берёзовая аллея", D_BIRCH, 7.0, 2, "gravel", False, 60),
    ("dirt_field_a", "Полевой просёлок запад", D_FIELD_A, 6.5, 2, "gravel", False, 60),
    ("dirt_field_b", "Полевой просёлок восток", D_FIELD_B, 6.5, 2, "gravel", False, 60),
    ("dirt_south", "Южный тракт", D_SOUTH, 7.5, 2, "gravel", False, 80),
    ("dirt_hills_w", "Западные холмы", D_HILLS_W, 6.5, 2, "gravel", False, 50),
    ("dirt_hills_e", "Восточные холмы", D_HILLS_E, 6.5, 2, "gravel", False, 50),
    ("dirt_meadow_ns", "Луговой меридиан", D_MEADOW_NS, 7.0, 2, "gravel", False, 70),
    ("dirt_lake_west", "Западный берег", D_LAKE_WEST, 6.5, 2, "gravel", False, 50),
    ("dirt_village_s", "Южный посёлок", D_VILLAGE_S, 7.0, 2, "gravel", False, 50),
    ("dirt_lake_south", "Южный берег озера", D_LAKE_SOUTH, 6.5, 2, "gravel", False, 50),
    ("dirt_dark_ew", "Поперёк Тёмного леса", D_DARK_EW, 6.5, 2, "gravel", False, 50),
    ("dirt_hills_link", "К вершине с запада", D_HILLS_LINK, 6.5, 2, "gravel", False, 50),
    ("dirt_north_rim", "Северная кромка", D_NORTH_RIM, 6.5, 2, "gravel", False, 60),
    ("dirt_meadow_w", "Западный край лугов", D_MEADOW_W, 7.0, 2, "gravel", False, 60),
    ("dirt_farm_mid", "Между полями", D_FARM_MID, 7.0, 2, "gravel", False, 70),
    ("dirt_birch_n", "Берёзовая северная", D_BIRCH_N, 6.5, 2, "gravel", False, 50),
    ("dirt_swamp_n", "Северный край болота", D_SWAMP_N, 6.5, 2, "gravel", False, 50),
    ("dirt_sawmill_s", "Лесовозная южная", D_SAWMILL_S, 7.0, 2, "gravel", False, 60),
    ("dirt_cliff_top", "По краю утёса", D_CLIFF_TOP, 6.5, 2, "gravel", False, 50),
    ("dirt_west_border", "Западная граница", D_WEST_BORDER, 6.0, 2, "gravel", False, 50),
]

roads_dense = {}
for (rid, _name, ctrl, _w, _lanes, _surf, closed, _spd) in ROAD_DEFS:
    roads_dense[rid] = catmull_rom(ctrl, closed=closed, step=5.0)

# Bridges: (road_id, centre, half-length, deck_y or None).  Deck
# profile comes from the smoothed road profile; where deck_y is set
# (dam, swamp causeway) the deck is held above the water level.
BRIDGES = [
    ("ring", np.array([800.0, 880.0]), 40.0, None),          # upper river NW
    ("ring", np.array([3340.0, 1420.0]), 38.0, None),        # waterfall tributary
    ("ring", np.array([3150.0, 2980.0]), 40.0, None),        # lower river SE
    ("cliff_road", np.array([3360.0, 690.0]), 45.0, None),   # gorge bridge
    ("meadow_straight", np.array([2200.0, 1930.0]), 38.0, None),
    ("forest_loop", np.array([1060.0, 1620.0]), 36.0, None), # wooden bridge
    ("lake_loop", np.array([2610.0, 2090.0]), 34.0, None),   # river inlet
    ("dam_road", np.array([3060.0, 2535.0]), 580.0, LAKE_Y + 0.95),
    ("swamp_causeway", np.array([1150.0, 2860.0]), 390.0, SWAMP_Y + 1.3),
]
# Tunnels: (road_id, centre, half-length) — cliff tunnel + ring gallery.
TUNNELS = [
    ("cliff_road", np.array([3550.0, 560.0]), 70.0),
    ("ring", np.array([2550.0, 760.0]), 55.0),
]

def road_profile(dense, max_grade, closed, follow=False):
    """Smooth, grade-limited target heights along a road centreline."""
    hs = np.array([bilinear(H, p[0], p[1]) for p in dense])
    # wide smoothing (two box passes); trails mostly follow the terrain
    for win in ((31, 15) if follow else (61, 31)):
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
    # Vertical-curve smoothing: round off grade breaks so crests and
    # sags are curves, not kinks (the car used to hop at every break).
    for _ in range(10):
        if closed:
            hs = hs + 0.35 * (0.5 * (np.roll(hs, 1) + np.roll(hs, -1)) - hs)
        else:
            hs[1:-1] = hs[1:-1] + 0.35 * (0.5 * (hs[:-2] + hs[2:]) - hs[1:-1])
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
flatten_jobs = {}
bridge_s_ranges = {}
tunnel_s_ranges = {}   # road_id -> list of (s0, s1)

for (rid, _name, _ctrl, width, _lanes, surf, closed, _spd) in ROAD_DEFS:
    dense = roads_dense[rid]
    follow = rid.startswith("trail_")
    max_grade = 0.075 if surf == "asphalt" else (0.16 if follow else 0.10)
    prof = road_profile(dense, max_grade, closed, follow=follow)
    seg_lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    s_cum = np.concatenate([[0.0], np.cumsum(seg_lens)])

    skip_ranges = []
    for (brid, centre, half_len, deck_y) in BRIDGES:
        if brid != rid:
            continue
        d = np.linalg.norm(dense - centre, axis=1)
        s0 = float(s_cum[int(np.argmin(d))])
        skip_ranges.append((s0 - half_len, s0 + half_len))
        if deck_y is not None:
            _deck = np.maximum(prof, deck_y)
            _w = smoothstep(s0 - half_len, s0 - half_len + 24.0, s_cum) * (
                1.0 - smoothstep(s0 + half_len - 24.0, s0 + half_len, s_cum))
            prof = prof * (1.0 - _w) + _deck * _w
    if skip_ranges:
        bridge_s_ranges[rid] = skip_ranges
    for (tun_rid, centre, half_len) in TUNNELS:
        if tun_rid != rid:
            continue
        d = np.linalg.norm(dense - centre, axis=1)
        s0 = float(s_cum[int(np.argmin(d))])
        tunnel_s_ranges.setdefault(rid, []).append((s0 - half_len, s0 + half_len))
    road_profiles[rid] = prof

    half_w = width * 0.5
    falloff = 14.0 if follow else 18.0

    def make_fn(prof=prof, s_cum=s_cum, half_w=half_w,
                falloff=falloff, skip_ranges=skip_ranges):
        def fn(sub, dist, s):
            target_h = np.interp(s, s_cum, prof)
            w = 1.0 - smoothstep(half_w + 3.0, half_w + falloff, dist)
            for (a, b) in skip_ranges:
                w = np.where((s > a) & (s < b), 0.0, w)
            return sub * (1.0 - w) + target_h * w
        return fn

    # 0.2.56: flattening moved after junction harmonisation below so
    # crossing profiles are reconciled before they touch the terrain.
    flatten_jobs[rid] = (dense, s_cum, prof, half_w, falloff, list(skip_ranges))

# Junction height harmonisation (0.2.56): where two roads cross or
# join, ease both profiles to a common height so the runtime deck
# ribbons meet flush instead of overlapping with flickering strips.
# Asphalt wins (dirt eases fully, asphalt barely moves); bridge and
# tunnel spans plus a 30 m apron stay untouched; deltas cap at 1.2 m.
_surf_by_id = {r[0]: r[5] for r in ROAD_DEFS}
_jgrid = {}
for _rid, _dense in roads_dense.items():
    for _i, _p in enumerate(_dense):
        _jgrid.setdefault((int(_p[0] // 16), int(_p[1] // 16)),
                          []).append((_rid, _i))


def _in_protected(_s, _ranges, _margin):
    return any(_a - _margin <= _s <= _b + _margin
               for (_a, _b) in _ranges)


_harmonised_points = 0
for _rid, _dense in roads_dense.items():
    _prof = road_profiles[_rid].copy()
    _s_cum = flatten_jobs[_rid][1]
    _protected = (list(bridge_s_ranges.get(_rid, []))
                  + list(tunnel_s_ranges.get(_rid, [])))
    for _i, _p in enumerate(_dense):
        if _in_protected(float(_s_cum[_i]), _protected, 30.0):
            continue
        _best = None
        _kx, _kz = int(_p[0] // 16), int(_p[1] // 16)
        for _gx in (_kx - 1, _kx, _kx + 1):
            for _gz in (_kz - 1, _kz, _kz + 1):
                for (_orid, _oi) in _jgrid.get((_gx, _gz), ()):
                    if _orid == _rid:
                        continue
                    _op = roads_dense[_orid][_oi]
                    _d = float(np.hypot(_op[0] - _p[0], _op[1] - _p[1]))
                    if _d < 18.0 and (_best is None or _d < _best[0]):
                        _best = (_d, float(road_profiles[_orid][_oi]),
                                 _surf_by_id[_orid])
        if _best is None:
            continue
        _d, _other_h, _other_surf = _best
        _t = min(1.0, max(0.0, (18.0 - _d) / 14.0))
        _w = _t * _t * (3.0 - 2.0 * _t)
        if _surf_by_id[_rid] == "asphalt" and _other_surf != "asphalt":
            _w *= 0.15
        _delta = float(np.clip((_other_h - _prof[_i]) * _w, -2.2, 2.2))
        if _delta != 0.0:
            _prof[_i] += _delta
            _harmonised_points += 1
    road_profiles[_rid] = _prof
    _job = flatten_jobs[_rid]
    flatten_jobs[_rid] = (_job[0], _job[1], _prof, _job[3], _job[4],
                          _job[5])
print(f"[forest] junction harmonisation: {_harmonised_points} points")

# Crossing reconciliation (0.2.57): plan crossings on steep slopes
# can leave the two profiles tens of metres apart after independent
# grade limiting; the capped harmonisation above cannot close those
# gaps and the lower road ends with a wall across its deck (the
# birch tracks crossing the ring shelf climbed 20 m in 12 m).  Force
# agreed heights at true crossings with long approach ramps;
# asphalt keeps most of its height, dirt takes the long climb.
_closed_by_id = {r[0]: bool(r[6]) for r in ROAD_DEFS}
_prio_by_surf = {"asphalt": 3.0, "gravel": 1.0}


def _surf_prio(_rid):
    return _prio_by_surf.get(_surf_by_id[_rid], 0.6)


_recon = {}
for _rid, _dense in roads_dense.items():
    _s_cum = flatten_jobs[_rid][1]
    _protected = (list(bridge_s_ranges.get(_rid, []))
                  + list(tunnel_s_ranges.get(_rid, [])))
    for _i, _p in enumerate(_dense):
        if _in_protected(float(_s_cum[_i]), _protected, 30.0):
            continue
        _kx, _kz = int(_p[0] // 16), int(_p[1] // 16)
        _best = None
        for _gx in (_kx - 1, _kx, _kx + 1):
            for _gz in (_kz - 1, _kz, _kz + 1):
                for (_orid, _oi) in _jgrid.get((_gx, _gz), ()):
                    if _orid == _rid:
                        continue
                    _op = roads_dense[_orid][_oi]
                    _d = float(np.hypot(_op[0] - _p[0], _op[1] - _p[1]))
                    if _d < 5.0 and (_best is None or _d < _best[0]):
                        _best = (_d, _orid,
                                 float(road_profiles[_orid][_oi]))
        if _best is None:
            continue
        _mine = float(road_profiles[_rid][_i])
        if abs(_best[2] - _mine) <= 2.5:
            continue
        _wa, _wb = _surf_prio(_rid), _surf_prio(_best[1])
        _agreed = (_mine * _wa + _best[2] * _wb) / (_wa + _wb)
        _recon.setdefault(_rid, []).append(
            (float(_s_cum[_i]), _agreed))
_recon_applied = 0
for _rid, _pts in _recon.items():
    _prof = road_profiles[_rid].copy()
    _s_cum = flatten_jobs[_rid][1]
    _total = float(_s_cum[-1])
    _closed_r = _closed_by_id.get(_rid, False)
    _pts.sort()
    _clusters = []
    for (_sc, _ah) in _pts:
        if _clusters and _sc - _clusters[-1][0][-1] < 40.0:
            _clusters[-1][0].append(_sc)
            _clusters[-1][1].append(_ah)
        else:
            _clusters.append(([_sc], [_ah]))
    for (_ss, _aa) in _clusters:
        _s0 = float(np.mean(_ss))
        _target = float(np.median(_aa))
        for _i in range(len(_prof)):
            _ds = abs(float(_s_cum[_i]) - _s0)
            if _closed_r:
                _ds = min(_ds, _total - _ds)
            if _ds < 130.0:
                _w = 1.0 - float(smoothstep(12.0, 130.0, _ds))
                _prof[_i] += (_target - _prof[_i]) * _w
        _recon_applied += 1
    for _ in range(2):
        _prev = np.roll(_prof, 1)
        _next = np.roll(_prof, -1)
        if not _closed_r:
            _prev[0] = _prof[0]
            _next[-1] = _prof[-1]
        _prof = 0.25 * _prev + 0.5 * _prof + 0.25 * _next
    road_profiles[_rid] = _prof
    _job = flatten_jobs[_rid]
    flatten_jobs[_rid] = (_job[0], _job[1], _prof, _job[3], _job[4],
                          _job[5])
print(f"[forest] crossing reconciliation: {_recon_applied} crossings")

# Water-margin lift (0.2.57): no road profile may dip towards the
# water anywhere near the lake, swamp or river arms.  Player footage
# showed dirt tracks fording 1.6 m under the river surface and the
# riverbank road running below water level.  The lift is distance-
# ramped so approaches stay smooth; tunnel interiors are exempt.
_rgrid = {}
for (_rdense, _rwy) in RIVERS:
    for _i in range(len(_rdense)):
        _rp = (float(_rdense[_i][0]), float(_rdense[_i][1]),
               float(_rwy[_i]))
        _rgrid.setdefault((int(_rp[0] // 32), int(_rp[1] // 32)),
                          []).append(_rp)


def _water_floor(x, z):
    best = None
    dl = math.hypot((x - LAKE_X) / LAKE_RX, (z - LAKE_Z) / LAKE_RZ)
    if dl < 1.14:
        best = (LAKE_Y + 0.6, 1.0 - float(smoothstep(1.0, 1.14, dl)))
    ds = math.hypot((x - SWAMP_X) / SWAMP_RX, (z - SWAMP_Z) / SWAMP_RZ)
    if ds < 1.16 and (best is None or SWAMP_Y + 0.55 > best[0]):
        best = (SWAMP_Y + 0.55,
                1.0 - float(smoothstep(1.0, 1.16, ds)))
    kx, kz = int(x // 32), int(z // 32)
    nearest = None
    for gx in (kx - 1, kx, kx + 1):
        for gz in (kz - 1, kz, kz + 1):
            for (rx, rz, rwy) in _rgrid.get((gx, gz), ()):
                dd = math.hypot(rx - x, rz - z)
                if dd < 30.0 and (nearest is None or dd < nearest[0]):
                    nearest = (dd, rwy)
    if nearest is not None:
        fy = nearest[1] + 0.65
        if best is None or fy > best[0]:
            best = (fy, 1.0 - float(smoothstep(10.0, 28.0,
                                               nearest[0])))
    return best


_lifted_points = 0
for _rid, _dense in roads_dense.items():
    _prof = road_profiles[_rid].copy()
    _s_cum = flatten_jobs[_rid][1]
    _tun = list(tunnel_s_ranges.get(_rid, []))
    _changed = False
    for _i, _p in enumerate(_dense):
        if _in_protected(float(_s_cum[_i]), _tun, 12.0):
            continue
        _fl = _water_floor(float(_p[0]), float(_p[1]))
        if _fl is None:
            continue
        _fy, _w = _fl
        if _prof[_i] < _fy and _w > 0.01:
            _prof[_i] += (_fy - _prof[_i]) * _w
            _changed = True
            _lifted_points += 1
    if _changed:
        for _ in range(2):
            _prev = np.roll(_prof, 1)
            _next = np.roll(_prof, -1)
            if not _closed_by_id.get(_rid, False):
                _prev[0] = _prof[0]
                _next[-1] = _prof[-1]
            _prof = 0.25 * _prev + 0.5 * _prof + 0.25 * _next
    road_profiles[_rid] = _prof
    _job = flatten_jobs[_rid]
    flatten_jobs[_rid] = (_job[0], _job[1], _prof, _job[3], _job[4],
                          _job[5])
print(f"[forest] water-margin lift: {_lifted_points} points")

# Terrain flattening for every road (was inline in the profile loop).
for (rid, _name, _ctrl, _width, _lanes, _surf, _closed, _spd) in ROAD_DEFS:
    dense, s_cum, prof, half_w, falloff, skip_ranges = flatten_jobs[rid]

    def make_fn0(prof=prof, s_cum=s_cum, half_w=half_w,
                 falloff=falloff, skip_ranges=skip_ranges):
        def fn(sub, dist, s):
            target_h = np.interp(s, s_cum, prof)
            w = 1.0 - smoothstep(half_w + 3.0, half_w + falloff, dist)
            for (a, b) in skip_ranges:
                w = np.where((s > a) & (s < b), 0.0, w)
            return sub * (1.0 - w) + target_h * w
        return fn

    _polyline_local_op_s(H, dense, half_w + falloff + STEP, make_fn0(), s_cum)

# Asphalt corridors win at junctions (see desert generator note).
for (rid, _name, _ctrl, _width, _lanes, surf, _closed, _spd) in ROAD_DEFS:
    if surf != "asphalt":
        continue
    dense, s_cum, prof, half_w, falloff, skip_ranges = flatten_jobs[rid]

    def make_fn2(prof=prof, s_cum=s_cum, half_w=half_w,
                 falloff=falloff, skip_ranges=skip_ranges):
        def fn(sub, dist, s):
            target_h = np.interp(s, s_cum, prof)
            w = 1.0 - smoothstep(half_w + 3.0, half_w + falloff, dist)
            for (a, b) in skip_ranges:
                w = np.where((s > a) & (s < b), 0.0, w)
            return sub * (1.0 - w) + target_h * w
        return fn

    _polyline_local_op_s(H, dense, half_w + falloff + STEP, make_fn2(), s_cum)

# Final corridor clamp (0.2.57): after every flatten pass, guarantee
# terrain never pokes through a road deck.  Later roads used to
# re-raise earlier corridors with their falloff skirts (a 5.4 m hill
# buried the ring bridge at 800,880).  min() only ever lowers cells,
# so bridge spans keep their carved riverbeds; tunnels are exempt.
for (rid, _name, _ctrl, _width, _lanes, _surf, _closed, _spd) in ROAD_DEFS:
    dense, s_cum, prof, half_w, falloff, skip_ranges = flatten_jobs[rid]
    _tun_ranges = list(tunnel_s_ranges.get(rid, []))

    def make_clamp(prof=prof, s_cum=s_cum, half_w=half_w,
                   tun_ranges=_tun_ranges):
        def fn(sub, dist, s):
            target = np.interp(s, s_cum, prof) - 0.04
            w = 1.0 - smoothstep(half_w + 1.2, half_w + 4.0, dist)
            for (a, b) in tun_ranges:
                w = np.where((s > a - 8.0) & (s < b + 8.0), 0.0, w)
            # Shave-only cap: where another road's corridor crosses
            # this one at a divergent height (mountain plan crossings)
            # the terrain belongs to the higher road; never trench
            # more than 6 m towards this road's profile.
            capped = np.where(sub - target <= 6.0,
                              np.minimum(sub, target), sub)
            return sub * (1.0 - w) + capped * w
        return fn

    _polyline_local_op_s(H, dense, half_w + 4.0 + STEP, make_clamp(),
                         s_cum)
print("[forest] corridor clamp applied")

roads_out = []
road_samples_by_id = {}
for (rid, name, _ctrl, width, lanes, surf, closed, spd) in ROAD_DEFS:
    dense = roads_dense[rid]
    samples_pts = resample_even(dense, 10.0)
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
        "id": "gf-" + rid, "name": name, "widthM": width, "lanes": lanes,
        "speedLimitKmh": spd, "surface": surf, "closed": bool(closed),
        "samples": samples,
    })

road_length_total = 0.0
for r in roads_out:
    pts = np.array([[s[0], s[2]] for s in r["samples"]])
    road_length_total += float(np.sum(np.linalg.norm(np.diff(pts, axis=0), axis=1)))
print(f"[forest] roads total length: {road_length_total/1000.0:.1f} km")

print("[forest] road/river distance rasters ...")
road_dist = np.full((N, N), 260.0)
for rid, dense in roads_dense.items():
    def d_fn(sub, dist, s):
        return np.minimum(sub, dist)
    polyline_local_op(road_dist, dense, 260.0, d_fn)

river_dist = np.full((N, N), 160.0)
for (_rd, _wy) in RIVERS:
    def d_fn2(sub, dist, s):
        return np.minimum(sub, dist)
    polyline_local_op(river_dist, _rd, 160.0, d_fn2)

gy, gx = np.gradient(H, STEP)
slope_grid = np.hypot(gx, gy)
grove_grid = fbm([24, 48], 2027)


def height_at(x, z):
    return bilinear(H, x, z)


def slope_at(x, z):
    return bilinear(slope_grid, x, z)


def road_dist_at(x, z):
    return bilinear(road_dist, x, z)


def river_dist_at(x, z):
    return bilinear(river_dist, x, z)


def grove_at(x, z):
    return bilinear(grove_grid, x, z)

def segment_points(x, z, yaw, length, step=1.0):
    """Sample points along a fence segment (builder basis: local +X)."""
    dx, dz = math.cos(yaw), -math.sin(yaw)
    n = max(2, int(length / step) + 1)
    return [(x + dx * (-length * 0.5 + length * i / n),
             z + dz * (-length * 0.5 + length * i / n)) for i in range(n + 1)]


def segment_clear_of_roads(x, z, yaw, length, clearance):
    """True when EVERY point of the segment stays at least
    `clearance` metres from any road centreline.  The old town
    fences only tested the segment centre with 5 m, so 14 m long
    fences ended with their ends on the carriageway (0.2.51)."""
    return all(road_dist_at(px, pz) >= clearance
               for (px, pz) in segment_points(x, z, yaw, length))

# Exact polyline clearance: the raster above is 8 m bilinear and
# can be a couple of metres off next to diagonal roads.  Segments
# are built lazily from roads_out on first use.
_EXACT_CACHE = {}


def _exact_segments():
    if "A" not in _EXACT_CACHE:
        A, B, HW = [], [], []
        for r in roads_out:
            pts = [(float(smp[0]), float(smp[2])) for smp in r["samples"]]
            if r.get("closed") and pts:
                pts = pts + [pts[0]]
            hw = float(r["widthM"]) * 0.5
            for a, b in zip(pts[:-1], pts[1:]):
                A.append(a)
                B.append(b)
                HW.append(hw)
        _EXACT_CACHE["A"] = np.array(A)
        _EXACT_CACHE["B"] = np.array(B)
        _EXACT_CACHE["HW"] = np.array(HW)
    return _EXACT_CACHE["A"], _EXACT_CACHE["B"], _EXACT_CACHE["HW"]


def exact_edge_clearances(points):
    """Per-point distance to nearest road EDGE (negative = on it)."""
    A, B, HW = _exact_segments()
    AB = B - A
    L2 = np.maximum((AB ** 2).sum(1), 1e-9)
    P = np.array(points, dtype=np.float64)
    best = np.full(len(P), 1e9)
    for j in range(0, len(A), 1500):
        a = A[j:j + 1500]
        ab = AB[j:j + 1500]
        l2 = L2[j:j + 1500]
        hw = HW[j:j + 1500]
        t = np.clip(((P[:, None, :] - a[None, :, :]) * ab[None, :, :]).sum(-1) / l2[None, :], 0, 1)
        proj = a[None, :, :] + t[:, :, None] * ab[None, :, :]
        d = np.linalg.norm(P[:, None, :] - proj, axis=-1) - hw[None, :]
        best = np.minimum(best, d.min(axis=1))
    return best


def exact_edge_clearance(points):
    """(min clearance to any road EDGE, nearest road point)."""
    A, B, HW = _exact_segments()
    AB = B - A
    L2 = np.maximum((AB ** 2).sum(1), 1e-9)
    P = np.array(points, dtype=np.float64)
    best = np.full(len(P), 1e9)
    best_pt = np.zeros((len(P), 2))
    for j in range(0, len(A), 1500):
        a = A[j:j + 1500]
        ab = AB[j:j + 1500]
        l2 = L2[j:j + 1500]
        hw = HW[j:j + 1500]
        t = np.clip(((P[:, None, :] - a[None, :, :]) * ab[None, :, :]).sum(-1) / l2[None, :], 0, 1)
        proj = a[None, :, :] + t[:, :, None] * ab[None, :, :]
        d = np.linalg.norm(P[:, None, :] - proj, axis=-1) - hw[None, :]
        k = np.argmin(d, axis=1)
        dk = d[np.arange(len(P)), k]
        upd = dk < best
        if upd.any():
            best[upd] = dk[upd]
            best_pt[upd] = proj[np.arange(len(P))[upd], k[upd]]
    i = int(np.argmin(best))
    return float(best[i]), best_pt[i]


def exact_nearest_road(points):
    """Per-point (edge clearance, nearest centreline point, segment dir).

    Chunked in both dimensions so the 0.2.53 scatter audit can run it
    over tens of thousands of instances without materialising a
    points-by-segments array for the whole world at once.
    """
    A, B, HW = _exact_segments()
    AB = B - A
    L2 = np.maximum((AB ** 2).sum(1), 1e-9)
    seg_len = np.sqrt(L2)
    P = np.array(points, dtype=np.float64).reshape(-1, 2)
    best = np.full(len(P), 1e9)
    best_pt = np.zeros((len(P), 2))
    best_dir = np.tile(np.array([1.0, 0.0]), (len(P), 1))
    for p0 in range(0, len(P), 384):
        pp = P[p0:p0 + 384]
        local_best = np.full(len(pp), 1e9)
        local_pt = np.zeros((len(pp), 2))
        local_dir = np.tile(np.array([1.0, 0.0]), (len(pp), 1))
        rows = np.arange(len(pp))
        for j in range(0, len(A), 1000):
            a = A[j:j + 1000]
            ab = AB[j:j + 1000]
            l2 = L2[j:j + 1000]
            hw = HW[j:j + 1000]
            t = np.clip(((pp[:, None, :] - a[None, :, :]) * ab[None, :, :]).sum(-1) / l2[None, :], 0, 1)
            proj = a[None, :, :] + t[:, :, None] * ab[None, :, :]
            d = np.linalg.norm(pp[:, None, :] - proj, axis=-1) - hw[None, :]
            k = np.argmin(d, axis=1)
            dk = d[rows, k]
            upd = dk < local_best
            if upd.any():
                upd_rows = rows[upd]
                upd_k = k[upd]
                local_best[upd] = dk[upd]
                local_pt[upd] = proj[upd_rows, upd_k]
                local_dir[upd] = ab[upd_k] / np.maximum(seg_len[j:j + 1000][upd_k][:, None], 1e-9)
        best[p0:p0 + len(pp)] = local_best
        best_pt[p0:p0 + len(pp)] = local_pt
        best_dir[p0:p0 + len(pp)] = local_dir
    return best, best_pt, best_dir


# ---------------------------------------------------------------- scatter
print("[forest] scatter placement ...")
road_pick = []
for rid, dense in roads_dense.items():
    lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    road_pick.append((rid, dense, np.concatenate([[0.0], np.cumsum(lens)])))
road_pick_total = sum(float(c[-1]) for _r, _d, c in road_pick)
road_pick_starts = []
_acc_pick = 0.0
for _r, _d, _c in road_pick:
    road_pick_starts.append(_acc_pick)
    _acc_pick += float(_c[-1])


def random_road_point():
    pick = rng.random() * road_pick_total
    for _pi, (_rid, dense, cum) in enumerate(road_pick):
        local_pick = pick - road_pick_starts[_pi]
        if 0.0 <= local_pick <= cum[-1]:
            pick = local_pick
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


def scatter(count, accept, along_ratio=0.45, min_road_dist=9.5, max_attempts_factor=36):
    out = []
    attempts = 0
    max_attempts = count * max_attempts_factor
    while len(out) < count and attempts < max_attempts:
        attempts += 1
        if rng.random() < along_ratio:
            p, perp = random_road_point()
            off = (min_road_dist + float(rng.exponential(60.0))) * (1 if rng.random() < 0.5 else -1)
            off = float(np.clip(off, -170.0, 170.0))
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


def _land_ok(x, z, max_slope=0.65):
    if lake_d(x, z) < 1.03 or in_fields(x, z, 2.0):
        return False
    if river_dist_at(x, z) < 9.0:
        return False
    if slope_at(x, z) > max_slope:
        return False
    if lake_d(x, z) < 1.35 and height_at(x, z) < LAKE_Y + 0.35:
        return False
    return True


def _zone_prob(table):
    def acc(x, z):
        if not _land_ok(x, z):
            return False
        return rng.random() < table.get(zone_of(x, z), 0.0)
    return acc


scatter_data = {}
# Trees (~39k).  Species mix target: spruce/pine in the north hills,
# mixed broadleaf in the dark forest, birch in the east, lone oaks in
# the meadows, crooked dead pines in the swamp.
scatter_data["spruce"] = mk_instances(scatter(15000, _zone_prob(
    {"hills": 0.95, "dark": 0.80, "grove": 0.35, "birch": 0.15, "sawmill": 0.25, "meadow": 0.01, "farm": 0.02})), 0.8, 1.5)
scatter_data["pine"] = mk_instances(scatter(8000, _zone_prob(
    {"hills": 0.80, "dark": 0.55, "grove": 0.40, "birch": 0.35, "sawmill": 0.40, "meadow": 0.02, "swamp": 0.20})), 0.8, 1.45)
scatter_data["leafy"] = mk_instances(scatter(9500, _zone_prob(
    {"dark": 0.90, "grove": 0.70, "birch": 0.40, "hills": 0.25, "meadow": 0.03, "farm": 0.12, "sawmill": 0.20})), 0.8, 1.4)
scatter_data["birch"] = mk_instances(scatter(4200, _zone_prob(
    {"birch": 0.95, "grove": 0.30, "dark": 0.25, "meadow": 0.04, "hills": 0.10})), 0.85, 1.35)
scatter_data["oak"] = mk_instances(scatter(800, _zone_prob(
    {"meadow": 0.70, "farm": 0.35, "grove": 0.30, "dark": 0.08, "birch": 0.15})), 0.9, 1.6)
scatter_data["dead_tree"] = mk_instances(scatter(500, _zone_prob(
    {"swamp": 0.90, "dark": 0.30, "hills": 0.10})), 0.8, 1.3)
# Undergrowth and ground detail.
scatter_data["bush"] = mk_instances(scatter(18000, _zone_prob(
    {"dark": 0.90, "hills": 0.75, "grove": 0.65, "birch": 0.60, "meadow": 0.35, "farm": 0.25, "sawmill": 0.40, "swamp": 0.35}),
    min_road_dist=8.5), 0.7, 1.5)
scatter_data["fern"] = mk_instances(scatter(12000, _zone_prob(
    {"dark": 0.95, "hills": 0.60, "birch": 0.50, "grove": 0.25}), min_road_dist=8.0), 0.8, 1.4)
scatter_data["flower"] = mk_instances(scatter(5000, _zone_prob(
    {"meadow": 0.95, "farm": 0.25, "grove": 0.20, "birch": 0.15}), min_road_dist=8.0), 0.8, 1.3)
scatter_data["mushroom"] = mk_instances(scatter(1500, lambda x, z: _land_ok(x, z, 0.4) and rng.random() < {"dark": 0.9, "hills": 0.5}.get(zone_of(x, z), 0.0),
    min_road_dist=8.0), 0.8, 1.3)
scatter_data["rock_small"] = mk_instances(scatter(9000, lambda x, z: _land_ok(x, z, 1.4) and (
    rng.random() < (0.9 if 8.0 <= river_dist_at(x, z) <= 24.0 else {"hills": 0.8, "dark": 0.5, "grove": 0.45, "meadow": 0.3, "birch": 0.4, "farm": 0.15, "sawmill": 0.4, "swamp": 0.2}.get(zone_of(x, z), 0.3))),
    min_road_dist=8.0), 0.7, 1.6)
scatter_data["rock_medium"] = mk_instances(scatter(1200, lambda x, z: _land_ok(x, z, 1.6) and (slope_at(x, z) > 0.15 or rng.random() < 0.3) and rng.random() < {"hills": 0.85, "grove": 0.4, "dark": 0.45}.get(zone_of(x, z), 0.25),
    min_road_dist=9.0), 0.8, 1.5)
scatter_data["rock_large"] = mk_instances(scatter(140, lambda x, z: _land_ok(x, z, 1.8) and slope_at(x, z) > 0.28 and zone_of(x, z) in ("hills", "grove"),
    min_road_dist=10.0), 0.9, 1.6)
scatter_data["stump"] = mk_instances(scatter(700, lambda x, z: _land_ok(x, z, 0.5) and (in_clearcut(x, z) or rng.random() < {"dark": 0.3, "sawmill": 0.5}.get(zone_of(x, z), 0.05)),
    min_road_dist=8.0), 0.8, 1.3)
scatter_data["fallen_log"] = mk_instances(scatter(700, _zone_prob(
    {"dark": 0.80, "hills": 0.50, "sawmill": 0.60, "grove": 0.20}), min_road_dist=8.5), 0.8, 1.3)
scatter_data["hay_bale"] = mk_instances(scatter(220, _zone_prob(
    {"farm": 0.90, "meadow": 0.50}), min_road_dist=9.0), 0.9, 1.1)

# Reeds: only on the real shoreline band of the lake and river banks.
reed_pts = []
_attempts = 0
while len(reed_pts) < 1650 and _attempts < 60000:
    _attempts += 1
    ang = rng.random() * math.tau
    dd = float(rng.uniform(0.96, 1.07))
    x = LAKE_X + math.cos(ang) * LAKE_RX * dd
    z = LAKE_Z + math.sin(ang) * LAKE_RZ * dd
    if road_dist_at(x, z) < 10.0:
        continue
    if LAKE_Y - 0.8 <= height_at(x, z) <= LAKE_Y + 0.55:
        reed_pts.append((float(x), float(z)))
for (_rd, _wy) in RIVERS:
    _attempts = 0
    _target = 300
    _got = 0
    while _got < _target and _attempts < 20000:
        _attempts += 1
        i = int(rng.integers(2, len(_rd) - 2))
        a, b = _rd[i - 1], _rd[i + 1]
        d = b - a
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        perp = np.array([-d[1], d[0]]) / n * (1 if rng.random() < 0.5 else -1)
        off = float(rng.uniform(6.5, 10.5))
        x = float(_rd[i][0] + perp[0] * off)
        z = float(_rd[i][1] + perp[1] * off)
        if not (30.0 < x < SIZE - 30.0 and 30.0 < z < SIZE - 30.0):
            continue
        if road_dist_at(x, z) < 10.0 or lake_d(x, z) < 1.0:
            continue
        h = height_at(x, z)
        if _wy[i] - 1.1 <= h <= _wy[i] + 0.9:
            reed_pts.append((x, z))
            _got += 1
scatter_data["reed"] = mk_instances(reed_pts, 0.85, 1.3)

# Crops: jittered rows inside the authored field rectangles.
for f in FIELDS:
    pts = []
    x0, x1 = f["x"] - f["w"] * 0.5 + 5.0, f["x"] + f["w"] * 0.5 - 5.0
    z0, z1 = f["z"] - f["d"] * 0.5 + 5.0, f["z"] + f["d"] * 0.5 - 5.0
    gx = x0
    while gx < x1:
        gz = z0
        while gz < z1:
            px = gx + float(rng.uniform(-1.6, 1.6))
            pz = gz + float(rng.uniform(-1.6, 1.6))
            if road_dist_at(px, pz) >= 7.0 and river_dist_at(px, pz) >= 8.0:
                pts.append([round(px, 1), round(pz, 1),
                            round(float(rng.uniform(0.85, 1.2)), 2),
                            round(float(rng.uniform(-0.12, 0.12)), 2)])
            gz += 6.5
        gx += 6.5
    scatter_data[f["crop"]] = scatter_data.get(f["crop"], []) + pts

# Authored singles: the island pine and the giant meadow oak.
scatter_data["pine"].append([ISLAND_X, ISLAND_Z, 1.7, 0.7])
scatter_data["pine"].append([ISLAND_X + 26.0, ISLAND_Z + 14.0, 0.9, 2.4])
scatter_data["oak"].append([1900.0, 2150.0, 2.7, 1.1])

# Grass tufts (0.2.57): geometric ground cover in the Forza style —
# ambient meadow/clearing tufts plus a dedicated road-verge pass so
# every roadside reads alive at driving distance.
def _grass_ok(x, z):
    if lake_d(x, z) < 1.02 or river_dist_at(x, z) < 6.0:
        return False
    if slope_at(x, z) > 0.55:
        return False
    if lake_d(x, z) < 1.30 and height_at(x, z) < LAKE_Y + 0.30:
        return False
    if swamp_d(x, z) < 1.05 and height_at(x, z) < SWAMP_Y + 0.30:
        return False
    return True


def _grass_zone(x, z):
    if not _grass_ok(x, z) or in_fields(x, z, 1.0):
        return False
    table = {"meadow": 0.95, "farm": 0.45, "grove": 0.38,
             "birch": 0.34, "dark": 0.14, "hills": 0.28,
             "sawmill": 0.30, "swamp": 0.18}
    return rng.random() < table.get(zone_of(x, z), 0.0)


_grass_pts = scatter(24000, _grass_zone, along_ratio=0.35,
                     min_road_dist=7.0)
_width_by_id = {r[0]: float(r[3]) for r in ROAD_DEFS}
for _rid, _dense in roads_dense.items():
    _hw = _width_by_id[_rid] * 0.5
    for _i in range(1, len(_dense), 3):
        if rng.random() > 0.42:
            continue
        _a, _b = _dense[_i - 1], _dense[_i]
        _d = _b - _a
        _n = float(np.linalg.norm(_d))
        if _n < 1e-6:
            continue
        _perp = np.array([-_d[1], _d[0]]) / _n
        _side = 1.0 if rng.random() < 0.5 else -1.0
        _off = _side * (_hw + float(rng.uniform(1.1, 3.4)))
        _x = float(_b[0] + _perp[0] * _off)
        _z = float(_b[1] + _perp[1] * _off)
        if 30.0 < _x < SIZE - 30.0 and 30.0 < _z < SIZE - 30.0 \
                and _grass_ok(_x, _z):
            _grass_pts.append((_x, _z))
scatter_data["grass_tuft"] = mk_instances(_grass_pts, 0.8, 1.6)

print("[forest] scatter totals:", {k: len(v) for k, v in scatter_data.items()})

# --- exact scatter road audit (prefiltered by the distance raster) --
def _gf_scatter_margin(kind, scale):
    if kind in ("spruce", "pine", "birch", "leafy", "oak", "dead_tree"):
        return 1.50
    if kind == "rock_large":
        return 1.10 + 1.55 * scale
    if kind == "rock_medium":
        return 1.15
    if kind in ("fallen_log", "hay_bale", "bush"):
        return 1.05
    if kind == "grass_tuft":
        return 0.55
    if kind == "reed":
        return 0.90
    return 0.80


_sc_moved = 0
_sc_dropped = 0
for _kind in list(scatter_data.keys()):
    _items = scatter_data[_kind]
    if not _items:
        continue
    _cand_idx = [i for i, it in enumerate(_items) if road_dist_at(float(it[0]), float(it[1])) < 26.0]
    if not _cand_idx:
        continue
    _pts = np.array([[float(_items[i][0]), float(_items[i][1])] for i in _cand_idx], dtype=np.float64)
    _clear, _near, _dirs = exact_nearest_road(_pts)
    _drop = set()
    for _ci, _idx in enumerate(_cand_idx):
        _inst = _items[_idx]
        _req = _gf_scatter_margin(_kind, float(_inst[2]))
        _p = _pts[_ci].copy()
        _c = float(_clear[_ci])
        _n = _near[_ci].copy()
        _d = _dirs[_ci].copy()
        _moved = False
        for _attempt in range(6):
            if _c >= _req:
                break
            _away = _p - _n
            _ln = float(np.linalg.norm(_away))
            if _ln < 1e-5:
                _away = np.array([-_d[1], _d[0]])
                _ln = 1.0
            _away = _away / _ln
            _p = np.clip(_p + _away * ((_req - _c) + 0.35), 32.0, SIZE - 32.0)
            _moved = True
            _cc, _nn, _dd = exact_nearest_road([_p])
            _c = float(_cc[0])
            _n = _nn[0].copy()
            _d = _dd[0].copy()
        if _c < _req or (_kind != "reed" and lake_d(float(_p[0]), float(_p[1])) < 1.0):
            _drop.add(_idx)
            _sc_dropped += 1
            continue
        if _moved:
            _sc_moved += 1
            _items[_idx] = [round(float(_p[0]), 1), round(float(_p[1]), 1), _inst[2], _inst[3]]
    if _drop:
        scatter_data[_kind] = [it for i, it in enumerate(_items) if i not in _drop]
print(f"[forest] exact scatter audit: moved {_sc_moved}, dropped {_sc_dropped}")

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



# ---------------------------------------------------------------- structures
print("[forest] structures ...")
structures = []
buildings = []


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
        buildings.append(s)
    return s


def _front_yaw(fx, fz):
    return math.atan2(-fx, -fz)


def _roadside_houses(road_id, count, spacing, offset, kind="house"):
    dense = roads_dense[road_id]
    lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(lens)])
    placed = 0
    s = spacing * 0.6
    side = 1.0
    while s < cum[-1] - 20.0 and placed < count:
        i = int(np.searchsorted(cum, s))
        i = min(max(i, 1), len(dense) - 1)
        a, b = dense[i - 1], dense[i]
        d = b - a
        n = np.linalg.norm(d)
        if n < 1e-6:
            s += spacing
            continue
        perp = np.array([-d[1], d[0]]) / n
        t = 0.0 if cum[i] == cum[i - 1] else (s - cum[i - 1]) / (cum[i] - cum[i - 1])
        p = a + (b - a) * t
        hx = float(p[0] + perp[0] * offset * side)
        hz = float(p[1] + perp[1] * offset * side)
        front = -perp * side
        yaw = _front_yaw(float(front[0]), float(front[1]))
        w = float(rng.uniform(8.5, 11.5))
        dep = float(rng.uniform(7.5, 10.0))
        h = float(rng.uniform(3.8, 5.2))
        if road_dist_at(hx, hz) >= offset - 3.5 and slope_at(hx, hz) < 0.45 and lake_d(hx, hz) > 1.05:
            add_structure(kind, hx, hz, yaw, round(w, 1), round(dep, 1), round(h, 1))
            # front-yard fence parallel to the facade, street side
            fx = hx + float(front[0]) * (dep * 0.5 + 3.2)
            fz = hz + float(front[1]) * (dep * 0.5 + 3.2)
            if segment_clear_of_roads(fx, fz, yaw, w + 3.0, 7.0):
                add_structure("fence", fx, fz, yaw, round(w + 3.0, 1), 0.3, 1.1, building=False)
            placed += 1
        side = -side
        s += spacing * float(rng.uniform(0.85, 1.3))
    return placed


# Village by the lake (east shore): houses, cafe, fuel, garage, church.
_village_houses = _roadside_houses("village_main", 14, 33.0, 15.0)
_village_houses += _roadside_houses("village_cross", 6, 36.0, 14.0)
add_structure("diner", 3558.0, 2090.0, _front_yaw(-0.85, 0.2), 16, 10, 4.4, name="Кафе «Причал»")
add_structure("gas_station", 3685.0, 2235.0, _front_yaw(-1.0, 0.0), 17, 12, 5, name="Заправка «Лесная»")
add_structure("garage", 3668.0, 2145.0, _front_yaw(-1.0, 0.1), 19, 13, 5.5, name="Гараж посёлка")
add_structure("church", 3542.0, 2320.0, _front_yaw(0.9, -0.2), 11, 18, 8.5, name="Церквушка у озера")
add_structure("pier", 3478.0, 2220.0, math.pi / 2, 18, 3.2, 1.2, name="Пристань", building=False)
add_structure("lighthouse", 3445.0, 2485.0, 0.4, 5, 5, 17, name="Маяк на озере")
add_structure("water_tower", 3720.0, 2050.0, 0.0, 7, 7, 20, name="Водокачка посёлка")
for _i in range(6):
    add_structure("town_pole", 3560.0 + (_i % 2) * 26.0, 1960.0 + _i * 82.0, 0.3, 0.4, 0.4, 6.5, building=False)

# Farmstead (south valley).
FARM_C = (2070.0, 3460.0)
add_structure("ranch_house", FARM_C[0] - 45.0, FARM_C[1] - 30.0, _front_yaw(0.0, -1.0), 13, 10, 5.2, name="Фермерский дом")
add_structure("barn", FARM_C[0] + 10.0, FARM_C[1] - 38.0, _front_yaw(0.0, -1.0), 20, 12, 7, name="Большой амбар")
add_structure("barn", FARM_C[0] + 48.0, FARM_C[1] + 6.0, _front_yaw(-1.0, 0.0), 16, 10, 6)
add_structure("warehouse", FARM_C[0] - 52.0, FARM_C[1] + 28.0, _front_yaw(0.0, 1.0), 22, 13, 6)
add_structure("shed", FARM_C[0] + 30.0, FARM_C[1] + 40.0, _front_yaw(0.0, 1.0), 10, 7, 3.6)
add_structure("shed", FARM_C[0] - 8.0, FARM_C[1] + 48.0, _front_yaw(0.0, 1.0), 8, 6, 3.2)
add_structure("silo", FARM_C[0] + 38.0, FARM_C[1] - 34.0, 0.0, 6.5, 6.5, 19, name="Силосная башня")
add_structure("silo", FARM_C[0] + 47.0, FARM_C[1] - 30.0, 0.0, 5.5, 5.5, 16)
add_structure("windmill", FARM_C[0] - 70.0, FARM_C[1] - 55.0, 0.7, 3, 3, 11, name="Ветряная мельница", building=False)
for _i in range(6):
    add_structure("greenhouse", FARM_C[0] - 88.0 + (_i % 3) * 17.0, FARM_C[1] + 6.0 + (_i // 3) * 13.0,
                  0.0, 14, 6, 3.4, building=False)
add_structure("tractor", FARM_C[0] + 6.0, FARM_C[1] - 12.0, 0.9, 2.4, 5.2, 2.8, building=False)
add_structure("tractor", 1720.0, 3220.0, -0.4, 2.4, 5.2, 2.8, building=False)
# Farmstead perimeter fence (~640 m) + two field-edge runs (~500 m).
_fx0, _fz0, _fx1, _fz1 = FARM_C[0] - 95.0, FARM_C[1] - 65.0, FARM_C[0] + 75.0, FARM_C[1] + 62.0
add_structure("fence", (_fx0 + _fx1) * 0.5 - 46.0, _fz0, 0.0, 78.0, 0.3, 1.1, building=False)
add_structure("fence", (_fx0 + _fx1) * 0.5 + 44.0, _fz0, 0.0, 80.0, 0.3, 1.1, building=False)
add_structure("fence", (_fx0 + _fx1) * 0.5, _fz1, 0.0, round(_fx1 - _fx0, 1), 0.3, 1.1, building=False)
add_structure("fence", _fx0, (_fz0 + _fz1) * 0.5, -math.pi / 2, round(_fz1 - _fz0, 1), 0.3, 1.1, building=False)
add_structure("fence", _fx1, (_fz0 + _fz1) * 0.5, -math.pi / 2, round(_fz1 - _fz0, 1), 0.3, 1.1, building=False)
add_structure("fence", 1580.0, 3024.0, 0.0, 296.0, 0.3, 1.1, building=False)
add_structure("fence", 2380.0, 3032.0, 0.0, 276.0, 0.3, 1.1, building=False)
add_structure("fence", 1900.0, 3760.0, 0.0, 500.0, 0.3, 1.1, building=False)

# Sawmill (south-west).
SAW_C = (920.0, 3520.0)
add_structure("sawmill_hall", SAW_C[0], SAW_C[1] - 25.0, _front_yaw(0.0, 1.0), 34, 14, 7.5, name="Пилорама")
add_structure("warehouse", SAW_C[0] - 55.0, SAW_C[1] + 5.0, _front_yaw(1.0, 0.0), 24, 13, 6)
add_structure("warehouse", SAW_C[0] + 58.0, SAW_C[1] + 18.0, _front_yaw(-1.0, 0.0), 20, 12, 5.5)
add_structure("office", SAW_C[0] - 30.0, SAW_C[1] - 52.0, _front_yaw(0.0, -1.0), 12, 8, 4.2, name="Контора лесопилки")
add_structure("shed", SAW_C[0] + 34.0, SAW_C[1] - 48.0, _front_yaw(0.0, -1.0), 11, 7, 3.4)
for _i in range(15):
    _lx = SAW_C[0] - 70.0 + float(rng.uniform(0.0, 150.0))
    _lz = SAW_C[1] + 32.0 + float(rng.uniform(0.0, 55.0))
    if road_dist_at(_lx, _lz) >= 9.0:
        add_structure("log_stack", _lx, _lz, float(rng.uniform(-0.15, 0.15)) + (0.0 if _i % 2 else math.pi / 2),
                      round(float(rng.uniform(7.0, 11.0)), 1), 3.2, 2.6, building=False)
add_structure("log_truck", SAW_C[0] - 12.0, SAW_C[1] + 8.0, 1.2, 2.6, 9.5, 3.4, building=False)
add_structure("log_truck", SAW_C[0] + 44.0, SAW_C[1] - 6.0, -0.5, 2.6, 9.5, 3.4, building=False)
for _i in range(8):
    add_structure("crate" if _i % 2 else "barrel_group",
                  SAW_C[0] + float(rng.uniform(-60.0, 60.0)), SAW_C[1] + float(rng.uniform(-40.0, 30.0)),
                  float(rng.random() * math.tau), 1.6, 1.6, 1.2, building=False)

# Summit viewpoint, waterfall, watchtowers, lonely cabins.
add_structure("viewpoint", SUMMIT[0] + 16.0, SUMMIT[1] + 10.0, 2.6, 9, 7, 3.8, name="Смотровая площадка", building=False)
add_structure("waterfall", WATERFALL[0], WATERFALL[1], -1.2, 14, 2, 26, name="Водопад", building=False)
for (_wx, _wz, _wn) in [(760.0, 1150.0, "Вышка Тёмного леса"), (2350.0, 520.0, "Вышка Хребта"),
                        (1250.0, 2620.0, "Вышка у болота"), (1150.0, 3360.0, "Вышка лесопилки")]:
    add_structure("viewpoint", _wx, _wz, float(rng.random() * math.tau), 5, 5, 9.5, name=_wn, building=False)
_cabins = 0
_attempts = 0
while _cabins < 8 and _attempts < 400:
    _attempts += 1
    _p, _perp = random_road_point()
    _off = float(rng.uniform(24.0, 55.0)) * (1 if rng.random() < 0.5 else -1)
    _cx = float(_p[0] + _perp[0] * _off)
    _cz = float(_p[1] + _perp[1] * _off)
    if not (60.0 < _cx < SIZE - 60.0 and 60.0 < _cz < SIZE - 60.0):
        continue
    if zone_of(_cx, _cz) not in ("dark", "hills", "grove", "birch"):
        continue
    if slope_at(_cx, _cz) > 0.3 or lake_d(_cx, _cz) < 1.1 or road_dist_at(_cx, _cz) < 20.0:
        continue
    _front = -_perp * (1 if _off > 0 else -1)
    add_structure("house", _cx, _cz, _front_yaw(float(_front[0]), float(_front[1])),
                  round(float(rng.uniform(6.5, 8.5)), 1), round(float(rng.uniform(5.5, 7.5)), 1),
                  round(float(rng.uniform(3.2, 4.0)), 1))
    _cabins += 1

# Power poles along the ring, billboards, road signs.
ring_dense = roads_dense["ring"]
_lens = np.linalg.norm(np.diff(ring_dense, axis=0), axis=1)
ring_cum = np.concatenate([[0.0], np.cumsum(_lens)])
_ring_half = 5.5
for (px, pz, pyaw, _cx, _cz, _s) in walk_polyline(ring_dense, ring_cum, 56.0, _ring_half + 3.4, jitter=0.08):
    _skip = False
    for (_a, _b) in tunnel_s_ranges.get("ring", []) + bridge_s_ranges.get("ring", []):
        if _a - 15.0 < _s < _b + 15.0:
            _skip = True
    if _skip:
        continue
    add_structure("power_pole", px, pz, pyaw, 0.5, 0.5, 11.5, building=False)
for (bx, bz, byaw, _cx, _cz, _s) in walk_polyline(ring_dense, ring_cum, 980.0, 15.0, jitter=0.2)[:6]:
    add_structure("billboard", bx, bz, byaw + math.pi / 2, 11, 0.6, 7.5, building=False)

_road_width_by_id = {r[0]: float(r[3]) for r in ROAD_DEFS}
_sign_counter = 0
_smash_left = 15
for rid, dense in roads_dense.items():
    lens = np.linalg.norm(np.diff(dense, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(lens)])
    _off = _road_width_by_id.get(rid, 8.0) * 0.5 + 1.35
    for (sx, sz, syaw, _cx, _cz, _s) in walk_polyline(dense, cum, 340.0, _off, jitter=0.4):
        _sign_counter += 1
        if _smash_left > 0 and _sign_counter % 9 == 0:
            add_structure("sign_smash", sx, sz, syaw, 1.1, 0.3, 2.6, building=False)
            _smash_left -= 1
        else:
            add_structure("sign", sx, sz, syaw, 1.1, 0.3, 2.6, building=False)

# Irrigation pipe lines across two fields (kept off roads by design).
pipes = []
for (_px0, _pz0, _px1, _pz1) in [(1460.0, 3080.0, 1700.0, 3160.0), (1900.0, 3540.0, 2180.0, 3680.0),
                                 (2280.0, 3080.0, 2480.0, 3160.0)]:
    _steps = 8
    for _i in range(_steps):
        _t0 = _i / _steps
        _t1 = (_i + 1) / _steps
        pipes.append([round(_px0 + (_px1 - _px0) * _t0, 1), round(_pz0 + (_pz1 - _pz0) * _t0, 1),
                      round(_px0 + (_px1 - _px0) * _t1, 1), round(_pz0 + (_pz1 - _pz0) * _t1, 1)])

print(f"[forest] structures: {len(structures)} (village houses {_village_houses}, signs {_sign_counter})")

# Guardrails where the road edge drops away (serpentine, cliff, dam).
guardrails = []
for (rid, _n, _c, width, _l, _sf, _cl, _sp) in ROAD_DEFS:
    if rid not in ("serpentine", "cliff_road", "ridge", "ring", "dam_road", "lake_loop"):
        continue
    dense = roads_dense[rid]
    half = width * 0.5
    for i in range(0, len(dense) - 2, 2):
        a, b = dense[i], dense[i + 2]
        d = b - a
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        perp = np.array([-d[1], d[0]]) / n
        mid = (a + b) * 0.5
        for side in (1.0, -1.0):
            edge = mid + perp * (half + 1.1) * side
            drop_pt = mid + perp * (half + 11.0) * side
            if height_at(float(edge[0]), float(edge[1])) - height_at(float(drop_pt[0]), float(drop_pt[1])) > 3.2:
                a_e = a + perp * (half + 1.1) * side
                b_e = b + perp * (half + 1.1) * side
                guardrails.append([round(float(a_e[0]), 1), round(float(a_e[1]), 1),
                                   round(float(b_e[0]), 1), round(float(b_e[1]), 1)])
# Exact filter: rails must keep 0.5 m off every carriageway edge.
if guardrails:
    _kept_rails = []
    for g in guardrails:
        _pts = [(g[0], g[1]), ((g[0] + g[2]) * 0.5, (g[1] + g[3]) * 0.5), (g[2], g[3])]
        if float(np.min(exact_edge_clearances(_pts))) >= 0.5:
            _kept_rails.append(g)
    guardrails = _kept_rails
print(f"[forest] guardrails: {len(guardrails)}")

# Fence exact filter: drop any run that reaches a carriageway.
_kept_structures = []
_dropped_fences = 0
for _st in structures:
    if _st["kind"] == "fence":
        _pts = segment_points(_st["x"], _st["z"], _st["yaw"], float(_st["w"]))
        if float(np.min(exact_edge_clearances(_pts))) < 1.2:
            _dropped_fences += 1
            continue
    _kept_structures.append(_st)
structures = _kept_structures
buildings = [s for s in structures if s in buildings]
print(f"[forest] fence filter: dropped {_dropped_fences}")

# --- exact small-structure footprint audit (same as desert 0.2.53) ---
def _structure_footprint_points(st):
    _yaw = float(st.get("yaw", 0.0))
    _ca, _sa = math.cos(_yaw), math.sin(_yaw)
    _ex = np.array([_ca, -_sa])
    _ez = np.array([_sa, _ca])
    _centre = np.array([float(st["x"]), float(st["z"])])
    _w = float(st.get("w", 1.0))
    _d = float(st.get("d", 1.0))
    _pts = []
    _nx = max(2, int(math.ceil(_w / 1.0)))
    _nz = max(2, int(math.ceil(_d / 1.0)))
    for _i in range(_nx + 1):
        _lx = -_w * 0.5 + _w * _i / _nx
        for _lz in (-_d * 0.5, _d * 0.5):
            _pts.append(_centre + _ex * _lx + _ez * _lz)
    for _i in range(1, _nz):
        _lz = -_d * 0.5 + _d * _i / _nz
        for _lx in (-_w * 0.5, _w * 0.5):
            _pts.append(_centre + _ex * _lx + _ez * _lz)
    return _pts


_small_margins = {
    "sign": 0.55, "sign_smash": 0.55, "power_pole": 0.80, "town_pole": 0.70,
    "billboard": 0.80, "barrel_group": 0.80, "crate": 0.80, "tank_small": 0.80,
    "container": 0.80, "tractor": 0.90, "log_truck": 0.90, "log_stack": 0.90,
    "greenhouse": 0.80, "viewpoint": 0.80,
}
_small_kept = []
_small_moved = 0
_small_dropped = 0
for _st in structures:
    _kind = _st.get("kind", "")
    if _kind not in _small_margins:
        _small_kept.append(_st)
        continue
    _req = _small_margins[_kind]
    _cur = dict(_st)
    _moved = False
    _worst = -1e9
    for _attempt in range(6):
        _pts = _structure_footprint_points(_cur)
        _clear, _near, _dirs = exact_nearest_road(_pts)
        _wi = int(np.argmin(_clear))
        _worst = float(_clear[_wi])
        if _worst >= _req:
            break
        _away = _pts[_wi] - _near[_wi]
        _ln = float(np.linalg.norm(_away))
        if _ln < 1e-5:
            _d = _dirs[_wi]
            _away = np.array([-_d[1], _d[0]])
            _ln = 1.0
        _away = _away / _ln
        _shift = (_req - _worst) + 0.30
        _cur["x"] = round(float(_cur["x"] + _away[0] * _shift), 1)
        _cur["z"] = round(float(_cur["z"] + _away[1] * _shift), 1)
        _moved = True
    if _worst < _req:
        _pts = _structure_footprint_points(_cur)
        _clear, _near, _dirs = exact_nearest_road(_pts)
        _worst = float(np.min(_clear))
    if _worst >= _req:
        if _moved:
            _small_moved += 1
        _small_kept.append(_cur)
    else:
        _small_dropped += 1
structures = _small_kept
buildings = [s for s in structures if s in buildings] if False else buildings
pole_points = [[round(s["x"], 1), round(s["z"], 1)] for s in structures if s["kind"] == "power_pole"]
smash_signs = [[round(s["x"], 1), round(s["z"], 1)] for s in structures if s["kind"] == "sign_smash"]
print(f"[forest] small-structure audit: moved {_small_moved}, dropped {_small_dropped}")

# ---------------------------------------------------------------- game content
print("[forest] game content ...")


def road_pts(rid):
    return [[float(s[0]), float(s[2])] for s in road_samples_by_id[rid]]


def road_slice(rid, a_xy, b_xy, reverse=False):
    pts = road_pts(rid)
    ia = min(range(len(pts)), key=lambda i: (pts[i][0] - a_xy[0]) ** 2 + (pts[i][1] - a_xy[1]) ** 2)
    ib = min(range(len(pts)), key=lambda i: (pts[i][0] - b_xy[0]) ** 2 + (pts[i][1] - b_xy[1]) ** 2)
    lo, hi = min(ia, ib), max(ia, ib)
    out = pts[lo:hi + 1]
    return list(reversed(out)) if reverse else out


def _drag_from(rid, s_from, length, name, did):
    samples = road_samples_by_id[rid]
    pts = np.array([[s[0], s[2]] for s in samples])
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    i0 = int(np.searchsorted(cum, s_from))
    i1 = int(np.searchsorted(cum, s_from + length))
    i0 = min(i0, len(samples) - 1)
    i1 = min(i1, len(samples) - 1)
    return {"id": did, "name": name,
            "start": [float(samples[i0][0]), float(samples[i0][2])],
            "finish": [float(samples[i1][0]), float(samples[i1][2])],
            "lengthM": round(float(cum[i1] - cum[i0]), 1)}


def _road_spot(rid, frac):
    samples = road_samples_by_id[rid]
    i = min(max(int(len(samples) * frac), 1), len(samples) - 2)
    a, b = samples[i], samples[i + 1]
    yaw = math.atan2(-(float(b[0]) - float(a[0])), -(float(b[2]) - float(a[2])))
    return float(a[0]), float(a[2]), round(yaw, 2)


circuits = [
    {"id": "circuit_lake", "name": "Озеро", "points": road_pts("lake_loop")},
    {"id": "circuit_forest", "name": "Тёмный лес", "points": road_pts("forest_loop")},
    {"id": "circuit_hills", "name": "Холмы", "points": road_pts("serpentine") + road_pts("ridge") +
     road_slice("ring", (3150.0, 900.0), (1900.0, 820.0), reverse=True)},
    {"id": "circuit_farm", "name": "Ферма", "points": road_pts("farm_loop")},
]
sprints = [
    {"id": "sprint_meadow", "name": "Луговая прямая", "points": road_pts("meadow_straight")},
    {"id": "sprint_cliff", "name": "К утёсу", "points": road_pts("cliff_road")},
    {"id": "sprint_river", "name": "Вдоль реки", "points": road_pts("riverbank")},
]
drags = [
    _drag_from("meadow_straight", 120.0, 1000.0, "Драг Луга-1000", "drag_meadow"),
    _drag_from("farm_straight", 150.0, 1000.0, "Драг Поля-1000", "drag_farm"),
]
jumps = []
for (_r, _f, _n) in [("forest_loop", 0.18, "Прыжок Лесное кольцо I"), ("forest_loop", 0.55, "Прыжок Лесное кольцо II"),
                     ("forest_loop", 0.83, "Прыжок Лесное кольцо III"), ("sawmill_a", 0.45, "Прыжок Лесовозная"),
                     ("sawmill_c", 0.5, "Прыжок Дальняя просека"), ("riverbank", 0.35, "Прыжок Речной I"),
                     ("riverbank", 0.7, "Прыжок Речной II"), ("ridge", 0.4, "Прыжок Хребет"),
                     ("dirt_dark_a", 0.5, "Прыжок Глухой просёлок"), ("dirt_meadow_ns", 0.45, "Прыжок Луговой"),
                     ("swamp_causeway", 0.85, "Прыжок Гать"), ("dirt_hills_w", 0.55, "Прыжок Западные холмы")]:
    _x, _z, _yaw = _road_spot(_r, _f)
    jumps.append({"name": _n, "x": _x, "z": _z, "yaw": _yaw})
speed_traps = []
for (_r, _f) in [("ring", 0.12), ("ring", 0.45), ("ring", 0.78), ("meadow_straight", 0.5),
                 ("farm_straight", 0.5), ("lake_loop", 0.3)]:
    _x, _z, _yaw = _road_spot(_r, _f)
    speed_traps.append({"x": _x, "z": _z, "yaw": _yaw})
drift_zones = [
    {"name": "Дрифт: площадь посёлка", "x": 3600.0, "z": 2180.0, "radius": 50.0},
    {"name": "Дрифт: двор лесопилки", "x": 920.0, "z": 3500.0, "radius": 55.0},
    {"name": "Дрифт: фермерский круг", "x": 2280.0, "z": 3300.0, "radius": 50.0},
    {"name": "Дрифт: лесная шпилька", "x": 1080.0, "z": 1750.0, "radius": 45.0},
    {"name": "Дрифт: вершина", "x": 1850.0, "z": 320.0, "radius": 45.0},
]
speed_zones = [
    {"name": "Скорость: луговая прямая", "from": [1350.0, 1905.0], "to": [2420.0, 1945.0]},
    {"name": "Скорость: северное кольцо", "from": [1350.0, 780.0], "to": [2450.0, 770.0]},
    {"name": "Скорость: полевая прямая", "from": [1400.0, 3355.0], "to": [2580.0, 3355.0]},
]
photo_spots = [
    {"name": "Фото: водопад", "x": 3355.0, "z": 700.0, "yaw": -0.8},
    {"name": "Фото: вершина холмов", "x": 1866.0, "z": 312.0, "yaw": 2.9},
    {"name": "Фото: дуб-гигант", "x": 1872.0, "z": 2122.0, "yaw": -2.4},
    {"name": "Фото: маяк на озере", "x": 3418.0, "z": 2458.0, "yaw": -2.2},
    {"name": "Фото: остров с сосной", "x": 2720.0, "z": 2050.0, "yaw": -1.4},
    {"name": "Фото: дамба", "x": 3060.0, "z": 2510.0, "yaw": 0.4},
    {"name": "Фото: болото", "x": 1150.0, "z": 2835.0, "yaw": 1.2},
    {"name": "Фото: пристань посёлка", "x": 3462.0, "z": 2220.0, "yaw": -1.6},
    {"name": "Фото: тоннель в утёсе", "x": 3500.0, "z": 600.0, "yaw": -0.7},
    {"name": "Фото: подсолнухи", "x": 1980.0, "z": 3180.0, "yaw": 2.2},
]
treasures = [
    {"x": 640.0, "z": 1250.0}, {"x": 2400.0, "z": 430.0}, {"x": 3350.0, "z": 980.0},
    {"x": 1550.0, "z": 2350.0}, {"x": 2925.0, "z": 2145.0}, {"x": 1050.0, "z": 2980.0},
    {"x": 2550.0, "z": 3450.0}, {"x": 3680.0, "z": 3050.0},
]
fast_travel = [
    {"name": "Гараж посёлка", "x": 3668.0, "z": 2162.0},
    {"name": "Ферма", "x": 2070.0, "z": 3410.0},
    {"name": "Лесопилка", "x": 920.0, "z": 3490.0},
    {"name": "Вершина холмов", "x": 1858.0, "z": 318.0},
    {"name": "Водопад", "x": 3405.0, "z": 650.0},
    {"name": "Пристань", "x": 3468.0, "z": 2220.0},
    {"name": "Лесное кольцо", "x": 700.0, "z": 1460.0},
    {"name": "Гать через болото", "x": 1160.0, "z": 2836.0},
]

landmarks = []
for (lx, lz, lkind, lname) in [
        (3385, 655, "gf-waterfall", "Водопад"),
        (1850, 300, "gf-summit", "Смотровая площадка на вершине"),
        (1900, 2150, "gf-giant-oak", "Дуб-гигант"),
        (3445, 2485, "gf-lighthouse", "Маяк на озере"),
        (2108, 3426, "gf-silo", "Силосная башня"),
        (2920, 2120, "gf-island", "Остров с одной сосной"),
        (3550, 560, "gf-cliff-tunnel", "Тоннель в скале"),
        (2550, 760, "gf-gallery", "Мост-галерея"),
        (3060, 2535, "gf-dam", "Дамба через озеро"),
        (3600, 2180, "gf-village", "Посёлок у озера"),
        (2070, 3460, "gf-farm", "Ферма"),
        (920, 3520, "gf-sawmill", "Лесопилка"),
        (1100, 2850, "gf-swamp", "Болото"),
        (3050, 2200, "gf-lake", "Лесное озеро"),
        (1450, 1740, "gf-ford", "Низководный брод"),
        (2000, 3405, "gf-windmill", "Ветряная мельница"),
        (3542, 2320, "gf-church", "Церквушка у озера"),
        (800, 880, "gf-bridge-nw", "Каменный мост"),
        (1060, 1620, "gf-bridge-wood", "Деревянный мост"),
        (3360, 690, "gf-bridge-gorge", "Мост над ущельем"),
        (760, 1150, "gf-watchtower", "Вышка Тёмного леса"),
        (1850, 1900, "gf-meadow", "Центральные луга"),
        (3600, 1700, "gf-birch", "Берёзовая роща"),
        (700, 2100, "gf-darkforest", "Тёмный лес"),
        (3920, 300, "gf-cliff", "Скалистый утёс"),
]:
    landmarks.append({"x": float(lx), "z": float(lz), "rotY": 0.0, "kind": lkind, "name": lname})

districts = [
    {"id": "gf-hills", "name": "Хвойные холмы", "x": 1900, "z": 600, "radiusM": 1500, "biome": "forest"},
    {"id": "gf-dark", "name": "Тёмный лес", "x": 650, "z": 2100, "radiusM": 1100, "biome": "forest"},
    {"id": "gf-meadows", "name": "Центральные луга", "x": 1850, "z": 1900, "radiusM": 800, "biome": "meadow"},
    {"id": "gf-lake", "name": "Лесное озеро", "x": 3050, "z": 2200, "radiusM": 700, "biome": "water"},
    {"id": "gf-village", "name": "Посёлок у озера", "x": 3600, "z": 2150, "radiusM": 450, "biome": "town"},
    {"id": "gf-farm", "name": "Фермерская долина", "x": 2000, "z": 3350, "radiusM": 900, "biome": "farm"},
    {"id": "gf-sawmill", "name": "Лесопилка", "x": 900, "z": 3500, "radiusM": 650, "biome": "industry"},
    {"id": "gf-swamp", "name": "Болото", "x": 1100, "z": 2850, "radiusM": 450, "biome": "swamp"},
    {"id": "gf-cliff", "name": "Скалистый утёс", "x": 3550, "z": 520, "radiusM": 650, "biome": "rock"},
    {"id": "gf-forest", "name": "Зелёный лес", "x": 2000, "z": 2000, "radiusM": 2600, "biome": "forest"},
]

zones = {
    "hills": {"minX": 0, "minZ": 0, "maxX": 4000, "maxZ": 1250},
    "darkForest": {"minX": 0, "minZ": 1150, "maxX": 1250, "maxZ": 3250},
    "meadows": {"minX": 1150, "minZ": 1250, "maxX": 2550, "maxZ": 2550},
    "farmValley": {"minX": 1150, "minZ": 2850, "maxX": 2850, "maxZ": 3850},
    "birchGrove": {"minX": 3250, "minZ": 1150, "maxX": 4000, "maxZ": 2450},
    "sawmill": {"minX": 450, "minZ": 3150, "maxX": 1350, "maxZ": 3850},
    "swamp": {"minX": 730, "minZ": 2565, "maxX": 1470, "maxZ": 3135},
    "gfLake": {"minX": 2600, "minZ": 1800, "maxX": 3500, "maxZ": 2600},
    "cliff": {"minX": 2900, "minZ": 50, "maxX": 4000, "maxZ": 1000},
}

# Spawn on the village main street, facing along the road.
_sx, _sz, _syaw = _road_spot("village_main", 0.25)
spawn = {"x": round(_sx, 1), "y": round(height_at(_sx, _sz) + 0.6, 3), "z": round(_sz, 1), "yaw": _syaw}

# Deer groups at meadow/forest edges + chimney smoke points (village).
deer_groups = [
    {"x": 1500.0, "z": 1700.0, "count": 5}, {"x": 2300.0, "z": 2250.0, "count": 6},
    {"x": 1750.0, "z": 2500.0, "count": 4}, {"x": 1250.0, "z": 2200.0, "count": 5},
    {"x": 2600.0, "z": 1650.0, "count": 4}, {"x": 1450.0, "z": 1500.0, "count": 6},
    {"x": 2900.0, "z": 2950.0, "count": 4}, {"x": 2100.0, "z": 1500.0, "count": 5},
    {"x": 1650.0, "z": 2750.0, "count": 4},
]
smoke_points = [[3560.0, 2030.0], [3630.0, 2120.0], [3585.0, 2260.0], [3620.0, 2350.0], [2025.0, 3430.0]]

_tree_kinds = ("spruce", "pine", "leafy", "birch", "oak", "dead_tree")
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
    "trees": int(sum(len(scatter_data.get(k, [])) for k in _tree_kinds)),
    "bushes": len(scatter_data.get("bush", [])),
    "palms": 0,
    "lamps": len(pole_points),
    "benches": 0,
}

forest_extra = {
    "lake": {"x": LAKE_X, "z": LAKE_Z, "radius": LAKE_RX, "rx": LAKE_RX, "rz": LAKE_RZ, "y": LAKE_Y},
    "river": [[[round(float(p[0]), 1), round(float(p[1]), 1), round(float(w), 2)]
               for p, w in zip(dense[::3], wy[::3])] for (dense, wy) in RIVERS],
    "swamp": {"x": SWAMP_X, "z": SWAMP_Z, "rx": SWAMP_RX, "rz": SWAMP_RZ, "y": SWAMP_Y},
    "fields": FIELDS,
    "structures": structures,
    "scatter": scatter_data,
    "pipes": pipes,
    "guardrails": guardrails,
    "poleLine": pole_points,
    "bridges": [{"road": "gf-" + brid, "x": float(c[0]), "z": float(c[1]), "halfLength": hl}
                for (brid, c, hl, _dy) in BRIDGES],
    "tunnels": [{"road": "gf-" + trid, "x": float(c[0]), "z": float(c[1]), "halfLength": hl}
                for (trid, c, hl) in TUNNELS],
    "tunnel": {"road": "gf-" + TUNNELS[0][0], "x": float(TUNNELS[0][1][0]),
               "z": float(TUNNELS[0][1][1]), "halfLength": TUNNELS[0][2]},
    "deerGroups": deer_groups,
    "smokePoints": smoke_points,
    "game": {
        "circuits": circuits, "sprints": sprints, "drags": drags, "jumps": jumps,
        "speedTraps": speed_traps, "driftZones": drift_zones, "speedZones": speed_zones,
        "photoSpots": photo_spots, "treasures": treasures, "fastTravel": fast_travel,
        "smashSigns": smash_signs,
    },
}

data = {
    "schemaVersion": 1,
    "name": "GreenForest",
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
    "pools": [{"x": LAKE_X, "z": LAKE_Z, "y": LAKE_Y, "w": LAKE_RX * 2.0, "d": LAKE_RZ * 2.0, "rotY": 0.0}],
    "trees": [], "bushes": [], "palms": [], "lamps": [], "benches": [],
    "stats": stats,
    "forest": forest_extra,
}

with open(OUT_JSON, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
print(f"[forest] wrote {OUT_JSON} ({os.path.getsize(OUT_JSON)/1e6:.1f} MB)")

# ---------------------------------------------------------------- report + preview
print("[forest] density report + preview ...")
CELL = 250.0
ncells = int(SIZE / CELL)
cell_counts = np.zeros((ncells, ncells), dtype=int)
for s in structures:
    cell_counts[min(int(s["z"] // CELL), ncells - 1), min(int(s["x"] // CELL), ncells - 1)] += 1
for kind in _tree_kinds + ("rock_large",):
    for inst in scatter_data.get(kind, [])[::7]:
        cell_counts[min(int(inst[1] // CELL), ncells - 1), min(int(inst[0] // CELL), ncells - 1)] += 1
empty_cells = int(np.sum(cell_counts == 0))

zone_tree_counts = {}
for kind in _tree_kinds:
    for inst in scatter_data.get(kind, []):
        zn = zone_of(float(inst[0]), float(inst[1]))
        zone_tree_counts[zn] = zone_tree_counts.get(zn, 0) + 1

lines = []
lines.append("GREENFOREST — отчёт плотности объектов (генератор generate_greenforest_world.py)")
lines.append("=" * 72)
lines.append(f"Дороги: {len(roads_out)} шт., суммарно {road_length_total/1000.0:.1f} км")
lines.append(f"Scatter-экземпляров всего: {stats['scatterInstances']}")
for k in sorted(scatter_data.keys()):
    lines.append(f"  {k}: {len(scatter_data[k])}")
lines.append(f"Деревьев всего: {stats['trees']}; по зонам: {zone_tree_counts}")
fence_len = sum(float(s["w"]) for s in structures if s["kind"] == "fence")
lines.append(f"Структур: {len(structures)}, зданий: {len(buildings)}, ориентиров: {len(landmarks)}")
lines.append(f"Заборов: {sum(1 for s in structures if s['kind'] == 'fence')} шт., суммарно {fence_len:.0f} м")
lines.append(f"Ограждений: {len(guardrails)} секций, столбов ЛЭП: {len(pole_points)}, труб орошения: {len(pipes)}")
lines.append(f"Мостов: {len(BRIDGES)} (включая дамбу и гать), тоннелей: {len(TUNNELS)}")
lines.append(f"Пустых клеток 250x250 м: {empty_cells} из {ncells*ncells}")
report = "\n".join(lines) + "\n"
with open(OUT_REPORT, "w", encoding="utf-8") as f:
    f.write(report)
print(report)

try:
    from PIL import Image, ImageDraw
    P = 1000
    sc = P / SIZE
    # base: height-tinted relief
    hsmall = np.array(Image.fromarray(
        (np.clip(H, 0, 180) / 180.0 * 255).astype(np.uint8)).resize((P, P), Image.BILINEAR), dtype=np.float64) / 255.0
    img_arr = np.zeros((P, P, 3), dtype=np.uint8)
    img_arr[..., 0] = (60 + hsmall * 150).astype(np.uint8)
    img_arr[..., 1] = (110 + hsmall * 90).astype(np.uint8)
    img_arr[..., 2] = (45 + hsmall * 60).astype(np.uint8)
    img = Image.fromarray(img_arr)
    dr = ImageDraw.Draw(img)
    # lake + swamp water
    dr.ellipse([(LAKE_X - LAKE_RX) * sc, (LAKE_Z - LAKE_RZ) * sc,
                (LAKE_X + LAKE_RX) * sc, (LAKE_Z + LAKE_RZ) * sc], fill=(60, 120, 190))
    dr.ellipse([(ISLAND_X - 70) * sc, (ISLAND_Z - 70) * sc,
                (ISLAND_X + 70) * sc, (ISLAND_Z + 70) * sc], fill=(90, 140, 70))
    dr.ellipse([(SWAMP_X - SWAMP_RX) * sc, (SWAMP_Z - SWAMP_RZ) * sc,
                (SWAMP_X + SWAMP_RX) * sc, (SWAMP_Z + SWAMP_RZ) * sc], fill=(70, 130, 140))
    for (dense, _wy) in RIVERS:
        dr.line([(float(p[0]) * sc, float(p[1]) * sc) for p in dense[::4]], fill=(70, 130, 200), width=2)
    for f in FIELDS:
        dr.rectangle([(f["x"] - f["w"] / 2) * sc, (f["z"] - f["d"] / 2) * sc,
                      (f["x"] + f["w"] / 2) * sc, (f["z"] + f["d"] / 2) * sc], fill=(170, 140, 70))
    for kind in _tree_kinds:
        for inst in scatter_data.get(kind, [])[::11]:
            dr.point([(float(inst[0]) * sc, float(inst[1]) * sc)], fill=(25, 70, 30))
    for r in roads_out:
        pts = [(s[0] * sc, s[2] * sc) for s in r["samples"]]
        col = (235, 235, 235) if r["surface"] == "asphalt" else (190, 160, 110)
        dr.line(pts, fill=col, width=2 if r["surface"] == "asphalt" else 1)
    for s in structures:
        if s.get("name"):
            dr.ellipse([s["x"] * sc - 3, s["z"] * sc - 3, s["x"] * sc + 3, s["z"] * sc + 3], fill=(255, 90, 60))
    img.save(OUT_PREVIEW)
    # density heatmap
    hm = np.clip(cell_counts / max(1, int(cell_counts.max())), 0, 1)
    hm_img = np.zeros((ncells, ncells, 3), dtype=np.uint8)
    hm_img[..., 0] = (hm * 255).astype(np.uint8)
    hm_img[..., 1] = ((1.0 - np.abs(hm - 0.5) * 2.0) * 200).astype(np.uint8)
    hm_img[..., 2] = ((1.0 - hm) * 200).astype(np.uint8)
    Image.fromarray(hm_img).resize((640, 640), Image.NEAREST).save(OUT_HEATMAP)
    print(f"[forest] previews: {OUT_PREVIEW}, {OUT_HEATMAP}")
except ImportError:
    print("[forest] PIL not available, previews skipped")
print("[forest] done")
