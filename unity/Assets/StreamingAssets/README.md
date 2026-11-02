# StreamingAssets (Unity runtime files)

- `Cars/` — supplied-car GLB models loaded at runtime by `CarModelLoader`.
  Committed: `bugatti_chiron_super_sport.glb` (plain Git, see
  `unity/.gitattributes`). The other cars are copied on demand.
- `Audio/` — recorded engine banks loaded by `EngineAudio`.
  Committed: `bugatti_chiron/` (rpm anchors + idle).

Refresh/copy everything from the shared repo asset tree:

```
node scripts/sync-unity-assets.mjs
```

(run from the repository root; the Mustang additionally needs
`git lfs pull` first because it lives in Git LFS.)
