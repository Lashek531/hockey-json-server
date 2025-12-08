import os
import io
import json
import datetime
import secrets
import subprocess
import sys
import zipfile
from pathlib import Path

from flask import Flask, request, jsonify, abort, send_file

from .config import BASE_DIR, UPLOAD_API_KEY

# ============================================
# НАСТРОЙКИ
# ============================================

# BASE_DIR приходит из общего config.py как Path или строка
BASE_DIR = Path(BASE_DIR)
BASE_DIR_STR = str(BASE_DIR)

# Каталог для «чёрного ящика»
UPLOAD_DIR = os.path.join(BASE_DIR_STR, "incoming")

# Ключ для авторизации по заголовку X-Api-Key
API_KEY = UPLOAD_API_KEY or "3vXjhEr1YvFzgL6gO2fc_"

# ============================================

app = Flask(__name__)


def ensure_dir(path: str) -> None:
    """Создать директорию, если её ещё нет."""
    os.makedirs(path, exist_ok=True)


def save_json_relative(rel_path: str, data: dict) -> str:
    """
    Сохраняет JSON-данные в файл BASE_DIR/rel_path.
    Создаёт промежуточные директории при необходимости.
    Возвращает абсолютный путь к сохранённому файлу.
    """
    abs_path = os.path.join(BASE_DIR_STR, rel_path)
    dir_path = os.path.dirname(abs_path)
    ensure_dir(dir_path)

    with open(abs_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return abs_path


def trigger_rebuild_indexes() -> None:
    """
    Запускает скрипт пересборки индексов в отдельном процессе.
    Ошибки логируем, но на HTTP-ответ не влияем.
    """
    try:
        # /opt/hockey-server/app/upload_api.py -> /opt/hockey-server
        root_dir = Path(__file__).resolve().parent.parent
        script_path = root_dir / "scripts" / "rebuild_indexes.py"

        # sys.executable укажет на python из venv,
        # который использует gunicorn.
        subprocess.Popen(
            [sys.executable, str(script_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        # Не роняем обработчик, просто логируем.
        try:
            app.logger.exception("Failed to trigger rebuild_indexes: %s", e)
        except Exception:
            # На случай, если вдруг logger недоступен
            pass


@app.before_request
def verify_api_key():
    """Простейшая авторизация по заголовку X-Api-Key.

    Все /api/... требуют ключа, КРОМЕ /api/download-db,
    который должен быть доступен публично для автоматического импорта базы.
    """
    # Разрешаем публичный доступ к выгрузке базы
    if request.path == "/api/download-db":
        return

    key = request.headers.get("X-Api-Key")
    if key != API_KEY:
        abort(401)


# ---------- 1. Универсальный "чёрный ящик" ----------

@app.route("/api/upload-json", methods=["POST"])
def upload_json():
    """
    Универсальная точка приёма:
    любой корректный JSON сохраняется в BASE_DIR/incoming/<timestamp>_<rand>.json
    """
    ensure_dir(UPLOAD_DIR)

    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    now = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    rnd = secrets.token_hex(3)
    filename = f"{now}_{rnd}.json"
    path = os.path.join(UPLOAD_DIR, filename)

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return jsonify({"status": "ok", "file": filename})


# ---------- 2. Активная игра: active_game.json ----------

@app.route("/api/upload-active-game", methods=["POST"])
def upload_active_game():
    """
    Принимает JSON активной игры и сохраняет его как BASE_DIR/active_game.json.
    Формат должен соответствовать "формату одной игры".
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    target_path = os.path.join(BASE_DIR_STR, "active_game.json")

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return jsonify({"status": "ok", "file": "active_game.json"})


# ---------- 3. Глобальный индекс: index.json в корне ----------

@app.route("/api/upload-root-index", methods=["POST"])
def upload_root_index():
    """
    Принимает глобальный index.json (currentSeason, seasons[] ... )
    и сохраняет его в BASE_DIR/index.json.
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    target_path = os.path.join(BASE_DIR_STR, "index.json")

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return jsonify({"status": "ok", "file": "index.json"})


# ---------- X. Настройки приложения: settings/app_settings.json ----------

@app.route("/api/upload-settings", methods=["POST"])
def upload_settings():
    """
    Принимает JSON настроек приложения и сохраняет его в
    BASE_DIR/settings/app_settings.json.

    Формат содержимого не жёстко валидируется: сервер только проверяет,
    что это корректный JSON, и сохраняет его "как есть".
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    rel_path = "settings/app_settings.json"
    save_json_relative(rel_path, data)

    return jsonify({"status": "ok", "file": rel_path})


# ---------- Y. Базовый список игроков: base_roster/base_players.json ----------

@app.route("/api/upload-base-roster", methods=["POST"])
def upload_base_roster():
    """
    Принимает JSON базового списка игроков и сохраняет его в
    BASE_DIR/base_roster/base_players.json.

    Ожидаемый формат (пример):

    {
      "version": 1,
      "updatedAt": "2025-12-07T20:00:00",
      "players": [
        {
          "user_id": 38962792,
          "full_name": "Чижик Сергей",
          "role": "def",
          "team": null,
          "rating": 1500
        }
      ]
    }
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    players = data.get("players")
    if players is None or not isinstance(players, list):
        return jsonify({
            "status": "error",
            "message": "Missing or invalid 'players' array"
        }), 400

    rel_path = "base_roster/base_players.json"
    save_json_relative(rel_path, data)

    return jsonify({"status": "ok", "file": rel_path})


# ---------- 4. Статистика игроков: stats/<season>/players.json ----------

@app.route("/api/upload-players-stats", methods=["POST"])
def upload_players_stats():
    """
    Принимает JSON статистики игроков сезона (players.json)
    и кладёт его в BASE_DIR/stats/<season>/players.json.

    Ожидается поле "season" в корне JSON:
    {
      "season": "25-26",
      ...
    }
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    season = data.get("season")
    if not season:
        return jsonify({"status": "error", "message": "Missing 'season' field"}), 400

    season_dir = os.path.join(BASE_DIR_STR, "stats", season)
    ensure_dir(season_dir)

    target_path = os.path.join(season_dir, "players.json")

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return jsonify({"status": "ok", "file": f"stats/{season}/players.json"})


# ---------- 5. Индекс завершённых игр сезона: finished/<season>/index.json ----

@app.route("/api/upload-finished-index", methods=["POST"])
def upload_finished_index():
    """
    Принимает индекс завершённых игр сезона:
    {
      "season": "25-26",
      "updatedAt": "...",
      "games": [ ... ]
    }

    Сохраняет в BASE_DIR/finished/<season>/index.json.
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    season = data.get("season")
    if not season:
        return jsonify({"status": "error", "message": "Missing 'season' field"}), 400

    season_dir = os.path.join(BASE_DIR_STR, "finished", season)
    ensure_dir(season_dir)

    target_path = os.path.join(season_dir, "index.json")

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    return jsonify({"status": "ok", "file": f"finished/{season}/index.json"})


# ---------- 6b. Составы на игру: rosters/roster.json ----------

@app.route("/api/upload-roster", methods=["POST"])
def upload_roster():
    """
    Принимает JSON с составами.

    Логика:
    1. Очистить каталог BASE_DIR/rosters полностью.
    2. Создать один файл:
         roster.json
    3. Сохранить присланный JSON.
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    rosters_dir = os.path.join(BASE_DIR_STR, "rosters")
    ensure_dir(rosters_dir)

    for fname in os.listdir(rosters_dir):
        fpath = os.path.join(rosters_dir, fname)
        try:
            if os.path.isfile(fpath):
                os.remove(fpath)
        except Exception:
            pass

    filename = "roster.json"
    target_path = os.path.join(rosters_dir, filename)

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    rel_path = f"rosters/{filename}"
    return jsonify({"status": "ok", "file": rel_path})


# ---------- 6. Завершённая игра: finished/<season>/<id>.json ----------

@app.route("/api/upload-finished-game", methods=["POST"])
def upload_finished_game():
    """
    Принимает JSON одной завершённой игры:

    {
      "id": "2025-11-29_16-48-57_pestovo",
      "season": "25-26",
      ...
    }

    И кладёт его в:
      BASE_DIR/finished/<season>/<id>.json
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    season = data.get("season")
    game_id = data.get("id")

    if not season or not game_id:
        return jsonify({
            "status": "error",
            "message": "Missing 'season' or 'id' field"
        }), 400

    season_dir = os.path.join(BASE_DIR_STR, "finished", season)
    ensure_dir(season_dir)

    filename = f"{game_id}.json"
    target_path = os.path.join(season_dir, filename)

    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    trigger_rebuild_indexes()

    rel_path = f"finished/{season}/{filename}"
    return jsonify({"status": "ok", "file": rel_path})


# ---------- 7. Удаление завершённой игры ----------

@app.route("/api/delete-finished-game", methods=["POST"])
def delete_finished_game():
    """
    Удаляет одну завершённую игру из finished/<season>/<id>.json.

    Варианты тела запроса:

    1) По season + id:
       {
         "season": "25-26",
         "id": "2025-11-29_16-48-57_pestovo"
       }

    2) По относительному пути:
       {
         "file": "finished/25-26/2025-11-29_16-48-57_pestovo.json"
       }
    """
    try:
        data = request.get_json(force=True)
    except Exception:
        return jsonify({"status": "error", "message": "Invalid JSON"}), 400

    file_rel = data.get("file")
    season = data.get("season")
    game_id = data.get("id")

    if file_rel:
        if ".." in file_rel or not file_rel.startswith("finished/"):
            return jsonify({
                "status": "error",
                "message": "Invalid 'file' path"
            }), 400

        target_path = os.path.join(BASE_DIR_STR, file_rel)
        parts = file_rel.split("/")
        if len(parts) >= 2:
            season = parts[1]
    else:
        if not season or not game_id:
            return jsonify({
                "status": "error",
                "message": "Missing 'season'/'id' or 'file'"
            }), 400

        filename = f"{game_id}.json"
        file_rel = f"finished/{season}/{filename}"
        target_path = os.path.join(BASE_DIR_STR, "finished", season, filename)

    deleted = False

    if os.path.exists(target_path):
        try:
            os.remove(target_path)
            deleted = True
        except Exception as e:
            return jsonify({
                "status": "error",
                "message": f"Failed to delete file: {e}"
            }), 500

    trigger_rebuild_indexes()

    return jsonify({
        "status": "ok",
        "file": file_rel,
        "deleted": deleted
    })


# ---------- 8. Выгрузка всей базы: ZIP hockey-json ----------

@app.route("/api/download-db", methods=["GET"])
def download_db():
    """
    Отдаёт ZIP-архив со всей базой BASE_DIR (как hockey-json/...).
    """
    if not os.path.isdir(BASE_DIR_STR):
        return jsonify({
            "status": "error",
            "message": f"DB root not found: {BASE_DIR_STR}"
        }), 500

    buf = io.BytesIO()

    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        info = {
            "schemaVersion": 1,
            "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "root": "hockey-json",
        }
        zf.writestr(
            "hockey-json/db_info.json",
            json.dumps(info, ensure_ascii=False, indent=2)
        )

        for root, dirs, files in os.walk(BASE_DIR_STR):
            for name in files:
                full_path = os.path.join(root, name)
                rel_path = os.path.relpath(full_path, BASE_DIR_STR)
                arcname = os.path.join("hockey-json", rel_path).replace("\\", "/")
                zf.write(full_path, arcname=arcname)

    buf.seek(0)

    return send_file(
        buf,
        mimetype="application/zip",
        as_attachment=True,
        download_name="hockey-db.zip",
    )


if __name__ == "__main__":
    # Локальный запуск (для отладки)
    app.run(host="0.0.0.0", port=5001, debug=True)
