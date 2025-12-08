#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Импорт полной базы Hockey JSON из ZIP-файла.

Поддерживаются два режима:
1) Локальный путь в файловой системе контейнера:
   python scripts/import_db.py /path/to/hockey-db.zip

2) URL (http/https):
   python scripts/import_db.py https://example.com/hockey-db.zip

Формат ZIP ожидается такой же, как у /api/download-db:
  hockey-json/db_info.json
  hockey-json/<остальная структура>

Скрипт:
  - полностью очищает BASE_DIR,
  - распаковывает содержимое hockey-json/ в BASE_DIR,
  - запускает пересборку индексов (scripts.rebuild_indexes.main()).
"""

import sys
import os
import zipfile
import tempfile
import shutil
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen
import ssl  # для поддержки https с самоподписанным сертификатом

# Импортируем BASE_DIR из app.config
ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.config import BASE_DIR  # noqa: E402
from scripts import rebuild_indexes  # noqa: E402


def is_url(s: str) -> bool:
    try:
        parsed = urlparse(s)
        return parsed.scheme in ("http", "https")
    except Exception:
        return False


def download_to_temp(url: str) -> Path:
    """
    Скачивает файл по URL во временный файл и возвращает путь к нему.

    Для https игнорирует проверку сертификата (актуально для самоподписанных
    сертификатов на тестовых/внутренних серверах). В боевом окружении
    рекомендуется использовать нормальный сертификат.
    """
    print(f"[INFO] Скачиваю ZIP по URL: {url}")
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".zip")
    os.close(tmp_fd)  # Закрываем файловый дескриптор, будем писать сами

    parsed = urlparse(url)
    context = None
    if parsed.scheme == "https":
        # Игнорируем проверку сертификата (self-signed)
        context = ssl._create_unverified_context()

    with urlopen(url, context=context) as resp, open(tmp_path, "wb") as out_f:
        shutil.copyfileobj(resp, out_f)

    print(f"[OK] Скачано во временный файл: {tmp_path}")
    return Path(tmp_path)


def clear_base_dir(base_dir: Path) -> None:
    """
    Полностью очищает содержимое BASE_DIR,
    но не удаляет сам каталог BASE_DIR.
    """
    if not base_dir.exists():
        print(f"[INFO] BASE_DIR не существует, создаю: {base_dir}")
        base_dir.mkdir(parents=True, exist_ok=True)
        return

    print(f"[INFO] Очищаю содержимое BASE_DIR: {base_dir}")
    for entry in base_dir.iterdir():
        try:
            if entry.is_file() or entry.is_symlink():
                entry.unlink()
            elif entry.is_dir():
                shutil.rmtree(entry)
        except Exception as e:
            print(f"[WARN] Не удалось удалить {entry}: {e}")
    print("[OK] BASE_DIR очищен.")


def extract_hockey_json(zip_path: Path, base_dir: Path) -> None:
    """
    Распаковывает содержимое каталога hockey-json/ из ZIP в BASE_DIR.
    """
    print(f"[INFO] Распаковываю ZIP: {zip_path}")
    with zipfile.ZipFile(zip_path, "r") as zf:
        # Проверим наличие префикса hockey-json/
        prefix = "hockey-json/"
        has_prefix = any(
            name.startswith(prefix) for name in zf.namelist()
        )
        if not has_prefix:
            raise RuntimeError(
                "В ZIP не найден каталог 'hockey-json/'. "
                "Формат архива не соответствует ожиданиям /api/download-db."
            )

        for member in zf.infolist():
            name = member.filename

            # Нас интересует только содержимое hockey-json/
            if not name.startswith(prefix):
                continue

            rel_path = name[len(prefix):]  # часть пути после hockey-json/
            if not rel_path:
                # Это корень hockey-json/, пропускаем
                continue

            target_path = base_dir / rel_path

            if member.is_dir():
                target_path.mkdir(parents=True, exist_ok=True)
                continue

            # Убедимся, что директория существует
            target_path.parent.mkdir(parents=True, exist_ok=True)

            with zf.open(member, "r") as src, open(target_path, "wb") as dst:
                shutil.copyfileobj(src, dst)

    print(f"[OK] Распаковано содержимое hockey-json/ в {base_dir}")


def main():
    if len(sys.argv) != 2:
        print(
            "Использование:\n"
            "  python scripts/import_db.py /path/to/hockey-db.zip\n"
            "  python scripts/import_db.py https://example.com/hockey-db.zip"
        )
        sys.exit(1)

    src = sys.argv[1]
    zip_path: Path
    tmp_to_delete: Path | None = None

    print(f"[INFO] BASE_DIR = {BASE_DIR}")

    try:
        if is_url(src):
            # Скачиваем по URL во временный файл
            tmp_to_delete = download_to_temp(src)
            zip_path = tmp_to_delete
        else:
            # Локальный путь
            zip_path = Path(src)
            if not zip_path.is_file():
                raise FileNotFoundError(f"ZIP-файл не найден: {zip_path}")

        # Очищаем текущую базу
        clear_base_dir(BASE_DIR)

        # Распаковываем архив
        extract_hockey_json(zip_path, BASE_DIR)

        # Пересборка индексов
        print("[INFO] Запуск пересборки индексов...")
        rebuild_indexes.main()
        print("[OK] Импорт базы завершён успешно.")

    finally:
        if tmp_to_delete and tmp_to_delete.exists():
            try:
                tmp_to_delete.unlink()
                print(f"[INFO] Удалён временный файл: {tmp_to_delete}")
            except Exception as e:
                print(f"[WARN] Не удалось удалить временный файл {tmp_to_delete}: {e}")


if __name__ == "__main__":
    main()
