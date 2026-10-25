#!/usr/bin/env python3
"""Generate tileable OpenGL tangent-space normal maps from local textures.

The source images are the project's own/user-supplied photo textures.  Height
is estimated from luminance, blurred slightly, and differentiated with a
wrap-around Sobel operator so the resulting maps tile without seams.

Run from the repository root:
    python3 scripts/generate-normal-maps.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
TEXTURES = ROOT / "src/assets/textures/realworld"

# filename, relief strength
JOBS = [
    ("user_grass.jpg", 2.0),
    ("rock.jpg", 2.6),
    ("user_sand_rippled.jpg", 2.3),
    ("user_concrete_slabs.jpg", 2.1),
    ("user_asphalt_dashed.jpg", 1.9),
    ("user_asphalt_plain.jpg", 1.9),
    ("user_asphalt_pothole.jpg", 2.3),
    ("user_asphalt_double_yellow.jpg", 1.5),
    ("asphalt_drag.jpg", 1.7),
    ("user_water_turquoise.jpg", 3.1),
    ("user_pool_mosaic.jpg", 1.5),
    ("user_stone_rubble.jpg", 3.0),
    ("facade_brick.jpg", 1.7),
    ("facade_modern.jpg", 1.45),
    ("facade_glass.jpg", 1.1),
    ("facade_panel.jpg", 1.55),
    ("facade_loft.jpg", 1.6),
    ("facade_pastel.jpg", 1.45),
    ("facade_industrial.jpg", 1.7),
    ("facade_shop.jpg", 1.1),
    ("facade_hotel.jpg", 1.4),
    ("facade_sandstone.jpg", 1.8),
    ("user_facade_blue_glass.jpg", 1.15),
    ("user_facade_gold_grid.jpg", 1.25),
    ("user_facade_silver.jpg", 1.25),
    ("user_marble_tiles.jpg", 1.3),
    ("user_travertine.jpg", 1.9),
    ("user_plaster_white.jpg", 1.3),
    ("user_wood_slats_dark.jpg", 2.2),
    ("user_concrete_dark.jpg", 2.0),
    ("user_roof_terracotta.jpg", 2.6),
    ("roof_slate.jpg", 2.4),
    ("user_roof_weathered.jpg", 2.0),
    ("user_wood_deck.jpg", 2.0),
    ("bench_wood.jpg", 1.8),
    ("oak_bark.jpg", 2.7),
    ("foliage.jpg", 1.5),
    ("metal_pole.jpg", 1.2),
    ("user_brushed_metal.jpg", 0.9),
    ("user_black_granite.jpg", 1.1),
    ("user_black_rough.jpg", 2.5),
    ("user_parking_deck.jpg", 1.9),
]


def shifted(a: np.ndarray, dy: int, dx: int) -> np.ndarray:
    return np.roll(np.roll(a, dy, axis=0), dx, axis=1)


def height_to_normal(height: np.ndarray, strength: float) -> np.ndarray:
    # Sobel derivatives. gx is along image columns; gy along image rows.
    gx = (
        shifted(height, -1, 1) + 2 * shifted(height, 0, 1) + shifted(height, 1, 1)
        - shifted(height, -1, -1) - 2 * shifted(height, 0, -1) - shifted(height, 1, -1)
    ) / 4.0
    gy = (
        shifted(height, 1, -1) + 2 * shifted(height, 1, 0) + shifted(height, 1, 1)
        - shifted(height, -1, -1) - 2 * shifted(height, -1, 0) - shifted(height, -1, 1)
    ) / 4.0

    # three.js image UVs are flipped vertically relative to image rows.
    # Encode an OpenGL-style (Y+) tangent-space normal.
    nx = -gx * strength
    ny = gy * strength
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack(
        [
            (nx * inv_len * 0.5 + 0.5) * 255.0,
            (ny * inv_len * 0.5 + 0.5) * 255.0,
            (nz * inv_len * 0.5 + 0.5) * 255.0,
        ],
        axis=-1,
    )
    return np.clip(rgb, 0, 255).astype(np.uint8)


def main() -> None:
    for filename, strength in JOBS:
        source = TEXTURES / filename
        if not source.exists():
            raise FileNotFoundError(source)
        image = Image.open(source).convert("L")
        image.thumbnail((512, 512), Image.Resampling.LANCZOS)
        image = image.filter(ImageFilter.GaussianBlur(radius=0.55))
        height = np.asarray(image, dtype=np.float32) / 255.0
        normal = Image.fromarray(height_to_normal(height, strength), mode="RGB")
        target = TEXTURES / f"{source.stem}_normal.jpg"
        normal.save(target, quality=88, optimize=True)
        print(f"{target.name}: {target.stat().st_size} bytes")


if __name__ == "__main__":
    main()
