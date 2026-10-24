# Mustang — исходный пакет модели

Оригинальный файл `Mustang.zip` был загружен владельцем репозитория с телефона в технический draft-релиз **Model Inbox** и затем перенесён в Git LFS в эту папку.

- Release ID: `422728278`
- Asset ID: `672275730`
- Имя файла: `Mustang.zip`
- Размер: `101934251` байт
- SHA-256: `8c70f0255531cd1358397c529ac536deeeab951c8aa30e7947b0092c5ade9db6`

Внутри архива лежит два точных дублирующих комплекта Blender/FBX/OBJ/STL и текстуры. Каноническим исходником считается сам ZIP целиком; отдельная распакованная копия в репозиторий не добавлялась, чтобы не хранить дубли.

Инвентаризация архива: [`asset-inbox/imports/mustang/inventory.md`](../../../asset-inbox/imports/mustang/inventory.md).

Игровой файл `public/assets/models/cars/mustang/mustang.glb` сгенерирован из `Mustang/Mustang.obj` скриптом [`scripts/blender_convert_car.py`](../../../scripts/blender_convert_car.py); цвета материалов при возможности читаются из `Mustang/Mustang.blend`.

- Runtime GLB: `5874616` байт
- SHA-256 runtime GLB: `51226f39c160b184dd74b608e11f0ff93f5902bee3a4a24f4ccc3526c8bfe456`
- Треугольников: `157759`
- Габариты в игре: `4.66 × 1.835 × 1.302` м (длина × ширина × высота)
- Отчёты: [`conversion.json`](../../../asset-inbox/imports/mustang/conversion.json) и [`loader-validation.json`](../../../asset-inbox/imports/mustang/loader-validation.json)
