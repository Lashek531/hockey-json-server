from pathlib import Path
import sys

# Добавляем корневую папку проекта (/opt/hockey-server) в sys.path,
# чтобы можно было импортировать app.config
ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.config import BASE_DIR


#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Пересчёт индексных файлов для онлайн-табло.

Что делает:
1. Ищет сезоны в /var/www/hockey-json/finished/<season>/.
2. Для каждого сезона:
   - читает все JSON-протоколы игр (кроме index.json),
   - строит finished/<season>/index.json (строго в формате, как у планшета),
   - строит stats/<season>/players.json (агрегированная статистика игроков).
3. Пересобирает корневой /var/www/hockey-json/index.json.

Скрипт идемпотентен: можно запускать сколько угодно раз.
"""

import json
import os
from pathlib import Path
from datetime import datetime
from collections import defaultdict
from typing import Optional, Dict, List, Tuple

# Базовый каталог хранилища табло
FINISHED_DIR = BASE_DIR / "finished"
STATS_DIR = BASE_DIR / "stats"
ROOT_INDEX_FILE = BASE_DIR / "index.json"

# Имена файлов индексов внутри сезона
SEASON_INDEX_FILENAME = "index.json"
PLAYERS_STATS_FILENAME = "players.json"


# ---------- Вспомогательные функции ----------

def load_json(path: Path):
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[WARN] Не удалось прочитать JSON {path}: {e}")
        return None


def save_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    tmp.replace(path)
    print(f"[OK] Записан файл {path}")


def discover_seasons() -> List[str]:
    """
    Ищем сезоны как подпапки в finished/.
    Возвращает список строк, например ["24-25", "25-26"].
    """
    if not FINISHED_DIR.exists():
        return []

    seasons: List[str] = []
    for entry in FINISHED_DIR.iterdir():
        if entry.is_dir():
            seasons.append(entry.name)
    seasons.sort()
    return seasons


def parse_iso_date(date_str: str, fallback_ts: float) -> float:
    """
    Пытаемся распарсить ISO-дату. Если не получилось — возвращаем fallback_ts.
    Возвращает timestamp (секунды).
    """
    if not date_str:
        return fallback_ts

    try:
        dt = datetime.fromisoformat(date_str)
        return dt.timestamp()
    except Exception:
        return fallback_ts


def clean_player_name(name: str) -> Optional[str]:
    """
    Чистим имя игрока:
    - убираем пробелы,
    - отбрасываем пустые и "null"/"None"/"нул".
    """
    if not isinstance(name, str):
        return None
    s = name.strip()
    if not s:
        return None
    lowered = s.lower()
    if lowered in {"null", "none", "нул"}:
        return None
    return s


# ---------- Пересчёт индекса и статистики по одному сезону ----------

def process_season(season: str) -> Tuple[List[Dict], Dict[str, Dict]]:
    """
    Обрабатывает один сезон:
    - читает все игры в finished/<season>/,
    - строит:
        finished/<season>/index.json
        stats/<season>/players.json
    """
    season_dir = FINISHED_DIR / season
    season_index_path = season_dir / SEASON_INDEX_FILENAME
    stats_season_dir = STATS_DIR / season
    players_stats_path = stats_season_dir / PLAYERS_STATS_FILENAME

    if not season_dir.exists():
        print(f"[WARN] Папка сезона не найдена: {season_dir}")
        return [], {}

    game_files: List[Path] = []
    for entry in season_dir.iterdir():
        if entry.is_file() and entry.suffix.lower() == ".json":
            if entry.name == SEASON_INDEX_FILENAME:
                continue
            game_files.append(entry)

    if not game_files:
        season_index_data = {
            "season": season,
            "updatedAt": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "games": []
        }
        save_json(season_index_path, season_index_data)
        save_json(players_stats_path, {"season": season, "players": []})
        return [], {}

    games_meta: List[Dict] = []

    players_stats: Dict[str, Dict] = defaultdict(lambda: {
        "games": 0,
        "goals": 0,
        "assists": 0,
        "points": 0,
        "wins": 0,
        "draws": 0,
        "losses": 0,
    })

    for game_file in game_files:
        data = load_json(game_file)
        if not isinstance(data, dict):
            continue

        file_rel_path = str(game_file.relative_to(BASE_DIR))

        game_id = data.get("gameId") or game_file.stem
        arena = data.get("arena") or ""
        date_str = data.get("date") or ""

        teams = data.get("teams") or {}
        red_obj = teams.get("RED") or {}
        white_obj = teams.get("WHITE") or {}

        red_name = red_obj.get("name") or "Красные"
        white_name = white_obj.get("name") or "Белые"

        final_score = data.get("finalScore") or {}
        red_score = int(final_score.get("RED") or 0)
        white_score = int(final_score.get("WHITE") or 0)

        mtime_ts = game_file.stat().st_mtime
        sort_ts = parse_iso_date(date_str, mtime_ts)

        games_meta.append({
            "id": game_id,
            "date": date_str,
            "arena": arena,
            "teamRed": red_name,
            "teamWhite": white_name,
            "scoreRed": red_score,
            "scoreWhite": white_score,
            "file": file_rel_path,
            "_sort_ts": sort_ts,
        })

        # --- Статистика игроков ---
        red_players = red_obj.get("players") or []
        white_players = white_obj.get("players") or []

        red_set = set()
        white_set = set()
        all_players_in_game = set()

        for name in red_players:
            cleaned = clean_player_name(name)
            if cleaned:
                red_set.add(cleaned)
                all_players_in_game.add(cleaned)

        for name in white_players:
            cleaned = clean_player_name(name)
            if cleaned:
                white_set.add(cleaned)
                all_players_in_game.add(cleaned)

        for name in all_players_in_game:
            players_stats[name]["games"] += 1

        if red_score != white_score:
            red_won = red_score > white_score
            for name in red_set:
                players_stats[name]["wins" if red_won else "losses"] += 1
            for name in white_set:
                players_stats[name]["wins" if not red_won else "losses"] += 1
        else:
            for name in all_players_in_game:
                players_stats[name]["draws"] += 1

        goals = data.get("goals") or []
        if isinstance(goals, list):
            for g in goals:
                if not isinstance(g, dict):
                    continue
                scorer = clean_player_name(g.get("scorer"))
                a1 = clean_player_name(g.get("assist1"))
                a2 = clean_player_name(g.get("assist2"))

                if scorer:
                    players_stats[scorer]["goals"] += 1
                if a1:
                    players_stats[a1]["assists"] += 1
                if a2:
                    players_stats[a2]["assists"] += 1

    for name, st in players_stats.items():
        st["points"] = st["goals"] + st["assists"]

    games_meta.sort(key=lambda g: g["_sort_ts"])
    for g in games_meta:
        g.pop("_sort_ts", None)

    season_index_data = {
        "season": season,
        "updatedAt": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "games": games_meta,
    }
    save_json(season_index_path, season_index_data)

    players_list = []
    for name, st in players_stats.items():
        players_list.append({
            "name": name,
            "games": st["games"],
            "goals": st["goals"],
            "assists": st["assists"],
            "points": st["points"],
            "wins": st["wins"],
            "draws": st["draws"],
            "losses": st["losses"],
        })

    players_list.sort(key=lambda p: (-p["points"], -p["goals"], p["name"]))

    stats_data = {
        "season": season,
        "players": players_list,
    }
    save_json(players_stats_path, stats_data)

    return games_meta, players_stats


# ---------- Корневой index.json ----------

def load_existing_root_index() -> Optional[Dict]:
    if not ROOT_INDEX_FILE.exists():
        return None
    data = load_json(ROOT_INDEX_FILE)
    return data if isinstance(data, dict) else None


def rebuild_root_index(all_seasons: List[str]) -> None:
    existing = load_existing_root_index()
    existing_current = (
        existing["currentSeason"]
        if existing and isinstance(existing.get("currentSeason"), str)
        else None
    )

    if existing_current in all_seasons:
        current_season = existing_current
    else:
        current_season = all_seasons[-1] if all_seasons else ""

    seasons_entries = []
    for season in all_seasons:
        seasons_entries.append({
            "id": season,
            "name": f"Сезон {season}",
            "finishedIndex": f"finished/{season}/index.json",
            "playersStats": f"stats/{season}/players.json",
            "activeGame": "active_game.json",
        })

    root_data = {
        "currentSeason": current_season,
        "seasons": seasons_entries,
    }

    save_json(ROOT_INDEX_FILE, root_data)


# ---------- main ----------

def main():
    print(f"[INFO] BASE_DIR = {BASE_DIR}")

    seasons = discover_seasons()
    if not seasons:
        print("[WARN] Сезоны в finished/ не найдены. Нечего индексировать.")
        rebuild_root_index([])
        return

    print(f"[INFO] Найдены сезоны: {', '.join(seasons)}")

    for season in seasons:
        print(f"[INFO] Обработка сезона {season}")
        process_season(season)

    rebuild_root_index(seasons)
    print("[INFO] Готово.")


if __name__ == "__main__":
    main()
