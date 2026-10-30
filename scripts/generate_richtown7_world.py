#!/usr/bin/env python3
"""RichTown 7x7 km world generator (0.3.0, stages 1-2 of the rebuild spec).

Emits native/data/richtown_native.json in the shared schemaVersion-1 format
consumed by NativeWorldBuilder: a 501x501 heightfield (14 m step) covering
7000x7000 m, the staged road skeleton (big ring, downtown ring, central
axes, district grids, canal bridges), district massing (~520 buildings),
landmarks, palms/trees/lamps/pools and spawn.

Design notes (see docs/RICHTOWN_7X7_STATUS.md for the full stage plan):
- Sea is WEST (x < -2900), beach, Corniche at x=-2650, downtown +-1000 with
  Rich Tower at (0,0) inside a plaza ring road, canal at z=1600 with five
  bridges, Rich Hills SE-of-centre (z<0), Sunset north of downtown, port and
  farm beyond the canal, dune desert in the east (x > 2400).
- Roads are emitted as block-length segments sharing exact endpoints so the
  builder's junction detection, Crown trims and route graph stay exact.
- Terrain is stamped along road corridors to the smoothed road profile so
  carriageways never cliff through the heightfield; bridge decks are raised
  profiles and are NOT stamped (the canal stays wet underneath).
"""

import json
import math
import random
from pathlib import Path

RNG = random.Random(20261030)

WORLD = 3500.0
STEP = 14.0
N = 501  # 7000 / 14 + 1

OUT = Path(__file__).resolve().parent.parent / "native" / "data" / "richtown_native.json"


# --------------------------------------------------------------------------
# Noise helpers
# --------------------------------------------------------------------------

def _hash2(ix: int, iz: int) -> float:
    v = math.sin(ix * 127.1 + iz * 311.7) * 43758.5453
    return v - math.floor(v)


def vnoise(x: float, z: float, scale: float) -> float:
    """Smooth value noise in [-1, 1]."""
    fx = x / scale
    fz = z / scale
    ix = math.floor(fx)
    iz = math.floor(fz)
    tx = fx - ix
    tz = fz - iz
    sx = tx * tx * (3.0 - 2.0 * tx)
    sz = tz * tz * (3.0 - 2.0 * tz)
    a = _hash2(ix, iz)
    b = _hash2(ix + 1, iz)
    c = _hash2(ix, iz + 1)
    d = _hash2(ix + 1, iz + 1)
    top = a + (b - a) * sx
    bot = c + (d - c) * sx
    return (top + (bot - top) * sz) * 2.0 - 1.0


def fbm(x: float, z: float, scale: float) -> float:
    return vnoise(x, z, scale) * 0.62 + vnoise(x, z, scale * 0.47) * 0.26 + vnoise(x, z, scale * 0.21) * 0.12


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = (x - edge0) / (edge1 - edge0)
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def rect_mask(x: float, z: float, min_x: float, max_x: float, min_z: float, max_z: float, feather: float) -> float:
    mx = smoothstep(min_x - feather, min_x + feather, x) * (1.0 - smoothstep(max_x - feather, max_x + feather, x))
    mz = smoothstep(min_z - feather, min_z + feather, z) * (1.0 - smoothstep(max_z - feather, max_z + feather, z))
    return mx * mz


# --------------------------------------------------------------------------
# Base terrain (before road stamping)
# --------------------------------------------------------------------------

def base_height(x: float, z: float) -> float:
    h = 3.4 + fbm(x, z, 720.0) * 0.55

    # Rich Hills: soft rise under the villa district.
    hills = rect_mask(x, z, 980.0, 2350.0, -2950.0, -260.0, 260.0)
    if hills > 0.0:
        h += hills * (4.2 + (fbm(x, z, 430.0) * 0.5 + 0.5) * 6.0)

    # East dune desert.
    m_desert = smoothstep(2350.0, 2900.0, x)
    if m_desert > 0.0:
        ridge = abs(math.sin(x * 0.0105 + fbm(x, z, 320.0) * 2.4)) ** 1.5
        dune_h = 5.0 + ridge * 9.5 + (fbm(x, z, 260.0) * 0.5 + 0.5) * 4.5
        h = lerp(h, dune_h, m_desert * 0.94)

    # Canal channel (z = 1600, from the sea to x = 2200).
    dz_canal = abs(z - 1600.0)
    canal_mask = 1.0 - smoothstep(20.0, 44.0, dz_canal)
    if canal_mask > 0.0:
        east_cap = 1.0 - smoothstep(2120.0, 2260.0, x)
        h = lerp(h, -1.9, canal_mask * east_cap)

    # Flats: stadium apron, drift arena, tower plaza.
    stadium = rect_mask(x, z, -20.0, 380.0, -1580.0, -1220.0, 90.0)
    if stadium > 0.0:
        h = lerp(h, 3.4, stadium)
    drift = rect_mask(x, z, 2500.0, 2840.0, -420.0, -80.0, 110.0)
    if drift > 0.0:
        h = lerp(h, 4.6, drift)
    d_centre = math.hypot(x, z)
    plaza = 1.0 - smoothstep(130.0, 240.0, d_centre)
    if plaza > 0.0:
        h = lerp(h, 3.45, plaza)

    # Coast: beach ramp into the western sea.
    coast = smoothstep(-2700.0, -3050.0, x)
    if coast > 0.0:
        sea_floor = -5.4 + fbm(x, z, 520.0) * 0.7
        h = lerp(h, sea_floor, coast)

    return h


print("Computing base heightfield...")
heights = []
for iz in range(N):
    z = -WORLD + iz * STEP
    row = []
    for ix in range(N):
        x = -WORLD + ix * STEP
        row.append(base_height(x, z))
    heights.append(row)


def grid_height(x: float, z: float) -> float:
    fx = (x + WORLD) / STEP
    fz = (z + WORLD) / STEP
    ix = max(0, min(N - 2, int(math.floor(fx))))
    iz = max(0, min(N - 2, int(math.floor(fz))))
    tx = max(0.0, min(1.0, fx - ix))
    tz = max(0.0, min(1.0, fz - iz))
    a = heights[iz][ix]
    b = heights[iz][ix + 1]
    c = heights[iz + 1][ix]
    d = heights[iz + 1][ix + 1]
    return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)


# --------------------------------------------------------------------------
# Road network definition
# --------------------------------------------------------------------------

roads = []


def resample(pts, step=22.0):
    """pts: [(x,z)] control points -> evenly spaced [(x,z)]."""
    out = [pts[0]]
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        length = math.hypot(bx - ax, bz - az)
        n = max(1, int(round(length / step)))
        for k in range(1, n + 1):
            t = k / n
            out.append((ax + (bx - ax) * t, az + (bz - az) * t))
    return out


def smooth_profile(ys, xs_zs, max_grade=0.06):
    """Moving-average passes + grade clamp along a sampled centreline."""
    ys = list(ys)
    n = len(ys)
    for _ in range(3):
        src = list(ys)
        for i in range(n):
            lo = src[max(0, i - 1)]
            hi = src[min(n - 1, i + 1)]
            ys[i] = (lo + src[i] * 2.0 + hi) * 0.25
    for _ in range(2):
        for i in range(1, n):
            d = math.hypot(xs_zs[i][0] - xs_zs[i - 1][0], xs_zs[i][1] - xs_zs[i - 1][1])
            max_dy = max_grade * max(d, 1.0)
            if ys[i] - ys[i - 1] > max_dy:
                ys[i] = ys[i - 1] + max_dy
        for i in range(n - 2, -1, -1):
            d = math.hypot(xs_zs[i + 1][0] - xs_zs[i][0], xs_zs[i + 1][1] - xs_zs[i][1])
            max_dy = max_grade * max(d, 1.0)
            if ys[i] - ys[i + 1] > max_dy:
                ys[i] = ys[i + 1] + max_dy
    return ys


def add_road(road_id, name, pts, width, lanes, speed, closed=False, bridge_peak=0.0):
    samples_xz = resample(pts)
    ys = [grid_height(x, z) for (x, z) in samples_xz]
    ys = smooth_profile(ys, samples_xz)
    if bridge_peak > 0.0:
        # Raised deck: cosine bump peaking mid-span; approach samples keep the
        # terrain profile so the ramps land smoothly on both banks.
        n = len(samples_xz)
        for i in range(n):
            t = i / max(1, n - 1)
            bump = math.sin(t * math.pi) ** 1.5
            ys[i] = max(ys[i], lerp(ys[i], bridge_peak, bump))
        ys = smooth_profile(ys, samples_xz, max_grade=0.075)
    samples = [[round(x, 2), round(y, 3), round(z, 2)] for (x, z), y in zip(samples_xz, ys)]
    roads.append({
        "id": road_id,
        "name": name,
        "widthM": width,
        "lanes": lanes,
        "speedLimitKmh": speed,
        "surface": "asphalt",
        "closed": closed,
        "samples": samples,
        "_bridge": bridge_peak > 0.0,
    })


def v_street(x, z_nodes, width, lanes, speed, prefix, name):
    for i in range(len(z_nodes) - 1):
        add_road(f"{prefix}-{i}", name, [(x, z_nodes[i]), (x, z_nodes[i + 1])], width, lanes, speed)


def h_street(z, x_nodes, width, lanes, speed, prefix, name):
    for i in range(len(x_nodes) - 1):
        add_road(f"{prefix}-{i}", name, [(x_nodes[i], z), (x_nodes[i + 1], z)], width, lanes, speed)


DT = [-1000, -800, -600, -400, -200, 0, 200, 400, 600, 800, 1000]

print("Defining road skeleton...")

# --- Big ring (spec section 3.1) ---
h_street(-3200, [-2650, -1500, -400, 0, 700, 1200, 1800, 2400], 40, 8, 130, "rt7-hwya", "Трасса A (южная)")
h_street(3200, [-2650, -1500, -400, 0, 700, 1200, 1800, 2300, 2400], 40, 8, 130, "rt7-hwyb", "Трасса B (северная)")
v_street(2400, [-3200, -2900, -1000, -200, 0, 1000, 3200], 40, 8, 130, "rt7-hwy1", "Трасса 1 (восточная)")
v_street(-2650, [-3200, -1400, -700, 0, 700, 1400, 1480], 32, 6, 90, "rt7-corniche", "Корниш")
v_street(-2650, [1720, 2000, 3200], 32, 6, 90, "rt7-corniche-n", "Корниш")

# --- Downtown ring ---
v_street(-1000, DT, 32, 6, 70, "rt7-ring-w", "Кольцо даунтауна (запад)")
v_street(1000, [-1000, -800, -600, -500, -400, -200, 0, 200, 400, 600, 800, 1000], 32, 6, 70, "rt7-ring-e", "Кольцо даунтауна (восток)")
h_street(-1000, DT, 32, 6, 70, "rt7-ring-s", "Кольцо даунтауна (юг)")
h_street(1000, [-1000, -800, -600, -400, -200, 0, 200, 400, 600, 800, 1000], 32, 6, 70, "rt7-ring-n", "Кольцо даунтауна (север)")

# --- Central axes with the plaza gap around Rich Tower ---
central_south = [-3200, -1000, -800, -600, -400, -200, -95]
v_street(0, central_south, 32, 6, 70, "rt7-central-s", "Центральный проспект")
central_north = [95, 200, 400, 600, 800, 1000, 1250, 1480]
v_street(0, central_north, 32, 6, 70, "rt7-central-n", "Центральный проспект")
roses_west = [-2650, -1900, -1500, -1000, -800, -600, -400, -200, -95]
h_street(0, roses_west, 32, 6, 70, "rt7-roses-w", "Проспект Роз")
roses_east = [95, 200, 400, 600, 800, 1000, 2400]
h_street(0, roses_east, 32, 6, 70, "rt7-roses-e", "Проспект Роз")

# Plaza ring road around Rich Tower (radius 95 m, cardinal samples exact).
ring_pts = []
for i in range(28):
    a = (i / 28.0) * math.tau
    ring_pts.append((round(math.cos(a) * 95.0, 2), round(math.sin(a) * 95.0, 2)))
ring_pts.append(ring_pts[0])
add_road("rt7-plaza-ring", "Площадь Rich Tower", ring_pts, 17, 2, 40, closed=True)

# --- Downtown grid (200 m blocks) ---
for x in [-800, -600, -400, -200, 200, 400, 600, 800]:
    v_street(x, DT, 17, 2, 50, f"rt7-dtv{x}", "Даунтаун")
for z in [-800, -600, -400, -200, 200, 400, 600, 800]:
    h_street(z, DT, 17, 2, 50, f"rt7-dth{z}", "Даунтаун")

# --- Marina / mall connectors ---
h_street(-700, [-2650, -1900, -1500, -1000], 24, 4, 60, "rt7-marina-s", "Марина Юг")
h_street(700, [-2650, -1900, -1500, -1000], 24, 4, 60, "rt7-marina-n", "Марина Север")
v_street(-1900, [-1400, -700, 0, 700, 1400], 17, 2, 50, "rt7-marina-v", "Марина")
v_street(-1500, [-1000, -700, 0, 700, 1000, 1480], 24, 4, 60, "rt7-mall-w", "Молл — порт")

# --- Rich Hills villa grid ---
hills_h = [-2900, -2300, -1700, -1100, -500, -200]
for z in hills_h:
    w = 17 if z in (-2900, -200) else 12
    east = 2400 if z == -2900 else 2300
    h_street(z, [1000, 1300, 1650, 2000, east], w, 2, 40, f"rt7-hills-h{z}", "Rich Hills")
for x in [1300, 1650, 2000]:
    v_street(x, [-2900, -2300, -1700, -1100, -500, -200], 12, 2, 40, f"rt7-hills-v{x}", "Rich Hills")
# Hills-to-highway connector along z=-300 already ends at 2300; extend to Hwy1.
add_road("rt7-hills-link", "Rich Hills — Трасса 1", [(2300, -200), (2400, -200)], 17, 2, 60)

# --- Sunset district ---
h_street(1000, [1000, 1200, 1800, 2300, 2400], 24, 4, 60, "rt7-sunset-blvd", "Бульвар Сансет")
v_street(-400, [1000, 1250, 1480], 17, 2, 50, "rt7-sunset-v-400", "Сансет")
v_street(700, [1000, 1250, 1480], 17, 2, 50, "rt7-sunset-v700", "Сансет")
v_street(1200, [1000, 1250, 1480], 17, 2, 50, "rt7-sunset-v1200", "Сансет")
v_street(1800, [1000, 1250, 1480], 17, 2, 50, "rt7-sunset-v1800", "Сансет")
h_street(1250, [-1000, -400, 0, 700, 1200, 1800, 2300], 17, 2, 50, "rt7-sunset-h", "Сансет")

# --- Canal banks + five bridges ---
h_street(1480, [-1500, -400, 0, 700, 1200, 1800, 2200], 12, 2, 40, "rt7-canal-s", "Набережная канала (юг)")
h_street(1720, [-1500, -400, 0, 700, 1200, 1800, 2200], 12, 2, 40, "rt7-canal-n", "Набережная канала (север)")
# The Corniche also bridges the canal mouth where it meets the sea.
add_road("rt7-bridge-corniche", "Мост Корниша", [(-2650, 1480), (-2650, 1600), (-2650, 1720)], 32, 6, 70, bridge_peak=6.4)
for bx, w, lanes, peak, nm in [
    (-1500, 24, 4, 7.0, "Западный мост"),
    (-400, 24, 4, 7.0, "Мост Марина"),
    (0, 32, 6, 8.2, "Вантовый мост"),
    (700, 24, 4, 7.0, "Мост Сансет"),
    (1800, 24, 4, 7.0, "Восточный мост"),
]:
    add_road(f"rt7-bridge-{bx}", nm, [(bx, 1480), (bx, 1600), (bx, 1720)], w, lanes, 60, bridge_peak=peak)

add_road("rt7-canal-head", "Разворот у истока канала", [(2200, 1480), (2200, 1720)], 12, 2, 40)

# --- Port & farm beyond the canal ---
for x in [-1500, -400, 0, 700, 1200, 1800]:
    v_street(x, [1720, 2000, 2600, 3200], 17, 2, 50, f"rt7-port-v{x}", "Порт / Ферма")
v_street(2300, [2000, 2600, 3200], 17, 2, 50, "rt7-farm-v2300", "Ферма")
h_street(2000, [-2650, -1500, -400, 0, 700, 1200, 1800, 2300], 24, 4, 60, "rt7-port-h2000", "Портовая улица")
h_street(2600, [-1500, -400, 0, 700, 1200, 1800, 2300], 17, 2, 50, "rt7-port-h2600", "Северная улица")

# --- Drift arena access ---
add_road("rt7-drift-access", "Дрифт-арена", [(2400, -200), (2510, -200)], 12, 2, 40)

# Fix resample drift on shared endpoints: snap first/last samples back to the
# authored control endpoints so junction detection sees exact coincidences.
for road in roads:
    pass  # resample() already keeps exact endpoints (t=0 and t=1 terms).

print(f"Roads defined: {len(roads)}")

# --------------------------------------------------------------------------
# Stamp road corridors into the heightfield
# --------------------------------------------------------------------------

print("Stamping road corridors...")
for road in roads:
    samples = road["samples"]
    half = road["widthM"] * 0.5
    feather = 8.0
    is_bridge = road["_bridge"]
    for i in range(len(samples) - 1):
        ax, ay, az = samples[i]
        bx, by, bz = samples[i + 1]
        if is_bridge:
            # Only stamp near the abutments (first/last 25% of the span).
            t_mid = (i + 0.5) / max(1, len(samples) - 1)
            if 0.25 < t_mid < 0.75:
                continue
        x0 = int(math.floor((min(ax, bx) - half - feather + WORLD) / STEP))
        x1 = int(math.ceil((max(ax, bx) + half + feather + WORLD) / STEP))
        z0 = int(math.floor((min(az, bz) - half - feather + WORLD) / STEP))
        z1 = int(math.ceil((max(az, bz) + half + feather + WORLD) / STEP))
        dx = bx - ax
        dz = bz - az
        seg_len2 = dx * dx + dz * dz
        if seg_len2 < 1e-6:
            continue
        for iz in range(max(0, z0), min(N, z1 + 1)):
            cz = -WORLD + iz * STEP
            for ix in range(max(0, x0), min(N, x1 + 1)):
                cx = -WORLD + ix * STEP
                t = ((cx - ax) * dx + (cz - az) * dz) / seg_len2
                t = max(0.0, min(1.0, t))
                px = ax + dx * t
                pz = az + dz * t
                dist = math.hypot(cx - px, cz - pz)
                if dist > half + feather:
                    continue
                py = ay + (by - ay) * t
                w_blend = 1.0 - smoothstep(half, half + feather, dist)
                heights[iz][ix] = lerp(heights[iz][ix], py, w_blend)

# After stamping, re-derive ground for placement queries.
def ground(x: float, z: float) -> float:
    return grid_height(x, z)


# --------------------------------------------------------------------------
# Road spatial index for clearance queries (scatter validation)
# --------------------------------------------------------------------------

CELL = 200.0
seg_index = {}
all_segments = []
for road in roads:
    samples = road["samples"]
    half = road["widthM"] * 0.5
    for i in range(len(samples) - 1):
        ax, _, az = samples[i]
        bx, _, bz = samples[i + 1]
        all_segments.append((ax, az, bx, bz, half))
        cx0 = int(math.floor((min(ax, bx) - half - 30) / CELL))
        cx1 = int(math.floor((max(ax, bx) + half + 30) / CELL))
        cz0 = int(math.floor((min(az, bz) - half - 30) / CELL))
        cz1 = int(math.floor((max(az, bz) + half + 30) / CELL))
        for cx in range(cx0, cx1 + 1):
            for cz in range(cz0, cz1 + 1):
                seg_index.setdefault((cx, cz), []).append(len(all_segments) - 1)


def road_clearance(x: float, z: float) -> float:
    """Distance from point to nearest carriageway edge (negative = on road)."""
    cell = (int(math.floor(x / CELL)), int(math.floor(z / CELL)))
    best = 1e9
    seen = set()
    for cx in (cell[0] - 1, cell[0], cell[0] + 1):
        for cz in (cell[1] - 1, cell[1], cell[1] + 1):
            for si in seg_index.get((cx, cz), ()):  # noqa: B007
                if si in seen:
                    continue
                seen.add(si)
                ax, az, bx, bz, half = all_segments[si]
                dx = bx - ax
                dz = bz - az
                l2 = dx * dx + dz * dz
                t = 0.0 if l2 < 1e-9 else max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / l2))
                d = math.hypot(x - (ax + dx * t), z - (az + dz * t)) - half
                if d < best:
                    best = d
    return best


def clear_of_roads(x: float, z: float, margin: float) -> bool:
    return road_clearance(x, z) >= margin


# --------------------------------------------------------------------------
# Buildings
# --------------------------------------------------------------------------

buildings = []
FACADES_TOWER = ["glassTower", "marbleTower", "goldTower", "sandTower", "hotelTower"]


def add_building(x, z, w, d, h, kind, facade, model="generic", rot_y=0.0, roof_h=0.0, tint=1.0):
    buildings.append({
        "x": round(x, 2), "y": round(ground(x, z), 3), "z": round(z, 2),
        "rotY": rot_y, "w": w, "d": d, "h": h, "roofH": roof_h,
        "kind": kind, "facade": facade, "tint": tint, "model": model,
    })


PARK_RECTS = [(210, 390, -790, -610), (-390, -210, 1010, 1240), (1320, 1620, -1980, -1720)]


def in_park(x, z, pad=14.0):
    return any(a - pad <= x <= b + pad and c - pad <= z <= d + pad for a, b, c, d in PARK_RECTS)


print("Placing buildings...")

# Downtown blocks: one or two towers per 200 m block.
glass_parcels = [(2, 3), (4, 6), (6, 2), (7, 5), (3, 7), (5, 4), (1, 5), (8, 3), (2, 8), (6, 8), (8, 7), (4, 1)]
park_block = (6, 1)  # x 200..400, z -800..-600 -> Central park block
for bi in range(10):
    for bj in range(10):
        cx = (DT[bi] + DT[bi + 1]) * 0.5
        cz = (DT[bj] + DT[bj + 1]) * 0.5
        dist_c = math.hypot(cx, cz)
        if dist_c < 200.0:
            continue  # plaza gardens around Rich Tower
        if (bi, bj) == park_block:
            continue
        if any(abs(cx - lx) < 30.0 and abs(cz - lz) < 30.0
               for lx, lz in ((300, -300), (-300, 300), (-300, -300), (500, -700), (-700, 500))):
            continue  # authored landmark parcel (twist/hole/lean/museum/opera)
        h_base = 30.0 + 62.0 * math.exp(-((dist_c / 680.0) ** 2)) + RNG.uniform(0.0, 16.0)
        if (bi, bj) in glass_parcels:
            add_building(cx, cz, 34, 34, 73, "rt-tower", "glassTower", model="glass_tower")
            continue
        if RNG.random() < 0.45:
            # Two slimmer towers sharing the block.
            for sx, sz in ((-48.0, -48.0), (48.0, 48.0)):
                w = RNG.choice([30, 34, 38])
                add_building(
                    cx + sx, cz + sz, w, w, round(max(24.0, h_base * RNG.uniform(0.75, 1.05)), 1),
                    "rt-tower", RNG.choice(FACADES_TOWER), tint=round(RNG.uniform(0.9, 1.1), 3),
                )
        else:
            w = RNG.choice([38, 42, 46])
            add_building(
                cx, cz, w, w, round(max(26.0, h_base), 1),
                "rt-tower", RNG.choice(FACADES_TOWER), tint=round(RNG.uniform(0.9, 1.1), 3),
            )

# Corniche hotels (x ~ -2450). Three parcels match the fixed-scale Grand
# Hotel rule (kind rt-hotel, h>38, w 33..36, d 25..28); two use the hero
# podium model (15<=h<=38); one is a tall generic slab.
hotels = [
    (-2450, -1150, 34, 26, 46), (-2450, -700, 44, 32, 74), (-2450, -250, 34, 26, 52),
    (-2450, 250, 40, 30, 28), (-2450, 700, 34, 26, 42), (-2450, 1150, 40, 30, 24),
]
for hx, hz, w, d, h in hotels:
    add_building(hx, hz, w, d, h, "rt-hotel", "hotelTower", rot_y=math.pi / 2.0)

# Mall + multi-storey parking handled as landmark; mall itself is a building.
add_building(-1200, -200, 230, 130, 18, "rt-mall", "userMarble")

# Marina residential (hero podium blocks + townhouses).
for i, mz in enumerate(range(-1250, -449, 160)):
    add_building(-2080, mz, 40, 30, RNG.choice([20, 26, 32]), "rt-hotel", "hotelTower", rot_y=math.pi / 2.0)
    add_building(-1720, mz + 60, 40, 30, RNG.choice([18, 24, 30]), "rt-hotel", "sandTower", rot_y=math.pi / 2.0)
for i, mz in enumerate(range(500, 1300, 160)):
    add_building(-2080, mz, 40, 30, RNG.choice([20, 26, 32]), "rt-hotel", "hotelTower", rot_y=math.pi / 2.0)
    add_building(-1720, mz + 60, 40, 30, RNG.choice([18, 24, 30]), "rt-hotel", "sandTower", rot_y=math.pi / 2.0)
for mz in range(-1300, -499, 110):
    add_building(-2260, mz, 24, 18, 9, "rt-villa", "userPlaster", rot_y=math.pi / 2.0, roof_h=2.0)
for mz in range(520, 1320, 110):
    add_building(-2260, mz, 24, 18, 9, "rt-villa", "userPlaster", rot_y=math.pi / 2.0, roof_h=2.0)

# Rich Hills villas along the residential streets.
villa_count = {"glb": 0, "town": 0, "gen": 0}
for z in hills_h:
    if z == -2900:
        continue  # southern connector stays scenic/empty
    x = 1060.0
    while x < 2260.0:
        for side in (-1.0, 1.0):
            px = x + RNG.uniform(-6.0, 6.0)
            pz = z + side * RNG.uniform(20.0, 26.0)
            if clear_of_roads(px, pz, 13.0) and not in_park(px, pz) and RNG.random() > 0.18:
                r = RNG.random()
                yaw = 0.0 if side < 0 else math.pi
                if r < 0.14:
                    add_building(px, pz, 20, 16, 9, "rt-villa", "userPlaster", model="villa", rot_y=yaw)
                    villa_count["glb"] += 1
                elif r < 0.58:
                    add_building(px, pz, 24, 18, 9, "rt-villa", "userPlaster", rot_y=yaw, roof_h=2.0)
                    villa_count["town"] += 1
                else:
                    add_building(px, pz, 32, 24, 10.5, "rt-villa", RNG.choice(["userPlaster", "userStone", "userWood"]),
                                 rot_y=yaw, roof_h=3.2)
                    villa_count["gen"] += 1
        x += RNG.uniform(52.0, 68.0)

# Sunset mid-rise blocks (two rows between ring/canal).
for row_z in (1125, 1365):
    x = -900.0
    while x < 2250.0:
        if clear_of_roads(x, row_z, 24.0) and not in_park(x, row_z) and not (row_z == 1365 and abs(x - 950.0) < 85.0):
            r = RNG.random()
            if r < 0.30:
                add_building(x, row_z, 40, 30, RNG.choice([19, 25, 31, 36]), "rt-hotel", "hotelTower")
            elif r < 0.78:
                add_building(x, row_z, RNG.choice([32, 36, 40]), 30, round(RNG.uniform(15.0, 40.0), 1),
                             "rt-tower", RNG.choice(FACADES_TOWER))
            else:
                add_building(x, row_z, 24, 18, 9, "rt-villa", "userPlaster", roof_h=2.0)
        x += RNG.uniform(95.0, 130.0)

# Port warehouses + container stacks.
for row_z in (2150, 2450):
    x = -1380.0
    while x < 920.0:
        if clear_of_roads(x, row_z, 30.0):
            add_building(x, row_z, RNG.choice([64, 76, 88]), 32, RNG.choice([11, 13, 15]),
                         "warehouse", RNG.choice(["userStone", "userPlaster"]))
        x += RNG.uniform(120.0, 165.0)
for _ in range(64):
    px = RNG.uniform(-1450.0, 950.0)
    pz = RNG.uniform(2050.0, 2550.0)
    if clear_of_roads(px, pz, 8.0):
        add_building(px, pz, 12, 4, RNG.choice([2.8, 5.6]), "rt-container", "userStone",
                     rot_y=RNG.choice([0.0, math.pi / 2.0]), tint=round(RNG.uniform(0.55, 1.25), 3))

# Farm barns and farmhouses.
for _ in range(10):
    px = RNG.uniform(1280.0, 2220.0)
    pz = RNG.uniform(2080.0, 2520.0)
    if clear_of_roads(px, pz, 22.0):
        add_building(px, pz, 30, 14, 7, "barn", "userWood", rot_y=RNG.choice([0.0, math.pi / 2.0]), roof_h=3.4)
for _ in range(7):
    px = RNG.uniform(1280.0, 2220.0)
    pz = RNG.uniform(1800.0, 3050.0)
    if clear_of_roads(px, pz, 16.0):
        add_building(px, pz, 24, 18, 9, "rt-villa", "userPlaster", roof_h=2.0)

# Beach cafes / low seaside blocks along the Corniche east side.
for cz in range(-2800, 2900, 380):
    px = -2555.0 + RNG.uniform(-8.0, 8.0)
    if clear_of_roads(px, cz, 20.0) and abs(cz) > 1450:
        add_building(px, cz, 30, 20, RNG.choice([11, 14]), "warehouse", "userMarble", rot_y=math.pi / 2.0)

print(f"Buildings: {len(buildings)} (villas glb/townhouse/generic: {villa_count})")

# --------------------------------------------------------------------------
# Landmarks
# --------------------------------------------------------------------------

landmarks = [
    {"kind": "rt-tower", "x": 0, "z": 0, "h": 148, "r": 0, "rotY": 0.0},
    {"kind": "rt-fountain", "x": 48, "z": 48, "h": 0, "r": 9, "rotY": 0.0},
    {"kind": "rt-fountain", "x": -1200, "z": 90, "h": 0, "r": 8, "rotY": 0.0},
    {"kind": "rt-arch", "x": 0, "z": -1150, "h": 43, "r": 0, "rotY": 0.0},
    {"kind": "rt-twist", "x": 300, "z": -300, "h": 105, "r": 0, "rotY": 0.0},
    {"kind": "rt-hole", "x": -300, "z": 300, "h": 78, "r": 0, "rotY": 0.0},
    {"kind": "rt-lean", "x": -300, "z": -300, "h": 88, "r": 0, "rotY": 0.0},
    {"kind": "rt-museum", "x": 500, "z": -700, "h": 26, "r": 0, "rotY": 0.0},
    {"kind": "rt-opera", "x": -700, "z": 500, "h": 22, "r": 0, "rotY": 0.0},
    {"kind": "rt-mosque", "x": 950, "z": 1365, "h": 30, "r": 0, "rotY": 0.0},
    {"kind": "rt-sail", "x": -2560, "z": -1750, "h": 95, "r": 0, "rotY": 0.0},
    {"kind": "rt-parking", "x": -1045, "z": 230, "h": 15, "r": 0, "rotY": 0.0},
    {"kind": "rt-parking", "x": 450, "z": -1250, "h": 15, "r": 0, "rotY": 0.0},
    {"kind": "rt7-stadium", "x": 190, "z": -1400, "h": 34, "r": 130, "rotY": 0.0},
    {"kind": "rt7-cable-bridge", "x": 0, "z": 1600, "h": 60, "r": 0, "rotY": 0.0},
]
for bx in (-1500, -400, 700, 1800):
    landmarks.append({"kind": "rt7-bridge-pier", "x": bx, "z": 1600, "h": 7, "r": 0, "rotY": 0.0})
for lz in (-2400, -1200, -400, 400, 1200, 2400):
    landmarks.append({"kind": "rt-lifeguard", "x": -2810, "z": lz, "h": 6, "r": 0, "rotY": 0.0})
for lm in landmarks:
    lm["y"] = round(ground(lm["x"], lm["z"]), 3)

# --------------------------------------------------------------------------
# Scatter: pools, palms, trees, bushes, lamps, benches
# --------------------------------------------------------------------------

pools = []
for hx, hz, w, d, h in hotels:
    pools.append({"x": hx - 34.0, "y": round(ground(hx - 34.0, hz), 3), "z": hz, "rotY": 0.0, "w": 16.0, "d": 8.0})
for b in buildings:
    if b["kind"] == "rt-villa" and RNG.random() < 0.34:
        px = b["x"] + RNG.uniform(-4.0, 4.0)
        pz = b["z"] + (-15.0 if b["rotY"] == 0.0 else 15.0)
        if clear_of_roads(px, pz, 5.5):
            pools.append({"x": round(px, 2), "y": round(ground(px, pz), 3), "z": round(pz, 2),
                          "rotY": 0.0, "w": 10.0, "d": 5.0})
pools = pools[:130]

palms = []


def add_palm(x, z):
    if not clear_of_roads(x, z, 2.4):
        return
    y = ground(x, z)
    if y < 0.35:
        return
    palms.append({"x": round(x, 2), "y": round(y, 3), "z": round(z, 2),
                  "rotY": round(RNG.uniform(0.0, math.tau), 3), "s": round(RNG.uniform(0.85, 1.25), 3)})


def palm_line(x0, z0, x1, z1, spacing, lateral=0.0):
    length = math.hypot(x1 - x0, z1 - z0)
    n = max(1, int(length / spacing))
    dx = (x1 - x0) / length
    dz = (z1 - z0) / length
    nx, nz = -dz, dx
    for i in range(n + 1):
        t = i / n
        jitter = RNG.uniform(-2.0, 2.0)
        add_palm(x0 + (x1 - x0) * t + nx * (lateral + jitter), z0 + (z1 - z0) * t + nz * (lateral + jitter))


# Corniche promenade (both sides), central axes, downtown ring, canal banks.
palm_line(-2670, -3150, -2670, 3150, 38)
palm_line(-2630, -3150, -2630, 3150, 38)
for side in (-19.0, 19.0):
    palm_line(side, -3150, side, -120, 42)
    palm_line(side, 120, side, 1470, 42)
    palm_line(-2630, side, -120, side, 42)
    palm_line(120, side, 2380, side, 42)
for sx in (-1019.0, 1019.0):
    palm_line(sx, -980, sx, 980, 44)
for sz in (-1019.0, 1019.0):
    palm_line(-980, sz, 980, sz, 44)
palm_line(-1480, 1468, 2180, 1468, 48)
palm_line(-1480, 1732, 2180, 1732, 48)
# Plaza ring + beach clusters + hotel fronts.
for i in range(16):
    a = (i / 16.0) * math.tau + 0.2
    add_palm(math.cos(a) * 112.0, math.sin(a) * 112.0)
for bz in range(-3000, 3100, 130):
    add_palm(-2745 + RNG.uniform(-14.0, 10.0), bz + RNG.uniform(-30.0, 30.0))
for hx, hz, w, d, h in hotels:
    for k in range(-2, 3):
        add_palm(hx - 30.0, hz + k * 14.0)

trees = []
bushes = []


def add_tree(x, z, scale=None):
    if not clear_of_roads(x, z, 2.6):
        return
    y = ground(x, z)
    if y < 0.35:
        return
    trees.append({"x": round(x, 2), "y": round(y, 3), "z": round(z, 2),
                  "rotY": round(RNG.uniform(0.0, math.tau), 3),
                  "s": round(scale if scale else RNG.uniform(0.8, 1.3), 3),
                  "type": "oak", "tint": round(RNG.uniform(0.85, 1.2), 3)})


# Central park block grove.
for _ in range(46):
    add_tree(RNG.uniform(218.0, 382.0), RNG.uniform(-782.0, -618.0))
# Sunset park block.
for _ in range(30):
    add_tree(RNG.uniform(-380.0, -220.0), RNG.uniform(1020.0, 1230.0))
# Hills park.
for _ in range(30):
    add_tree(RNG.uniform(1330.0, 1610.0), RNG.uniform(-1970.0, -1730.0))
# Farm orchard rows.
for ox in range(1260, 2260, 34):
    for oz in range(2680, 3020, 34):
        if RNG.random() > 0.22:
            add_tree(ox + RNG.uniform(-3.0, 3.0), oz + RNG.uniform(-3.0, 3.0), scale=RNG.uniform(0.55, 0.8))
# Plaza garden oaks.
for gx, gz in ((120, 120), (-120, 120), (120, -120), (-120, -120), (150, 0), (-150, 0), (0, 150), (0, -150)):
    add_tree(gx + RNG.uniform(-12.0, 12.0), gz + RNG.uniform(-12.0, 12.0), scale=1.05)
for _ in range(220):
    bx = RNG.uniform(-2600.0, 2350.0)
    bz = RNG.uniform(-3100.0, 3100.0)
    if clear_of_roads(bx, bz, 2.2) and ground(bx, bz) > 0.4 and abs(bz - 1600.0) > 60.0:
        bushes.append({"x": round(bx, 2), "y": round(ground(bx, bz), 3), "z": round(bz, 2),
                       "rotY": round(RNG.uniform(0.0, math.tau), 3),
                       "s": round(RNG.uniform(0.7, 1.2), 3), "tint": round(RNG.uniform(0.85, 1.15), 3)})

lamps = []


def add_lamp(x, z, yaw, side):
    if not clear_of_roads(x, z, 0.4):
        return
    if road_clearance(x, z) > 6.0:
        return  # keep lamps hugging the carriageway edge
    lamps.append({"x": round(x, 2), "y": round(ground(x, z), 3), "z": round(z, 2),
                  "rotY": yaw, "side": side})


def lamp_line(x0, z0, x1, z1, spacing, lateral, yaw, side):
    length = math.hypot(x1 - x0, z1 - z0)
    n = max(1, int(length / spacing))
    dx = (x1 - x0) / length
    dz = (z1 - z0) / length
    nx, nz = -dz, dx
    for i in range(1, n):
        t = i / n
        add_lamp(x0 + (x1 - x0) * t + nx * lateral, z0 + (z1 - z0) * t + nz * lateral, yaw, side)


# Corniche
lamp_line(-2672, -3180, -2672, 3180, 55, 0, math.pi / 2.0, -1)
lamp_line(-2628, -3180, -2628, 3180, 55, 0, -math.pi / 2.0, 1)
# Central + Roses
lamp_line(-18.5, -3180, -18.5, -120, 55, 0, math.pi / 2.0, -1)
lamp_line(18.5, -3180, 18.5, -120, 55, 0, -math.pi / 2.0, 1)
lamp_line(-18.5, 120, -18.5, 3180, 55, 0, math.pi / 2.0, -1)
lamp_line(18.5, 120, 18.5, 3180, 55, 0, -math.pi / 2.0, 1)
lamp_line(-2630, -18.5, -120, -18.5, 55, 0, 0.0, -1)
lamp_line(-2630, 18.5, -120, 18.5, 55, 0, math.pi, 1)
lamp_line(120, -18.5, 2380, -18.5, 55, 0, 0.0, -1)
lamp_line(120, 18.5, 2380, 18.5, 55, 0, math.pi, 1)
# Highways (one side, sparse)
lamp_line(-2630, -3222, 2380, -3222, 90, 0, 0.0, 1)
lamp_line(-2630, 3222, 2380, 3222, 90, 0, math.pi, -1)
lamp_line(2422, -3180, 2422, 3180, 90, 0, -math.pi / 2.0, 1)
# Downtown ring
lamp_line(-1018.5, -980, -1018.5, 980, 60, 0, math.pi / 2.0, -1)
lamp_line(1018.5, -980, 1018.5, 980, 60, 0, -math.pi / 2.0, 1)
lamp_line(-980, -1018.5, 980, -1018.5, 60, 0, 0.0, -1)
lamp_line(-980, 1018.5, 980, 1018.5, 60, 0, math.pi, 1)
# Downtown grid (one side per street)
for gx in (-800, -600, -400, -200, 200, 400, 600, 800):
    lamp_line(gx + 10.5, -980, gx + 10.5, 980, 75, 0, -math.pi / 2.0, 1)
for gz in (-800, -600, -400, -200, 200, 400, 600, 800):
    lamp_line(-980, gz - 10.5, 980, gz - 10.5, 75, 0, 0.0, -1)

benches = []
for i in range(18):
    a = (i / 18.0) * math.tau
    bx = math.cos(a) * 122.0
    bz = math.sin(a) * 122.0
    benches.append({"x": round(bx, 2), "y": round(ground(bx, bz), 3), "z": round(bz, 2),
                    "rotY": round(-a + math.pi / 2.0, 3)})
for bz in range(-2400, 2500, 300):
    bx = -2695.0
    benches.append({"x": bx, "y": round(ground(bx, bz), 3), "z": float(bz), "rotY": -math.pi / 2.0})

print(f"Scatter: palms={len(palms)} trees={len(trees)} bushes={len(bushes)} lamps={len(lamps)} benches={len(benches)} pools={len(pools)}")

# --------------------------------------------------------------------------
# Zones / districts / spawn / stats
# --------------------------------------------------------------------------

zones = {
    "sea": {"minX": -3500, "maxX": -2780, "minZ": -3500, "maxZ": 3500},
    "beach": {"minX": -2960, "maxX": -2610, "minZ": -3500, "maxZ": 3500},
    "marina": {"minX": -3500, "maxX": 2240, "minZ": 1570, "maxZ": 1630},  # the canal water body
    "rtPlaza": {"minX": -150, "maxX": 150, "minZ": -150, "maxZ": 150},
    "richtown": {"minX": -3500, "maxX": 3500, "minZ": -3500, "maxZ": 3500},
    "downtown": {"minX": -1030, "maxX": 1030, "minZ": -1030, "maxZ": 1030},
    "port": {"minX": -1530, "maxX": 1030, "minZ": 1690, "maxZ": 3030},
    "farm": {"minX": 1170, "maxX": 2330, "minZ": 1690, "maxZ": 3030},
    "dunes": {"minX": 2420, "maxX": 3500, "minZ": -3500, "maxZ": 3500},
    "drift": {"minX": 2500, "maxX": 2840, "minZ": -420, "maxZ": -80},
    "mallParking": {"minX": -1430, "maxX": -970, "minZ": 50, "maxZ": 350},
    "parkCentral": {"minX": 210, "maxX": 390, "minZ": -790, "maxZ": -610},
    "parkSunset": {"minX": -390, "maxX": -210, "minZ": 1010, "maxZ": 1240},
    "parkHills": {"minX": 1320, "maxX": 1620, "minZ": -1980, "maxZ": -1720},
}

districts = [
    {"id": "downtown", "name": "Даунтаун", "x": 0, "z": 0, "radiusM": 1050, "biome": "urban"},
    {"id": "corniche-hotels", "name": "Отели Корниша", "x": -2450, "z": 0, "radiusM": 900, "biome": "urban"},
    {"id": "marina-south", "name": "Марина Юг", "x": -1900, "z": -850, "radiusM": 520, "biome": "urban"},
    {"id": "marina-north", "name": "Марина Север", "x": -1900, "z": 850, "radiusM": 520, "biome": "urban"},
    {"id": "mall", "name": "RichTown Mall", "x": -1200, "z": -100, "radiusM": 380, "biome": "urban"},
    {"id": "rich-hills", "name": "Rich Hills", "x": 1650, "z": -1600, "radiusM": 1000, "biome": "urban"},
    {"id": "sunset", "name": "Сансет", "x": 600, "z": 1250, "radiusM": 850, "biome": "urban"},
    {"id": "port", "name": "Порт", "x": -250, "z": 2350, "radiusM": 950, "biome": "urban"},
    {"id": "farm", "name": "Ферма и роща", "x": 1750, "z": 2350, "radiusM": 750, "biome": "park"},
    {"id": "desert-east", "name": "Восточная пустыня", "x": 3000, "z": 0, "radiusM": 1000, "biome": "desert"},
    {"id": "stadium", "name": "Стадион RichTown", "x": 190, "z": -1400, "radiusM": 320, "biome": "urban"},
    {"id": "beach", "name": "Пляж", "x": -2800, "z": 0, "radiusM": 700, "biome": "park"},
]

spawn = {"x": 5.0, "y": round(ground(5.0, 640.0) + 0.4, 3), "z": 640.0, "yaw": 0.0}

flat_heights = []
for iz in range(N):
    for ix in range(N):
        flat_heights.append(round(heights[iz][ix], 3))

total_samples = sum(len(r["samples"]) for r in roads)
road_length_km = 0.0
for r in roads:
    s = r["samples"]
    for i in range(len(s) - 1):
        road_length_km += math.hypot(s[i + 1][0] - s[i][0], s[i + 1][2] - s[i][2]) / 1000.0

for r in roads:
    r.pop("_bridge", None)

data = {
    "schemaVersion": 1,
    "name": "RichTown",
    "layout": "richtown7",
    "units": "metres",
    "seed": 20261030,
    "bounds": {"minX": -3500, "maxX": 3500, "minZ": -3500, "maxZ": 3500},
    "spawn": spawn,
    "districts": districts,
    "zones": zones,
    "terrain": {
        "minX": -3500, "maxX": 3500, "minZ": -3500, "maxZ": 3500,
        "stepM": STEP, "cols": N, "rows": N, "heights": flat_heights,
    },
    "roads": roads,
    "buildings": buildings,
    "landmarks": landmarks,
    "pools": pools,
    "trees": trees,
    "bushes": bushes,
    "palms": palms,
    "lamps": lamps,
    "benches": benches,
    "stats": {
        "terrainVertices": N * N,
        "roadEdges": len(roads),
        "roadSamples": total_samples,
        "roadLengthKm": round(road_length_km, 1),
        "buildings": len(buildings),
        "blenderVillas": sum(1 for b in buildings if b["model"] == "villa"),
        "blenderGlassTowers": sum(1 for b in buildings if b["model"] == "glass_tower"),
        "genericBuildings": sum(1 for b in buildings if b["model"] == "generic"),
        "landmarks": len(landmarks),
        "pools": len(pools),
        "trees": len(trees),
        "bushes": len(bushes),
        "palms": len(palms),
        "lamps": len(lamps),
        "benches": len(benches),
    },
}

# Connectivity self-check: endpoint graph must be one component.
endpoints = {}
for ri, r in enumerate(roads):
    for end in (r["samples"][0], r["samples"][-1]):
        key = (round(end[0]), round(end[2]))
        endpoints.setdefault(key, []).append(ri)
adj = {i: set() for i in range(len(roads))}
for key, ris in endpoints.items():
    for a in ris:
        for b in ris:
            if a != b:
                adj[a].add(b)
seen = set()
stack = [0]
while stack:
    cur = stack.pop()
    if cur in seen:
        continue
    seen.add(cur)
    stack.extend(adj[cur] - seen)
print(f"Connectivity: {len(seen)}/{len(roads)} roads in main component")
orphans = [roads[i]["id"] for i in range(len(roads)) if i not in seen]
if orphans:
    print("ORPHAN ROADS:", orphans[:20])

OUT.parent.mkdir(parents=True, exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"))
print(f"Wrote {OUT} ({OUT.stat().st_size / 1e6:.2f} MB)")
print(f"Stats: {data['stats']}")
