# Hockey JSON Server

Производственный backend для любительского хоккейного табло:

- **hockey-api** — Flask + gunicorn, принимает JSON от Android-приложения, Telegram-бота и т. д.
- **hockey-nginx** — раздаёт готовые JSON-файлы и проксирует `/api/...` в `hockey-api`.
- **Traefik** — фронтовой reverse-proxy с HTTPS и поддержкой Let's Encrypt.
- **hockey-data** — volume с базой JSON-файлов (`/var/www/hockey-json`).

Проект упакован в Docker и готов к развёртыванию на любом VPS командой:

```bash
docker compose up -d --build
Полная спецификация форматов JSON вынесена в отдельный файл: SPEC_JSON.md.

1. Архитектура и компоненты
1.1. Контейнеры
hockey-api

Образ собирается из Dockerfile.

Приложение Flask + gunicorn.

Хранит/читает данные из /var/www/hockey-json.

Автоматически:

генерирует API-ключ, если он не задан;

при первом старте может импортировать базу из ZIP (локальный путь или URL);

пересчитывает индексы через scripts/rebuild_indexes.py.

hockey-nginx

Образ: nginx:1.27-alpine.

Конфиг: docker/nginx/hockey-json.conf.

Раздаёт содержимое /var/www/hockey-json как статические файлы.

Проксирует все location /api/ в сервис hockey-api:5001.

traefik

Образ: traefik:v3.1.

Слушает порты 80 и 443 на хосте.

Использует конфиг traefik/traefik.yml и файл acme.json для хранения сертификатов.

Может автоматически получать TLS-сертификаты Let’s Encrypt (при наличии домена).

Volume hockey-data

Мапится как /var/www/hockey-json во всех контейнерах.

Содержит все JSON-файлы табло (игры, индексы, статистику, настройки и т. д.).

1.2. Структура данных в /var/www/hockey-json
Подробно форматы описаны в SPEC_JSON.md. Кратко:

text
Копировать код
/var/www/hockey-json/
  index.json                  # корневой индекс сезонов
  active_game.json            # активная/последняя игра
  incoming/                   # "чёрный ящик" upload-json
  finished/
    <season>/
      index.json              # индекс завершённых игр сезона
      <gameId>.json           # протокол конкретной игры
  stats/
    <season>/
      players.json            # статистика игроков по сезону
  rosters/
    roster.json               # актуальный ростер на ближайшую игру
  settings/
    app_settings.json         # настройки приложения
  base_roster/
    base_players.json         # базовый список игроков + рейтинг
2. Структура репозитория
text
Копировать код
hockey-json-server/
  app/
    __init__.py              # create_app()
    config.py                # конфигурация (BASE_DIR, UPLOAD_API_KEY)
    upload_api.py            # Flask-приложение с API эндпоинтами
    api/
      __init__.py
      routes.py              # (на будущее, для расширения API)
  scripts/
    __init__.py
    rebuild_indexes.py       # пересборка индексов и статистики
    import_db.py             # импорт базы из ZIP (файл или URL)
  docker/
    nginx/
      hockey-json.conf       # конфиг nginx внутри контейнера
  traefik/
    traefik.yml              # конфиг Traefik (file provider)
  Dockerfile                 # образ hockey-api
  docker-compose.yml         # весь стек: traefik + nginx + api + volume
  requirements.txt           # Python-зависимости
  SPEC_JSON.md               # спецификация всех JSON-форматов
  README.md                  # этот файл
  .env.example               # пример env-переменных
  .gitignore
3. Требования
VPS или сервер с:

Docker Engine

Docker Compose v2 (docker compose)

Пример проверки:

bash
Копировать код
docker --version
docker compose version
4. Быстрый старт (развёртывание на новом сервере)
4.1. Клонирование репозитория
bash
Копировать код
git clone https://github.com/your-user/hockey-json-server.git
cd hockey-json-server
(Адрес репозитория подставьте свой.)

4.2. Настройка .env
Создайте файл .env на основе .env.example:

bash
Копировать код
cp .env.example .env
nano .env
Важные переменные:

dotenv
Копировать код
# Фиксированный API-ключ для всех /api/... эндпоинтов.
# Можно оставить пустым — при первом старте контейнер сгенерирует случайный ключ
# и выведет его в лог. Для production лучше задать руками.
UPLOAD_API_KEY=CHANGE_ME_TO_STRONG_KEY

# E-mail для Let’s Encrypt (обязателен, если будете использовать реальный домен).
TRAEFIK_ACME_EMAIL=admin@example.com

# Режим импорта базы при первом старте:
#   none  - не импортировать (создать пустую структуру /var/www/hockey-json)
#   local - импортировать из локального файла внутри контейнера (см. ниже)
#   url   - импортировать по HTTP/HTTPS URL
DB_IMPORT_MODE=none

# Источник базы:
#   при DB_IMPORT_MODE=local: путь внутри контейнера, например: /hockey-db.zip
#   при DB_IMPORT_MODE=url:   полный URL, например: https://example.com/hockey-db.zip
DB_IMPORT_SOURCE=

# Если true — при старте принудительно переинициализировать базу (перезаписать существующую).
DB_FORCE_RESET=false
Для начала можно оставить:

dotenv
Копировать код
UPLOAD_API_KEY=мой_секретный_ключ
DB_IMPORT_MODE=none
DB_IMPORT_SOURCE=
DB_FORCE_RESET=false
4.3. Запуск всего стека
bash
Копировать код
docker compose up -d --build
Проверка состояния:

bash
Копировать код
docker compose ps
Ожидаемые сервисы:

traefik (порты 80/443)

hockey-nginx

hockey-api

4.4. Получение API-ключа и статуса инициализации
Если UPLOAD_API_KEY в .env оставили пустым, контейнер сгенерирует ключ автоматически. Узнать его можно так:

bash
Копировать код
docker logs hockey-api | grep "API Key" | tail -n 1
Пример вывода:

text
Копировать код
API Key: hockey_0za1ZJNyOgzy19KzeS28Q4MJ_KEY
Этот ключ обязательно нужно использовать в заголовке X-Api-Key для всех запросов к /api/....

5. Доступ к API
5.1. Базовый URL
Варианты:

При обращении по IP:

HTTP: http://<SERVER_IP>/api/...

HTTPS: https://<SERVER_IP>/api/... (Traefik выдаёт свой self-signed сертификат, можно использовать -k в curl).

При наличии домена (рекомендуется для Let’s Encrypt):

HTTP: http://your-domain/api/...

HTTPS: https://your-domain/api/... (Traefik автоматически получит сертификат Let’s Encrypt при валидной DNS-записи и открытых портах 80/443).

5.2. Авторизация
Все эндпоинты /api/... принимают простой API-ключ:

http
Копировать код
X-Api-Key: <UPLOAD_API_KEY>
При неверном или отсутствующем ключе — ответ 401 Unauthorized.

5.3. Пример запроса upload-json (через Traefik)
bash
Копировать код
API_KEY="ВАШ_API_КЛЮЧ"
SERVER="your-domain-or-ip"

curl -k "https://$SERVER/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{"test": "hello", "source": "curl"}'
Ответ:

json
Копировать код
{"status":"ok","file":"2025-12-08T...json"}
Файл будет сохранён в /var/www/hockey-json/incoming.

6. Жизненный цикл базы и auto-import
База хранится в volume hockey-data и монтируется в контейнеры как /var/www/hockey-json.

6.1. Поведение при первом старте
Скрипт entrypoint.sh в контейнере hockey-api делает:

Определяет BASE_DIR (по умолчанию /var/www/hockey-json).

Если файла BASE_DIR/.initialized нет:

читает DB_IMPORT_MODE и DB_IMPORT_SOURCE;

если:

DB_IMPORT_MODE=local и DB_IMPORT_SOURCE задан → вызывает
python /app/scripts/import_db.py <локальный_путь>;

DB_IMPORT_MODE=url и DB_IMPORT_SOURCE задан → вызывает
python /app/scripts/import_db.py <URL>;

иначе (none или пустые значения) оставляет базу пустой;

после успешной инициализации создаёт флаг BASE_DIR/.initialized.

Если .initialized уже существует:

база считается инициализированной и не трогается;

если при этом DB_FORCE_RESET=true, то импорт выполняется заново.

6.2. Скрипт import_db.py
Поддерживает два сценария:

Импорт из локального файла внутри контейнера:

bash
Копировать код
python /app/scripts/import_db.py /path/to/hockey-db.zip
Импорт по HTTP/HTTPS URL:

bash
Копировать код
python /app/scripts/import_db.py https://example.com/hockey-db.zip
Во всех случаях скрипт:

очищает содержимое BASE_DIR;

распаковывает hockey-json/ из ZIP внутрь BASE_DIR;

запускает rebuild_indexes.py, который:

по всем сезонам пересчитывает:

finished/<season>/index.json

stats/<season>/players.json

пересобирает корневой /var/www/hockey-json/index.json.

7. Миграция со старого сервера (пример)
7.1. Шаг 1. Выгрузить базу со старого сервера
На старом сервере с работающим API:

bash
Копировать код
OLD_API_KEY="старый_ключ"
OLD_BASE="https://old-host-or-ip:8443"

curl -k -H "X-Api-Key: $OLD_API_KEY" \
  "$OLD_BASE/api/download-db" \
  --output hockey-db.zip
Полученный hockey-db.zip содержит:

text
Копировать код
hockey-json/db_info.json
hockey-json/<всё содержимое старого BASE_DIR>
7.2. Вариант A: ручной импорт через docker cp
Скопировать hockey-db.zip на новый сервер (scp/rsync).

На новом сервере:

bash
Копировать код
cd /opt/hockey-json-server

# Убедиться, что стек запущен
docker compose up -d

# Скопировать архив внутрь контейнера hockey-api
docker cp hockey-db.zip hockey-api:/hockey-db.zip

# Выполнить импорт
docker exec -it hockey-api python /app/scripts/import_db.py /hockey-db.zip
Проверить содержимое /var/www/hockey-json (можно через docker exec или через nginx/HTTP).

7.3. Вариант B: авто-импорт по URL
Разместить hockey-db.zip по HTTPS/HTTP URL, доступному с нового сервера:

например, положить файл на какой-нибудь статический хостинг или на свой nginx.

В .env на новом сервере настроить:

dotenv
Копировать код
DB_IMPORT_MODE=url
DB_IMPORT_SOURCE=https://example.com/hockey-db.zip
DB_FORCE_RESET=false   # true, если хотим перезатереть существующую базу
Перезапустить стек:

bash
Копировать код
docker compose down
docker compose up -d --build
В логах hockey-api увидеть:

скачивание ZIP;

успешный импорт;

запуск пересчёта индексов.

8. Основные API-эндпоинты
Полные форматы — в SPEC_JSON.md. Здесь только сводка.

Все запросы — с заголовком:

http
Копировать код
X-Api-Key: <UPLOAD_API_KEY>
Content-Type: application/json
8.1. Логгер любого JSON
POST /api/upload-json
Сохраняет любой JSON в incoming/<timestamp>_<rand>.json.

8.2. Активная игра
POST /api/upload-active-game
Сохраняет JSON активной игры в active_game.json.

8.3. Корневой индекс сезонов
POST /api/upload-root-index
Сохраняет корневой index.json.

8.4. Статистика игроков сезона
POST /api/upload-players-stats
Сохраняет stats/<season>/players.json.

8.5. Индекс завершённых игр сезона
POST /api/upload-finished-index
Сохраняет finished/<season>/index.json.

8.6. Завершённая игра
POST /api/upload-finished-game
Сохраняет finished/<season>/<id>.json и триггерит пересчёт индексов.

8.7. Удаление завершённой игры
POST /api/delete-finished-game
Удаляет finished/<season>/<id>.json (или путь file) и пересчитывает индексы.

8.8. Выгрузка всей базы
GET /api/download-db
Отдаёт ZIP hockey-db.zip со всей базой.

8.9. Текущий ростер
POST /api/upload-roster
Очищает rosters/ и сохраняет rosters/roster.json.

8.10. Настройки приложения
POST /api/upload-settings
Сохраняет settings/app_settings.json.

8.11. Базовый список игроков
POST /api/upload-base-roster
Сохраняет base_roster/base_players.json.

9. Локальный запуск без Docker (для разработки)
Для разработки можно запустить Flask-приложение напрямую.

bash
Копировать код
# В корне репозитория
python -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

# Создать базовую директорию данных (локально)
mkdir -p /var/www/hockey-json

# Задать API-ключ (обязателен)
export UPLOAD_API_KEY=DEV_SECRET_KEY

# Запустить Flask (dev-сервер)
export FLASK_APP=app.upload_api
flask run --host=0.0.0.0 --port=5001
После этого API будет доступен по адресу:

text
Копировать код
http://localhost:5001/api/...
(В production обязательно использовать gunicorn + nginx/Traefik, как в Docker-стеке.)

10. Итог
Репозиторий содержит полный, готовый к деплою стек backend-сервера хоккейного табло.

Развёртывание нового сервера сводится к:

git clone ...

.env (API-ключ, email, режим импорта базы)

docker compose up -d --build

База может быть автоматически импортирована:

либо вручную через docker cp + import_db.py,

либо автоматически по URL при первом старте контейнера.

Все детали форматов JSON — в SPEC_JSON.md. Этот README описывает инфраструктуру, деплой и сценарии восстановления сервера.
