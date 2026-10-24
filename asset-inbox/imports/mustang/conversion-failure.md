# Conversion failure diagnostics: mustang

Run: https://github.com/Aleksandr-pro/Nitches/actions/runs/40099142669
Commit: cd0d721f9daa5f8f0bd045e59d327662e45fa03f

## download-convert-step.log

```text
Downloading release asset 672275730 (Mustang.zip) for mustang...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
 30 97.2M   30 30.0M    0     0  32.3M      0  0:00:03 --:--:--  0:00:03 32.3M 70 97.2M   70 68.1M    0     0  36.0M      0  0:00:02  0:00:01  0:00:01 39.5M100 97.2M  100 97.2M    0     0  37.0M      0  0:00:02  0:00:02 --:--:-- 39.5M
Downloaded 101934251 bytes, sha256 8c70f0255531cd1358397c529ac536deeeab951c8aa30e7947b0092c5ade9db6
Dumping material colors from Blender source (best effort)...
Blender 4.0.2
Read blend: "/home/runner/work/_temp/model-convert/mustang/extract/Mustang/Mustang.blend"
Warning: region type 4 missing in space type "Info" (id: 7) - removing region
{
  "dumpedMaterials": 31,
  "dumpedObjects": 106
}
Converting Mustang/Mustang.obj to optimized GLB...
Blender 4.0.2
OBJ import of 'Mustang.obj' took 503.0 ms
Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Traceback (most recent call last):
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 705, in <module>
    raise SystemExit(main())
                     ^^^^^^
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 699, in main
    convert(args)
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 630, in convert
    bpy.ops.export_scene.gltf(
  File "/usr/share/blender/scripts/modules/bpy/ops.py", line 109, in __call__
    ret = _op_call(self.idname_py(), kw)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
RuntimeError: Error: Python: Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Location: /usr/share/blender/scripts/modules/bpy/ops.py:109

13:41:40 | ERROR: Draco mesh compression is not available because library could not be found at /usr/bin/4.0/python/lib/python3.12/site-packages/libextern_draco.so
Error: Python: Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Location: /usr/share/blender/scripts/modules/bpy/ops.py:109

Blender quit
```

## mustang/blender-dump.log

```text
Blender 4.0.2
Read blend: "/home/runner/work/_temp/model-convert/mustang/extract/Mustang/Mustang.blend"
Warning: region type 4 missing in space type "Info" (id: 7) - removing region
{
  "dumpedMaterials": 31,
  "dumpedObjects": 106
}
```

## mustang/blender-convert.log

```text
Blender 4.0.2
OBJ import of 'Mustang.obj' took 503.0 ms
Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Traceback (most recent call last):
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 705, in <module>
    raise SystemExit(main())
                     ^^^^^^
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 699, in main
    convert(args)
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_car.py", line 630, in convert
    bpy.ops.export_scene.gltf(
  File "/usr/share/blender/scripts/modules/bpy/ops.py", line 109, in __call__
    ret = _op_call(self.idname_py(), kw)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
RuntimeError: Error: Python: Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Location: /usr/share/blender/scripts/modules/bpy/ops.py:109

13:41:40 | ERROR: Draco mesh compression is not available because library could not be found at /usr/bin/4.0/python/lib/python3.12/site-packages/libextern_draco.so
Error: Python: Traceback (most recent call last):
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/__init__.py", line 752, in execute
    from .blender.exp import gltf2_blender_export
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_export.py", line 16, in <module>
    from . import gltf2_blender_gather
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather.py", line 11, in <module>
    from . import gltf2_blender_gather_nodes
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_nodes.py", line 15, in <module>
    from . import gltf2_blender_gather_tree
  File "/usr/share/blender/scripts/addons/io_scene_gltf2/blender/exp/gltf2_blender_gather_tree.py", line 7, in <module>
    import numpy as np
ModuleNotFoundError: No module named 'numpy'
Location: /usr/share/blender/scripts/modules/bpy/ops.py:109

Blender quit
```

## mustang/inventory.stdout.json

```text
{
  "archive": {
    "name": "Mustang.zip",
    "size": 101934251,
    "sha256": "8c70f0255531cd1358397c529ac536deeeab951c8aa30e7947b0092c5ade9db6"
  },
  "summary": {
    "entryCount": 22,
    "fileCount": 20,
    "totalUncompressedBytes": 243581056,
    "extractionEnabled": true,
    "unsafeEntryCount": 0,
    "extractionErrorCount": 0
  },
  "runtimeCandidates": [],
  "sourceCandidates": [
    "Mustang/Mustang.blend",
    "Mustang/Mustang.blend1",
    "Mustang/Mustang.fbx",
    "Mustang/Mustang.mtl",
    "Mustang/Mustang.obj",
    "Mustang/Mustang.stl",
    "Mustang/Textures/Mustang.blend",
    "Mustang/Textures/Mustang.blend1",
    "Mustang/Textures/Mustang.fbx",
    "Mustang/Textures/Mustang.mtl",
    "Mustang/Textures/Mustang.obj",
    "Mustang/Textures/Mustang.stl"
  ],
  "warnings": [
    "Найдено текстур крупнее 2048 px: 2; для мобильной runtime-версии их обычно нужно уменьшать/сжимать.",
    "Найдено точных дубликатов: 6 групп; повторные копии занимают около 110.12 MiB. В LFS одинаковые объекты хранятся по хешу один раз, но распакованный набор лучше не дублировать."
  ]
}
```

## mustang/blend-materials.json

```text
      ],
      "dimensions": [
        0.8014160990715027,
        0.8014160990715027,
        0.2926703691482544
      ],
      "location": [
        -2.3900234699249268,
        -1.2248938083648682,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRAxle",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.22509342432022095,
        0.22509342432022095,
        0.4955359399318695
      ],
      "location": [
        -2.3900234699249268,
        -1.3356812000274658,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRSpoke1",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        -2.3900234699249268,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRSpoke2",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        -2.3900234699249268,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRSpoke3",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        -2.3900234699249268,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRSpoke4",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532044112682343,
        0.273463636636734
      ],
      "location": [
        -2.3900234699249268,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRSpoke5",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        -2.3900234699249268,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelBRTire",
      "type": "MESH",
      "materials": [
        "M_Tire1"
      ],
      "dimensions": [
        1.0276111364364624,
        1.027611255645752,
        0.3223373591899872
      ],
      "location": [
        -2.3900234699249268,
        -1.2248938083648682,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRTire",
      "type": "MESH",
      "materials": [
        "M_Tire1"
      ],
      "dimensions": [
        1.0276111364364624,
        1.027611255645752,
        0.3223373591899872
      ],
      "location": [
        1.584822654724121,
        -1.2248938083648682,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRSpoke5",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        1.584822654724121,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRSpoke4",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532044112682343,
        0.273463636636734
      ],
      "location": [
        1.584822654724121,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRSpoke3",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        1.584822654724121,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRSpoke2",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        1.584822654724121,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRSpoke1",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.03435148298740387,
        0.16532041132450104,
        0.27346357703208923
      ],
      "location": [
        1.584822654724121,
        -1.3605388402938843,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRAxle",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.22509342432022095,
        0.22509342432022095,
        0.5240487456321716
      ],
      "location": [
        1.584822654724121,
        -1.3356812000274658,
        0.15269555151462555
      ]
    },
    {
      "name": "M_WheelFRRim",
      "type": "MESH",
      "materials": [
        "M_Rim1",
        "M_Rim2"
      ],
      "dimensions": [
        0.8014160990715027,
        0.8014160990715027,
        0.2926703691482544
      ],
      "location": [
        1.584822654724121,
        -1.2248938083648682,
        0.15269555151462555
      ]
    },
    {
      "name": "StudioLight3",
      "type": "MESH",
      "materials": [
        "StudioLight"
      ],
      "dimensions": [
        4.840292453765869,
        1.3017759323120117,
        0.0
      ],
      "location": [
        0.7116694450378418,
        -6.308693885803223,
        3.2296395301818848
      ]
    },
    {
      "name": "StudioLight4",
      "type": "MESH",
      "materials": [
        "StudioLight"
      ],
      "dimensions": [
        4.777238368988037,
        1.3212498426437378,
        0.0
      ],
      "location": [
        4.923572540283203,
        0.3227846622467041,
        2.4523730278015137
      ]
    },
    {
      "name": "StudioLight2",
      "type": "MESH",
      "materials": [
        "StudioLight"
      ],
      "dimensions": [
        4.840292453765869,
        1.3017759323120117,
        0.0
      ],
      "location": [
        -4.423750877380371,
        -3.977583885192871,
        3.2296395301818848
      ]
    },
    {
      "name": "StudioLight1",
      "type": "MESH",
      "materials": [
        "StudioLight"
      ],
      "dimensions": [
        3.3715474605560303,
        0.9324752688407898,
        0.0
      ],
      "location": [
        -0.6973212957382202,
        2.1520347595214844,
        4.857755661010742
      ]
    },
    {
      "name": "StudioLight5",
      "type": "MESH",
      "materials": [
        "StudioLight"
      ],
      "dimensions": [
        4.840017795562744,
        1.3386129140853882,
        0.0
      ],
      "location": [
        0.42129969596862793,
        -0.23982521891593933,
        5.9291534423828125
      ]
    },
    {
      "name": "Camera",
      "type": "CAMERA",
      "materials": [],
      "dimensions": [
        0.0,
        0.0,
        0.0
      ],
      "location": [
        6.680755138397217,
        -5.185603141784668,
        0.7324787974357605
      ]
    },
    {
      "name": "StudioGround",
      "type": "MESH",
      "materials": [
        "Ground",
        "Ground2"
      ],
      "dimensions": [
        68.0987777709961,
        68.0987777709961,
        16.22075080871582
      ],
      "location": [
        -0.23716187477111816,
        -0.2129894495010376,
        -0.31738847494125366
      ]
    }
  ]
}
```

