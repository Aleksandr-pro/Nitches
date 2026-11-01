#!/usr/bin/env python3
"""Prepare the supplied Bugatti CSR2 textures for the glTF converter.

Reads the owner's ``textures.zip`` contents (diff/ref/gloss/opac/nrml maps)
and writes game-ready maps into the output directory:

* ``*_diff_rgba.png`` - base colour with the ``opac`` map merged into the
  alpha channel (real cut-out for badges, grilles and interior trim).
* ``*_diff.jpg`` - opaque base colour.
* ``*_mr.jpg`` - glTF metallic-roughness: G = 255 - gloss, B = ref.
* ``*_nrml.png`` - normals kept lossless.
* ``*_emissive.jpg`` - light/interior glow maps.

Example::

    python3 scripts/prepare_bugatti_textures.py \
        --input google_drive/textures/textures --output /tmp/bugatti_tex
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def load(directory: Path, name: str) -> Image.Image:
    path = directory / name
    if not path.exists():
        raise SystemExit(f"missing texture {path}")
    return Image.open(path)


def mr_from_ref_gloss(ref: Image.Image, gloss: Image.Image) -> Image.Image:
    size = ref.size
    roughness = gloss.convert("L").resize(size).point(lambda v: 255 - v)
    metallic = ref.convert("L").resize(size)
    out = Image.new("RGB", size, (0, 0, 0))
    out.paste(Image.merge("RGB", (
        Image.new("L", size, 0), roughness, metallic)))
    return out


def rgba_merge(diff: Image.Image, opac: Image.Image) -> Image.Image:
    base = diff.convert("RGB")
    alpha = opac.convert("L").resize(base.size)
    base.putalpha(alpha)
    return base


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    src = Path(args.input)
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    # Badge (alpha cut-out decals).
    rgba_merge(load(src, "Badge_diff.png"), load(src, "Badge_opac.png")).save(
        out / "badge_diff_rgba.png")
    load(src, "Badge_nrml.png").save(out / "badge_nrml.png")
    mr_from_ref_gloss(load(src, "Badge_ref.png"), load(src, "Badge_gloss.png")
                      ).save(out / "badge_mr.jpg", quality=90)

    # Grilles.
    for key, stem, alpha in (("grille1", "Grille1", True),
                             ("grille2", "Grille2", False),
                             ("grille3", "Grille3", True)):
        diff = load(src, f"{stem}_diff.png")
        if alpha:
            rgba_merge(diff, load(src, f"{stem}_opac.png")).save(
                out / f"{key}_diff_rgba.png")
        else:
            diff.convert("RGB").save(out / f"{key}_diff.jpg", quality=90)
        load(src, f"{stem}_nrml.png").save(out / f"{key}_nrml.png")
        mr_from_ref_gloss(load(src, f"{stem}_ref.png"),
                          load(src, f"{stem}_gloss.png")).save(
            out / f"{key}_mr.jpg", quality=90)

    # Interior (alpha cut-out trim) + glow.
    rgba_merge(load(src, "Interior_diff.png"),
               load(src, "Interior_opac.png")).save(
        out / "interior_diff_rgba.png")
    load(src, "Interior_nrml.png").save(out / "interior_nrml.png")
    mr_from_ref_gloss(load(src, "Interior_ref.png"),
                      load(src, "Interior_gloss.png")).save(
        out / "interior_mr.jpg", quality=90)
    load(src, "Interior_emissive.png").convert("RGB").save(
        out / "interior_emissive.jpg", quality=90)

    # Lights.
    load(src, "Light_diff.png").convert("RGB").save(
        out / "light_diff.jpg", quality=90)
    load(src, "Light_emissive.png").convert("RGB").save(
        out / "light_emissive.jpg", quality=90)
    mr_from_ref_gloss(load(src, "Light_ref.png"),
                      load(src, "Light_gloss.png")).save(
        out / "light_mr.jpg", quality=90)

    # Wheel atlas (tire + rim + rotor share one atlas).
    load(src, "Wheel1A_diff.png").convert("RGB").save(
        out / "wheel_diff.jpg", quality=92)
    load(src, "Wheel1_nrml.png").save(out / "wheel_nrml.png")
    mr_from_ref_gloss(load(src, "Wheel1A_ref.png"),
                      load(src, "Wheel1A_gloss.png")).save(
        out / "wheel_mr.jpg", quality=90)

    # Exposed carbon body: base colour + a metallic-roughness map whose
    # roughness comes from the authored roughness map; metalness is a
    # constant mid value matching the scene shader (0.5).
    load(src, "Carbon_Fiber_001_basecolor.jpg").convert("RGB").save(
        out / "carbon_base.jpg", quality=92)
    rough = load(src, "Carbon_Fiber_001_roughness.jpg").convert("L")
    metal = Image.new("L", rough.size, 128)
    Image.merge("RGB", (Image.new("L", rough.size, 0), rough, metal)).save(
        out / "carbon_mr.jpg", quality=90)

    for path in sorted(out.iterdir()):
        print(f"{path.name:28s} {path.stat().st_size:9d}")


if __name__ == "__main__":
    main()
