# Импортный Манхэттен вместо Kingsford City (v0.8.0)

Модель `NewYork-City-Manhattan.fbx`, загруженная владельцем через draft
GitHub Release «Model Inbox», установлена вместо процедурного района
Kingsford City на карте Festival Britain.

## Конвертация (GitHub Runner, Blender 4.0.2)

- Манифест: `asset-inbox/city-conversions/kingsford-manhattan-city.json`
- Workflow: `.github/workflows/model-inbox-city-convert.yml`
- Скрипт: `scripts/blender_convert_city.py`
- Отчёты: `asset-inbox/city-conversions/kingsford-manhattan-city/`
  (`conversion.md`, `conversion.json`, `occupancy.svg`, `loader-validation.json`)

FBX ссылается на 13 внешних PNG-текстур, которых нет в загрузке. По решению
владельца они игнорируются: конвертер назначает детерминированные
vertex-colour материалы (асфальт/бетон/крыши/фасады/«окна»).

Параметры: масштаб 250 м/ед. по горизонтали и 230 м/ед. по вертикали от
уровня земли исходника `Z=0.008`, выравнивание уличного уровня в единую
плиту, децимация 733 180 → 368 041 треугольников, нарезка на 18
пространственных чанков по 250 м в одном GLB.

Результат:

- GLB: `public/assets/models/cities/kingsford-manhattan-city/kingsford-manhattan-city.glb`
  (45 863 380 байт, Git LFS), footprint 1197.7 × 994.2 м, высота до 96 м.
- Сгенерированные данные: `src/world/manhattanCityData.js` (чанки, bounds и
  2 130 прямоугольных коллайдеров из occupancy-растра 4 м по исходной,
  недецимированной геометрии).
- Исходный FBX сохранён в LFS: `asset-source/cities/kingsford-manhattan-city/`.

## Размещение в мире

- Центр города: центр района Kingsford `(1250, -1050)`, без поворота.
- `src/world/manhattanCity.js` — чистый контракт размещения: footprint
  1212 × 1000 м, высота плато 9 м, мировые OBB-коллайдеры.
- `festivalBritain.heightAt` применяет прямоугольное плато 9 м последним
  шагом (blend 90 м снаружи), поверхность внутри — бетон, террейн под
  городом красится в бетонный цвет.
- `dressing.js` не ставит процедурные деревья/здания/фонари/стены внутри
  footprint; дорожные ленты Kingsford маскируются опцией `excludeBounds`
  в `buildRoadRibbonGeometry` (подключается в `worldStreamer.js`).
- `src/world/manhattanCityModel.js` асинхронно грузит GLB при старте
  Британии, ставит его на плато, регистрирует коллайдеры в
  `foundation.colliderIndex` и отключает далёкие чанки (>2700 м).
  Диагностика: `window.__NH_WORLD__.city`.

## Как перегенерировать

Изменить манифест конвертации или `scripts/blender_convert_city.py` и
запушить в ветку `arena/**` — workflow сам скачает FBX из Model Inbox,
проверит размер/SHA-256, прогонит Blender, провалидирует GLB
(`validate-glb-loader.mjs --generic`), зальёт байты в LFS с проверкой
повторного скачивания и закоммитит результат в ту же ветку.

## Известные ограничения

- Текстуры отсутствуют: город выглядит как окрашенная фотограмметрия.
  Когда владелец догрузит PNG, потребуется новая конвертация с материалами.
- Коллайдеры — приближение occupancy-растра, а не ручные фасады; въезды в
  город не выровнены по улицам Манхэттена.
- Мосты/эстакады исходника остаются визуальными: машина едет по плато.
