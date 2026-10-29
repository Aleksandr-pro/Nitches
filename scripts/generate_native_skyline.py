#!/usr/bin/env python3
"""Generate deterministic, seamless 4096x512 RGBA skyline plates for Godot."""
from __future__ import annotations

import random
import struct
import zlib
from pathlib import Path

WIDTH = 4096
HEIGHT = 512
OUT = Path("src/assets/textures/realworld")


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def save_png(path: Path, pixels: bytearray) -> None:
    rows = bytearray()
    stride = WIDTH * 4
    for y in range(HEIGHT):
        rows.append(0)
        rows.extend(pixels[y * stride:(y + 1) * stride])
    body = b"\x89PNG\r\n\x1a\n"
    body += png_chunk(b"IHDR", struct.pack(">2I5B", WIDTH, HEIGHT, 8, 6, 0, 0, 0))
    body += png_chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    body += png_chunk(b"IEND", b"")
    path.write_bytes(body)


def build_layer(seed: int, far: bool) -> bytearray:
    rng = random.Random(seed)
    pixels = bytearray(WIDTH * HEIGHT * 4)
    buildings: list[tuple[int, int, int, tuple[int, int, int], int]] = []
    anchor_width = 104 if far else 126
    anchor_height = rng.randint(115, 190) if far else 275
    anchor_color = (85, 113, 139) if far else (36, 51, 70)
    # One building straddles x=0/4096, so the panorama joins without a cut seam.
    buildings.append((-anchor_width // 2, anchor_width, anchor_height, anchor_color, seed))
    x = anchor_width // 2 + 12
    limit = WIDTH - anchor_width // 2 - 12
    while x < limit:
        width = rng.randint(24 if far else 22, 94 if far else 112)
        gap = rng.randint(5, 18)
        height = rng.randint(65, 190) if far else int((rng.random() ** 0.70) * 330 + 70)
        if rng.random() < (0.06 if far else 0.085):
            height = min(290 if far else 440, height + rng.randint(90, 180))
            width = rng.randint(26, 54)
        if far:
            base = (82 + rng.randint(-10, 13), 112 + rng.randint(-10, 15), 139 + rng.randint(-8, 17))
        else:
            base = (31 + rng.randint(-8, 13), 46 + rng.randint(-8, 12), 64 + rng.randint(-6, 13))
        buildings.append((x, width, height, base, rng.randrange(1_000_000)))
        x += width + gap

    stride = WIDTH * 4
    for bx, bw, bh, base, building_seed in buildings:
        start = bx % WIDTH
        end = start + bw
        if end <= WIDTH:
            pieces = [(start, end, 0)]
        else:
            pieces = [(start, WIDTH, 0), (0, end - WIDTH, WIDTH - start)]
        top = max(20, HEIGHT - 27 - bh)
        facade_alpha = 238 if far else 250
        for left, right, local_start in pieces:
            for px in range(left, right):
                local_x = local_start + px - left
                bay_width = max(7, bw // max(2, bw // 12))
                bay_shade = 0.82 if local_x % bay_width == 0 else 1.0
                side_shade = 0.84 if local_x < bw * 0.18 else 1.0
                for py in range(top, HEIGHT - 26):
                    distance_top = py - top
                    row_shade = 0.76 + 0.24 * (distance_top / max(1, bh))
                    color = tuple(max(0, min(255, int(c * side_shade * bay_shade * row_shade))) for c in base)
                    alpha = facade_alpha
                    if distance_top > 9 and local_x % 11 in (3, 4, 5) and py % 15 in (5, 6, 7):
                        lit = ((local_x * 31 + py * 17 + building_seed) % 13) < (2 if far else 3)
                        if lit:
                            color = (max(color[0], 124), max(color[1], 91), max(color[2], 58))
                            alpha = 218
                    offset = py * stride + px * 4
                    pixels[offset:offset + 4] = bytes((*color, alpha))

        # Rooftop caps add a little skyline rhythm without breaking the seam anchor.
        if bx >= 0 and not far and bw > 42 and building_seed % 3 == 0:
            cap_width = max(5, bw // 5)
            cap_left = min(bx + bw - cap_width, bx + bw // 2 - cap_width // 2)
            cap_height = min(42, max(12, bh // 5))
            cap_top = max(10, top - cap_height)
            cap_color = tuple(min(255, int(c * 1.12)) for c in base)
            for py in range(cap_top, top):
                for px in range(cap_left, cap_left + cap_width):
                    offset = py * stride + px * 4
                    pixels[offset:offset + 4] = bytes((*cap_color, 245))

    for py in range(HEIGHT - 42, HEIGHT):
        fade = min(1.0, max(0.0, (HEIGHT - py) / 42.0))
        alpha_scale = int(255 * fade)
        row = py * stride
        for px in range(WIDTH):
            offset = row + px * 4
            if pixels[offset + 3]:
                pixels[offset + 3] = min(pixels[offset + 3], alpha_scale)
    return pixels


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save_png(OUT / "skyline_rich_town_near.png", build_layer(61291, far=False))
    save_png(OUT / "skyline_rich_town_far.png", build_layer(82017, far=True))
    print(f"Generated two seamless {WIDTH}x{HEIGHT} RGBA skyline layers in {OUT}")


if __name__ == "__main__":
    main()
