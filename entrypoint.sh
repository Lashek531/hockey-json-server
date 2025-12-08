#!/usr/bin/env bash
set -e

echo "=== Hockey API entrypoint ==="

# Базовая директория с JSON
BASE_DIR=${BASE_DIR:-/var/www/hockey-json}
INIT_FLAG="${BASE_DIR}/.initialized"

UPLOAD_API_KEY_ENV="${UPLOAD_API_KEY:-}"

# Если ключ не задан — сгенерируем
if [ -z "$UPLOAD_API_KEY_ENV" ]; then
  echo "[INFO] UPLOAD_API_KEY не задан, генерирую случайный ключ..."
  UPLOAD_API_KEY_ENV="hockey_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)_KEY"
  export UPLOAD_API_KEY="$UPLOAD_API_KEY_ENV"
  echo "[INFO] Сгенерированный API ключ: $UPLOAD_API_KEY_ENV"
else
  echo "[INFO] Используется API ключ из окружения."
fi

DB_IMPORT_MODE="${DB_IMPORT_MODE:-none}"
DB_IMPORT_SOURCE="${DB_IMPORT_SOURCE:-}"
DB_FORCE_RESET="${DB_FORCE_RESET:-false}"

mkdir -p "$BASE_DIR"

SHOULD_INIT=false

if [ ! -f "$INIT_FLAG" ]; then
  echo "[INFO] База ещё не инициализирована."
  SHOULD_INIT=true
else
  echo "[INFO] База уже инициализирована (найден $INIT_FLAG)."
  if [ "$DB_FORCE_RESET" = "true" ]; then
    echo "[INFO] DB_FORCE_RESET=true — будет выполнен повторный импорт."
    SHOULD_INIT=true
  fi
fi

if [ "$SHOULD_INIT" = true ]; then
  echo "=== Инициализация базы данных ==="
  echo "[INFO] DB_IMPORT_MODE=$DB_IMPORT_MODE"
  echo "[INFO] DB_IMPORT_SOURCE=$DB_IMPORT_SOURCE"

  if [ "$DB_IMPORT_MODE" = "local" ] && [ -n "$DB_IMPORT_SOURCE" ]; then
    echo "[INFO] Импорт локального ZIP: $DB_IMPORT_SOURCE"
    python /app/scripts/import_db.py "$DB_IMPORT_SOURCE" || {
      echo "[ERROR] Импорт локального ZIP завершился с ошибкой."
      exit 1
    }
  elif [ "$DB_IMPORT_MODE" = "url" ] && [ -n "$DB_IMPORT_SOURCE" ]; then
    echo "[INFO] Импорт ZIP по URL: $DB_IMPORT_SOURCE"
    python /app/scripts/import_db.py "$DB_IMPORT_SOURCE" || {
      echo "[ERROR] Импорт ZIP по URL завершился с ошибкой."
      exit 1
    }
  else
    echo "[INFO] Режим импорта: none или источник не указан — база остаётся пустой/существующей."
  fi

  touch "$INIT_FLAG"
  echo "[INFO] Создан флаг инициализации: $INIT_FLAG"
fi

echo "=========================================="
echo "Hockey JSON API успешно запущен."
echo "API Key: $UPLOAD_API_KEY_ENV"
echo "DB_IMPORT_MODE: $DB_IMPORT_MODE"
echo "DB_IMPORT_SOURCE: $DB_IMPORT_SOURCE"
echo "BASE_DIR: $BASE_DIR"
echo "=========================================="

# Запускаем gunicorn
exec gunicorn -b 0.0.0.0:5001 "app:create_app()"
