#!/usr/bin/env python3
"""Create the 0.2.40 garage/store cards from real CI gameplay frames.

The screenshot tour renders at 960x540 with the full HUD.  For a menu
card we keep only the central road/car window between the steering
wheel and the right-hand action buttons, then scale that real frame
to the established 1024x576 menu-card size.  No render, stock photo,
or generated image is involved.
"""

from pathlib import Path
import sys

from PIL import Image


CARDS = {
    "08a_car_audi_r8.png": "menu_audi_r8_gameplay.jpg",
    "08b_car_camaro_ss.png": "menu_camaro_ss_gameplay.jpg",
    "08c_car_mercedes_560_sel.png": "menu_mercedes_560_sel_gameplay.jpg",
}

# At 960x540 the chase car sits in the middle.  This 456x256 window
# starts just right of the 280 px steering-wheel control and ends
# just left of the drift/N2O controls; vertically it starts below the
# minimap/gauge and includes the rear bumper and contact shadow.
CROP_960 = (288, 240, 744, 496)
OUTPUT_SIZE = (1024, 576)


def scaled_crop(size: tuple[int, int]) -> tuple[int, int, int, int]:
    sx = size[0] / 960.0
    sy = size[1] / 540.0
    return (
        round(CROP_960[0] * sx),
        round(CROP_960[1] * sy),
        round(CROP_960[2] * sx),
        round(CROP_960[3] * sy),
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <ci-screenshot-directory>", file=sys.stderr)
        return 2

    source_dir = Path(sys.argv[1]).resolve()
    repo_root = Path(__file__).resolve().parent.parent
    output_dir = repo_root / "src/assets/ui"
    output_dir.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    for source_name, output_name in CARDS.items():
        source = source_dir / source_name
        if not source.is_file():
            missing.append(str(source))
            continue
        with Image.open(source) as frame:
            rgb = frame.convert("RGB")
            card = rgb.crop(scaled_crop(rgb.size)).resize(OUTPUT_SIZE, Image.Resampling.LANCZOS)
            output = output_dir / output_name
            card.save(output, "JPEG", quality=90, subsampling=1, optimize=True)
            print(f"{source} -> {output} ({output.stat().st_size} bytes)")

    if missing:
        print("Missing required CI car frames:", *missing, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
