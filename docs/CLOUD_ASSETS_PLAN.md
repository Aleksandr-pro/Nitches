# Единая облачная система 3D-ресурсов: аудит и план интеграции

Статус: **этап 1 — аудит выполнен, план ожидает согласования**.

Цель документа — зафиксировать минимальную архитектуру Cloudflare R2 для Nitches Horizon до начала реализации. Массовый перенос моделей на этом этапе не выполняется.

## 1. Фактический стек проекта

### Движок и платформы

- Игра написана на **Three.js 0.180.0 + Vite 7.3.7**, ванильный JavaScript, WebGL.
- Основные платформы:
  - браузер/PWA;
  - Android APK через **Capacitor 8.5.3** и WebView.
- `capacitor.config.json` использует `androidScheme: "https"`; в AndroidManifest уже есть разрешение `INTERNET`.
- Отдельного нативного движка, постоянного игрового сервера и тест-раннера в проекте нет.
- IOS-папки и дополнительных Capacitor-плагинов сейчас нет; установлены только `@capacitor/core`, `@capacitor/android` и CLI.

### Как устроена игра сейчас

- `src/main.js` — монолит примерно на 4 500 строк. Он синхронно при старте строит сцену, остров, дороги, растительность, инфраструктуру, трафик, физику и UI.
- `src/gtr.js` — процедурная GT-R35.
- `src/mustang.js` — единственный внешний runtime-GLB, загружаемый локально из `public/assets/models/cars/mustang/mustang.glb` через `GLTFLoader.loadAsync()`.
- Остальные автомобили и почти весь мир строятся кодом и Canvas-текстурами.
- Мир: террейн 640 × 640 м, 330 деревьев, 260 кустов, 3 800 пучков травы и 95 камней. Повторяющиеся деревья/кусты/трава/камни уже используют `InstancedMesh`.
- Стриминга по областям мира нет: все статические объекты создаются один раз при запуске.
- Коллайдеры окружения — плоский массив окружностей `{x, z, r}`, который линейно проверяется в физике игрока. Для текущего масштаба это приемлемо, для тысяч облачных объектов понадобится пространственная сетка.
- Размещение объектов мира сейчас задано кодом и детерминированным генератором. Отдельного формата world-pack/placement-manifest пока нет.

### Текущие ассеты и сборка

- Runtime-GLB лежат в `public/assets/models/**`, хранятся в Git LFS, копируются Vite в `dist/`, затем Capacitor переносит их в APK.
- Mustang: 5 874 616 байт, 157 759 треугольников, габариты 4,66 × 1,835 × 1,302 м, узлы `Wheel_*` и `Wheel_*_Spin`.
- Исходный `Mustang.zip` на 101 934 251 байт хранится в `asset-source/**` и в APK не попадает.
- CI умеет:
  - скачивать реальные runtime-байты из LFS;
  - проверять GLB настоящим Three.js `GLTFLoader`;
  - собирать web и выполнять Capacitor sync;
  - принимать модели из Model Inbox и конвертировать автомобильный OBJ в Blender.

### Текущий кэш и сеть

- `public/sw.js` — простой network-first runtime-кэш только для same-origin GET.
- У текущего service worker нет проверки SHA-256, лимита размера, LRU, статистики и отдельной политики для моделей.
- Cross-origin запросы к будущему R2 service worker не перехватывает.
- `localStorage` используется только для маленьких настроек и рекордов.
- IndexedDB, Capacitor Filesystem и собственный Resource Manager пока отсутствуют.
- Draco, Meshopt и KTX2/Basis декодеры к `GLTFLoader` не подключены.

## 2. Главный архитектурный вывод

Для этого проекта не нужен постоянно работающий сервер и не нужен Worker в первой версии.

Минимальная совместимая схема:

```text
Git / Model Inbox / Blender
          │
          ▼
 Publisher: валидация GLB → SHA-256 → immutable key → manifest version
          │
          ▼
 Cloudflare R2 (public runtime bucket)
          │ HTTPS + custom domain + Cloudflare Cache + CORS
          ▼
 Resource Manager в игре
   ├── current pointer и versioned manifest
   ├── IndexedDB: проверенные Blob-файлы и метаданные кэша
   ├── downloader: dedupe, retries, AbortController, concurrency
   ├── GLTFLoader.parseAsync(ArrayBuffer)
   └── category adapters: static / instanced / vehicle
          │
          ▼
 Three.js scene + существующая физика/коллайдеры
```

Git LFS не нужно выбрасывать сразу:

- исходные пакеты и редактируемые источники остаются в Model Inbox + Git LFS;
- R2 становится каналом доставки **опубликованных runtime-ресурсов**;
- критичные для первого запуска ресурсы и процедурный мир остаются в APK как минимум на время прототипа и переходного периода.

## 3. Предлагаемая организация R2

### Бакеты и домены

Рекомендуется разделить окружения:

- `nitches-game-assets-dev` — прототип и проверка публикаций;
- `nitches-game-assets-prod` — публичные runtime-ресурсы игры.

Если на старте проще один бакет, допустимы префиксы каналов `dev/` и `prod/`, но отдельные бакеты дают более чистое разделение прав.

Для production нужен собственный поддомен, например:

```text
https://assets.<ваш-домен>/
```

`r2.dev` допустим только для dev-прототипа: Cloudflare позиционирует его как non-production endpoint с rate limit и без возможностей custom domain для Cache/WAF/Bot Management. Для production Cloudflare рекомендует custom domain.

В публичный runtime-бакет нельзя класть:

- исходные ZIP/Blend/FBX, если они не должны быть публично доступны;
- неопубликованные модели;
- секреты и служебные файлы;
- приватные исходники.

Публичный bucket означает, что любой, кто знает URL объекта, может скачать файл. Это не защита от копирования моделей.

### Ключи объектов

Файлы публикуются только по неизменяемым ключам с версией и полным SHA-256:

```text
manifests/current.json
manifests/versions/1.0.0-<manifest-sha256>/manifest.json

trees/oak_001/1.0.0/model-<sha256>.glb
vehicles/mustang/1.0.0/model-<sha256>.glb
buildings/house_001/1.0.0/model-<sha256>.glb
shared/textures/<sha256>.webp
materials/<sha256>.json
```

Правила:

- один SHA-256 всегда означает одни и те же байты;
- существующий immutable key не перезаписывается другими байтами;
- обновление модели создаёт новый ключ и новую версию манифеста;
- `manifests/current.json` обновляется последним и служит только указателем на проверенную версию каталога;
- откат выполняется возвратом `current.json` на предыдущий versioned manifest;
- старые файлы не удаляются до окончания grace-периода и проверки, что ни current, ни rollback-манифесты на них не ссылаются.

### Cache-Control и CDN

- `manifests/current.json`: короткий TTL, например `public, max-age=30, s-maxage=30, stale-while-revalidate=60`.
- Версионированные манифесты и hashed-модели: `public, max-age=31536000, immutable`.
- Для custom domain нужна Cache Rule, делающая GLB и остальные игровые файлы eligible for cache: Cloudflare по умолчанию кэширует не все типы файлов.
- Content-Type задаётся при загрузке: `model/gltf-binary` для `.glb`, `application/json` для манифестов и корректные типы для текстур.

### CORS

Для публичного runtime-доступа нужны только `GET` и `HEAD` без credentials.

Начальный список Origin для проверки:

- `https://localhost` — Android Capacitor WebView;
- `http://localhost:5173` — Vite dev;
- `http://localhost:4173` — Vite preview;
- будущий production web origin, если игра будет опубликована как сайт;
- `capacitor://localhost` — зарезервировать в плане на случай iOS, но проверить отдельно.

Cloudflare возвращает CORS-заголовки для cross-origin запросов с валидным `Origin`, если для bucket настроена CORS policy и используется custom domain.

### Права публикации

- Клиент игры получает только публичный base URL; никаких R2-ключей в APK/PWA.
- Для publisher создаётся bucket-scoped токен **Object Read & Write** только на нужный бакет.
- Секреты не передаются в чат и не коммитятся. Владелец проекта добавляет их сам в GitHub Actions Secrets, когда дойдём до автоматизации.
- Для ручного прототипа владелец может загрузить 2–3 файла через Cloudflare Dashboard по точным ключам из инструкции.

## 4. Единый каталог ресурсов

### Pointer

`manifests/current.json`:

```json
{
  "schemaVersion": 1,
  "catalogVersion": "1.0.0",
  "manifestPath": "manifests/versions/1.0.0-<sha256>/manifest.json",
  "manifestSizeBytes": 12345,
  "manifestSha256": "<64 hex>",
  "publishedAt": "2026-10-24T00:00:00Z"
}
```

Клиент:

1. Скачивает pointer с коротким timeout.
2. Проверяет схему и безопасный относительный путь.
3. Скачивает versioned manifest.
4. Сверяет размер и SHA-256.
5. Только после полной валидации сохраняет каталог как последний известный хороший.

При офлайне используется последний валидированный каталог из IndexedDB, а не частично скачанный JSON.

### Versioned manifest

Предлагаемая схема v1:

```json
{
  "schemaVersion": 1,
  "catalogVersion": "1.0.0",
  "generatedAt": "2026-10-24T00:00:00Z",
  "minClient": {
    "assetSchemaVersion": 1
  },
  "categories": [
    { "id": "vehicles" },
    { "id": "buildings" },
    { "id": "trees" },
    { "id": "vegetation" },
    { "id": "roads" },
    { "id": "infrastructure" },
    { "id": "props" },
    { "id": "terrain" },
    { "id": "effects" }
  ],
  "files": {
    "<sha256>": {
      "key": "trees/oak_001/1.0.0/model-<sha256>.glb",
      "sizeBytes": 123456,
      "sha256": "<sha256>",
      "mediaType": "model/gltf-binary",
      "role": "model"
    }
  },
  "assets": [
    {
      "id": "tree_oak_001",
      "type": "trees",
      "version": "1.0.0",
      "modelFile": "<sha256>",
      "dependencies": [],
      "lod": [
        {
          "name": "lod0",
          "maxDistance": 90,
          "file": "<sha256>"
        }
      ],
      "bounds": {
        "min": [0, 0, 0],
        "max": [0, 0, 0],
        "size": [0, 0, 0]
      },
      "pivot": [0, 0, 0],
      "collider": {
        "kind": "cylinder",
        "center": [0, 0, 0],
        "radius": 0.45,
        "height": 5.5
      },
      "render": {
        "castShadow": true,
        "receiveShadow": true,
        "instancing": "allowed"
      },
      "gameplay": {},
      "source": {
        "name": "",
        "license": ""
      }
    }
  ]
}
```

В production-манифесте нулевые размеры, пустые SHA и примерные bounds запрещены: publisher заполняет их реальными значениями из валидатора.

### Правила валидации каталога

Клиент и publisher должны одинаково проверять:

- поддерживаемый `schemaVersion`;
- уникальность `asset.id` и file SHA;
- `id` и `type` по строгому regex, например `^[a-z][a-z0-9_-]{1,63}$`;
- только относительные POSIX-ключи без `..`, backslash, абсолютных URL и пустых сегментов;
- длину ключа не больше 1024 байт;
- SHA-256 ровно 64 hex-символа;
- неотрицательный безопасный `sizeBytes`;
- все `modelFile`, LOD и зависимости существуют;
- отсутствие циклов зависимостей;
- допустимые расширения и media type;
- конечные числа в bounds/pivot/collider;
- ограничения на размер JSON, число файлов и суммарный размер обязательного набора.

Категория — строка из каталога, а не enum, зашитый в downloader. Новая категория со статичным GLB может появиться без изменения сетевого кода. Но новая игровая логика категории всё равно требует adapter в клиенте.

### Что каталог не решает сам по себе

Asset manifest описывает файлы, но не говорит миру, где поставить новый дом или дерево и как добавить автомобиль в гараж.

Поэтому разделяем:

1. **Asset catalog** — модели, файлы, зависимости, LOD, bounds, collider defaults.
2. **Content/world packs** — позже: размещения экземпляров, ячейки мира, трансформации, переопределения коллайдеров.
3. **Vehicle definitions** — позже: физика, UI-статистика, краски и контракт колёс для добавления машин без кода.

Для вертикального прототипа одно размещение дерева будет временно задано в коде. Это сознательно: сначала проверяем R2 → manifest → cache → Three.js, а не проектируем редактор мира.

## 5. Resource Manager для Three.js

Предлагаемая структура модулей:

```text
src/resources/
  assetConfig.js       — base URL, канал, лимиты, feature flag
  assetManifest.js     — загрузка pointer/manifest, валидация, индексы, зависимости
  assetCache.js        — интерфейс кэша и IndexedDB-реализация
  assetDownloader.js   — fetch, dedupe, retries, AbortController, progress
  ResourceManager.js   — публичный API, память, refcount, статистика
  gltfAssetFactory.js  — GLTFLoader.parseAsync, шаблоны и клоны
  adapters/
    staticProp.js      — тени, pivot, collider
    vehicle.js         — колёса/краска, позже на базе Mustang
    instancedProp.js   — позже для деревьев/фонарей/пропов
```

### Публичный API

Ориентир для реализации:

```js
await resources.init({ signal });
resources.getAsset('tree_oak_001');
resources.listAssets({ type: 'trees' });
await resources.ensureAsset('tree_oak_001', { signal, onProgress });
const handle = await resources.loadGltf('tree_oak_001', { lod: 'lod0' });
const instance = handle.instantiate();
handle.release();
resources.getStats();
await resources.clearCache({ includeRequired: false });
```

### Разделение четырёх состояний

Resource Manager обязан различать:

1. **Remote** — файл существует в R2 и описан в манифесте.
2. **Downloaded/cached** — проверенный Blob лежит в IndexedDB.
3. **Parsed/in memory** — GLTF распарсен в шаблон Three.js.
4. **Instantiated** — клон или InstancedMesh добавлен в сцену.

Скачивание файла не должно автоматически создавать объект мира, а удаление экземпляра не должно автоматически удалять диск-кэш.

### Память и повторное использование

- Один SHA скачивается один раз даже при параллельных запросах.
- Один parsed template переиспользуется клонами.
- Для каждого template ведётся refcount активных экземпляров.
- При нулевом refcount шаблон может жить в ограниченном memory-LRU; при вытеснении вызываются `geometry.dispose()`, `material.dispose()` и dispose текстур с учётом shared-владения.
- Статистика: catalog version, cache hit/miss, bytes downloaded/cached, active downloads, parsed templates, ошибки и время загрузки.
- Ошибка одного необязательного ресурса не должна останавливать игру.

## 6. Выбор локального кэша

### Рекомендация: IndexedDB для игровых файлов

Причины:

- работает в браузере и Android WebView без нового нативного плагина;
- хранит `Blob`/`ArrayBuffer` и метаданные рядом;
- позволяет индексы по SHA, размеру, `lastAccessedAt`, версии каталога;
- даёт точный LRU и staging до проверки целостности;
- не зависит от service worker.

Cache API оставляем для app shell PWA, а не как основной реестр моделей. Capacitor Filesystem рассматриваем позже, если пакеты станут очень большими или понадобится нативная потоковая запись без загрузки всего файла в память.

Важно: браузерное хранилище по умолчанию может быть вытеснено при нехватке места. Поэтому клиент:

- запрашивает `navigator.storage.persist()` opportunistic, но не зависит от успеха;
- смотрит `navigator.storage.estimate()`;
- считает кэш восстанавливаемым, а не единственным источником критичных данных;
- сохраняет bundled/procedural fallback для базовой игры.

### Атомарная запись

1. Скачать файл чанками, контролировать прогресс и отмену.
2. Собрать `Blob` во временную staging-запись IndexedDB.
3. Проверить фактический размер.
4. Посчитать SHA-256 через `crypto.subtle.digest`.
5. Только при совпадении записать canonical record по SHA и удалить staging.
6. На старте чистить старые staging-записи.

### Политика вытеснения

Начальный мягкий лимит прототипа: **512 MiB**, но не больше безопасной доли доступной квоты.

Порядок очистки:

1. staging и повреждённые записи;
2. файлы, которых нет ни в текущем, ни в rollback-каталоге;
3. LRU среди необязательных и неактивных файлов;
4. никогда не вытеснять файлы с активным refcount или обязательные для текущего мира без явной политики.

При `QuotaExceededError`: одна попытка LRU-очистки и повтор; при повторной ошибке ресурс можно использовать только из памяти текущей сессии, а игра продолжает работу.

## 7. Формат моделей для первой версии

Для прототипа и первого production-контракта:

- только самодостаточный binary glTF 2.0 `.glb`;
- все buffers и изображения встроены;
- запрещены внешние URI внутри GLB, пока Resource Manager не научится перехватывать их через `LoadingManager`;
- Draco/Meshopt/KTX2 запрещены до подключения и измерения декодеров;
- 1 единица = 1 метр, `+Y` вверх;
- pivot и ориентация задаются контрактом категории и проверяются publisher/validator;
- для автомобилей сохраняется текущий контракт `Wheel_FL/FR/RL/RR` + `Wheel_*_Spin`;
- интерьеры автомобилей не требуются.

Это ограничение сознательно уменьшает поверхность ошибок: один файл = один SHA = одна проверка целостности = один `GLTFLoader.parseAsync(ArrayBuffer)`.

## 8. Вертикальный прототип этапа 2

### Тестовый ресурс

Предлагается отдельный generated-фиксчурный ресурс:

- `id`: `tree_oak_001`;
- `type`: `trees`;
- маленькая low-poly модель дуба, сгенерированная детерминированным скриптом;
- визуально отличимая крона, чтобы было легко понять, что загрузился именно облачный объект;
- один экземпляр рядом с фестивальной зоной старта, вне дорожного полотна;
- collider-цилиндр из манифеста добавляется в существующий `colliders` только для активного экземпляра.

Существующие 330 процедурных деревьев на этом этапе не заменяем.

### Поток прототипа

1. Publisher-скрипт генерирует GLB в ignored staging-каталог.
2. Считает SHA-256, размер, bounds и треугольники.
3. Формирует immutable key, versioned manifest и `current.json`.
4. Владелец загружает файлы в dev bucket вручную или publisher загружает их после настройки секретов.
5. Игра с configured `VITE_ASSET_CDN_BASE_URL`:
   - читает pointer;
   - валидирует каталог;
   - проверяет IndexedDB;
   - скачивает только отсутствующий GLB;
   - сверяет SHA-256;
   - парсит и ставит дерево в мир.
6. Повторный запуск должен показать cache hit без повторного скачивания байтов модели.

### Файлы прототипа

Планируемые изменения после согласования:

```text
.env.example
docs/CLOUD_ASSETS.md
scripts/generate-cloud-prototype-tree.mjs
scripts/build-cloud-catalog.mjs
scripts/validate-cloud-catalog.mjs
src/resources/assetConfig.js
src/resources/assetManifest.js
src/resources/assetCache.js
src/resources/assetDownloader.js
src/resources/ResourceManager.js
src/resources/gltfAssetFactory.js
src/resources/adapters/staticProp.js
src/cloudPrototype.js
src/main.js — минимальный init hook и одна точка размещения
tests/resources/*.test.mjs — Node built-in test runner без нового фреймворка
```

`src/mustang.js` на этапе прототипа не переписываем. Сначала доказываем универсальный путь на дереве.

### Критерии приёмки прототипа

- При пустом кэше дерево скачивается из публичного R2 URL и появляется в игре.
- При повторном запуске модель берётся из IndexedDB; сеть нужна максимум для маленького `current.json`.
- В офлайне после первого успешного запуска дерево появляется из кэша.
- Повреждённый Blob в кэше обнаруживается по SHA, удаляется и скачивается заново; игра не падает.
- При недоступном R2 и пустом кэше игра запускается без облачного дерева.
- Отмена/переключение сцены не оставляет висячих скачиваний.
- В статистике видны catalog version, cache hit/miss, размер и результат проверки.
- Web build и Capacitor sync в чистом CI проходят; локальный bundled Mustang продолжает работать.

## 9. Следующие этапы после прототипа

### Этап 3. Универсальный каталог

- Добавить минимум второй статический тип, например тестовый дом или фонарь, тем же путём.
- Обобщить validator: vehicle-профиль отдельно, static-профиль без требования колёс.
- Добавить category adapter registry без изменения downloader/cache.

### Этап 4. Кэш и обновления

- Полные тесты обновления каталога v1 → v2.
- Rollback pointer.
- LRU, quota, staging cleanup, статистика в debug-интерфейсе.
- Проверка Android WebView после перезапуска приложения и очистки кэша ОС.

### Этап 5. Mustang и здания

- Опубликовать тот же Mustang GLB в R2 в shadow-режиме.
- Подключить его через Resource Manager при включённом feature flag.
- Порядок источников: валидный облачный кэш → bundled GLB → облачная загрузка → процедурный fallback.
- Не удалять Mustang из APK, пока отдельно не решено, допустим ли первый запуск без интернета без этой машины.
- Подключить одно статическое здание как cloud prop без изменения физики мира кроме его collider.

### Этап 6. Стриминг мира

Текущий остров всего 640 × 640 м, поэтому стриминг нужен сначала для облачных пропов, а не для переписывания всего мира.

- Разбить мир на ячейки, например 80 × 80 м.
- Ввести world-pack/placement descriptors.
- Для повторяющихся cloud-объектов строить `InstancedMesh` на ячейку и LOD.
- Предзагружать соседние ячейки по направлению/скорости игрока.
- Выгружать экземпляры с гистерезисом, не удаляя диск-кэш автоматически.
- Заменить линейный поиск коллайдеров пространственной сеткой.

Террейн, дороги и базовая процедурная растительность остаются bundled core до отдельного решения.

### Этап 7. Автоматизация публикации

Publisher должен уметь:

1. Принять descriptor ресурса и GLB.
2. Проверить GLB, bounds, треугольники, внешние URI и контракты категории.
3. Посчитать size/SHA-256.
4. Сформировать immutable key и staging-каталог, повторяющий R2.
5. Сформировать новый versioned manifest на базе предыдущего.
6. В `--dry-run` ничего не загружать.
7. Загрузить сначала файлы, затем versioned manifest, затем pointer.
8. Сделать публичный smoke GET и повторную проверку SHA уже с CDN.
9. Напечатать rollback-инструкцию и список изменённых ключей.

Для загрузки на этапе автоматизации выбирается официальный Wrangler `r2 object put` или S3-compatible инструмент после проверки, какой способ удобнее для bucket-scoped credentials и per-object Cache-Control. Секреты хранятся только в GitHub Actions Secrets или локальном окружении владельца.

### Этап 8. Полная проверка

- Первый запуск онлайн/офлайн.
- Повторный запуск из кэша.
- Обновление и откат каталога.
- Повреждённый файл и неверный SHA.
- Прерванная загрузка и повтор.
- Нехватка места/квоты.
- Переключение ячеек мира.
- Память, draw calls, треугольники и FPS до/после.
- Android APK на реальном устройстве.

## 10. Риски и блокеры

1. **Cloudflare ещё не настроен в репозитории.** Неизвестны аккаунт, R2 subscription, bucket и домен.
2. **Агент не должен получать секреты.** Создание bucket/domain/CORS и добавление GitHub Secrets выполняет владелец по инструкции.
3. **CORS в Capacitor нужно проверить на реальном WebView.** Особенно фактический `Origin`.
4. **IndexedDB не вечна.** ОС/браузер может вытеснить best-effort storage; критичный контент должен иметь fallback.
5. **Публичность = копируемость.** R2 public bucket не защищает модели.
6. **Каталог не размещает объекты сам.** Для полностью data-driven мира позже нужны placement/world packs и vehicle definitions.
7. **Сжатие пока не поддерживается клиентом.** Draco/Meshopt/KTX2 включать только после декодеров и замеров.
8. **Текущий service worker слишком простой.** Перед production cloud launch его политику нужно разделить: app shell отдельно, модели — через Resource Manager.
9. **Дублирование LFS и R2 на переходном этапе.** Нужна дисциплина: LFS хранит источники/архивы, R2 — опубликованные runtime-версии, Git — descriptors/hashes/код.
10. **Стоимость.** По официальной документации R2 free tier даёт 10 GB-month Standard storage, 1 млн Class A и 10 млн Class B операций в месяц, egress не тарифицируется; для прототипа этого достаточно, но production-нагрузку нужно считать по фактическим запросам.

## 11. Решения, которые нужно согласовать перед этапом 2

1. Есть ли уже Cloudflare-аккаунт с R2 и собственный домен в Cloudflare?
2. Подтверждается ли гибридная модель: базовая игра и критичный fallback остаются в APK, облако добавляет/обновляет контент?
3. Первый облачный ресурс — сгенерированный тестовый дуб или сразу копия Mustang?
4. Владелец готов сам создать bucket/domain/CORS по пошаговой инструкции, не передавая секреты в чат?

## 12. Официальные источники Cloudflare

- Public buckets и custom domains: https://developers.cloudflare.com/r2/buckets/public-buckets/
- CORS для R2: https://developers.cloudflare.com/r2/buckets/cors/
- Cache для R2 custom domain: https://developers.cloudflare.com/cache/interaction-cloudflare-products/r2/
- Лимиты R2: https://developers.cloudflare.com/r2/platform/limits/
- Цены и free tier R2: https://developers.cloudflare.com/r2/pricing/
- R2 API tokens и bucket scope: https://developers.cloudflare.com/r2/api/tokens/
- Wrangler `r2 object put`: https://developers.cloudflare.com/r2/reference/wrangler-commands/
