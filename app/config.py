from pathlib import Path
import json
import os

# Путь по умолчанию, если файла настроек нет
DEFAULT_BASE_DIR = Path("/var/www/hockey-json")

SETTINGS_FILE = Path(__file__).resolve().parent.parent / "config" / "settings.json"


def _load_settings() -> dict:
    """Загружает settings.json, если он есть."""
    if SETTINGS_FILE.exists():
        with SETTINGS_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)
    return {}


_settings = _load_settings()

# Базовая директория с JSON-данными
BASE_DIR = Path(_settings.get("baseDir", str(DEFAULT_BASE_DIR))).resolve()

# На будущее: можно добавлять другие настройки, например ключи и режимы
UPLOAD_API_KEY = os.getenv("UPLOAD_API_KEY", "")

