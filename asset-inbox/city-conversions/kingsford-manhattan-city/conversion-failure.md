# City conversion failure diagnostics: kingsford-manhattan-city

Run: https://github.com/Aleksandr-pro/Nitches/actions/runs/40138059730
Commit: 1befe32a6a104ba7354c227553202bdc5698279f

## download-convert-step.log

```text
Downloading Model Inbox asset 673283843 (NewYork-City-Manhattan.fbx) for kingsford-manhattan-city...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
 77 38.9M   77 30.0M    0     0  23.9M      0  0:00:01  0:00:01 --:--:-- 23.9M100 38.9M  100 38.9M    0     0  27.5M      0  0:00:01  0:00:01 --:--:-- 56.8M
Downloaded 40847916 bytes, sha256 42d948589eb8e93d70e1322a3c3420882d4ffb07c3c4fa08088786d5756e96c7
Converting NewYork-City-Manhattan.fbx into a chunked, textureless city GLB...
/usr/share/blender/scripts/addons/io_scene_gltf2/io/exp/gltf2_io_image_data.py:25: SyntaxWarning: invalid escape sequence '\.'
  regex_dot = re.compile("\.")
/usr/share/blender/scripts/addons/io_scene_gltf2/io/exp/gltf2_io_image_data.py:27: SyntaxWarning: invalid escape sequence '\]'
  new_name = "".join([char for char in adjusted_name if char not in "!#$&'()*+,/:;<>?@[\]^`{|}~"])
Blender 4.0.2
FBX version: 7400
22:41:40 | ERROR: Draco mesh compression is not available because library could not be found at /usr/bin/4.0/python/lib/python3.12/site-packages/libextern_draco.so
22:41:40 | INFO: Starting glTF 2.0 export
22:41:40 | WARNING: Mesh manhattan_00_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_00_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_00_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | INFO: Extracting primitive: manhattan_01_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_00 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_00 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_03
22:41:41 | INFO: Primitives created: 1
22:41:41 | INFO: Finished glTF 2.0 export in 1.093168020248413 s

{
  "source": {
    "name": "NewYork-City-Manhattan.fbx",
    "size": 40847916,
    "sha256": "42d948589eb8e93d70e1322a3c3420882d4ffb07c3c4fa08088786d5756e96c7",
    "blenderVersion": "4.0.2",
    "missingTexturesIgnored": true
  },
  "localBounds": {
    "minX": -596.278,
    "maxX": 596.278,
    "minZ": -496.835,
    "maxZ": 496.835,
    "minY": 0.0,
    "maxY": 95.996,
    "widthM": 1192.556,
    "depthM": 993.669
  },
  "chunks": 18,
  "colliders": 2130,
  "stats": {
    "originalVertices": 440955,
    "originalTriangles": 733180,
    "decimatedTriangles": 368218,
    "outputVertices": 194104,
    "outputTriangles": 368041,
    "decimationRatio": 0.463733,
    "glbBytes": 45863460,
    "glbSha256": "97e2fff390827364dd9143c2f7b0b57a247a33afcd818e8615a23328290e51be"
  },
  "warnings": [
    "The FBX references 13 external PNG textures that are not present in Model Inbox; they were deliberately ignored and replaced with vertex colours.",
    "Source scale is interpreted as miniature/kilometre-like units; conversion uses 250 m/unit horizontally so the footprint fits Kingsford district.",
    "Street-level source vertices at or below the configured ground Z are flattened to the city plate; bridges and elevated terrain remain approximate.",
    "Colliders are an occupancy-raster approximation of merged photogrammetry geometry, not hand-authored building footprints.",
    "Chunk splitting assigns triangles by centroid; hairline seams can occur where a source triangle crosses a 250 m boundary."
  ]
}
Generated city GLB: 45863460 bytes, about 368041 triangles
```

## copy-step.log

```text
git-lfs/3.8.0 (GitHub; linux amd64; go 1.27.0)
Updated Git hooks.
Git LFS initialized.
The following paths are ignored by one of your .gitignore files:
asset-inbox/city-conversions/kingsford-manhattan-city/blender-convert.log
hint: Use -f if you really want to add them.
hint: Disable this message with "git config set advice.addIgnoredFile false"
```

## kingsford-manhattan-city/blender-convert.log

```text
/usr/share/blender/scripts/addons/io_scene_gltf2/io/exp/gltf2_io_image_data.py:25: SyntaxWarning: invalid escape sequence '\.'
  regex_dot = re.compile("\.")
/usr/share/blender/scripts/addons/io_scene_gltf2/io/exp/gltf2_io_image_data.py:27: SyntaxWarning: invalid escape sequence '\]'
  new_name = "".join([char for char in adjusted_name if char not in "!#$&'()*+,/:;<>?@[\]^`{|}~"])
Blender 4.0.2
FBX version: 7400
22:41:40 | ERROR: Draco mesh compression is not available because library could not be found at /usr/bin/4.0/python/lib/python3.12/site-packages/libextern_draco.so
22:41:40 | INFO: Starting glTF 2.0 export
22:41:40 | WARNING: Mesh manhattan_00_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_00_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_00_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_00_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | INFO: Extracting primitive: manhattan_01_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_01_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_01_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_00 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_02_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_02_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_00 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_00
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_03_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_03_03
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_01 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_01
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_02 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_02
22:41:40 | INFO: Primitives created: 1
22:41:40 | WARNING: Mesh manhattan_04_03 is not valid, and may be exported wrongly
22:41:40 | INFO: Extracting primitive: manhattan_04_03
22:41:41 | INFO: Primitives created: 1
22:41:41 | INFO: Finished glTF 2.0 export in 1.093168020248413 s

{
  "source": {
    "name": "NewYork-City-Manhattan.fbx",
    "size": 40847916,
    "sha256": "42d948589eb8e93d70e1322a3c3420882d4ffb07c3c4fa08088786d5756e96c7",
    "blenderVersion": "4.0.2",
    "missingTexturesIgnored": true
  },
  "localBounds": {
    "minX": -596.278,
    "maxX": 596.278,
    "minZ": -496.835,
    "maxZ": 496.835,
    "minY": 0.0,
    "maxY": 95.996,
    "widthM": 1192.556,
    "depthM": 993.669
  },
  "chunks": 18,
  "colliders": 2130,
  "stats": {
    "originalVertices": 440955,
    "originalTriangles": 733180,
    "decimatedTriangles": 368218,
    "outputVertices": 194104,
    "outputTriangles": 368041,
    "decimationRatio": 0.463733,
    "glbBytes": 45863460,
    "glbSha256": "97e2fff390827364dd9143c2f7b0b57a247a33afcd818e8615a23328290e51be"
  },
  "warnings": [
    "The FBX references 13 external PNG textures that are not present in Model Inbox; they were deliberately ignored and replaced with vertex colours.",
    "Source scale is interpreted as miniature/kilometre-like units; conversion uses 250 m/unit horizontally so the footprint fits Kingsford district.",
    "Street-level source vertices at or below the configured ground Z are flattened to the city plate; bridges and elevated terrain remain approximate.",
    "Colliders are an occupancy-raster approximation of merged photogrammetry geometry, not hand-authored building footprints.",
    "Chunk splitting assigns triangles by centroid; hairline seams can occur where a source triangle crosses a 250 m boundary."
  ]
}
```

## kingsford-manhattan-city/conversion.json

```text
        2.0
      ],
      [
        503.72,
        425.17,
        4.0,
        2.0
      ],
      [
        535.72,
        425.17,
        16.0,
        2.0
      ],
      [
        475.72,
        427.17,
        4.0,
        4.0
      ],
      [
        491.72,
        427.17,
        4.0,
        4.0
      ],
      [
        183.72,
        429.17,
        4.0,
        2.0
      ],
      [
        197.72,
        429.17,
        6.0,
        2.0
      ],
      [
        213.72,
        429.17,
        2.0,
        2.0
      ],
      [
        227.72,
        429.17,
        8.0,
        2.0
      ],
      [
        307.72,
        429.17,
        60.0,
        2.0
      ],
      [
        437.72,
        429.17,
        26.0,
        2.0
      ],
      [
        519.72,
        429.17,
        16.0,
        2.0
      ],
      [
        547.72,
        431.17,
        4.0,
        4.0
      ],
      [
        203.72,
        433.17,
        8.0,
        2.0
      ],
      [
        233.72,
        433.17,
        10.0,
        2.0
      ],
      [
        289.72,
        433.17,
        42.0,
        2.0
      ],
      [
        379.72,
        433.17,
        4.0,
        2.0
      ],
      [
        455.72,
        433.17,
        24.0,
        2.0
      ],
      [
        507.72,
        433.17,
        20.0,
        2.0
      ],
      [
        353.72,
        435.17,
        14.0,
        4.0
      ],
      [
        211.72,
        437.17,
        8.0,
        2.0
      ],
      [
        281.72,
        437.17,
        50.0,
        2.0
      ],
      [
        381.72,
        437.17,
        6.0,
        2.0
      ],
      [
        457.72,
        437.17,
        22.0,
        2.0
      ],
      [
        515.72,
        437.17,
        28.0,
        2.0
      ],
      [
        193.72,
        439.17,
        2.0,
        4.0
      ],
      [
        221.72,
        441.17,
        14.0,
        2.0
      ],
      [
        249.72,
        441.17,
        6.0,
        2.0
      ],
      [
        261.72,
        441.17,
        2.0,
        2.0
      ],
      [
        323.72,
        441.17,
        20.0,
        2.0
      ],
      [
        357.72,
        441.17,
        6.0,
        2.0
      ],
      [
        379.72,
        441.17,
        8.0,
        2.0
      ],
      [
        399.72,
        441.17,
        4.0,
        2.0
      ],
      [
        467.72,
        441.17,
        12.0,
        2.0
      ],
      [
        489.72,
        441.17,
        2.0,
        2.0
      ],
      [
        501.72,
        441.17,
        6.0,
        2.0
      ],
      [
        525.72,
        441.17,
        10.0,
        2.0
      ],
      [
        279.72,
        443.17,
        12.0,
        4.0
      ],
      [
        235.72,
        445.17,
        20.0,
        2.0
      ],
      [
        327.72,
        445.17,
        16.0,
        2.0
      ],
      [
        353.72,
        445.17,
        6.0,
        2.0
      ],
      [
        389.72,
        445.17,
        22.0,
        2.0
      ],
      [
        471.72,
        445.17,
        8.0,
        2.0
      ],
      [
        521.72,
        445.17,
        2.0,
        2.0
      ],
      [
        243.72,
        449.17,
        8.0,
        2.0
      ],
      [
        275.72,
        449.17,
        12.0,
        2.0
      ],
      [
        319.72,
        449.17,
        8.0,
        2.0
      ],
      [
        347.72,
        449.17,
        16.0,
        2.0
      ],
      [
        401.72,
        449.17,
        34.0,
        2.0
      ],
      [
        501.72,
        449.17,
        2.0,
        2.0
      ],
      [
        209.72,
        451.17,
        6.0,
        4.0
      ],
      [
        241.72,
        453.17,
        6.0,
        2.0
      ],
      [
        357.72,
        453.17,
        26.0,
        2.0
      ],
      [
        419.72,
        453.17,
        28.0,
        2.0
      ],
      [
        499.72,
        453.17,
        4.0,
        2.0
      ],
      [
        271.72,
        455.17,
        12.0,
        4.0
      ],
      [
        397.72,
        457.17,
        66.0,
        2.0
      ],
      [
        495.72,
        457.17,
        4.0,
        2.0
      ],
      [
        271.72,
        461.17,
        8.0,
        2.0
      ],
      [
        365.72,
        463.17,
        38.0,
        4.0
      ],
      [
        439.72,
        463.17,
        32.0,
        4.0
      ],
      [
        401.72,
        469.17,
        70.0,
        2.0
      ],
      [
        337.72,
        473.17,
        6.0,
        2.0
      ],
      [
        363.72,
        473.17,
        16.0,
        2.0
      ],
      [
        387.72,
        473.17,
        4.0,
        2.0
      ],
      [
        425.72,
        473.17,
        26.0,
        2.0
      ],
      [
        463.72,
        473.17,
        4.0,
        2.0
      ],
      [
        351.72,
        477.17,
        4.0,
        2.0
      ],
      [
        369.72,
        477.17,
        10.0,
        2.0
      ],
      [
        389.72,
        477.17,
        6.0,
        2.0
      ],
      [
        429.72,
        477.17,
        30.0,
        2.0
      ],
      [
        399.72,
        481.17,
        16.0,
        2.0
      ],
      [
        449.72,
        481.17,
        14.0,
        2.0
      ],
      [
        495.72,
        481.17,
        4.0,
        2.0
      ],
      [
        389.72,
        485.17,
        2.0,
        2.0
      ],
      [
        397.72,
        485.17,
        2.0,
        2.0
      ],
      [
        409.72,
        485.17,
        6.0,
        2.0
      ],
      [
        457.72,
        487.17,
        10.0,
        4.0
      ]
    ]
  },
  "stats": {
    "originalVertices": 440955,
    "originalTriangles": 733180,
    "decimatedTriangles": 368218,
    "outputVertices": 194104,
    "outputTriangles": 368041,
    "decimationRatio": 0.4637,
    "glbBytes": 45863460,
    "glbSha256": "97e2fff390827364dd9143c2f7b0b57a247a33afcd818e8615a23328290e51be"
  },
  "exportOptions": [
    "export_animations",
    "export_apply",
    "export_attributes",
    "export_cameras",
    "export_colors",
    "export_format",
    "export_image_format",
    "export_lights",
    "export_materials",
    "export_normals",
    "export_texcoords",
    "export_yup",
    "filepath",
    "use_selection"
  ],
  "warnings": [
    "The FBX references 13 external PNG textures that are not present in Model Inbox; they were deliberately ignored and replaced with vertex colours.",
    "Source scale is interpreted as miniature/kilometre-like units; conversion uses 250 m/unit horizontally so the footprint fits Kingsford district.",
    "Street-level source vertices at or below the configured ground Z are flattened to the city plate; bridges and elevated terrain remain approximate.",
    "Colliders are an occupancy-raster approximation of merged photogrammetry geometry, not hand-authored building footprints.",
    "Chunk splitting assigns triangles by centroid; hairline seams can occur where a source triangle crosses a 250 m boundary."
  ]
}
```

## kingsford-manhattan-city/conversion.md

```text
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
- GLB: 45,863,460 bytes, SHA-256 `97e2fff390827364dd9143c2f7b0b57a247a33afcd818e8615a23328290e51be`
- Colliders: 2,130 merged rectangles from 33,821 occupied 4 m cells

## Heaviest chunks

| Chunk | Triangles | Max height |
|---|---:|---:|
| `manhattan_04_03` | 156,987 | 449.5 m |
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
```

## kingsford-manhattan-city/loader-validation.json

```text
{
  "file": "/home/runner/work/_temp/model-city-convert/kingsford-manhattan-city/generated/kingsford-manhattan-city.glb",
  "mode": "generic",
  "bytes": 45863460,
  "meshes": 18,
  "vertices": 1050811,
  "meshesWithVertexColors": 18,
  "triangles": 365851,
  "nodes": [
    "Scene",
    "KingsfordManhattanCity",
    "manhattan_00_01",
    "manhattan_00_02",
    "manhattan_00_03",
    "manhattan_01_00",
    "manhattan_01_01",
    "manhattan_01_02",
    "manhattan_01_03",
    "manhattan_02_00",
    "manhattan_02_01",
    "manhattan_02_02",
    "manhattan_02_03",
    "manhattan_03_00",
    "manhattan_03_01",
    "manhattan_03_02",
    "manhattan_03_03",
    "manhattan_04_01",
    "manhattan_04_02",
    "manhattan_04_03"
  ],
  "materials": [
    "ManhattanVertexColor"
  ],
  "gltf": {
    "images": 0,
    "textures": 0,
    "extensionsUsed": [],
    "extensionsRequired": []
  },
  "bounds": {
    "min": [
      -601.057419,
      0,
      -497.443802
    ],
    "max": [
      596.632843,
      449.474579,
      496.780006
    ],
    "sizeXYZ": [
      1197.690262,
      449.474579,
      994.223808
    ],
    "center": [
      -2.212288,
      224.737289,
      -0.331898
    ]
  },
  "wheels": null,
  "animations": 0
}
```

