
INSTALL.md
# Установка Hockey JSON Server с нуля

Этот документ описывает, как развернуть Hockey JSON Server на любом VPS с Docker и Traefik (HTTPS + Let's Encrypt), импортировать базу и проверить работу.

## 1. Предварительные требования

1. **VPS / сервер** с Linux (Ubuntu/Debian или аналогичный).
2. **Права root** или доступ через `sudo`.
3. **Открыты порты** `80` и `443` извне (Traefik будет слушать их для HTTP/HTTPS и Let's Encrypt).
4. **Домен** (например, `hockey.example.com`), у которого A-запись указывает на IP сервера.
5. Установлен Docker и Docker Compose:
   - Docker Engine 25+ / 29+  
   - Docker Compose v2+ (плагин `docker compose`)

Проверка:

```bash
docker --version
docker compose version

2. Клонирование репозитория
cd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server


Дальнейшие команды считаем выполняются из каталога:

/opt/hockey-json-server

3. Настройка окружения (.env)

В репозитории есть пример .env:

cp .env.example .env
nano .env


Внутри .env есть переменные с комментариями. Заполни минимум:

Домен и почта для Let's Encrypt
(имена переменных смотри прямо в .env, они помечены как REQUIRED для Traefik).

API-ключ (если хочешь задать заранее)
UPLOAD_API_KEY=...
Если оставить пустым, контейнер с API сгенерирует случайный ключ при первом старте и выведет его в логи.

Импорт базы при первом запуске
Переменные (смотри в .env, там описания):

DB_IMPORT_MODE — режим импорта:

none – не импортировать (создаётся пустая база).

local – импортировать ZIP-файл, который лежит в файловой системе хоста.

url – скачать ZIP по HTTP(S) и импортировать.

DB_IMPORT_SOURCE — путь к ZIP или URL в зависимости от режима:

при local — путь на хосте, например: /opt/backups/hockey-db.zip;

при url — полный URL, например: https://old-server.example.com/hockey-db.zip.

Файл .env.example содержит комментарии к каждой переменной — ориентируйся на них как на источник правды.

4. Первый запуск

Когда .env заполнен:

docker compose up -d --build


Docker:

соберёт образ hockey-api (Flask + gunicorn),

поднимет контейнер hockey-nginx (раздаёт JSON и проксирует запросы к API),

поднимет traefik (reverse-proxy + HTTPS + Let’s Encrypt),

выполнит начальную инициализацию базы (import_db.py) согласно DB_IMPORT_MODE и DB_IMPORT_SOURCE.

Проверка, что все контейнеры запущены
docker compose ps


Ожидаем статус Up для:

traefik

hockey-nginx

hockey-api

Если что-то в состоянии Exited, смотри логи:

docker logs traefik
docker logs hockey-api
docker logs hockey-nginx

5. API-ключ и информация об инициализации

Если UPLOAD_API_KEY в .env был пустым, ключ будет сгенерирован при первом старте и выведен в лог hockey-api.

Получить его:

docker logs hockey-api | grep "API Key" | tail -n 1


Типичный вывод:

API Key: hockey_XXXXXX_KEY


Там же в логах при старте будет информация:

использованный DB_IMPORT_MODE,

источник импорта DB_IMPORT_SOURCE,

путь к базе BASE_DIR (/var/www/hockey-json внутри контейнера).

Пример:

Hockey JSON API успешно запущен.
API Key: hockey_XXXXXX_KEY
DB_IMPORT_MODE: url
DB_IMPORT_SOURCE: https://old-server.example.com/hockey-db.zip
BASE_DIR: /var/www/hockey-json

6. Проверка HTTPS и API
6.1. Проверка HTTPS Traefik’ом

После первого старта Traefik может занять до минуты на получение сертификата Let’s Encrypt.

Проверка в браузере:

https://<твой-домен>/


Должен открыться autoindex от hockey-nginx (папка с JSON-файлами). Браузер покажет валидный сертификат Let’s Encrypt (если всё правильно с DNS/портами).

6.2. Тестовый запрос к API

Используем curl. Подставь:

DOMAIN — твой домен,

API_KEY — ключ, который в .env или в логах.

DOMAIN="hockey.example.com"
API_KEY="hockey_XXXXXX_KEY"

curl -k "https://$DOMAIN/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{"test": "install-check", "source": "curl"}'


Ожидаемый ответ:

{"file":"2025-12-08T13-54-53_7c9615.json","status":"ok"}


Появление нового файла можно проверить в контейнере:

docker exec -it hockey-api ls -1 /var/www/hockey-json/incoming


Или на хосте, если volume смонтирован в локальную папку (см. docker-compose.yml).

6.3. Проверка выгрузки базы
curl -k -H "X-Api-Key: $API_KEY" \
  "https://$DOMAIN/api/download-db" \
  --output hockey-db-test.zip


Файл hockey-db-test.zip должен появиться в текущей директории.

7. Импорт базы при первом запуске
7.1. Импорт из локального ZIP

Скопировать ZIP с базой на сервер, например:

scp hockey-db.zip root@server:/opt/backups/hockey-db.zip


В .env указать:

DB_IMPORT_MODE=local
DB_IMPORT_SOURCE=/opt/backups/hockey-db.zip


Запустить:

docker compose up -d --build


При первом старте:

база в /var/www/hockey-json будет очищена,

содержимое hockey-json/ из ZIP распаковано туда,

скрипт rebuild_indexes.py пересчитает индексы и статистику,

создастся флаг /var/www/hockey-json/.initialized, чтобы импорт не повторялся.

7.2. Импорт из URL

Сделать ZIP доступным по HTTPS, например, разместив его на старом сервере/облаке.

В .env указать:

DB_IMPORT_MODE=url
DB_IMPORT_SOURCE=https://old-server.example.com/hockey-db.zip


Запустить:

docker compose up -d --build


Скрипт внутри контейнера скачает ZIP во временный файл, распакует, пересчитает индексы и удалит временный ZIP.

7.3. Повторный импорт на уже работающем сервере

Чтобы повторно выполнить импорт (например, при восстановлении из нового бэкапа):

Остановить стек:

docker compose down


Удалить флаг инициализации в volume базы. Есть два варианта:

через docker run / docker exec в уже существующий volume;

или просто удалить/пере создать volume в docker-compose.yml.

Проще всего:

удалить volume (будет потеряна база),

настроить новый импорт и снова выполнить docker compose up -d.

Вариант под конкретный сценарий восстановления можно выбрать вручную.

8. Обновление версии сервера

Для обновления версии бэкенда с GitHub:

cd /opt/hockey-json-server
git pull
docker compose up -d --build


Docker пересоберёт образ hockey-api, если изменились зависимости/код.

Traefik и nginx поднимутся с существующей конфигурацией и томами.

База в /var/www/hockey-json сохранится (volume не трогаем).

9. Краткая памятка

Репозиторий:
https://github.com/Lashek531/hockey-json-server

Конфиг окружения: .env (см. .env.example).

Первый запуск: docker compose up -d --build

Проверка API:

curl -k "https://<DOMAIN>/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <API_KEY>" \
  -d '{"test": "ok"}'


Экспорт базы: GET /api/download-db с тем же API-ключом.

Импорт базы при первом старте: DB_IMPORT_MODE + DB_IMPORT_SOURCE.

Все детальные форматы JSON описаны в SPEC_JSON.md
.


---

## Новый README.md

```markdown
# Hockey JSON Server

Production-ready backend для любительского хоккейного табло.

Сервер принимает JSON из Android-приложения и вспомогательных утилит, хранит их в файловой структуре, пересчитывает индексы и статистику, и раздаёт готовые JSON по HTTPS для веб-табло и интеграций (например, Telegram-бота).

Проект полностью контейнеризирован (Docker + Traefik + nginx) и готов к развёртыванию на любом VPS одной командой.

```bash
docker compose up -d --build


Подробная инструкция по установке и восстановлению базы: см. INSTALL.md
.

Кратко о функционале

Приём JSON через HTTP API (/api/...) с авторизацией по X-Api-Key.

Хранение базы в дереве:

/var/www/hockey-json/
  index.json
  active_game.json
  incoming/
  finished/<season>/*.json
  finished/<season>/index.json
  stats/<season>/players.json
  rosters/roster.json
  settings/app_settings.json
  base_roster/base_players.json


Поддерживаемые операции:

Логирование произвольного JSON (/api/upload-json).

Сохранение активной игры (/api/upload-active-game).

Сохранение завершённой игры (/api/upload-finished-game).

Удаление завершённой игры (/api/delete-finished-game).

Пересчёт индексов и статистики по сезонам (scripts/rebuild_indexes.py).

Обновление глобального индекса сезонов (/api/upload-root-index).

Обновление настроек, ростеров, базового списка игроков.

Выгрузка всей базы одним ZIP-файлом (/api/download-db).

Автоматическое построение HTTPS-front:

Traefik как reverse-proxy.

Автоматическое получение сертификатов Let’s Encrypt (при корректной настройке домена).

nginx как upstream-сервис для раздачи статического содержимого и проксирования API.

Все форматы JSON детально описаны в SPEC_JSON.md
.

Архитектура контейнеров

Стек описан в docker-compose.yml
 и включает:

hockey-api

Базовый образ: python:3.12-slim

Flask + gunicorn.

Код в /app/app.

База JSON: /var/www/hockey-json (volume).

Скрипты: /app/scripts (rebuild_indexes.py, import_db.py).

Точка входа: entrypoint.sh

генерирует API-ключ при отсутствии UPLOAD_API_KEY;

выполняет начальный импорт базы (DB_IMPORT_MODE / DB_IMPORT_SOURCE);

запускает gunicorn.

hockey-nginx

Базовый образ: nginx:alpine.

Конфиг: docker/nginx/hockey-json.conf

root /var/www/hockey-json (same volume, что у hockey-api);

автоиндекс JSON-файлов;

прокси /api/... на hockey-api:5001.

traefik

Базовый образ: traefik:v3.

Конфиг: traefik/traefik.yml
 + динамические настройки из labels.

Слушает порты 80 и 443.

Разруливает маршрутизацию по домену и TLS (Let’s Encrypt / self-signed при отладке).

Схема трафика:

клиент (HTTPS) → Traefik (443) → nginx (hockey-nginx, 80) → Flask/gunicorn (hockey-api, 5001)

Структура репозитория
hockey-json-server/
  app/
    __init__.py           # create_app() и фабрика Flask-приложения
    config.py             # BASE_DIR, загрузка настроек и API key из окружения
    upload_api.py         # все Flask-роуты /api/...
    api/
      __init__.py
      routes.py           # (резерв для расширений/версионирования API)
  scripts/
    __init__.py
    rebuild_indexes.py    # пересчёт finished/<season>/index.json и stats/<season>/players.json
    import_db.py          # импорт базы из ZIP (файл или URL)
  docker/
    nginx/
      hockey-json.conf    # конфиг nginx внутри контейнера
  traefik/
    traefik.yml           # статический конфиг Traefik
  Dockerfile              # образ hockey-api
  docker-compose.yml      # описания сервисов: traefik, hockey-nginx, hockey-api
  entrypoint.sh           # entrypoint для hockey-api
  requirements.txt        # Python-зависимости
  .env.example            # пример переменных окружения
  .gitignore
  README.md
  INSTALL.md              # (этот файл нужно создать по инструкции)
  SPEC_JSON.md            # спецификация всех JSON-форматов

Краткий обзор API

Все эндпоинты используют авторизацию по заголовку:

X-Api-Key: <UPLOAD_API_KEY>


Если заголовок отсутствует или ключ неверный — ответ 401 Unauthorized.

Основные маршруты (подробности см. в коде app/upload_api.py):

POST /api/upload-json
Логирование произвольного JSON в incoming/.

POST /api/upload-active-game
Сохранение текущей/активной игры в active_game.json.

POST /api/upload-root-index
Обновление корневого index.json.

POST /api/upload-players-stats
Сохранение stats/<season>/players.json.

POST /api/upload-finished-index
Сохранение finished/<season>/index.json (если по каким-то причинам нужно из клиента).

POST /api/upload-finished-game
Сохранение finished/<season>/<id>.json с пересчётом индексов и статистики.

POST /api/delete-finished-game
Удаление игры по season + id или по относительному пути и пересчёт индексных файлов.

POST /api/upload-roster
Обновление текущего ростера (rosters/roster.json).

POST /api/upload-settings
Настройки приложения (settings/app_settings.json).

POST /api/upload-base-roster
Базовый список игроков (base_roster/base_players.json).

GET /api/download-db
Выгрузка ZIP-архива всей базы (hockey-json/db_info.json + всё содержимое BASE_DIR).

Форматы всех файлов формализованы в SPEC_JSON.md
.

Быстрый старт (TL;DR)

Установи Docker + Docker Compose.

Клонируй репозиторий:

cd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server


Создай .env:

cp .env.example .env
nano .env


Настрой домен, почту для Let’s Encrypt, API-ключ и режим импорта базы.

Запусти стек:

docker compose up -d --build


Получи API-ключ (если не задал вручную):

docker logs hockey-api | grep "API Key" | tail -n 1


Проверь API:

DOMAIN="hockey.example.com"
API_KEY="hockey_XXXXXX_KEY"

curl -k "https://$DOMAIN/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $API_KEY" \
  -d '{"test": "ok"}'


Подробный сценарий развёртывания и восстановления см. в INSTALL.md
.


---

**Что дальше делать тебе:**

1. На сервере (или локально) создать/перезаписать файлы:

```bash
cd /opt/hockey-json-server

nano INSTALL.md   # вставить первый блок
nano README.md    # заменить содержимое вторым блоком


Закоммитить и отправить на GitHub:

git add INSTALL.md README.md
git commit -m "Add INSTALL guide and update README"
git push
