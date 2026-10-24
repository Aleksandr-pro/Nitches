# Облачные 3D-ресурсы Nitches Horizon: запуск Stage 2

Этот документ описывает уже реализованный клиентский путь и ручную настройку
Cloudflare R2 с нуля. Инструкция рассчитана на выполнение с телефона.

## Текущий статус

Реализовано и проверено локально:

- единый `ResourceManager` для всех будущих категорий ресурсов;
- версионированный каталог с указателем `manifests/current.json`;
- проверка размера и SHA-256 каждого файла;
- IndexedDB-кэш с временной staging-записью, последним известным хорошим
  каталогом и LRU-вытеснением;
- загрузчик с ограничением параллельности, повторными попытками, отменой и
  дедупликацией одинаковых SHA-256;
- парсинг только самодостаточных GLB без внешних URI и без Draco/Meshopt/KTX2;
- статический адаптер: тени, pivot, трансформация и круговая проекция
  коллайдера для текущей физики;
- первый облачный объект `tree_oak_001`: детерминированно генерируемый дуб,
  127 292 байта, 1 464 треугольника;
- неблокирующая интеграция в игру: если CDN выключен или недоступен,
  встроенный мир и автомобили из APK продолжают работать.

Не выполнено только то, что невозможно сделать без владельца аккаунта:

- создать Cloudflare-аккаунт и R2 bucket;
- включить публичный URL и CORS;
- загрузить staging-файлы;
- проверить живой R2 URL и Android WebView на реальном устройстве.

## Как устроена публикация

В публичный bucket должны попасть ровно три объекта первого каталога в
следующем порядке:

1. GLB-модель по неизменяемому ключу с полным SHA-256;
2. версионированный `manifest.json`;
3. `manifests/current.json` — последним.

Точные ключи, размеры, SHA-256, Content-Type и Cache-Control находятся в
`.cloud-assets/publishing.json` и в артефакте GitHub Actions
`nitches-cloud-assets-staging`. Этот report является источником истины при
ручной загрузке.

Локально бандл собирается командами:

```bash
npm test
npm run cloud:bundle
```

Результат:

```text
.cloud-assets/
  publishing.json
  staging/
    manifests/current.json
    manifests/versions/<version>-<manifest-sha256>/manifest.json
    trees/tree_oak_001/1.0.0/model-<sha256>.glb
```

Папка `.cloud-assets/` не коммитится: GLB и каталог можно воспроизвести из
скриптов в репозитории.

## Настройка Cloudflare с нуля на телефоне

### 1. Создать аккаунт

1. Откройте Cloudflare и создайте аккаунт.
2. Подтвердите адрес электронной почты.
3. Включите двухфакторную аутентификацию, если Cloudflare её предложит.
4. Откройте раздел **R2 Object Storage**.
5. Если Cloudflare попросит включить R2 или указать платёжные данные,
   следуйте подсказкам интерфейса. Для прототипа достаточно бесплатного
   лимита Standard storage.

Никогда не отправляйте пароль, API Token, Access Key ID или Secret Access Key
в чат, GitHub Issue или коммит. Для ручной загрузки через Dashboard токен не
нужен.

### 2. Создать dev bucket

1. Нажмите **Create bucket**.
2. Имя: `nitches-game-assets-dev`.
3. Location: **Automatic**.
4. Storage class: **Standard**.
5. Создайте bucket.

Production bucket (`nitches-game-assets-prod`) на этапе прототипа создавать
необязательно.

### 3. Включить публичный URL для dev

Для первого теста допустим `r2.dev`:

1. Откройте bucket `nitches-game-assets-dev`.
2. Перейдите в **Settings**.
3. В блоке **Public access / R2.dev subdomain** включите публичный доступ.
4. Подтвердите включение.
5. Сохраните выданный адрес вида
   `https://pub-<случайный-идентификатор>.r2.dev`.

Это dev-адрес с ограничениями Cloudflare. Для production позднее нужен
собственный поддомен на домене в Cloudflare, например
`https://assets.<домен>`, и Cache Rule для игровых расширений.

### 4. Настроить CORS

В настройках bucket добавьте CORS policy только для чтения:

- Allowed methods: `GET`, `HEAD`;
- Allowed headers: `*`;
- Max age: `86400`;
- Allowed origins для начала:
  - `https://localhost`;
  - `http://localhost:5173`;
  - `http://localhost:4173`;
  - `capacitor://localhost`.

Если интерфейс принимает JSON, используйте:

```json
[
  {
    "AllowedOrigins": [
      "https://localhost",
      "http://localhost:5173",
      "http://localhost:4173",
      "capacitor://localhost"
    ],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 86400
  }
]
```

Если проверка идёт из временного веб-превью с динамическим доменом, лучше
добавить его точный Origin. Временный `*` допустим только в dev bucket с
публичным тестовым дубом; в production используйте точный список Origin.

### 5. Получить staging bundle на телефоне

1. Откройте репозиторий на GitHub.
2. Перейдите в **Actions → Cloud asset staging bundle**.
3. Дождитесь успешного запуска и скачайте artifact
   `nitches-cloud-assets-staging`.
4. Распакуйте ZIP.
5. Откройте `publishing.json` и держите его перед глазами при загрузке.

### 6. Загрузить объекты в правильном порядке

Загружайте строго в порядке `uploadOrder` из `publishing.json`:

1. **Модель** (`trees/.../model-<sha256>.glb`).
2. **Версионированный манифест**
   (`manifests/versions/.../manifest.json`).
3. **Указатель** (`manifests/current.json`) — последним.

В R2 «папки» являются частью полного ключа объекта. Если Dashboard при
загрузке предлагает имя, укажите полный ключ из поля `key`, а не только имя
файла. Если интерфейс позволяет задать метаданные, используйте
`contentType` и `cacheControl` из report. Если таких полей на телефоне нет,
прототип всё равно можно проверить: клиент сам сверяет размер и SHA-256, а
тип ответа не использует как доказательство целостности.

### 7. Проверить публичные URL вручную

Откройте в браузере:

```text
<BASE_URL>/manifests/current.json
```

Затем откройте путь из поля `manifestPath`:

```text
<BASE_URL>/<manifestPath>
```

Затем откройте ключ GLB из поля `files.<sha256>.key`: браузер должен скачать
файл, а не показать 404/403.

### 8. Проверить живой каталог из GitHub Actions

1. Откройте **Actions → Cloud asset staging bundle → Run workflow**.
2. В поле **Public asset base URL** вставьте сохранённый `r2.dev` адрес без
   завершающего `/`.
3. Запустите workflow.
4. Шаг **Validate published catalog** должен скачать pointer, манифест и GLB,
   сверить SHA-256 и распарсить модель настоящим Three.js GLTFLoader.

Локальный эквивалент:

```bash
node scripts/validate-cloud-catalog.mjs --base-url "https://pub-<id>.r2.dev"
```

### 9. Подключить публичный URL к сборкам

Публичный base URL не является секретом. Добавьте его как GitHub Actions
**Variable**, а не Secret:

1. **Settings → Secrets and variables → Actions → Variables**.
2. **New repository variable**.
3. Name: `VITE_ASSET_CDN_BASE_URL`.
4. Value: публичный base URL без завершающего `/`.
5. Сохраните.

После этого веб-сборка и будущие APK будут компилироваться с этим адресом.
Для локальной разработки можно создать `.env.local` на основе
`.env.example`; в dev-режиме также поддерживается
`?assetBase=https://...`, но production-сборка query-override игнорирует.

## Проверка игрового сценария

После сборки с заданным `VITE_ASSET_CDN_BASE_URL` проверьте:

1. **Первый запуск онлайн, кэш пуст**: дуб с оранжевым кольцом появляется
   возле фестивальной зоны, игра не ждёт загрузку на стартовом экране.
2. **Повторный запуск**: модель берётся из IndexedDB; по сети максимум
   обновляется маленький `current.json`.
3. **Офлайн после успешного запуска**: каталог и дуб берутся из кэша.
4. **Офлайн с пустым кэшем**: игра работает без облачного дуба.
5. **Неверный URL/CORS**: игра работает без облачного дуба, ошибка видна
   только в консоли/статистике Resource Manager.
6. **Android**: после первого онлайн-запуска полностью закройте приложение,
   включите авиарежим и запустите снова — дуб должен остаться.

В dev-сборке менеджер доступен в консоли как `window.NitchesResources`, а его
`getStatus()` и `getStats()` показывают версию каталога, источник
(`network`/`cache`), cache hit/miss, загрузки и ошибки целостности.

## Обновление и откат

Обновление модели не перезаписывает старый immutable key:

1. собрать новый GLB и новый каталог;
2. загрузить новый GLB;
3. загрузить новый версионированный манифест;
4. проверить объекты по публичному URL;
5. только после этого заменить `manifests/current.json`.

Откат — снова загрузить предыдущий `current.json`, который указывает на
предыдущий проверенный манифест. Старые GLB и манифесты не удаляйте, пока
current и rollback-версии могут на них ссылаться.

## Частые проблемы

### 404 на `current.json`

Проверьте, что ключ именно `manifests/current.json`, а файл не оказался в
корне bucket с именем только `current.json`.

### 404 на манифест или GLB

Сверьте каждый символ ключа с `publishing.json`. SHA-256 в имени должен быть
полным (64 hex-символа).

### В браузере файл открывается, а игра его не грузит

Чаще всего причина — CORS или смешанный контент. Base URL должен быть HTTPS,
а фактический Origin игры должен присутствовать в CORS policy. Для Android
Capacitor основной Origin — `https://localhost`.

### Игра запустилась без дуба

Это ожидаемый fallback. Проверьте:

- задан ли `VITE_ASSET_CDN_BASE_URL` именно в той сборке, которую запустили;
- открывается ли `current.json` извне;
- проходит ли remote validation;
- нет ли ошибки CORS в консоли;
- не очищались ли данные приложения перед офлайн-тестом.

### Старый каталог после обновления

`current.json` должен иметь короткий TTL. Если при ручной загрузке
Cache-Control задать не удалось, подождите истечения CDN TTL или выполните
purge для custom domain. Версионированные объекты при этом менять не нужно.

## Безопасность

- В клиент компилируется только публичный read-only base URL.
- R2 API-ключи в репозиторий, `.env.example`, APK и PWA не попадают.
- Скачанные GLB никогда не исполняются как код; они проходят schema/size/SHA
  проверки и парсятся как данные.
- Публичный bucket означает, что любой человек со ссылкой может скачать
  модель. Исходные ZIP/Blend/FBX и неопубликованные ассеты туда не кладут.
- Автоматическая публикация с bucket-scoped токеном будет отдельным этапом;
  для Stage 2 достаточно ручной загрузки через Dashboard.

## Официальные ссылки

- Public buckets и custom domains: https://developers.cloudflare.com/r2/buckets/public-buckets/
- CORS для R2: https://developers.cloudflare.com/r2/buckets/cors/
- Cache для R2 custom domain: https://developers.cloudflare.com/cache/interaction-cloudflare-products/r2/
- Лимиты R2: https://developers.cloudflare.com/r2/platform/limits/
- Цены и free tier R2: https://developers.cloudflare.com/r2/pricing/
