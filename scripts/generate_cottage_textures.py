#!/usr/bin/env python3
"""Generate the Sail Island cottage PBR texture family.

The source albedo images are the photographic textures already approved
for RichTown.  This script creates cottage-specific derivatives with
matching tangent-space normal maps and, importantly, real roughness
variation maps instead of one flat roughness number per material.

Outputs are 1024x1024, tileable JPGs in src/assets/textures/realworld:
    cottage_<name>.jpg
    cottage_<name>_normal.jpg
    cottage_<name>_roughness.jpg

Requires Pillow and NumPy.  The generated files are committed, so the
normal game CI does not need to run this script.
"""

from pathlib import Path
import math

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
TEXTURE_DIR = ROOT / "src" / "assets" / "textures" / "realworld"
SIZE = 1024
RNG = np.random.default_rng(20261028)


def load(name: str) -> np.ndarray:
    image = Image.open(TEXTURE_DIR / name).convert("RGB")
    if image.size != (SIZE, SIZE):
        image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return np.asarray(image).astype(np.float32) / 255.0


def save(name: str, array: np.ndarray) -> None:
    data = np.clip(array, 0.0, 1.0)
    if data.ndim == 2:
        image = Image.fromarray((data * 255.0).astype(np.uint8), mode="L").convert("RGB")
    else:
        image = Image.fromarray((data * 255.0).astype(np.uint8), mode="RGB")
    image.save(TEXTURE_DIR / name, quality=92, subsampling=1, optimize=True)
    print(name)


def blur(array: np.ndarray, radius: float) -> np.ndarray:
    if radius <= 0:
        return array.copy()
    clipped = np.clip(array, 0.0, 1.0)
    if clipped.ndim == 2:
        image = Image.fromarray((clipped * 255.0).astype(np.uint8), mode="L")
        return np.asarray(image.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0
    image = Image.fromarray((clipped * 255.0).astype(np.uint8), mode="RGB")
    return np.asarray(image.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


def luminance(array: np.ndarray) -> np.ndarray:
    return array[..., 0] * 0.2126 + array[..., 1] * 0.7152 + array[..., 2] * 0.0722


def periodic_noise(grid_x: int, grid_y: int | None = None, seed_offset: int = 0) -> np.ndarray:
    """Smooth tileable value noise made by cropping the centre of a 3x3 tile."""
    if grid_y is None:
        grid_y = grid_x
    generator = np.random.default_rng(20261028 + seed_offset + grid_x * 131 + grid_y * 17)
    small = generator.random((grid_y, grid_x), dtype=np.float32)
    tiled = np.tile(small, (3, 3))
    image = Image.fromarray((tiled * 255.0).astype(np.uint8), mode="L")
    image = image.resize((SIZE * 3, SIZE * 3), Image.Resampling.BICUBIC)
    centre = np.asarray(image).astype(np.float32) / 255.0
    return centre[SIZE:SIZE * 2, SIZE:SIZE * 2]


def fractal_noise(octaves: tuple[int, ...] = (4, 8, 16, 32, 64), seed_offset: int = 0) -> np.ndarray:
    total = np.zeros((SIZE, SIZE), dtype=np.float32)
    weight_sum = 0.0
    for index, grid in enumerate(octaves):
        weight = 1.0 / (index + 1.0)
        total += periodic_noise(grid, seed_offset=seed_offset + index * 101) * weight
        weight_sum += weight
    total /= weight_sum
    low = float(total.min())
    high = float(total.max())
    return (total - low) / max(high - low, 1e-6)


def normal_from_height(height: np.ndarray, strength: float = 2.0) -> np.ndarray:
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)) * strength
    nz = np.ones_like(height)
    length = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack((dx / length * 0.5 + 0.5, dy / length * 0.5 + 0.5, nz / length * 0.5 + 0.5), axis=-1)


def write_set(name: str, albedo: np.ndarray, height: np.ndarray, roughness: np.ndarray, normal_strength: float) -> None:
    save(f"cottage_{name}.jpg", albedo)
    save(f"cottage_{name}_normal.jpg", normal_from_height(height, normal_strength))
    save(f"cottage_{name}_roughness.jpg", roughness)


def grade(array: np.ndarray, tint: tuple[float, float, float], saturation: float = 1.0, lift: float = 0.0) -> np.ndarray:
    grey = luminance(array)[..., None]
    result = grey + (array - grey) * saturation
    return np.clip(result * np.array(tint, dtype=np.float32) + lift, 0.0, 1.0)


def make_rammed_sand() -> None:
    plaster = load("user_plaster_white.jpg")
    mineral = blur(load("user_stone_tiles_beige.jpg"), 18.0)
    albedo = grade(plaster * 0.62 + mineral * 0.38, (1.04, 0.94, 0.76), 0.72, 0.015)
    y = np.linspace(0.0, 1.0, SIZE, endpoint=False, dtype=np.float32)[:, None]
    # Rammed-earth strata are broad, wavy compaction layers, not siding:
    # keep only five low-contrast bands and let mineral mottling break
    # every boundary before it can read as a man-made plank groove.
    band_phase = y * 5.0 + (periodic_noise(10, 42, 11) - 0.5) * 0.34
    bands = 0.5 + 0.5 * np.sin(band_phase * math.tau)
    seams = np.exp(-((np.abs(np.mod(band_phase + 0.5, 1.0) - 0.5) * 30.0) ** 2))
    pits = np.clip((fractal_noise((64, 128, 256), 19) - 0.72) * 4.5, 0.0, 1.0)
    fine = fractal_noise((32, 64, 128, 256), 23)
    weather = fractal_noise((6, 12, 24), 29)
    albedo *= (0.965 + bands[..., None] * 0.038)
    albedo *= (1.0 - seams[..., None] * 0.055)
    albedo *= (1.0 - pits[..., None] * 0.16)
    albedo *= (0.94 + weather[..., None] * 0.10)
    height = luminance(albedo) * 0.30 + bands * 0.13 - seams * 0.17 - pits * 0.42 + fine * 0.26
    roughness = 0.90 + fine * 0.09 + pits * 0.08 - bands * 0.025 + weather * 0.03
    write_set("rammed_sand", albedo, height, roughness, 2.3)


def make_travertine() -> None:
    source = Image.open(TEXTURE_DIR / "user_travertine.jpg").convert("RGB")
    # Crop inside one photographic tile so the new facade stone does not
    # inherit the old 4x4 grout grid, then mirror-tile it seamlessly.
    tile = source.crop((270, 525, 490, 745)).resize((512, 512), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (SIZE, SIZE))
    canvas.paste(tile, (0, 0))
    canvas.paste(tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (512, 0))
    canvas.paste(tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM), (0, 512))
    canvas.paste(tile.transpose(Image.Transpose.ROTATE_180), (512, 512))
    mirrored = np.asarray(canvas).astype(np.float32) / 255.0
    # A rolled copy feathered through the central cross hides the mirror
    # symmetry without introducing a new hard seam.
    rolled = np.roll(mirrored, (173, 269), axis=(0, 1))
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    cross = np.clip(1.0 - np.minimum(np.abs(xx - 511.5), np.abs(yy - 511.5)) / 150.0, 0.0, 1.0)
    cross = (cross * cross * (3.0 - 2.0 * cross))[..., None]
    albedo = grade(mirrored * (1.0 - cross * 0.58) + rolled * cross * 0.58, (1.02, 0.96, 0.86), 0.84, 0.01)
    pores = np.clip((fractal_noise((96, 192), 31) - 0.66) * 4.0, 0.0, 1.0)
    long_pores = np.clip((periodic_noise(12, 128, 37) - 0.70) * 4.2, 0.0, 1.0)
    veins = fractal_noise((4, 8, 16), 41)
    albedo *= (1.0 - pores[..., None] * 0.24 - long_pores[..., None] * 0.16)
    albedo *= (0.96 + veins[..., None] * 0.07)
    height = luminance(albedo) * 0.42 - pores * 0.55 - long_pores * 0.34 + veins * 0.10
    roughness = 0.76 + pores * 0.23 + long_pores * 0.18 - np.clip(veins - 0.58, 0.0, 1.0) * 0.22
    write_set("travertine_coarse", albedo, height, roughness, 2.4)


def make_limestone_blocks() -> None:
    source = load("user_stone_tiles_beige.jpg")
    # Blur away the donor's small French-pattern joints and lay a new,
    # larger ashlar coursing over its photographic mineral grain.  This
    # makes the cottage stone read as 600-900 mm facade blocks instead
    # of reusing the existing floor-tile image unchanged.
    albedo = grade(blur(source, 5.0), (0.98, 0.93, 0.81), 0.58, 0.045)
    joints = np.zeros((SIZE, SIZE), dtype=np.float32)
    tone = np.zeros((SIZE, SIZE), dtype=np.float32)
    generator = np.random.default_rng(551)
    row_height = 146
    for row, top in enumerate(range(-row_height, SIZE + row_height, row_height)):
        offset = -180 if row % 2 else 0
        for left in range(offset, SIZE + 360, 360):
            value = float(generator.uniform(-0.045, 0.045))
            x0, x1 = max(left, 0), min(left + 360, SIZE)
            y0, y1 = max(top, 0), min(top + row_height, SIZE)
            if x1 > x0 and y1 > y0:
                tone[y0:y1, x0:x1] = value
            if 0 <= left < SIZE:
                joints[y0:y1, max(left - 2, 0):min(left + 3, SIZE)] = 1.0
        if 0 <= top < SIZE:
            joints[max(top - 2, 0):min(top + 3, SIZE), :] = 1.0
    joints = blur(joints, 0.7)
    chips = np.clip((fractal_noise((64, 128, 256), 53) - 0.74) * 4.6, 0.0, 1.0)
    salt = np.clip((fractal_noise((32, 64, 128), 59) - 0.70) * 3.6, 0.0, 1.0)
    albedo *= (1.0 + tone[..., None])
    albedo *= (1.0 - joints[..., None] * 0.30 - chips[..., None] * 0.14)
    albedo = np.clip(albedo + salt[..., None] * 0.05, 0.0, 1.0)
    height = luminance(source) * 0.24 - joints * 0.58 - chips * 0.28 + fractal_noise((64, 128), 61) * 0.16
    roughness = 0.87 + joints * 0.13 + chips * 0.08 + salt * 0.05 - np.abs(tone) * 0.35
    write_set("limestone_blocks", albedo, height, roughness, 2.8)


def load_top_half(name: str) -> np.ndarray:
    """Use only the donor's upper half where its lower half has a seam."""
    image = Image.open(TEXTURE_DIR / name).convert("RGB")
    image = image.crop((0, 0, image.width, image.height // 2))
    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    return np.asarray(image).astype(np.float32) / 255.0


def make_basalt() -> None:
    source = load("user_black_granite.jpg")
    albedo = grade(source, (0.88, 0.94, 1.04), 0.48, 0.025)
    vesicles = np.clip((fractal_noise((128, 256), 67) - 0.70) * 4.8, 0.0, 1.0)
    worn = fractal_noise((8, 16, 32), 71)
    scratches = np.clip((periodic_noise(12, 256, 73) - 0.78) * 5.0, 0.0, 1.0)
    albedo *= (1.0 - vesicles[..., None] * 0.38)
    albedo = np.clip(albedo + scratches[..., None] * 0.035, 0.0, 1.0)
    height = luminance(source) * 0.30 - vesicles * 0.50 + fractal_noise((64, 128, 256), 79) * 0.22
    roughness = 0.58 + (1.0 - worn) * 0.30 + vesicles * 0.20 - scratches * 0.14
    write_set("basalt", albedo, height, roughness, 2.5)


def make_teak() -> None:
    source = load_top_half("user_wood_slats_dark.jpg")
    albedo = grade(source, (1.10, 0.88, 0.62), 0.82, 0.035)
    bleach = fractal_noise((8, 16, 32), 83)
    cracks = np.clip((periodic_noise(192, 24, 89) - 0.74) * 4.5, 0.0, 1.0)
    grey = luminance(albedo)[..., None]
    albedo = albedo * (1.0 - bleach[..., None] * 0.18) + grey * bleach[..., None] * 0.18
    albedo *= (1.0 - cracks[..., None] * 0.28)
    height = luminance(source) * 0.38 - cracks * 0.42 + periodic_noise(160, 32, 97) * 0.14
    roughness = 0.76 + bleach * 0.20 + cracks * 0.16 - np.clip(0.45 - luminance(source), 0.0, 0.45) * 0.24
    write_set("teak_weathered", albedo, height, roughness, 2.2)


def make_roof_metal() -> None:
    source = load_top_half("user_brushed_metal.jpg")
    albedo = grade(source, (0.58, 0.50, 0.42), 0.55, -0.01)
    x = np.linspace(0.0, 1.0, SIZE, endpoint=False, dtype=np.float32)[None, :]
    panel_phase = np.mod(x * 8.0, 1.0)
    seam = np.exp(-((panel_phase - 0.03) * 34.0) ** 2) + np.exp(-((panel_phase - 0.97) * 34.0) ** 2)
    seam = np.repeat(np.clip(seam, 0.0, 1.0), SIZE, axis=0)
    panel_tone = (np.floor(x * 8.0).astype(np.int32) % 2).astype(np.float32)
    panel_tone = np.repeat(panel_tone, SIZE, axis=0)
    oxidation = fractal_noise((16, 32, 64), 103)
    streaks = periodic_noise(96, 8, 107)
    albedo *= (0.94 + panel_tone[..., None] * 0.07)
    albedo *= (1.0 - seam[..., None] * 0.34)
    albedo = np.clip(albedo + np.stack((oxidation * 0.035, oxidation * 0.018, oxidation * 0.004), axis=-1), 0.0, 1.0)
    height = seam * 0.72 + luminance(source) * 0.18 + streaks * 0.06
    roughness = 0.44 + oxidation * 0.30 + streaks * 0.12 - seam * 0.08
    write_set("roof_metal", albedo, height, roughness, 2.0)


def make_paving() -> None:
    source = load("user_concrete_slabs.jpg")
    albedo = grade(source, (1.02, 0.94, 0.80), 0.62, 0.02)
    lum = luminance(source)
    joints = np.clip((blur(lum, 3.0) - lum) * 8.0, 0.0, 1.0)
    aggregate = fractal_noise((128, 256), 109)
    dust = fractal_noise((8, 16, 32), 113)
    albedo *= (0.95 + aggregate[..., None] * 0.10)
    albedo = np.clip(albedo + dust[..., None] * np.array((0.045, 0.032, 0.012), dtype=np.float32), 0.0, 1.0)
    height = lum * 0.30 - joints * 0.50 + aggregate * 0.15
    roughness = 0.86 + joints * 0.14 + aggregate * 0.08 - dust * 0.04
    write_set("paving", albedo, height, roughness, 2.35)


def main() -> None:
    make_rammed_sand()
    make_travertine()
    make_limestone_blocks()
    make_basalt()
    make_teak()
    make_roof_metal()
    make_paving()


if __name__ == "__main__":
    main()
