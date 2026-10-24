# 3D-модели и большие ассеты: Git LFS

В проекте настроено хранение больших бинарных ресурсов через **Git Large File Storage (Git LFS)**. В обычном Git остаются исходный код, конфигурация, документация и маленькие текстовые pointer-файлы LFS; сами модели и текстуры хранятся в LFS-хранилище GitHub и скачиваются при checkout/pull.

> Важно: файл, который начинается со строки `version https://git-lfs.github.com/spec/v1`, — это не модель, а pointer. Сборка специально падает, если такой файл остался вместо реальных байтов.

## Что уже есть в репозитории

Первая внешняя машина уже подключена: **Mustang Fastback** загружается из `public/assets/models/cars/mustang/mustang.glb` через `src/mustang.js`, а её исходный пакет хранится в `asset-source/cars/mustang/Mustang.zip`. Остальные машины пока строятся процедурно в `src/gtr.js` и `src/main.js`. Для сквозной проверки LFS также добавлен маленький детерминированный фикстурный файл:

```text
public/assets/models/_pipeline/pipeline-smoke.glb
```

Это не игровая машина, а тестовая «коробочная» модель автомобиля на 36 треугольников. Её генератор лежит в `scripts/generate-pipeline-smoke-glb.mjs`, поэтому CI может пересоздать ожидаемые байты и сравнить SHA-256 с тем, что реально скачалось из LFS.

## Куда класть файлы

| Что | Куда | Попадает в игру/APK? |
|---|---|---|
| Оптимизированная runtime-модель машины `.glb` | `public/assets/models/cars/<car-id>/<car-id>.glb` | Да |
| Runtime-текстуры и sidecar-файлы `.bin` для `.gltf` | рядом с моделью в `public/assets/models/cars/<car-id>/` | Да |
| Исходник Blender/Maya/Max | `asset-source/cars/<car-id>/` | Нет |
| Несжатые исходные текстуры `.psd`, `.xcf`, 4K/8K PNG | `asset-source/cars/<car-id>/textures/` | Нет |
| Архив исходной поставки модели | `asset-source/cars/<car-id>/` | Нет |
| Лицензия/источник модели | `asset-source/cars/<car-id>/LICENSE.txt` или `SOURCE.md` | Нет |

Рекомендуемая структура для новой машины:

```text
asset-source/cars/my-car/
  my-car.blend
  textures/
  SOURCE.md
public/assets/models/cars/my-car/
  my-car.glb
```

Файлы из `public/` Vite копирует в `dist/` без переименования, а Capacitor затем копирует `dist/` в Android-приложение. Поэтому размер каждого runtime-GLB почти один в один увеличивает APK и офлайн-пакет PWA.

> Добавление файла в `public/assets/models/cars/` гарантирует его хранение, скачивание и попадание в сборку. Чтобы машина появилась в гараже/игре, её ещё нужно зарегистрировать в коде и подключить через `GLTFLoader` с настройкой колёс, материалов, масштаба и коллизий. Это отдельный шаг интеграции конкретной модели.

## Какие типы отслеживает LFS

Правила находятся в [`.gitattributes`](../.gitattributes):

- модели: `.glb`, `.fbx`, `.blend`, `.blend1`, `.dae`, `.3ds`, `.max`, `.ma`, `.mb`, `.obj`, `.mtl`, `.stl`, `.ply`, `.usdz`, `.usdc` — где бы они ни лежали;
- `.bin` внутри `public/assets/models/` и `asset-source/` — sidecar-данные для текстовых `.gltf`;
- текстуры `.png`, `.jpg`, `.jpeg`, `.webp`, `.ktx2`, `.basis`, `.tga`, `.tif`, `.tiff`, `.hdr`, `.exr`, `.dds` — только внутри `public/assets/` и `asset-source/`;
- исходники текстур `.psd`, `.xcf` и архивы поставки — только в `asset-source/`.

Текстовый `.gltf` намеренно остаётся обычным Git-файлом: его удобно читать и сравнивать, а тяжёлые `.bin`/текстуры рядом с ним уходят в LFS. Для автомобилей всё равно предпочтителен один самодостаточный `.glb`.

Существующие Android/PWA-иконки вне asset-каталогов в LFS не переводятся. История Git не переписывалась; правила действуют на вновь добавляемые файлы. Не запускайте `git lfs migrate import` без отдельного согласования: эта команда переписывает историю.

## Требования к runtime-модели автомобиля

- Формат: **binary glTF 2.0 (`.glb`)**, один файл, текстуры встроены.
- Масштаб: **1 единица = 1 метр**. Реальная длина и колёсная база автомобиля обязательны — физика проекта метрическая.
- Ориентация: нос автомобиля смотрит в **+Z**, верх — **+Y**, центр между осями находится в начале координат, нижняя точка шин касается `Y=0`.
- Отдельные узлы колёс с именами ровно `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`; pivot каждого колеса — в центре его ступицы. Внутри каждого pivot должен быть дочерний узел `Wheel_*_Spin`, в который игра записывает вращение по X, а рулевое вращение по Y применяется к самому pivot.
- Желательные отдельные узлы/материалы: кузов (`Paint`), стекло, шины, диски, фары, салон. Материал краски не должен «запекать» один-единственный цвет в текстуру, если машине нужна перекраска из гаража.
- Бюджет мобильной WebGL-модели: ориентируйтесь на 50–150 тыс. треугольников и разумный размер файла (лучше до 15–30 МБ на машину), текстуры обычно не крупнее 2048×2048. Это рекомендации, а не жёсткий лимит валидатора.
- Не используйте Draco/Meshopt-сжатие и KTX2, пока соответствующие декодеры не подключены к загрузчику игры: файл сохранится и соберётся, но runtime может его не открыть.
- Загружайте только модели и текстуры, на которые у вас есть права. Источник и лицензию сохраняйте рядом с исходником.

## Один раз на компьютере разработчика

Установите Git LFS с [git-lfs.com](https://git-lfs.com/), затем в клоне репозитория:

```bash
git lfs install --local
git lfs version
```

Проверка, что конкретный файл действительно попадёт в LFS:

```bash
git check-attr filter -- public/assets/models/cars/my-car/my-car.glb
# Ожидается: filter: lfs
```

## Добавить новую модель

```bash
mkdir -p public/assets/models/cars/my-car asset-source/cars/my-car
cp /path/to/my-car.glb public/assets/models/cars/my-car/
cp /path/to/my-car.blend asset-source/cars/my-car/

git lfs status
git lfs ls-files
npm run assets:check
npm run build

git add .gitattributes public/assets/models/cars/my-car asset-source/cars/my-car
git commit -m "feat(cars): add my-car model"
git push
```

Перед коммитом откройте staged-версию GLB: в индексе Git должен лежать маленький pointer, а в рабочем каталоге — настоящая модель. Это нормальная работа LFS.

## С телефона: большие файлы 100–200 МБ через Model Inbox

Вложения чата Arena не принимают ZIP/GLB, а обычная кнопка GitHub **Upload files** не подходит для LFS-моделей. Для загрузки с телефона используйте технический черновик релиза **«📥 Model Inbox — загрузка 3D-моделей с телефона (не релиз игры)»** на странице GitHub Releases:

1. Откройте черновик **Model Inbox** в мобильном Chrome. Если кнопок редактирования не видно, включите «Версия для ПК».
2. Нажмите карандаш / **Edit release**.
3. В блоке **Attach binaries…** выберите один архив одной машины (`.zip`, `.7z`, `.rar`) или одиночный `.glb`. Для 100–200 МБ используйте Wi‑Fi и не закрывайте вкладку до конца загрузки.
4. Сохраните черновик кнопкой **Update release**. Не публикуйте его и не загружайте модели в игровые релизы `v0.4.0`, `v0.3.1` и т.п.
5. Напишите в чат: `Загрузил <имя-файла> в Model Inbox`. После этого файл заберут из inbox и сначала инвентаризируют, а уже затем — после подтверждения прав/лицензии и выбора runtime-файла — перенесут в Git LFS и подготовят PR. Не удаляйте файл из inbox до подтверждения импорта.

Имя архива давайте латиницей без пробелов, например `mustang-gt.zip`. Если внутри лежит `.gltf`, архивируйте всю папку целиком вместе с `.bin` и текстурами.

Размер 100–200 МБ допустим для загрузки и хранения исходника, но не как финальный размер каждой runtime-машины: файл из `public/` почти один в один увеличит APK и будет тяжело загружаться на телефоне. Такие пакеты сначала рассматриваются как исходники в `asset-source/`; для игры из них делается оптимизированный `.glb` разумного размера, после чего модель отдельно регистрируется в коде.

### Как maintainer забирает файл из Model Inbox

Для каждого загруженного архива создаётся маленький манифест `asset-inbox/imports/<car-id>.json` с `releaseId`, `assetId`, именем файла и ожидаемым размером. Push такого манифеста в ветку `arena/**` запускает workflow **Model Inbox inventory**: GitHub runner скачивает asset из draft-релиза по API, проверяет размер и SHA-256, безопасно распаковывает ZIP во временный каталог, не запуская содержимое, и коммитит обратно только отчёты `asset-inbox/imports/<car-id>/inventory.md` и `inventory.json`.

Отчёт показывает состав архива, точные дубликаты, runtime-кандидаты `.glb/.gltf`, исходники, текстуры, а для OBJ/MTL — объекты, материалы, оценку треугольников после триангуляции и сырые габариты. Сама модель на этом шаге ещё не копируется ни в `public/`, ни в `asset-source/`: сначала нужно подтвердить источник/лицензию и решить, какой файл конвертировать и насколько сильно оптимизировать.

Когда решение принято, создаётся манифест `asset-inbox/conversions/<car-id>.json`. Push в не-`main` ветку запускает workflow **Model Inbox convert**: runner устанавливает Blender, снова скачивает и проверяет архив из inbox, безопасно распаковывает его, читает цвета из `.blend` (best effort), запускает `scripts/blender_convert_car.py` для декимации, нормализации масштаба/осей и сборки узлов `Wheel_*`/`Wheel_*_Spin`, затем проверяет результат настоящим Three.js `GLTFLoader`. Исходный ZIP коммитится в `asset-source/cars/<car-id>/`, оптимизированный GLB — в `public/assets/models/cars/<car-id>/`, а отчёты `conversion.json` и `loader-validation.json` — рядом с инвентаризацией. Перед push runner загружает объекты в LFS, удаляет локальные копии и кэш, скачивает их заново и сверяет SHA-256.

Для Mustang исходные ~717 тыс. треугольников и 232 МиБ распакованных дублирующих комплектов превратились в runtime-GLB на **157 759 треугольников** и **5 874 616 байт**; исходный ZIP целиком сохранён только как архивный источник и в APK не попадает.

## Клонировать и собрать в чистом окружении

```bash
git clone https://github.com/Aleksandr-pro/Nitches.git
cd Nitches
git lfs install --local
git lfs pull --include="public/assets/models/**" --exclude=""
npm ci
npm run build
npx cap sync android
```

Для обычной сборки нужны только runtime-модели из `public/assets/models/**`. Архивные исходники в `asset-source/**` могут оставаться LFS-pointer'ами: `npm run assets:check` предупредит о них, но не упадёт, чтобы каждый web/APK-билд не скачивал, например, 102-МБ ZIP Mustang. Если нужно материализовать и строго проверить **все** исходники, выполните:

```bash
git lfs pull --include="public/assets/models/**,asset-source/**" --exclude=""
npm run assets:check-all
```

`npm run build` автоматически выполняет:

1. `prebuild` → `scripts/check-lfs-assets.mjs`: ищет pointer-файлы, проверяет GLB-заголовок/чанки/JSON, sidecar-ссылки `.gltf`, подписи текстур и SHA-256;
2. Vite build;
3. `postbuild` → повторную проверку и сравнение каждого runtime-ассета из `public/` с его копией в `dist/` по SHA-256.

Если модель не скачалась из LFS, сборка остановится до Vite с сообщением вида:

```text
✗ public/assets/models/cars/my-car/my-car.glb: still a Git LFS pointer ...
Run: git lfs pull --include="public/assets/models/**" --exclude=""
```

## Что настроено в CI

- `.github/workflows/validate-assets.yml` — чистая проверка на GitHub-hosted runner: checkout с `lfs: false`, явный `git lfs pull` только runtime-моделей `public/assets/models/**`, сверка фикстурного GLB с генератором, `npm ci`, `npm run build`, `npx cap sync android` и сравнение SHA-256 в `public/`, `dist/` и Android assets.
- `.github/workflows/build-apk.yml` — релизная сборка APK делает такой же runtime-only LFS pull и валидацию до установки зависимостей. APK не соберётся из pointer-файлов, а большие архивные исходники из `asset-source/` при этом не скачиваются.
- `.github/workflows/model-inbox-convert.yml` — импорт выбранной модели из Model Inbox: скачивание архива, Blender-конвертация, GLTFLoader-валидация, загрузка GLB и исходного ZIP в LFS и проверка повторным скачиванием по SHA-256.

## Квоты GitHub LFS и запасной план

Лимиты зависят от тарифного плана владельца репозитория: GitHub документирует максимальный размер одного LFS-файла и включённые квоты хранилища/трафика в официальной документации [About Git Large File Storage](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage) и [Git Large File Storage billing](https://docs.github.com/en/billing/concepts/product-billing/git-lfs). Текущий расход смотрите в настройках биллинга GitHub; каждая новая версия бинарного файла занимает хранилище целиком, а каждое скачивание в CI расходует bandwidth.

Если парк моделей перерастёт квоту LFS, не храните GLB в обычном Git. Запасной вариант:

1. Версионированные пакеты моделей в отдельном GitHub Release, например `assets-v1`, без перезаписи уже опубликованных файлов; в Git хранить только манифест `{ carId, url, sha256, size }` и скрипт скачивания на этапе сборки. Официальные ограничения релизных ассетов описаны в [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).
2. Либо объектное хранилище/CDN (S3, Cloudflare R2 и т.п.) с неизменяемыми путями вида `models/<car-id>/<sha256>.glb`; в Git — тот же манифест с хешами.
3. Для офлайн-APK такие файлы нужно скачивать именно при сборке и включать в пакет, либо отдельно проектировать внутриигровую загрузку с кэшем. Просто заменить LFS внешней ссылкой времени выполнения нельзя: игра рассчитана на офлайн после установки.

Пока объёмы укладываются в LFS, отдельный манифест и внешнее хранилище проекту не нужны.
