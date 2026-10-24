# City conversion failure diagnostics: kingsford-manhattan-city

Run: https://github.com/Aleksandr-pro/Nitches/actions/runs/40139890420
Commit: cdf51f35ae39016ff852fb722044d28b01cd52e5

## download-convert-step.log

```text
Downloading Model Inbox asset 673283843 (NewYork-City-Manhattan.fbx) for kingsford-manhattan-city...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
 54 38.9M   54 21.3M    0     0  21.5M      0  0:00:01 --:--:--  0:00:01 21.5M100 38.9M  100 38.9M    0     0  24.5M      0  0:00:01  0:00:01 --:--:-- 29.7M
Downloaded 40847916 bytes, sha256 42d948589eb8e93d70e1322a3c3420882d4ffb07c3c4fa08088786d5756e96c7
Converting NewYork-City-Manhattan.fbx into a chunked, textureless city GLB...
Blender 4.0.2
Traceback (most recent call last):
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_city.py", line 933, in <module>
    raise SystemExit(main())
                     ^^^^^^
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_city.py", line 787, in main
    raise RuntimeError(
RuntimeError: Decimated geometry escaped the original city bounds (x -601.1..596.6, y -496.8..497.4, maxHeight 96.0 m vs original 96.0 m); a world transform was probably applied twice.
FBX version: 7400

Blender quit
```

## kingsford-manhattan-city/blender-convert.log

```text
Blender 4.0.2
Traceback (most recent call last):
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_city.py", line 933, in <module>
    raise SystemExit(main())
                     ^^^^^^
  File "/home/runner/work/Nitches/Nitches/scripts/blender_convert_city.py", line 787, in main
    raise RuntimeError(
RuntimeError: Decimated geometry escaped the original city bounds (x -601.1..596.6, y -496.8..497.4, maxHeight 96.0 m vs original 96.0 m); a world transform was probably applied twice.
FBX version: 7400

Blender quit
```

