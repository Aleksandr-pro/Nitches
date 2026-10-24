# City conversion — New York City - Manhattan

- Source: `NewYork-City-Manhattan.fbx` (40,847,916 bytes)
- Source SHA-256: `42d948589eb8e93d70e1322a3c3420882d4ffb07c3c4fa08088786d5756e96c7`
- Blender: 4.0.2
- External textures: **missing and intentionally ignored**; deterministic vertex colours are used instead.

## Transform

- Horizontal scale: 250.0 m/unit
- Vertical scale: 230.0 m/unit above source Z 0.008
- Local footprint: **1192.6 × 993.7 m**
- Local height: 0.0…96.0 m
- Local coordinates: X east, Y up, Z south (Blender north maps to negative Z).

## Output

- Original: 733,180 triangles / 440,955 vertices
- After decimation: 368,218 triangles
- Exported chunks: 18 objects, 368,041 triangles
- GLB: 45,863,380 bytes, SHA-256 `5c848e88d591667875b741e9ceca94b7ade0b414b3ed20fd1b658ab03bd8602f`
- Colliders: 2,130 merged rectangles from 33,821 occupied 4 m cells

## Heaviest chunks

| Chunk | Triangles | Max height |
|---|---:|---:|
| `manhattan_04_03` | 156,987 | 96.0 m |
| `manhattan_03_03` | 85,874 | 95.5 m |
| `manhattan_03_02` | 28,623 | 44.5 m |
| `manhattan_00_01` | 18,642 | 72.7 m |
| `manhattan_00_02` | 15,301 | 56.6 m |
| `manhattan_04_02` | 10,957 | 35.7 m |
| `manhattan_02_03` | 10,800 | 29.9 m |
| `manhattan_03_01` | 7,397 | 18.5 m |
| `manhattan_02_02` | 7,283 | 27.0 m |
| `manhattan_01_02` | 6,904 | 19.5 m |
| `manhattan_03_00` | 4,452 | 26.0 m |
| `manhattan_01_01` | 3,821 | 43.0 m |
| `manhattan_01_03` | 3,684 | 14.7 m |
| `manhattan_02_01` | 3,064 | 13.6 m |
| `manhattan_00_03` | 1,846 | 23.7 m |
| `manhattan_02_00` | 1,228 | 22.3 m |
| `manhattan_04_01` | 1,042 | 15.8 m |
| `manhattan_01_00` | 136 | 19.6 m |

## Warnings

- The FBX references 13 external PNG textures that are not present in Model Inbox; they were deliberately ignored and replaced with vertex colours.
- Source scale is interpreted as miniature/kilometre-like units; conversion uses 250 m/unit horizontally so the footprint fits Kingsford district.
- Street-level source vertices at or below the configured ground Z are flattened to the city plate; bridges and elevated terrain remain approximate.
- Colliders are an occupancy-raster approximation of merged photogrammetry geometry, not hand-authored building footprints.
- Chunk splitting assigns triangles by centroid; hairline seams can occur where a source triangle crosses a 250 m boundary.
