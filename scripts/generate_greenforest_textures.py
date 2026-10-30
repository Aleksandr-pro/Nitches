#!/usr/bin/env python3
"""Procedural seamless PBR texture sets for the GreenForest world (0.2.54).

Same in-house approach as the Desert sets: albedo + tangent-space
normal (from a height field) + roughness, tiling seamlessly, all
generated from seeded fractal noise so the look is reproducible:

  gf_meadow       living meadow grass with dry patches and flower flecks
  gf_forest_floor leaf/needle litter with moss patches
  gf_mud          wet clayey mud with smooth puddle-sheen patches
  gf_rock_gray    fractured gray cliff rock with mossy crevices
  gf_field_soil   plowed field rows with soil clods

Run:  python3 scripts/generate_greenforest_textures.py
Output: src/assets/textures/realworld/gf_*.jpg (staged by
scripts/sync-native-assets.mjs like every other runtime texture).
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_desert_textures import (  # noqa: E402
    S, add_stones, clip01, fractal, mix, normalize, save_set, smoothstep,
)

SEED = 20261102



def _pil_detail_pass(rng, albedo, height, strokes):
    """Draw wrapped micro-strokes (fn(draw, x, y)) on albedo/height."""
    img = Image.fromarray((clip01(albedo) * 255).astype(np.uint8))
    him = Image.fromarray((clip01(height) * 255).astype(np.uint8))
    da = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(him)
    for fn, count in strokes:
        for _ in range(count):
            x, y = float(rng.random() * S), float(rng.random() * S)
            for ox in (0, -S, S):
                for oy in (0, -S, S):
                    fn(rng, da, dh, x + ox, y + oy)
    return (np.asarray(img).astype(np.float64) / 255.0,
            np.asarray(him).astype(np.float64) / 255.0)



def _crack_walk(rng, da, dh, x, y):
    # joint-set fractures: broken angular grooves drawn segment by
    # segment with jitter, gaps and varying width; no harsh core line —
    # the groove shading comes from the normal map
    ang = (0.0 if rng.random() < 0.55 else 1.5708) \
        + float(rng.uniform(-0.4, 0.4))
    px, py = x, y
    for _ in range(int(rng.integers(8, 16))):
        ang += float(rng.uniform(-0.24, 0.24))
        ln = float(rng.uniform(7.0, 13.0))
        nx = px + np.cos(ang) * ln + float(rng.uniform(-1.2, 1.2))
        ny = py + np.sin(ang) * ln + float(rng.uniform(-1.2, 1.2))
        if rng.random() > 0.14:
            wdt = int(rng.integers(3, 6))
            # height-only groove: albedo lines always read as drawn-on
            dh.line([(px, py), (nx, ny)], fill=72, width=wdt + 1)
        px, py = nx, ny

def _grass_stroke(rng, da, dh, x, y):
    ang = float(rng.uniform(-0.5, 0.5)) - 1.57
    ln = float(rng.uniform(5.0, 11.0))
    bend = float(rng.uniform(-2.0, 2.0))
    col = (int(rng.uniform(52, 96)), int(rng.uniform(110, 165)),
           int(rng.uniform(30, 58)))
    mx, my = x + bend * 0.4, y - ln * 0.55
    tx, ty = x + bend, y - ln
    da.line([(x, y), (mx, my), (tx, ty)], fill=col, width=2)
    dh.line([(x, y), (mx, my), (tx, ty)], fill=235, width=2)


def _twig_stroke(rng, da, dh, x, y):
    ang = float(rng.random() * 3.14159)
    ln = float(rng.uniform(9.0, 26.0))
    dx, dy = np.cos(ang) * ln, np.sin(ang) * ln
    col = (int(rng.uniform(52, 88)), int(rng.uniform(36, 60)),
           int(rng.uniform(20, 34)))
    da.line([(x, y), (x + dx, y + dy)], fill=col, width=3)
    dh.line([(x, y), (x + dx, y + dy)], fill=225, width=3)


def _needle_stroke(rng, da, dh, x, y):
    for _ in range(4):
        ang = float(rng.random() * 3.14159)
        ln = float(rng.uniform(4.0, 8.0))
        dx, dy = np.cos(ang) * ln, np.sin(ang) * ln
        col = (int(rng.uniform(30, 58)), int(rng.uniform(64, 102)),
               int(rng.uniform(22, 40)))
        da.line([(x, y), (x + dx, y + dy)], fill=col, width=2)

def meadow(rng):
    base = fractal(rng, beta=2.1, fmax=90.0)
    fine = fractal(rng, beta=1.6, fmax=420.0)
    dry = fractal(rng, beta=2.4, fmax=36.0)
    albedo = mix((0.13, 0.30, 0.08), (0.28, 0.47, 0.15), clip01(base * 0.65 + fine * 0.45))
    # sun-dried yellow-green patches break the uniform green carpet
    albedo = mix(albedo, (0.44, 0.43, 0.17), smoothstep(0.60, 0.92, dry) * 0.68)
    # worn dirt exposures where the sward thins out
    dirt = fractal(rng, beta=2.2, fmax=60.0)
    albedo = mix(albedo, (0.23, 0.165, 0.095), smoothstep(0.68, 0.95, dirt) * smoothstep(0.45, 0.15, base) * 0.55)
    # dark damp hollows
    albedo = mix(albedo, (0.07, 0.18, 0.06), smoothstep(0.30, 0.05, base) * 0.45)
    # per-pixel blade grain so the carpet does not blur into one wash
    grain = fractal(rng, beta=1.15, fmax=900.0)
    albedo = clip01(albedo + (grain[..., None] - 0.5) * np.array([0.05, 0.13, 0.04])[None, None, :])
    height = fine * 0.55 + base * 0.45
    # dense blade clumps
    albedo, height, _ = add_stones(
        rng, albedo, height, 9200, 1.0, 2.4,
        [(0.20, 0.42, 0.11), (0.27, 0.50, 0.15), (0.16, 0.34, 0.09), (0.38, 0.48, 0.18)],
        bump_amp=0.08, angular=True)
    # scattered tiny flower flecks (white / yellow / violet)
    flecks = rng.random((S, S))
    for thresh, col in ((0.9985, (0.92, 0.90, 0.82)), (0.9970, (0.85, 0.70, 0.16)), (0.9955, (0.45, 0.36, 0.62))):
        m = flecks > thresh
        albedo[m] = col
    albedo, height = _pil_detail_pass(rng, albedo, height, [(_grass_stroke, 2800)])
    rough = np.full((S, S), 0.96)
    return albedo, height, rough


def forest_floor(rng):
    base = fractal(rng, beta=2.0, fmax=120.0)
    fine = fractal(rng, beta=1.7, fmax=380.0)
    moss = fractal(rng, beta=2.3, fmax=48.0)
    albedo = mix((0.13, 0.095, 0.055), (0.25, 0.185, 0.10), clip01(base * 0.6 + fine * 0.5))
    # needle-brown warm patches (old spruce litter)
    albedo = mix(albedo, (0.32, 0.20, 0.10), smoothstep(0.60, 0.90, base) * 0.40)
    # moss takes over damp low-frequency patches
    albedo = mix(albedo, (0.09, 0.21, 0.07), smoothstep(0.55, 0.88, moss) * 0.70)
    height = fine * 0.7 + base * 0.3
    # fallen leaf litter flecks
    albedo, height, _ = add_stones(
        rng, albedo, height, 4700, 2.0, 5.2,
        [(0.38, 0.24, 0.10), (0.45, 0.30, 0.13), (0.30, 0.20, 0.09), (0.50, 0.36, 0.16)],
        bump_amp=0.10, angular=True)
    # damp near-black pockets under the litter
    albedo = mix(albedo, (0.055, 0.045, 0.03), smoothstep(0.34, 0.08, base) * 0.45)
    albedo, height = _pil_detail_pass(rng, albedo, height, [(_twig_stroke, 850), (_needle_stroke, 1500)])
    rough = np.full((S, S), 0.97) - smoothstep(0.55, 0.88, moss) * 0.09
    return albedo, height, rough


def mud(rng):
    base = fractal(rng, beta=2.2, fmax=70.0)
    fine = fractal(rng, beta=1.8, fmax=260.0)
    puddle = fractal(rng, beta=2.5, fmax=26.0)
    albedo = mix((0.11, 0.08, 0.05), (0.23, 0.165, 0.10), clip01(base * 0.7 + fine * 0.4))
    # grayish wet clay smears
    albedo = mix(albedo, (0.24, 0.22, 0.18), smoothstep(0.64, 0.94, base) * 0.35)
    height = base * 0.6 + fine * 0.4
    # puddle patches: flatter and much smoother (sky sheen)
    pm = smoothstep(0.62, 0.85, puddle)
    height = height * (1.0 - pm * 0.75) + 0.35 * pm
    rough = np.full((S, S), 0.82)
    rough = rough * (1.0 - pm) + 0.12 * pm
    albedo = mix(albedo, (0.075, 0.06, 0.045), pm * 0.55)
    albedo, height, _ = add_stones(
        rng, albedo, height, 850, 2.0, 6.0,
        [(0.30, 0.28, 0.26), (0.36, 0.33, 0.29)], bump_amp=0.14, angular=True)
    return albedo, height, rough


def rock_gray(rng):
    base = fractal(rng, beta=1.9, fmax=150.0)
    warp = fractal(rng, beta=2.2, fmax=42.0)
    yy = np.linspace(0.0, 1.0, S)[:, None] * np.ones((1, S))
    strata = yy * 7.0 + warp * 1.1 + base * 0.35
    band_id = np.floor(strata)
    band_frac = strata - band_id
    band_tint = fractal(rng, beta=2.8, fmax=10.0)
    # angular facet plateaus: quantised low-frequency field
    facet_src = fractal(rng, beta=2.1, fmax=90.0)
    levels = 6.0
    q = np.floor(facet_src * levels) / levels
    plateau = q + (facet_src - q) * 0.35
    shade = clip01(plateau * 0.72 + base * 0.38 + (band_frac - 0.5) * 0.10)
    albedo = mix((0.20, 0.205, 0.215), (0.58, 0.59, 0.60), shade)
    # warm/cool tint alternating per stratum band
    warm = np.mod(band_id, 2.0) * 0.5 + band_tint * 0.5
    albedo = mix(albedo, (0.50, 0.46, 0.40), smoothstep(0.55, 0.90, warm) * 0.22)
    albedo = mix(albedo, (0.32, 0.37, 0.44), smoothstep(0.45, 0.10, warm) * 0.20)
    # sediment dust in the band seams
    seam = 1.0 - smoothstep(0.0, 0.16, np.minimum(band_frac, 1.0 - band_frac))
    albedo = mix(albedo, (0.34, 0.30, 0.24), seam * 0.30)
    height = plateau * 0.62 + base * 0.38 + seam * -0.05
    # granular speckle
    grain = fractal(rng, beta=1.2, fmax=900.0)
    albedo = clip01(albedo + (grain[..., None] - 0.5) * 0.09)
    # moss creeps over damp low facets
    moss = fractal(rng, beta=2.4, fmax=55.0)
    albedo = mix(albedo, (0.13, 0.26, 0.10), smoothstep(0.58, 0.90, moss) * smoothstep(0.55, 0.25, base) * 0.60)
    # pale lichen dusting on high facets
    lich = fractal(rng, beta=2.6, fmax=70.0)
    albedo = mix(albedo, (0.56, 0.58, 0.49), smoothstep(0.72, 0.96, lich) * smoothstep(0.55, 0.85, base) * 0.26)
    height = normalize(height)
    # big jagged fractures cut through everything
    albedo, height = _pil_detail_pass(rng, albedo, height, [(_crack_walk, 26)])
    rough = np.full((S, S), 0.94) - smoothstep(0.58, 0.90, moss) * 0.05
    return albedo, normalize(height), rough

def field_soil(rng):
    base = fractal(rng, beta=2.1, fmax=90.0)
    warp = fractal(rng, beta=2.3, fmax=30.0)
    xx = np.ones((S, 1)) * np.linspace(0.0, 1.0, S)[None, :]
    rows = 0.5 + 0.5 * np.sin(2.0 * np.pi * (xx * 26.0 + warp * 0.7))
    albedo = mix((0.20, 0.14, 0.085), (0.34, 0.24, 0.14), clip01(rows * 0.45 + base * 0.65))
    # sparse green shoots along the row crests
    shoots = smoothstep(0.78, 0.98, rows) * smoothstep(0.45, 0.75, fractal(rng, beta=1.8, fmax=200.0))
    albedo = mix(albedo, (0.20, 0.38, 0.12), shoots * 0.55)
    height = rows * 0.65 + base * 0.35
    albedo, height, _ = add_stones(
        rng, albedo, height, 2300, 2.5, 8.0,
        [(0.30, 0.21, 0.12), (0.36, 0.26, 0.15), (0.26, 0.18, 0.10)],
        bump_amp=0.18, angular=True)
    rough = np.full((S, S), 0.95)
    return albedo, height, rough


def main():
    rng = np.random.default_rng(SEED)
    a, h, r = meadow(rng)
    save_set("gf_meadow", a, h, r, 2.6)
    a, h, r = forest_floor(rng)
    save_set("gf_forest_floor", a, h, r, 2.6)
    a, h, r = mud(rng)
    save_set("gf_mud", a, h, r, 1.6)
    a, h, r = rock_gray(rng)
    save_set("gf_rock_gray", a, h, r, 3.6)
    a, h, r = field_soil(rng)
    save_set("gf_field_soil", a, h, r, 2.2)
    print("[forest-textures] done")


if __name__ == "__main__":
    main()
