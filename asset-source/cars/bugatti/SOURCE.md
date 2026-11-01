# Bugatti Chiron Super Sport — source provenance

Supplied by the repository owner on 2026-11-01 via Google Drive
folder `1FxXGqyVcaOTwf34EUmdLcKnir8D8e3FM`:

| File | Bytes | Notes |
|---|---|---|
| `uploads_files_4478463_Underground+Garage+Scene.blend` | 77 857 327 | Garage diorama scene; the car (CSR2-style Chiron Super Sport WRE model) is the 56 objects using `CSR2_*` materials. This is the master source. |
| `textures.zip` | 14 055 231 | CSR2 texture set (diff/ref/gloss/opac/nrml), unpacks to `textures/textures/`. |
| `uploads_files_4478463_Underground+Garage+Scene.mtl` | 13 954 | OBJ material file from a scene export; reference only (no matching .obj was supplied). |
| `bugatti.fbx` | 4 140 | Empty FBX (RootNode only) — not used. |
| `Характеристики.txt` | 3 830 | Supplied spec sheet (mass/dimensions, W16 torque plateau, DCT ratios, aero); kept here as `characteristics_supplied.txt` and mirrored into the catalogue entry. |

The large originals live on the owner's Google Drive and are not
mirrored into Git (the converted GLB + report are the shipped,
auditable artifacts, like the Audi/Camaro/Mercedes conversions).

## Rebuild

```bash
# 1. CSR2 maps -> glTF maps (numpy/Pillow venv)
python3 scripts/prepare_bugatti_textures.py \
    --input <unpacked textures/textures> --output /tmp/bugatti_tex

# 2. Scene -> game GLB + report (Blender / bpy module)
blender -b --python scripts/blender_convert_bugatti_chiron.py -- \
    --blend "uploads_files_4478463_Underground+Garage+Scene.blend" \
    --textures /tmp/bugatti_tex \
    --output src/assets/models/cars/bugatti_chiron_super_sport.glb \
    --report src/assets/models/cars/bugatti_chiron_super_sport_report.json

# 3. Optional review renders
blender -b --python scripts/dev_render_car.py -- \
    --glb src/assets/models/cars/bugatti_chiron_super_sport.glb \
    --out /tmp/bugatti_review
```
