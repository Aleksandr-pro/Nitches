#!/usr/bin/env python3
"""Procedural seamless PBR texture sets for the Desert world (0.2.50).

The owner asked for realistic ground/trail surfaces made by us, not a
single flat picture.  Each set is generated as albedo + tangent-space
normal (derived from a height field) + roughness, tiling seamlessly:

  dz_packed_earth  cracked packed dirt with embedded pebbles
  dz_trail_gravel  angular gravel for dirt roads / trails
  dz_sand_dune     wind-rippled dune sand with fine grain
  dz_salt_crust    polygonal salt plates with dark seams
  dz_rock_red      layered red sandstone for rock terrain / boulders
  dz_cactus_skin   ribbed saguaro skin with areoles and spine dots

Run:  PYTHONPATH=<numpy+pillow> python3 scripts/generate_desert_textures.py
Output: src/assets/textures/realworld/dz_*.jpg (staged by
scripts/sync-native-assets.mjs like every other runtime texture).
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "assets", "textures", "realworld")
S = 1024
SEED = 20261030


def clip01(a):
    return np.clip(a, 0.0, 1.0)


def normalize(a):
    lo, hi = np.percentile(a, 1.0), np.percentile(a, 99.0)
    return clip01((a - lo) / max(hi - lo, 1e-9))


def smoothstep(e0, e1, x):
    t = clip01((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def fractal(rng, beta=2.0, fmax=180.0, size=S):
    """Periodic fractal noise via a filtered FFT of white noise."""
    white = rng.standard_normal((size, size))
    F = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    r2 = fx * fx + fy * fy
    amp = (1.0 + r2) ** (-beta / 2.0)
    amp *= np.exp(-r2 / (2.0 * fmax * fmax))
    amp[0, 0] = 0.0
    return normalize(np.real(np.fft.ifft2(F * amp)))


def normal_from_height(h, strength=2.2):
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    inv = 1.0 / np.sqrt(gx * gx + gy * gy + nz * nz)
    return np.stack([
        clip01(0.5 - 0.5 * gx * inv),
        clip01(0.5 - 0.5 * gy * inv),
        clip01(0.5 + 0.5 * nz * inv),
    ], axis=-1)


def save_jpg(name, arr):
    img = Image.fromarray((clip01(arr) * 255.0).astype(np.uint8))
    img.save(os.path.join(OUT, name), quality=90)
    print("wrote", name)


def save_set(prefix, albedo, height, rough, normal_strength=2.2):
    save_jpg(f"{prefix}.jpg", albedo)
    save_jpg(f"{prefix}_normal.jpg", normal_from_height(height, normal_strength))
    if rough is not None:
        save_jpg(f"{prefix}_roughness.jpg", np.stack([rough] * 3, axis=-1))


def add_stones(rng, albedo, height, count, rmin, rmax, palette, bump_amp=0.22, angular=True):
    """Draw wrapped stones/pebbles onto albedo and a bump layer."""
    alb_img = Image.fromarray((clip01(albedo) * 255).astype(np.uint8))
    bump = Image.new("L", (S, S), 0)
    da = ImageDraw.Draw(alb_img)
    db = ImageDraw.Draw(bump)
    for _ in range(count):
        cx, cy = rng.random() * S, rng.random() * S
        r = rng.uniform(rmin, rmax)
        col = palette[int(rng.integers(0, len(palette)))]
        lum = 0.299 * col[0] + 0.587 * col[1] + 0.114 * col[2]
        sat = rng.uniform(0.70, 1.0)
        bright = rng.uniform(0.80, 1.10)
        col = tuple(int(clip01((lum + (c - lum) * sat) * bright) * 255) for c in col)
        dark = tuple(int(c * 0.68) for c in col)
        bump_v = int(rng.uniform(120, 255))
        if angular:
            npts = int(rng.integers(5, 8))
            base_ang = rng.random() * math.tau
            pts = []
            for k in range(npts):
                ang = base_ang + math.tau * k / npts
                rr = r * rng.uniform(0.62, 1.12)
                pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr * rng.uniform(0.7, 1.0)))
            for ox in (-S, 0, S):
                for oy in (-S, 0, S):
                    pp = [(x + ox, y + oy) for (x, y) in pts]
                    da.polygon(pp, fill=col, outline=dark)
                    db.polygon(pp, fill=bump_v)
        else:
            rx, ry = r, r * rng.uniform(0.65, 0.95)
            for ox in (-S, 0, S):
                for oy in (-S, 0, S):
                    box = [cx - rx + ox, cy - ry + oy, cx + rx + ox, cy + ry + oy]
                    da.ellipse(box, fill=col, outline=dark)
                    db.ellipse(box, fill=bump_v)
    bump = bump.filter(ImageFilter.GaussianBlur(1.1))
    bump_arr = np.asarray(bump, dtype=np.float64) / 255.0
    return np.asarray(alb_img, dtype=np.float64) / 255.0, height + bump_arr * bump_amp, bump_arr


def mix(c0, c1, t):
    c0 = np.asarray(c0, dtype=np.float64)
    c1 = np.asarray(c1, dtype=np.float64)
    if c0.ndim == 1:
        c0 = c0[None, None, :]
    if c1.ndim == 1:
        c1 = c1[None, None, :]
    if t.ndim == 2:
        t = t[..., None]
    return c0 * (1.0 - t) + c1 * t


def packed_earth(rng):
    large = fractal(rng, beta=2.1, fmax=26)
    mid = fractal(rng, beta=2.3, fmax=64)
    fine = fractal(rng, beta=2.7, fmax=320)
    grain = fractal(rng, beta=3.3, fmax=500)
    height = large * 0.40 + mid * 0.22 + fine * 0.30 + grain * 0.08
    cn = fractal(rng, beta=2.0, fmax=80)
    crack = smoothstep(0.026, 0.0, np.abs(cn - 0.5))
    cn2 = fractal(rng, beta=2.2, fmax=150)
    crack = np.maximum(crack, smoothstep(0.016, 0.0, np.abs(cn2 - 0.5)) * 0.75)
    cn3 = fractal(rng, beta=2.4, fmax=260)
    crack = np.maximum(crack, smoothstep(0.010, 0.0, np.abs(cn3 - 0.5)) * 0.5)
    height -= crack * 0.30
    albedo = mix((0.56, 0.42, 0.28), (0.72, 0.57, 0.39), large)
    albedo = mix(albedo, (0.47, 0.33, 0.23), smoothstep(0.55, 0.85, mid) * 0.35)
    albedo = mix(albedo, (0.78, 0.66, 0.47), smoothstep(0.62, 0.90, large) * 0.25)
    albedo = albedo * (0.84 + fine[..., None] * 0.20 + grain[..., None] * 0.12)
    albedo = mix(albedo, (0.36, 0.27, 0.19), crack * 0.8)
    palette = [(0.52, 0.47, 0.42), (0.60, 0.52, 0.44), (0.46, 0.40, 0.35), (0.64, 0.56, 0.46)]
    albedo, height, bump = add_stones(rng, albedo, height, 700, 2.0, 7.0, palette, 0.16, angular=False)
    rough = clip01(0.94 - bump * 0.10 + crack * 0.03 + (grain - 0.5) * 0.05)
    return albedo, height, rough


def trail_gravel(rng):
    large = fractal(rng, beta=2.1, fmax=22)
    mid = fractal(rng, beta=2.3, fmax=70)
    fine = fractal(rng, beta=2.8, fmax=380)
    grain = fractal(rng, beta=3.4, fmax=500)
    height = large * 0.26 + mid * 0.18 + fine * 0.26 + grain * 0.10
    albedo = mix((0.48, 0.39, 0.30), (0.60, 0.50, 0.38), large)
    albedo = mix(albedo, (0.42, 0.34, 0.27), smoothstep(0.55, 0.85, mid) * 0.3)
    albedo = albedo * (0.82 + fine[..., None] * 0.20 + grain[..., None] * 0.16)
    palette = [(0.54, 0.51, 0.47), (0.58, 0.52, 0.45), (0.47, 0.42, 0.37),
               (0.63, 0.57, 0.49), (0.53, 0.44, 0.36), (0.44, 0.42, 0.40)]
    albedo, height, bump = add_stones(rng, albedo, height, 2600, 3.5, 15.0, palette, 0.30, angular=True)
    albedo, height, bump2 = add_stones(rng, albedo, height, 800, 1.5, 4.5, palette, 0.12, angular=False)
    rough = clip01(0.96 - np.maximum(bump, bump2) * 0.10 + (grain - 0.5) * 0.04)
    return albedo, height, rough


def sand_dune(rng):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    warp = fractal(rng, beta=2.0, fmax=18)
    ang = 0.62
    phase = (xx * math.cos(ang) + yy * math.sin(ang)) / 47.0 * math.tau + warp * 5.2
    ripple = 0.5 + 0.5 * np.sin(phase)
    ripple = ripple ** 1.35
    ripple2 = 0.5 + 0.5 * np.sin(phase * 3.7 + 1.3)
    fine = fractal(rng, beta=3.0, fmax=420)
    grain = fractal(rng, beta=3.4, fmax=500)
    height = ripple * 0.55 + ripple2 * 0.12 + fine * 0.18 + fractal(rng, beta=2.2, fmax=30) * 0.15
    slope = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    albedo = mix((0.80, 0.63, 0.42), (0.90, 0.74, 0.52), height)
    albedo = albedo * (0.92 - clip01(slope * 3.0)[..., None] * 0.10 + fine[..., None] * 0.07 + grain[..., None] * 0.09)
    palette = [(0.66, 0.58, 0.48), (0.72, 0.64, 0.52)]
    albedo, height, _b = add_stones(rng, albedo, height, 120, 1.5, 4.5, palette, 0.08, angular=False)
    rough = clip01(0.97 + (fine - 0.5) * 0.03)
    return albedo, height, rough


def salt_crust(rng):
    n = 512
    pts = rng.random((170, 2)) * n
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    f1 = np.full((n, n), 1e18)
    f2 = np.full((n, n), 1e18)
    owner = np.zeros((n, n), dtype=np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px); dx = np.minimum(dx, n - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, n - dy)
        d = dx * dx + dy * dy
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        owner = np.where(closer, i, owner)
        f1 = np.where(closer, d, f1)
    edge = np.sqrt(f2) - np.sqrt(f1)
    shade = rng.uniform(0.80, 1.0, size=len(pts))[owner]
    crack = smoothstep(2.6, 0.4, edge)
    alb512 = mix((0.90, 0.89, 0.83), (0.97, 0.96, 0.92), (shade - 0.80) / 0.20)
    alb512 = mix(alb512, (0.62, 0.56, 0.47), crack * 0.75)
    h512 = 0.35 + shade * 0.25 + clip01(edge / 16.0) * 0.22 - crack * 0.30
    alb_img = Image.fromarray((clip01(alb512) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
    h_img = Image.fromarray((clip01(h512) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
    albedo = np.asarray(alb_img, dtype=np.float64) / 255.0
    height = np.asarray(h_img, dtype=np.float64) / 255.0
    fine = fractal(rng, beta=2.9, fmax=380)
    grain = fractal(rng, beta=3.4, fmax=500)
    dirt = fractal(rng, beta=2.2, fmax=26)
    height = height * 0.78 + fine * 0.12 + grain * 0.06
    albedo = albedo * (0.93 + fine[..., None] * 0.08 + grain[..., None] * 0.06)
    albedo = mix(albedo, (0.80, 0.72, 0.60), smoothstep(0.55, 0.85, dirt) * 0.28)
    sparkle = (rng.random((S, S)) > 0.9985).astype(np.float64)
    albedo = clip01(albedo + sparkle[..., None] * 0.25)
    rough = clip01(0.50 + fine * 0.18 + dirt * 0.10 - sparkle * 0.2)
    return albedo, height, rough


def rock_red(rng):
    yy, _xx = np.mgrid[0:S, 0:S].astype(np.float64)
    base = fractal(rng, beta=1.9, fmax=110)
    mid = fractal(rng, beta=2.3, fmax=70)
    fine = fractal(rng, beta=2.7, fmax=340)
    grain = fractal(rng, beta=3.3, fmax=500)
    warp = fractal(rng, beta=2.0, fmax=20)
    band = 0.5 + 0.5 * np.sin(math.tau * (yy / S * 13.0 + warp * 2.2))
    t = clip01(band * 0.38 + base * 0.62)
    steps = np.floor(t * 7.0) / 7.0
    t2 = clip01(t * 0.55 + steps * 0.45)
    albedo = mix((0.43, 0.25, 0.17), (0.65, 0.39, 0.26), t2)
    albedo = mix(albedo, (0.76, 0.54, 0.39), smoothstep(0.74, 0.96, t2) * 0.55)
    albedo = mix(albedo, (0.46, 0.37, 0.31), smoothstep(0.58, 0.88, mid) * 0.30)
    fn = fractal(rng, beta=2.1, fmax=120)
    frac = smoothstep(0.014, 0.0, np.abs(fn - 0.5))
    albedo = mix(albedo, (0.28, 0.18, 0.13), frac * 0.55)
    col_noise = normalize(np.asarray(Image.fromarray(
        (rng.random((24, S)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC), dtype=np.float64) / 255.0)
    albedo = albedo * (0.82 + fine[..., None] * 0.20 + grain[..., None] * 0.14 + col_noise[..., None] * 0.05)
    height = base * 0.48 + steps * 0.20 + fine * 0.24 + grain * 0.08 - frac * 0.18
    palette = [(0.50, 0.34, 0.24), (0.58, 0.41, 0.30)]
    albedo, height, _b = add_stones(rng, albedo, height, 220, 2.0, 5.5, palette, 0.12, angular=True)
    rough = clip01(0.95 + (grain - 0.5) * 0.05)
    return albedo, height, rough


def cactus_skin(rng):
    ribs = 18
    u = np.linspace(0.0, 1.0, S, endpoint=False)[None, :] * np.ones((S, 1))
    warp = fractal(rng, beta=2.0, fmax=14)
    uw = u + (warp - 0.5) * 0.030
    prof = 0.5 + 0.5 * np.cos(math.tau * ribs * uw)
    height = prof ** 0.8 * 0.85
    fine = fractal(rng, beta=2.8, fmax=300)
    height += fine * 0.10
    albedo = mix((0.13, 0.29, 0.12), (0.27, 0.49, 0.22), prof)
    rib_gain = rng.uniform(0.90, 1.08, size=ribs + 1)
    rib_gain[ribs] = rib_gain[0]
    rib_id = np.clip((uw * ribs).astype(np.int32), 0, ribs)
    albedo = albedo * rib_gain[rib_id][..., None]
    bleach = fractal(rng, beta=2.2, fmax=20)
    albedo = mix(albedo, (0.42, 0.52, 0.26), smoothstep(0.60, 0.90, bleach) * 0.22)
    albedo = albedo * (0.93 + fine[..., None] * 0.12)
    alb_img = Image.fromarray((clip01(albedo) * 255).astype(np.uint8))
    bump = Image.new("L", (S, S), 0)
    da = ImageDraw.Draw(alb_img)
    db = ImageDraw.Draw(bump)
    for k in range(ribs):
        x0 = (k + 0.5) * S / ribs
        sway_a = rng.uniform(1.5, 4.0)
        sway_k = int(rng.integers(1, 4))
        sway_p = rng.random() * math.tau
        y = rng.uniform(0, 26)
        while y < S:
            if rng.random() > 0.10:
                x = x0 + sway_a * math.sin(math.tau * sway_k * y / S + sway_p) + rng.uniform(-1.5, 1.5)
                rx = rng.uniform(2.2, 4.2)
                ry = rx * rng.uniform(0.6, 0.85)
                tan = int(rng.uniform(185, 225))
                da.ellipse([x - rx, y - ry, x + rx, y + ry], fill=(tan, int(tan * 0.90), int(tan * 0.68)))
                da.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(240, 232, 198))
                db.ellipse([x - 2, y - 2, x + 2, y + 2], fill=200)
            y += rng.uniform(20, 38)
    bump = bump.filter(ImageFilter.GaussianBlur(0.8))
    height += np.asarray(bump, dtype=np.float64) / 255.0 * 0.10
    albedo = np.asarray(alb_img, dtype=np.float64) / 255.0
    rough = clip01(0.78 + (1.0 - prof) * 0.10)
    return albedo, height, rough


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)
    a, h, r = packed_earth(rng)
    save_set("dz_packed_earth", a, h, r, 2.4)
    a, h, r = trail_gravel(rng)
    save_set("dz_trail_gravel", a, h, r, 2.6)
    a, h, r = sand_dune(rng)
    save_set("dz_sand_dune", a, h, r, 2.0)
    a, h, r = salt_crust(rng)
    save_set("dz_salt_crust", a, h, r, 2.4)
    a, h, r = rock_red(rng)
    save_set("dz_rock_red", a, h, r, 2.4)
    a, h, r = cactus_skin(rng)
    save_set("dz_cactus_skin", a, h, r, 3.0)
    print("[desert-textures] done")


if __name__ == "__main__":
    main()
