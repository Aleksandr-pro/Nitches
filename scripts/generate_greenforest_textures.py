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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_desert_textures import (  # noqa: E402
    S, add_stones, clip01, fractal, mix, normalize, save_set, smoothstep,
)

SEED = 20261102


def meadow(rng):
    base = fractal(rng, beta=2.1, fmax=90.0)
    fine = fractal(rng, beta=1.6, fmax=420.0)
    dry = fractal(rng, beta=2.4, fmax=36.0)
    albedo = mix((0.13, 0.30, 0.08), (0.28, 0.47, 0.15), clip01(base * 0.65 + fine * 0.45))
    # sun-dried yellow-green patches break the uniform green carpet
    albedo = mix(albedo, (0.44, 0.43, 0.17), smoothstep(0.62, 0.92, dry) * 0.55)
    # dark damp hollows
    albedo = mix(albedo, (0.07, 0.18, 0.06), smoothstep(0.30, 0.05, base) * 0.45)
    # per-pixel blade grain so the carpet does not blur into one wash
    grain = fractal(rng, beta=1.15, fmax=900.0)
    albedo = clip01(albedo + (grain[..., None] - 0.5) * np.array([0.05, 0.13, 0.04])[None, None, :])
    height = fine * 0.55 + base * 0.45
    # dense blade clumps
    albedo, height, _ = add_stones(
        rng, albedo, height, 5200, 1.1, 2.8,
        [(0.20, 0.42, 0.11), (0.27, 0.50, 0.15), (0.16, 0.34, 0.09), (0.38, 0.48, 0.18)],
        bump_amp=0.08, angular=True)
    # scattered tiny flower flecks (white / yellow / violet)
    flecks = rng.random((S, S))
    for thresh, col in ((0.9985, (0.92, 0.90, 0.82)), (0.9970, (0.85, 0.70, 0.16)), (0.9955, (0.45, 0.36, 0.62))):
        m = flecks > thresh
        albedo[m] = col
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
        rng, albedo, height, 2600, 2.2, 5.5,
        [(0.38, 0.24, 0.10), (0.45, 0.30, 0.13), (0.30, 0.20, 0.09), (0.50, 0.36, 0.16)],
        bump_amp=0.10, angular=True)
    rough = np.full((S, S), 0.97)
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
    rough = rough * (1.0 - pm) + 0.18 * pm
    albedo, height, _ = add_stones(
        rng, albedo, height, 500, 2.0, 6.0,
        [(0.30, 0.28, 0.26), (0.36, 0.33, 0.29)], bump_amp=0.14, angular=True)
    return albedo, height, rough


def rock_gray(rng):
    base = fractal(rng, beta=1.9, fmax=160.0)
    warp = fractal(rng, beta=2.2, fmax=40.0)
    yy = np.linspace(0.0, 1.0, S)[:, None] * np.ones((1, S))
    band = 0.5 + 0.5 * np.sin(2.0 * np.pi * (yy * 5.0 + warp * 0.9))
    t = clip01(band * 0.18 + base * 0.82)
    albedo = mix((0.26, 0.27, 0.28), (0.50, 0.51, 0.52), t)
    # cool blue-gray shadowed facets and warm lichen dusting
    facet = fractal(rng, beta=2.6, fmax=18.0)
    albedo = mix(albedo, (0.30, 0.34, 0.40), smoothstep(0.62, 0.92, facet) * 0.35)
    height = base
    # fractures: thin dark ridges of a high-frequency field
    frac_src = fractal(rng, beta=1.5, fmax=300.0)
    frac = smoothstep(0.46, 0.50, frac_src) * (1.0 - smoothstep(0.50, 0.54, frac_src))
    albedo = mix(albedo, (0.12, 0.125, 0.13), frac * 0.65)
    height = height - frac * 0.35
    # moss creeps into the low, damp parts of the height field
    moss = fractal(rng, beta=2.4, fmax=55.0)
    albedo = mix(albedo, (0.13, 0.26, 0.10), smoothstep(0.58, 0.90, moss) * smoothstep(0.55, 0.25, base) * 0.65)
    rough = np.full((S, S), 0.94)
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
        rng, albedo, height, 1500, 2.5, 8.0,
        [(0.30, 0.21, 0.12), (0.36, 0.26, 0.15), (0.26, 0.18, 0.10)],
        bump_amp=0.18, angular=True)
    rough = np.full((S, S), 0.95)
    return albedo, height, rough


def main():
    rng = np.random.default_rng(SEED)
    a, h, r = meadow(rng)
    save_set("gf_meadow", a, h, r, 1.8)
    a, h, r = forest_floor(rng)
    save_set("gf_forest_floor", a, h, r, 2.2)
    a, h, r = mud(rng)
    save_set("gf_mud", a, h, r, 1.6)
    a, h, r = rock_gray(rng)
    save_set("gf_rock_gray", a, h, r, 2.6)
    a, h, r = field_soil(rng)
    save_set("gf_field_soil", a, h, r, 2.2)
    print("[forest-textures] done")


if __name__ == "__main__":
    main()
