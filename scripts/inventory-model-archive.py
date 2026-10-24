#!/usr/bin/env python3
"""Inventory a model ZIP from the GitHub Release Model Inbox.

The script never executes archive contents. It safely extracts a ZIP to a
temporary directory, hashes files, and parses common model/texture headers so
an import decision can be made before anything is copied into Git LFS or the
runtime game directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import posixpath
import shutil
import struct
import sys
import tempfile
import urllib.parse
import zipfile
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath

MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024
MAX_ENTRY_BYTES = 1 * 1024 * 1024 * 1024
MAX_JSON_ENTRIES = 5000
MAX_MD_ENTRIES = 200
MODEL_EXTS = {
    ".glb", ".gltf", ".fbx", ".blend", ".blend1", ".dae", ".3ds", ".max",
    ".ma", ".mb", ".obj", ".mtl", ".stl", ".ply", ".usdz", ".usdc",
}
RUNTIME_EXTS = {".glb", ".gltf"}
SOURCE_EXTS = MODEL_EXTS - RUNTIME_EXTS
TEXTURE_EXTS = {
    ".png", ".jpg", ".jpeg", ".webp", ".ktx2", ".basis", ".tga", ".hdr",
    ".exr", ".dds", ".bmp", ".psd", ".xcf", ".tif", ".tiff",
}
ARCHIVE_EXTS = {".zip", ".7z", ".rar", ".tar", ".tgz"}
TEXT_HINTS = ("license", "licence", "readme", "source", "credit", "info", "author")


def sha256_stream(read_chunk) -> str:
    h = hashlib.sha256()
    while True:
        chunk = read_chunk()
        if not chunk:
            break
        h.update(chunk)
    return h.hexdigest()


def sha256_file(path: Path) -> str:
    with path.open("rb") as f:
        return sha256_stream(lambda: f.read(1024 * 1024))


def extension_of(name: str) -> str:
    lower = name.lower()
    if lower.endswith(".tar.gz"):
        return ".tar.gz"
    suffix = PurePosixPath(lower).suffix
    return suffix or "(none)"


def is_symlink(info: zipfile.ZipInfo) -> bool:
    mode = (info.external_attr >> 16) & 0o170000
    return mode == 0o120000


def normalized_parts(name: str) -> list[str]:
    normalized = name.replace("\\", "/")
    return [part for part in normalized.split("/") if part not in ("", ".")]


def path_is_safe(name: str) -> bool:
    normalized = name.replace("\\", "/")
    if normalized.startswith("/") or normalized.startswith("//"):
        return False
    parts = normalized_parts(normalized)
    if not parts or any(part == ".." for part in parts):
        return False
    # Windows drive or alternate-data-stream style first component.
    if ":" in parts[0]:
        return False
    return True


def human_bytes(size: int) -> str:
    units = ["B", "KiB", "MiB", "GiB"]
    value = float(size)
    unit = units[0]
    for unit in units:
        if value < 1024 or unit == units[-1]:
            break
        value /= 1024
    if unit == "B":
        return f"{size} B"
    return f"{value:.2f} {unit}"


def multiply(a: list[float], b: list[float]) -> list[float]:
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return out


def identity() -> list[float]:
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def node_matrix(node: dict) -> list[float]:
    if isinstance(node.get("matrix"), list) and len(node["matrix"]) == 16:
        values = [float(v) for v in node["matrix"]]
        # glTF matrices are column-major; convert to row-major.
        return [values[c * 4 + r] for r in range(4) for c in range(4)]

    t = node.get("translation") or [0, 0, 0]
    s = node.get("scale") or [1, 1, 1]
    q = node.get("rotation") or [0, 0, 0, 1]
    try:
        tx, ty, tz = [float(v) for v in t[:3]]
        sx, sy, sz = [float(v) for v in s[:3]]
        x, y, z, w = [float(v) for v in q[:4]]
    except Exception:
        return identity()

    norm = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / norm, y / norm, z / norm, w / norm
    r = [
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    ]
    scale = [sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, 0, 0, 0, 1]
    translation = [1, 0, 0, tx, 0, 1, 0, ty, 0, 0, 1, tz, 0, 0, 0, 1]
    return multiply(translation, multiply(r, scale))


def transform_point(m: list[float], p: list[float]) -> list[float]:
    x, y, z = p
    return [
        m[0] * x + m[1] * y + m[2] * z + m[3],
        m[4] * x + m[5] * y + m[6] * z + m[7],
        m[8] * x + m[9] * y + m[10] * z + m[11],
    ]


def estimate_triangles(gltf: dict) -> int:
    accessors = gltf.get("accessors") or []
    total = 0
    for mesh in gltf.get("meshes") or []:
        for primitive in mesh.get("primitives") or []:
            accessor_index = primitive.get("indices")
            if accessor_index is None:
                accessor_index = (primitive.get("attributes") or {}).get("POSITION")
            count = 0
            if isinstance(accessor_index, int) and 0 <= accessor_index < len(accessors):
                count = int(accessors[accessor_index].get("count") or 0)
            mode = int(primitive.get("mode", 4))
            if mode == 4:
                total += count // 3
            elif mode in (5, 6):
                total += max(0, count - 2)
    return total


def estimate_bounds(gltf: dict) -> dict | None:
    nodes = gltf.get("nodes") or []
    meshes = gltf.get("meshes") or []
    accessors = gltf.get("accessors") or []
    scenes = gltf.get("scenes") or []
    if not nodes or not scenes:
        return None

    mins = [math.inf, math.inf, math.inf]
    maxs = [-math.inf, -math.inf, -math.inf]
    found = False

    def visit(node_index: int, parent: list[float], depth: int = 0) -> None:
        nonlocal found
        if depth > 64 or not (0 <= node_index < len(nodes)):
            return
        node = nodes[node_index]
        world = multiply(parent, node_matrix(node))
        mesh_index = node.get("mesh")
        if isinstance(mesh_index, int) and 0 <= mesh_index < len(meshes):
            for primitive in meshes[mesh_index].get("primitives") or []:
                accessor_index = (primitive.get("attributes") or {}).get("POSITION")
                if not isinstance(accessor_index, int) or not (0 <= accessor_index < len(accessors)):
                    continue
                accessor = accessors[accessor_index]
                amin = accessor.get("min")
                amax = accessor.get("max")
                if not (isinstance(amin, list) and isinstance(amax, list) and len(amin) >= 3 and len(amax) >= 3):
                    continue
                for x in (float(amin[0]), float(amax[0])):
                    for y in (float(amin[1]), float(amax[1])):
                        for z in (float(amin[2]), float(amax[2])):
                            p = transform_point(world, [x, y, z])
                            for i in range(3):
                                mins[i] = min(mins[i], p[i])
                                maxs[i] = max(maxs[i], p[i])
                            found = True
        for child in node.get("children") or []:
            if isinstance(child, int):
                visit(child, world, depth + 1)

    scene_index = int(gltf.get("scene", 0) or 0)
    scene = scenes[scene_index] if 0 <= scene_index < len(scenes) else scenes[0]
    for root in scene.get("nodes") or []:
        if isinstance(root, int):
            visit(root, identity())
    if not found:
        return None
    size = [maxs[i] - mins[i] for i in range(3)]
    return {
        "min": [round(v, 6) for v in mins],
        "max": [round(v, 6) for v in maxs],
        "sizeXYZ": [round(v, 6) for v in size],
        "note": "Estimated from POSITION accessor min/max and node transforms; skins/morphs ignored.",
    }


def summarize_gltf(gltf: dict, archive_paths: set[str] | None = None, gltf_archive_path: str | None = None) -> dict:
    result: dict = {
        "asset": gltf.get("asset") or {},
        "extensionsUsed": gltf.get("extensionsUsed") or [],
        "extensionsRequired": gltf.get("extensionsRequired") or [],
        "counts": {
            "scenes": len(gltf.get("scenes") or []),
            "nodes": len(gltf.get("nodes") or []),
            "meshes": len(gltf.get("meshes") or []),
            "materials": len(gltf.get("materials") or []),
            "textures": len(gltf.get("textures") or []),
            "images": len(gltf.get("images") or []),
            "skins": len(gltf.get("skins") or []),
            "animations": len(gltf.get("animations") or []),
            "cameras": len(gltf.get("cameras") or []),
        },
        "estimatedTriangles": estimate_triangles(gltf),
        "bounds": estimate_bounds(gltf),
        "nodeNames": [node.get("name") for node in (gltf.get("nodes") or []) if node.get("name")],
        "meshNames": [mesh.get("name") for mesh in (gltf.get("meshes") or []) if mesh.get("name")],
        "materialNames": [mat.get("name") for mat in (gltf.get("materials") or []) if mat.get("name")],
    }

    buffer_views = gltf.get("bufferViews") or []
    images = []
    for image in gltf.get("images") or []:
        item = {"name": image.get("name"), "mimeType": image.get("mimeType"), "uri": image.get("uri")}
        view_index = image.get("bufferView")
        if isinstance(view_index, int) and 0 <= view_index < len(buffer_views):
            item["byteLength"] = buffer_views[view_index].get("byteLength")
        images.append(item)
    result["images"] = images

    if archive_paths is not None and gltf_archive_path:
        base_dir = posixpath.dirname(gltf_archive_path)
        resources = []
        for kind, items in (("buffer", gltf.get("buffers") or []), ("image", gltf.get("images") or [])):
            for item in items:
                uri = item.get("uri")
                if not uri or uri.startswith("data:"):
                    continue
                if uri.startswith("http://") or uri.startswith("https://"):
                    resources.append({"kind": kind, "uri": uri, "present": False, "externalUrl": True})
                    continue
                decoded = urllib.parse.unquote(uri.split("#", 1)[0].split("?", 1)[0])
                resolved = posixpath.normpath(posixpath.join(base_dir, decoded))
                resources.append({
                    "kind": kind,
                    "uri": uri,
                    "resolvedArchivePath": resolved,
                    "present": resolved in archive_paths,
                })
        result["externalResources"] = resources
    return result


def parse_glb(path: Path) -> dict:
    size = path.stat().st_size
    if size < 20:
        return {"valid": False, "error": "File is too small for a GLB header"}
    with path.open("rb") as f:
        header = f.read(20)
        magic, version, declared_length, json_length, json_type = struct.unpack("<IIIII", header)
        if magic != 0x46546C67:
            return {"valid": False, "error": "Missing glTF magic"}
        if version != 2:
            return {"valid": False, "error": f"Unsupported GLB version {version}"}
        if declared_length != size:
            return {"valid": False, "error": f"Declared length {declared_length} != actual size {size}"}
        if json_type != 0x4E4F534A:
            return {"valid": False, "error": "First chunk is not JSON"}
        if 20 + json_length > size:
            return {"valid": False, "error": "JSON chunk exceeds file size"}
        raw_json = f.read(json_length)
    try:
        gltf = json.loads(raw_json.decode("utf-8").rstrip("\x00 "))
    except Exception as exc:
        return {"valid": False, "error": f"Invalid glTF JSON: {exc}"}
    summary = summarize_gltf(gltf)
    summary.update({"valid": True, "glbVersion": version, "jsonChunkBytes": json_length})
    return summary


def parse_gltf(path: Path, archive_paths: set[str], archive_path: str) -> dict:
    try:
        gltf = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"valid": False, "error": f"Invalid glTF JSON: {exc}"}
    summary = summarize_gltf(gltf, archive_paths, archive_path)
    summary["valid"] = True
    missing = [r for r in summary.get("externalResources", []) if not r.get("present")]
    if missing:
        summary["valid"] = False
        summary["error"] = "One or more external buffer/image resources are missing or external URLs"
    return summary


def parse_blend(path: Path) -> dict:
    with path.open("rb") as f:
        head = f.read(32)
    if not head.startswith(b"BLENDER") or len(head) < 12:
        return {"valid": False, "error": "Missing BLENDER header"}
    pointer = chr(head[7])
    endian = chr(head[8])
    version = head[9:12].decode("ascii", errors="replace")
    return {
        "valid": True,
        "blendVersion": version,
        "pointerSize": "64-bit" if pointer == "-" else "32-bit" if pointer == "_" else pointer,
        "endianness": "little" if endian == "v" else "big" if endian == "V" else endian,
    }


def parse_fbx(path: Path) -> dict:
    with path.open("rb") as f:
        head = f.read(64)
    if head.startswith(b"Kaydara FBX Binary"):
        version = struct.unpack("<I", head[23:27])[0] if len(head) >= 27 else None
        return {"valid": True, "format": "binary", "fbxVersion": version}
    text = head.decode("utf-8", errors="ignore")
    if "FBX" in text or text.lstrip().startswith(";"):
        return {"valid": True, "format": "ascii-or-header-detected"}
    return {"valid": False, "error": "FBX signature was not recognized"}


def parse_obj(path: Path) -> dict:
    counts = Counter()
    material_libraries: list[str] = []
    materials_used: Counter[str] = Counter()
    face_vertex_counts: Counter[int] = Counter()
    objects: list[str] = []
    object_stats: dict[str, Counter[str]] = defaultdict(Counter)
    group_count = 0
    current_object = "(default)"
    current_material = "(none)"
    bounds_min = [math.inf, math.inf, math.inf]
    bounds_max = [-math.inf, -math.inf, -math.inf]
    estimated_triangles = 0
    truncated = False

    try:
        with path.open("r", encoding="utf-8", errors="ignore") as f:
            for index, line in enumerate(f):
                if index > 10_000_000:
                    truncated = True
                    break
                if not line or line[0] == "#":
                    continue
                parts = line.strip().split()
                if not parts:
                    continue
                keyword = parts[0]
                if keyword == "v" and len(parts) >= 4:
                    counts["vertices"] += 1
                    object_stats[current_object]["vertices"] += 1
                    try:
                        vertex = [float(parts[1]), float(parts[2]), float(parts[3])]
                    except ValueError:
                        continue
                    for axis, value in enumerate(vertex):
                        bounds_min[axis] = min(bounds_min[axis], value)
                        bounds_max[axis] = max(bounds_max[axis], value)
                elif keyword == "vt":
                    counts["uvs"] += 1
                    object_stats[current_object]["uvs"] += 1
                elif keyword == "vn":
                    counts["normals"] += 1
                    object_stats[current_object]["normals"] += 1
                elif keyword == "f":
                    face_vertices = max(0, len(parts) - 1)
                    counts["faces"] += 1
                    face_vertex_counts[face_vertices] += 1
                    triangles = max(0, face_vertices - 2)
                    estimated_triangles += triangles
                    object_stats[current_object]["faces"] += 1
                    object_stats[current_object]["estimatedTriangles"] += triangles
                elif keyword == "mtllib" and len(parts) > 1:
                    material_libraries.append(" ".join(parts[1:]))
                elif keyword == "usemtl":
                    current_material = " ".join(parts[1:]) if len(parts) > 1 else "(none)"
                    materials_used[current_material] += 1
                elif keyword == "o":
                    current_object = " ".join(parts[1:]) if len(parts) > 1 else "(unnamed)"
                    objects.append(current_object)
                elif keyword == "g":
                    group_count += 1
                    if current_object == "(default)" and len(parts) > 1:
                        current_object = " ".join(parts[1:])
    except Exception as exc:
        return {"valid": False, "error": str(exc)}

    bounds = None
    if counts["vertices"] and all(math.isfinite(v) for v in bounds_min + bounds_max):
        bounds = {
            "min": [round(v, 6) for v in bounds_min],
            "max": [round(v, 6) for v in bounds_max],
            "sizeXYZ": [round(bounds_max[i] - bounds_min[i], 6) for i in range(3)],
            "note": "Raw OBJ vertex bounds before any axis conversion.",
        }

    object_details = [
        {"name": name, **dict(stats)}
        for name, stats in sorted(object_stats.items(), key=lambda kv: kv[1].get("estimatedTriangles", 0), reverse=True)
    ]
    return {
        "valid": counts["vertices"] > 0 and counts["faces"] > 0,
        "counts": dict(counts),
        "estimatedTriangles": estimated_triangles,
        "faceVertexCounts": {str(k): v for k, v in sorted(face_vertex_counts.items())},
        "bounds": bounds,
        "materialLibraries": material_libraries[:20],
        "materialsUsed": [
            {"name": name, "useCount": count}
            for name, count in materials_used.most_common(100)
        ],
        "objectCount": len(objects),
        "groupCount": group_count,
        "objects": objects[:200],
        "objectsTruncated": len(objects) > 200,
        "largestObjectsByTriangles": object_details[:50],
        "countTruncated": truncated,
        "lastMaterialSeen": current_material,
    }


def parse_mtl(path: Path) -> dict:
    materials: list[dict] = []
    current: dict | None = None
    texture_keys = {
        "map_kd", "map_ka", "map_ks", "map_ns", "map_d", "disp", "decal",
        "bump", "map_bump", "refl", "map_pr", "map_pm", "map_ps", "norm",
    }
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception as exc:
        return {"valid": False, "error": str(exc)}

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        key = parts[0].lower()
        value = " ".join(parts[1:])
        if key == "newmtl":
            current = {"name": value, "properties": {}, "textures": {}}
            materials.append(current)
            continue
        if current is None:
            current = {"name": "(default)", "properties": {}, "textures": {}}
            materials.append(current)
        if key in texture_keys:
            # MTL texture statements may include options before the file name;
            # keep the full statement for later manual/converter inspection.
            current["textures"][parts[0]] = value
        else:
            current["properties"][parts[0]] = value

    return {
        "valid": bool(materials),
        "materialCount": len(materials),
        "materials": materials[:100],
        "materialsTruncated": len(materials) > 100,
    }


def jpeg_dimensions(data: bytes) -> tuple[int, int] | None:
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None
    i = 2
    sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        if marker == 0xDA:
            break
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        if length < 2:
            break
        if marker in sof_markers and i + 9 < len(data):
            height = struct.unpack(">H", data[i + 5:i + 7])[0]
            width = struct.unpack(">H", data[i + 7:i + 9])[0]
            return width, height
        i += 2 + length
    return None


def image_dimensions(path: Path, ext: str) -> dict:
    try:
        with path.open("rb") as f:
            head = f.read(65536)
    except Exception as exc:
        return {"error": str(exc)}
    dims = None
    signature_ok = None
    if ext == ".png":
        signature_ok = head.startswith(b"\x89PNG\r\n\x1a\n")
        if signature_ok and len(head) >= 24:
            dims = struct.unpack(">II", head[16:24])
    elif ext in (".jpg", ".jpeg"):
        signature_ok = head.startswith(b"\xff\xd8")
        dims = jpeg_dimensions(head)
    elif ext == ".webp":
        signature_ok = head[:4] == b"RIFF" and head[8:12] == b"WEBP"
        if signature_ok and len(head) >= 30:
            kind = head[12:16]
            if kind == b"VP8X":
                width = 1 + int.from_bytes(head[24:27], "little")
                height = 1 + int.from_bytes(head[27:30], "little")
                dims = (width, height)
            elif kind == b"VP8 " and len(head) >= 30:
                width = struct.unpack("<H", head[26:28])[0] & 0x3FFF
                height = struct.unpack("<H", head[28:30])[0] & 0x3FFF
                dims = (width, height)
    elif ext == ".dds":
        signature_ok = head.startswith(b"DDS ")
        if signature_ok and len(head) >= 20:
            height, width = struct.unpack("<II", head[12:20])
            dims = (width, height)
    elif ext == ".tga" and len(head) >= 18:
        width, height = struct.unpack("<HH", head[12:16])
        dims = (width, height)
    elif ext == ".bmp":
        signature_ok = head.startswith(b"BM")
        if signature_ok and len(head) >= 26:
            width, height = struct.unpack("<ii", head[18:26])
            dims = (width, abs(height))
    result: dict = {}
    if signature_ok is not None:
        result["signatureOk"] = bool(signature_ok)
    if dims and dims[0] > 0 and dims[1] > 0:
        result["width"] = int(dims[0])
        result["height"] = int(dims[1])
    return result


def extract_safely(zf: zipfile.ZipFile, info: zipfile.ZipInfo, dest_root: Path) -> tuple[Path | None, str | None, str | None]:
    parts = normalized_parts(info.filename)
    dest = dest_root.joinpath(*parts)
    if info.is_dir():
        dest.mkdir(parents=True, exist_ok=True)
        return dest, None, None
    dest.parent.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256()
    try:
        with zf.open(info, "r") as src, dest.open("wb") as dst:
            while True:
                chunk = src.read(1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
                dst.write(chunk)
    except Exception as exc:
        return None, None, str(exc)
    return dest, h.hexdigest(), None


def build_markdown(data: dict) -> str:
    archive = data["archive"]
    lines: list[str] = []
    lines.append(f"# Инвентаризация Model Inbox: {data.get('carId') or archive['name']}")
    lines.append("")
    lines.append("Этот отчёт создан автоматически по архиву из GitHub Release Model Inbox. Содержимое не запускалось; модели ещё не скопированы в игру.")
    lines.append("")
    lines.append("## Исходный архив")
    lines.append("")
    lines.append(f"- Файл: `{archive['name']}`")
    lines.append(f"- Размер: {archive['size']} байт ({human_bytes(archive['size'])})")
    lines.append(f"- SHA-256: `{archive['sha256']}`")
    if data.get("releaseId"):
        lines.append(f"- Release ID: `{data['releaseId']}`")
    if data.get("assetId"):
        lines.append(f"- Asset ID: `{data['assetId']}`")
    lines.append(f"- Записей в ZIP: {data['summary']['entryCount']}; файлов: {data['summary']['fileCount']}; распаковано логически: {human_bytes(data['summary']['totalUncompressedBytes'])}")
    lines.append("")

    if data.get("warnings"):
        lines.append("## Предупреждения")
        lines.append("")
        for warning in data["warnings"]:
            lines.append(f"- ⚠️ {warning}")
        lines.append("")

    if data.get("duplicateGroups"):
        lines.append("## Точные дубликаты")
        lines.append("")
        lines.append("Одинаковые файлы в LFS физически хранятся по SHA-256 один раз, но для конвертации достаточно одной копии.")
        lines.append("")
        for group in data["duplicateGroups"]:
            paths = ", ".join(f"`{path}`" for path in group["paths"])
            lines.append(f"- {human_bytes(group['size'])} × {group['count']}: {paths}")
        lines.append("")

    lines.append("## Кандидаты")
    lines.append("")
    lines.append(f"- Runtime `.glb/.gltf`: {len(data['candidates']['runtime'])}")
    lines.append(f"- Исходные 3D-форматы: {len(data['candidates']['source'])}")
    lines.append(f"- Текстуры: {len(data['candidates']['textures'])}")
    lines.append(f"- Вложенные архивы: {len(data['candidates']['nestedArchives'])}")
    lines.append("")

    if data["candidates"]["runtime"]:
        lines.append("### Runtime-модели")
        lines.append("")
        for item in data["candidates"]["runtime"]:
            parsed = item.get("parsed") or {}
            lines.append(f"#### `{item['path']}`")
            lines.append("")
            lines.append(f"- Размер: {item['size']} байт ({human_bytes(item['size'])})")
            lines.append(f"- Валидация: {'✅' if parsed.get('valid') else '❌'} {parsed.get('error', '')}".rstrip())
            if parsed.get("counts"):
                c = parsed["counts"]
                lines.append(
                    f"- Мешей: {c['meshes']}; узлов: {c['nodes']}; материалов: {c['materials']}; "
                    f"изображений: {c['images']}; анимаций: {c['animations']}; треугольников ≈ {parsed.get('estimatedTriangles', 0)}"
                )
            bounds = parsed.get("bounds")
            if bounds:
                lines.append(f"- Габариты XYZ по accessor bounds: `{bounds['sizeXYZ']}`")
            names = parsed.get("nodeNames") or []
            if names:
                lines.append("- Узлы: " + ", ".join(f"`{name}`" for name in names[:40]))
            extensions = parsed.get("extensionsUsed") or []
            if extensions:
                lines.append("- Расширения glTF: " + ", ".join(f"`{ext}`" for ext in extensions))
            lines.append("")

    if data["candidates"]["source"]:
        lines.append("### Исходные модели")
        lines.append("")
        for item in data["candidates"]["source"][:50]:
            parsed = item.get("parsed") or {}
            details: list[str] = []
            if parsed.get("counts"):
                details.extend(f"{k}={v}" for k, v in parsed["counts"].items())
            if parsed.get("estimatedTriangles") is not None:
                details.append(f"triangles≈{parsed['estimatedTriangles']}")
            if parsed.get("objectCount") is not None:
                details.append(f"objects={parsed['objectCount']}")
            if parsed.get("bounds"):
                details.append(f"rawSizeXYZ={parsed['bounds']['sizeXYZ']}")
            if parsed.get("materialCount") is not None:
                details.append(f"materials={parsed['materialCount']}")
            if parsed.get("blendVersion"):
                details.append(f"Blender {parsed['blendVersion']}")
            if parsed.get("fbxVersion"):
                details.append(f"FBX {parsed['fbxVersion']}")
            extra = ("; " + ", ".join(details)) if details else ""
            lines.append(f"- `{item['path']}` — {human_bytes(item['size'])}{extra}")
        lines.append("")

    if data["candidates"]["textures"]:
        lines.append("### Крупнейшие текстуры")
        lines.append("")
        for item in sorted(data["candidates"]["textures"], key=lambda x: x["size"], reverse=True)[:30]:
            dims = item.get("image") or {}
            dim_text = f", {dims['width']}×{dims['height']}" if "width" in dims and "height" in dims else ""
            lines.append(f"- `{item['path']}` — {human_bytes(item['size'])}{dim_text}")
        lines.append("")

    lines.append("## Крупнейшие файлы")
    lines.append("")
    for item in data["largestFiles"][:30]:
        lines.append(f"- `{item['path']}` — {item['size']} байт ({human_bytes(item['size'])})")
    lines.append("")

    lines.append("## Состав архива")
    lines.append("")
    shown = data["entries"][:MAX_MD_ENTRIES]
    for entry in shown:
        if entry.get("isDirectory"):
            lines.append(f"- 📁 `{entry['path']}`")
        else:
            lines.append(f"- `{entry['path']}` — {human_bytes(entry['size'])}")
    if len(data["entries"]) > len(shown):
        lines.append(f"- … и ещё {len(data['entries']) - len(shown)} записей; полный список смотрите в `inventory.json`.")
    lines.append("")
    lines.append("## Следующий шаг")
    lines.append("")
    lines.append("По этому отчёту нужно выбрать runtime-файл или сконвертировать исходник в оптимизированный `.glb`, затем отдельно зарегистрировать автомобиль в игровом коде и проверить чистую LFS-сборку.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Inventory a model ZIP archive")
    parser.add_argument("archive", type=Path)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--car-id", default="")
    parser.add_argument("--release-id", default="")
    parser.add_argument("--asset-id", default="")
    parser.add_argument("--expected-size", type=int, default=0)
    args = parser.parse_args()

    archive_path: Path = args.archive
    if not archive_path.is_file():
        print(f"Archive not found: {archive_path}", file=sys.stderr)
        return 2
    archive_size = archive_path.stat().st_size
    if args.expected_size and archive_size != args.expected_size:
        print(f"Expected size {args.expected_size}, got {archive_size}", file=sys.stderr)
        return 2

    warnings: list[str] = []
    archive_sha = sha256_file(archive_path)

    try:
        zf = zipfile.ZipFile(archive_path)
    except Exception as exc:
        print(f"Cannot open ZIP: {exc}", file=sys.stderr)
        return 2

    infos = zf.infolist()
    entries: list[dict] = []
    archive_paths: set[str] = set()
    unsafe: list[str] = []
    total_uncompressed = 0
    file_count = 0
    by_extension: dict[str, dict[str, int]] = defaultdict(lambda: {"count": 0, "uncompressedBytes": 0, "compressedBytes": 0})

    for info in infos:
        safe = path_is_safe(info.filename) and not is_symlink(info)
        if not safe:
            unsafe.append(info.filename)
        normalized = posixpath.normpath("/".join(normalized_parts(info.filename))) if normalized_parts(info.filename) else info.filename
        is_dir = info.is_dir()
        if not is_dir:
            file_count += 1
            total_uncompressed += info.file_size
            archive_paths.add(normalized)
            ext = extension_of(info.filename)
            by_extension[ext]["count"] += 1
            by_extension[ext]["uncompressedBytes"] += info.file_size
            by_extension[ext]["compressedBytes"] += info.compress_size
        entries.append({
            "path": info.filename,
            "normalizedPath": normalized,
            "isDirectory": is_dir,
            "size": info.file_size,
            "compressedSize": info.compress_size,
            "crc32": f"{info.CRC:08x}",
            "extension": extension_of(info.filename) if not is_dir else "(directory)",
            "safePath": safe,
            "isSymlink": is_symlink(info),
        })

    extraction_enabled = True
    if unsafe:
        warnings.append(f"В ZIP есть небезопасные пути или симлинки ({len(unsafe)}); они не распаковывались.")
    if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
        warnings.append(f"Общий распакованный размер {human_bytes(total_uncompressed)} превышает лимит инвентаризации {human_bytes(MAX_UNCOMPRESSED_BYTES)}; глубокий разбор пропущен.")
        extraction_enabled = False

    extracted: dict[str, Path] = {}
    hashes: dict[str, str] = {}
    extraction_errors: list[dict] = []

    with tempfile.TemporaryDirectory(prefix="nitches-model-inventory-") as tmp:
        tmp_root = Path(tmp)
        if extraction_enabled:
            for info in infos:
                if info.is_dir():
                    continue
                normalized = posixpath.normpath("/".join(normalized_parts(info.filename)))
                entry = next((e for e in entries if e["path"] == info.filename and e["normalizedPath"] == normalized), None)
                if not entry or not entry["safePath"]:
                    continue
                if info.file_size > MAX_ENTRY_BYTES:
                    extraction_errors.append({"path": info.filename, "error": f"Entry exceeds {MAX_ENTRY_BYTES} bytes"})
                    continue
                dest, digest, error = extract_safely(zf, info, tmp_root)
                if error:
                    extraction_errors.append({"path": info.filename, "error": error})
                    continue
                if dest:
                    extracted[normalized] = dest
                if digest:
                    hashes[normalized] = digest
                    entry["sha256"] = digest

        # Attach extracted hashes (also covers entries if extraction list was capped elsewhere).
        for entry in entries:
            if entry["normalizedPath"] in hashes:
                entry["sha256"] = hashes[entry["normalizedPath"]]

        def candidate(item_path: str) -> dict:
            entry = next(e for e in entries if e["normalizedPath"] == item_path)
            out = {
                "path": entry["path"],
                "normalizedPath": item_path,
                "size": entry["size"],
                "compressedSize": entry["compressedSize"],
                "extension": entry["extension"],
                "sha256": entry.get("sha256"),
            }
            local = extracted.get(item_path)
            ext = entry["extension"]
            if local:
                if ext == ".glb":
                    out["parsed"] = parse_glb(local)
                elif ext == ".gltf":
                    out["parsed"] = parse_gltf(local, archive_paths, item_path)
                elif ext in (".blend", ".blend1"):
                    out["parsed"] = parse_blend(local)
                elif ext == ".fbx":
                    out["parsed"] = parse_fbx(local)
                elif ext == ".obj":
                    out["parsed"] = parse_obj(local)
                elif ext == ".mtl":
                    out["parsed"] = parse_mtl(local)
                if ext in TEXTURE_EXTS:
                    out["image"] = image_dimensions(local, ext)
            return out

        files = [e for e in entries if not e["isDirectory"]]
        runtime = [candidate(e["normalizedPath"]) for e in files if e["extension"] in RUNTIME_EXTS]
        source = [candidate(e["normalizedPath"]) for e in files if e["extension"] in SOURCE_EXTS]
        textures = [candidate(e["normalizedPath"]) for e in files if e["extension"] in TEXTURE_EXTS]
        nested = [candidate(e["normalizedPath"]) for e in files if e["extension"] in ARCHIVE_EXTS or e["extension"] == ".tar.gz"]

        text_candidates = []
        for entry in files:
            lower = entry["path"].lower()
            if entry["size"] > 65536:
                continue
            if any(hint in lower for hint in TEXT_HINTS) or entry["extension"] in (".txt", ".md", ".mtl"):
                text_candidates.append(entry)
        text_candidates.sort(key=lambda e: (0 if any(h in e["path"].lower() for h in ("license", "licence", "readme", "source", "credit")) else 1, e["path"].lower()))
        text_previews = []
        for entry in text_candidates[:8]:
            local = extracted.get(entry["normalizedPath"])
            if not local:
                continue
            try:
                text = local.read_bytes()[:12000].decode("utf-8", errors="replace")
            except Exception as exc:
                text = f"<cannot read: {exc}>"
            text_previews.append({"path": entry["path"], "size": entry["size"], "preview": text})

    if extraction_errors:
        warnings.append(f"При распаковке возникло ошибок: {len(extraction_errors)}; подробности в JSON.")
    if not runtime and not source:
        warnings.append("В архиве не найдены распознанные 3D-модели (.glb/.gltf/.fbx/.blend/.obj и др.).")
    for item in runtime:
        if item["size"] > 50 * 1024 * 1024:
            warnings.append(f"Runtime-кандидат `{item['path']}` весит {human_bytes(item['size'])}; перед включением в мобильную игру нужна оптимизация.")
        parsed = item.get("parsed") or {}
        extensions = set((parsed.get("extensionsUsed") or []) + (parsed.get("extensionsRequired") or []))
        risky = sorted(extensions & {"KHR_draco_mesh_compression", "KHR_texture_basisu", "EXT_meshopt_compression"})
        if risky:
            warnings.append(f"`{item['path']}` использует расширения {', '.join(risky)}; соответствующие декодеры ещё нужно подключить или переэкспортировать модель.")
        if parsed and not parsed.get("valid"):
            warnings.append(f"Runtime-кандидат `{item['path']}` не прошёл базовую проверку: {parsed.get('error', 'unknown error')}")
    large_textures = []
    for item in textures:
        dims = item.get("image") or {}
        if dims.get("width", 0) > 2048 or dims.get("height", 0) > 2048:
            large_textures.append(item["path"])
    if large_textures:
        warnings.append(f"Найдено текстур крупнее 2048 px: {len(large_textures)}; для мобильной runtime-версии их обычно нужно уменьшать/сжимать.")
    if nested:
        warnings.append("В архиве есть вложенные архивы; инвентаризатор не распаковывает их рекурсивно.")

    duplicate_map: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        digest = entry.get("sha256")
        if digest and not entry["isDirectory"]:
            duplicate_map[digest].append(entry)
    duplicate_groups = []
    duplicate_wasted_bytes = 0
    for digest, group in duplicate_map.items():
        if len(group) < 2:
            continue
        duplicate_wasted_bytes += sum(item["size"] for item in group[1:])
        duplicate_groups.append({
            "sha256": digest,
            "size": group[0]["size"],
            "count": len(group),
            "paths": [item["path"] for item in group],
        })
    duplicate_groups.sort(key=lambda group: group["size"], reverse=True)
    if duplicate_groups:
        warnings.append(
            f"Найдено точных дубликатов: {len(duplicate_groups)} групп; повторные копии занимают около {human_bytes(duplicate_wasted_bytes)}. "
            "В LFS одинаковые объекты хранятся по хешу один раз, но распакованный набор лучше не дублировать."
        )

    sorted_extensions = [
        {"extension": ext, **values}
        for ext, values in sorted(by_extension.items(), key=lambda kv: kv[1]["uncompressedBytes"], reverse=True)
    ]
    largest = sorted(
        [{"path": e["path"], "size": e["size"], "extension": e["extension"]} for e in entries if not e["isDirectory"]],
        key=lambda x: x["size"],
        reverse=True,
    )[:50]

    data = {
        "carId": args.car_id,
        "releaseId": int(args.release_id) if str(args.release_id).isdigit() else args.release_id,
        "assetId": int(args.asset_id) if str(args.asset_id).isdigit() else args.asset_id,
        "archive": {
            "name": archive_path.name,
            "size": archive_size,
            "sha256": archive_sha,
        },
        "summary": {
            "entryCount": len(infos),
            "fileCount": file_count,
            "totalUncompressedBytes": total_uncompressed,
            "extractionEnabled": extraction_enabled,
            "unsafeEntryCount": len(unsafe),
            "extractionErrorCount": len(extraction_errors),
        },
        "byExtension": sorted_extensions,
        "candidates": {
            "runtime": runtime,
            "source": source,
            "textures": textures,
            "nestedArchives": nested,
        },
        "duplicateGroups": duplicate_groups,
        "textPreviews": text_previews,
        "extractionErrors": extraction_errors,
        "warnings": warnings,
        "largestFiles": largest,
        "entries": entries[:MAX_JSON_ENTRIES],
        "entriesTruncated": len(entries) > MAX_JSON_ENTRIES,
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "inventory.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.out_dir / "inventory.md").write_text(build_markdown(data), encoding="utf-8")
    print(json.dumps({
        "archive": data["archive"],
        "summary": data["summary"],
        "runtimeCandidates": [x["path"] for x in runtime],
        "sourceCandidates": [x["path"] for x in source],
        "warnings": warnings,
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
