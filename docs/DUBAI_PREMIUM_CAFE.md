# Dubai-inspired premium cafe asset

## Reusable model

- Source asset: `src/assets/models/props/dubai_premium_cafe.glb`
- Native runtime copy: `res://assets/props/dubai_premium_cafe.glb`
- Reproducible generator: `scripts/generate_dubai_premium_cafe.py` (Python 3 with `numpy` and `trimesh`; `python3 scripts/generate_dubai_premium_cafe.py` rebuilds the source GLB)
- Native asset staging: `node scripts/sync-native-assets.mjs`
- GLB check: `node scripts/validate-glb-loader.mjs --generic src/assets/models/props/dubai_premium_cafe.glb`

The GLB is a self-contained, 11-part, approximately 8,000-triangle model. Its ground-centred origin is at `(0, 0, 0)`; local `Y` is up and the public entrance/terrace face local `+X`. The measured local bounds are approximately `11.42 × 4.41 × 9.02 m` (`X × Y × Z`). It is designed to be instanced at real-world scale (`Vector3.ONE`) without rescaling.

The model uses named material groups (`CafeTravertine`, `CafeLimestone`, `CafeBronze`, `CafeSteel`, `CafeGlass`, `CafeOak`, `CafeWarmLight`, `CafeCream`, `CafeCounter`, `CafeGreen`, `CafeCeramic`). `NativeWorldBuilder._prop_material()` maps those names to the project's PBR materials, so the runtime GLB does not depend on external texture files.

## Current RichTown placement

`NativeWorldBuilder._build_premium_boulevard_details()` instances the asset five times at approximately:

- `(718, terrain height, -67)` — west side, yaw `0`
- `(718, terrain height, -20)` — west side, yaw `0`
- `(718, terrain height, 27)` — west side, yaw `0`
- `(782, terrain height, -58)` — east side, yaw `PI`
- `(782, terrain height, 18)` — east side, yaw `PI`

The model is offset upward by 5.5 cm to sit just above the promenade paving. At yaw `0`, its terrace points toward RichTown Boulevard at `X=760`; the east-side copies use yaw `PI` so their terraces face the same carriageway. The full 11.6 × 9.2 m placement rectangle is checked against exported and generated buildings before an instance is accepted. Each interior shell gets a static collision box; terrace seating stays decorative.

A future world builder can reuse the model at any clear plot by staging the asset and adding a transform with the same origin/orientation contract. Use `_add_batched_model(parent, "res://assets/props/dubai_premium_cafe.glb", transforms, "DubaiPremiumCafes")` to batch multiple copies.
