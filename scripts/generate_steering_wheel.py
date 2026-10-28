#!/usr/bin/env python3
"""Turn the supplied straight-on steering-wheel product photo into a HUD PNG.

The white studio background and the large white openings inside the rim are
removed as connected neutral-white regions.  Small pale details that are
enclosed by the wheel itself (button legends, bright trim and the centre
emblem) stay opaque.  Edge pixels are colour-decontaminated against the
studio white so the wheel has no pale fringe over a dark game scene, and
the detected rim centre is placed exactly at the output canvas centre.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance
from scipy import ndimage


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--size", type=int, default=1024)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    rgb = np.asarray(source).astype(np.float32)
    min_channel = rgb.min(axis=2)
    max_channel = rgb.max(axis=2)

    # The wheel is the only non-white object; its bbox supplies a robust
    # rotation centre (the product photo is straight-on and symmetrical).
    object_mask = min_channel < 245.0
    ys, xs = np.where(object_mask)
    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    centre_x = (left + right) * 0.5
    centre_y = (top + bottom) * 0.5

    neutral_white = (min_channel >= 238.0) & ((max_channel - min_channel) <= 18.0)
    labels, count = ndimage.label(neutral_white, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]]))
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    border_labels = set(
        np.unique(
            np.concatenate(
                [labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]]
            )
        ).tolist()
    )
    background_labels = [
        label
        for label in range(1, count + 1)
        if label in border_labels or sizes[label] >= 2500
    ]
    background = np.isin(labels, background_labels)

    alpha = np.where(background, 0.0, 1.0).astype(np.float32)
    # Feather only the 3 px rim/background frontier.  Interior pale details
    # remain fully opaque because they are not near a removed region.
    distance_to_background = ndimage.distance_transform_edt(~background)
    edge = (~background) & (distance_to_background <= 3.0)
    edge_alpha = np.clip((248.0 - min_channel) / 55.0, 0.0, 1.0)
    alpha[edge] = np.minimum(alpha[edge], edge_alpha[edge])
    alpha = ndimage.gaussian_filter(alpha, sigma=0.55)
    alpha[background] = 0.0
    alpha[alpha < 0.012] = 0.0

    # Undo the white studio contribution in semi-transparent edge pixels.
    studio_white = 254.0
    safe_alpha = np.maximum(alpha[..., None], 0.05)
    clean_rgb = np.clip((rgb - (1.0 - alpha[..., None]) * studio_white) / safe_alpha, 0.0, 255.0)
    clean_rgb[alpha >= 0.995] = rgb[alpha >= 0.995]

    rgba = np.dstack([clean_rgb, alpha * 255.0]).astype(np.uint8)
    cutout = Image.fromarray(rgba, "RGBA")

    bbox_w = right - left
    bbox_h = bottom - top
    side = int(np.ceil(max(bbox_w, bbox_h) * 1.09))
    if side % 2 == 0:
        side += 1
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    paste_x = int(round(side * 0.5 - centre_x))
    paste_y = int(round(side * 0.5 - centre_y))
    canvas.alpha_composite(cutout, (paste_x, paste_y))

    # A restrained product-photo cleanup: the source is already sharp, so
    # this only restores a little contrast lost to the white-backdrop key.
    rgb_part = canvas.convert("RGB")
    rgb_part = ImageEnhance.Contrast(rgb_part).enhance(1.045)
    rgb_part = ImageEnhance.Color(rgb_part).enhance(1.035)
    rgb_part = ImageEnhance.Sharpness(rgb_part).enhance(1.10)
    canvas = Image.merge("RGBA", (*rgb_part.split(), canvas.getchannel("A")))
    canvas = canvas.resize((args.size, args.size), Image.Resampling.LANCZOS)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, optimize=True)
    print(
        f"source={source.size[0]}x{source.size[1]} bbox=({left},{top})-({right},{bottom}) "
        f"centre=({centre_x:.1f},{centre_y:.1f}) output={args.output} {canvas.size[0]}x{canvas.size[1]}"
    )


if __name__ == "__main__":
    main()
