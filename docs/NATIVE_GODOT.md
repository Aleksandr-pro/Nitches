# Nitches Horizon Native (Godot 4)

## Решение

Начиная с нативного этапа игра собирается как обычное Android-приложение на
**Godot 4.7.2**, а не как страница внутри Android WebView.

Старый стек (Vite + Three.js + Capacitor) остаётся в репозитории только как
источник уже созданных данных мира и канонических runtime-ассетов на время
перехода. Новый игровой runtime находится в `native/` и не запускает
HTML/JavaScript внутри APK.

Почему выбран Godot:

- настоящий ARM64 executable и нативный рендер (Mobile renderer);
- физика RigidBody3D/Jolt, raycast-подвеска и коллизии выполняются движком;
- MultiMesh позволяет отрисовывать повторяющиеся здания, фонари и растительность
  малым числом draw calls;
- проект полностью собирается headless в GitHub Actions без Unity/Unreal
  лицензий, аккаунтов редактора и ручных действий владельца;
- существующие GLB, JPG/PNG и normal maps импортируются без повторной
  покупки или загрузки ассетов.

## Что уже есть в Native Alpha 0.1.1

- `native/project.godot` — настоящий Godot-проект, Mobile renderer, Jolt;
- `native/scenes/main.tscn` — главная сцена;
- `NativeWorldBuilder` — RichTown 980×1000 м в реальных метрах:
  - heightmap-террейн 99×101 и HeightMapShape3D-коллизия;
  - 41 дорожное ребро, асфальт и тротуары;
  - 52 здания, включая 14 Blender-вилл и 8 Blender-стеклянных башен;
  - 15 ориентиров, включая главную 148-метровую башню и арку;
  - море/марина, 18 бассейнов, 112 пальм и 98 Blender-фонарей;
  - день, закат и ночь с emissive-окнами и фонарями;
- `NativeVehicle` — Mustang как RigidBody3D:
  - четыре raycast-подвески с пружинами, демпферами и anti-roll;
  - продольные/боковые силы шин в точках контакта;
  - задний привод, ручник/дрифт, нитро, передачи и звук двигателя;
  - вращающиеся/поворачивающиеся колёса из GLB;
- `NativeHud` и `NativeMinimap` — скорость, район, FPS/draw calls/tris,
  сенсорные педали и руление;
- три камеры: chase, hood и top.

## Данные и ассеты

`scripts/export-native-world.mjs` экспортирует детерминированный план
RichTown из существующего генератора мира в `native/data/richtown_native.json`.
Это одноразовый мост данных: Godot не исполняет Three.js код.

JSON не является обычным Godot-ресурсом, поэтому Android preset обязан
содержать `include_filter="*.json"`. Без этого фильтра редакторный запуск
может работать, а экспортированный APK останется без данных мира. Начиная с
0.1.1 CI отдельно запускает экспортированный PCK вне исходного дерева и
проверяет в APK путь `assets/data/richtown_native.json`.

`scripts/sync-native-assets.mjs` копирует нужные файлы в игнорируемую папку
`native/assets/` перед импортом Godot:

- Mustang GLB из `public/assets/models/cars/mustang/` (в CI сначала
  материализуется Git LFS);
- Blender GLB и plant pack из `src/assets/models/`;
- выбранные текстуры и normal maps из `src/assets/textures/realworld/`.

Скрипт проверяет сигнатуру `glTF`, поэтому LFS-pointer не попадёт в APK.

## Сборка

Локальная подготовка данных:

```bash
node scripts/export-native-world.mjs
node scripts/sync-native-assets.mjs
node scripts/validate-native-project.mjs --require-assets
```

Полная Android-сборка выполняется workflow
`.github/workflows/native-godot-android.yml`. Он скачивает официальный
Godot 4.7.2 и export templates из GitHub Releases, настраивает Android SDK,
подписывает APK ключом из секретов (или одноразовым ключом раннера, если
секретов нет), проверяет подпись и наличие `lib/arm64-v8a/libgodot_android.so`
и загружает артефакт `NitchesHorizonNative-apk`.

Перед APK workflow запускает строгий `--native-smoke`: данные мира не пустые,
Mustang стоит на колёсах у спавна и находится в frustum текущей камеры,
миникарта получила дороги/здания, а скорость и педали полностью лежат в
viewport. Та же проверка повторяется на экспортированном PCK, чтобы успешный
редакторный импорт больше не маскировал пустую телефонную сборку.

Пароли keystore не хранятся в `export_presets.cfg`: CI передаёт их только
через `GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables.

## Следующие этапы

1. Разбить RichTown на стриминговые чанки 250×250 м и добавить
   VisibilityRange/LOD для зданий и растительности.
2. Заменить оставшиеся generic-массы отдельными Blender-моделями районов.
3. Перенести трафик, гонки, дрифт-зоны, прогресс и сохранения в GDScript.
4. Добавить частицы шин/нитро, следы, повреждения и полноценный звук.
5. Профилировать на телефоне по HUD-метрикам и ввести пресеты качества
   (разрешение, MSAA, тени, дальность, плотность трафика).
6. После паритета функций удалить Capacitor APK из основного релизного пути.
