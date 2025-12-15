# Hockey JSON Server

Производственный backend для любительского хоккейного табло и экосистемы вокруг него
(Android-приложение, Telegram-бот, web-viewer и т. д.).

Сервер принимает JSON-данные, хранит их в файловой базе и автоматически
пересобирает индексы и статистику.

---

## 1. Архитектура

### 1.1. Основные компоненты

* **hockey-api**
  Flask + gunicorn.
  Принимает все `/api/...` запросы, пишет данные в файловую базу.

* **hockey-nginx**
  `nginx:1.27-alpine`.
  Раздаёт JSON-файлы как статические и проксирует `/api/...` → `hockey-api:5001`.

* **Traefik**
  `traefik:v3.1`.
  Front reverse-proxy, HTTPS, автоматические сертификаты Let’s Encrypt.

* **hockey-data (Docker volume)**
  Монтируется как `/var/www/hockey-json`.
  Содержит всю базу данных проекта.

---

## 2. Структура данных

База всегда находится в:

```
/var/www/hockey-json/
```

Краткая структура:

```
/var/www/hockey-json/
  index.json                  # корневой индекс сезонов
  active_game.json            # активная игра
  incoming/                   # универсальный приём любых JSON
  finished/
    <season>/
      index.json              # индекс завершённых игр сезона
      <gameId>.json           # протокол конкретной игры
  stats/
    <season>/
      players.json            # статистика игроков сезона
  rosters/
    roster.json               # составы на ближайшую игру
  settings/
    app_settings.json         # настройки приложения
  base_roster/
    base_players.json         # базовый список игроков + рейтинг
```

**Форматы всех JSON подробно описаны в `SPEC_JSON.md`.**

---

## 3. Структура репозитория

```
hockey-json-server/
  app/
    config.py                 # BASE_DIR, UPLOAD_API_KEY
    upload_api.py             # все API-эндпоинты
  scripts/
    import_db.py              # импорт базы из ZIP
    rebuild_indexes.py        # пересборка индексов и статистики
  docker/
    nginx/hockey-json.conf
  traefik/
    traefik.yml
  Dockerfile
  docker-compose.yml
  requirements.txt
  SPEC_JSON.md
  README.md
  .env.example
```

---

## 4. Требования

* Linux VPS
* Docker Engine
* Docker Compose v2

Проверка:

```bash
docker --version
docker compose version
```

---

## 5. Развёртывание (production)

### 5.1. Клонирование

```bash
git clone https://github.com/your-user/hockey-json-server.git
cd hockey-json-server
```

---

### 5.2. Установка через install.sh (рекомендуется)

В репозитории используется **интерактивный install.sh**, который:

* устанавливает Docker;
* проверяет DNS и IP;
* настраивает Traefik;
* **ждёт реального выпуска сертификата Let’s Encrypt**;
* инициализирует базу.

```bash
chmod +x install.sh
sudo ./install.sh
```

По итогам установки скрипт **обязательно выводит**:

* базовый URL сервера;
* API-ключ;
* путь к volume базы.

---

### 5.3. Вводимые данные при установке

| Параметр    | Пример                                        |
| ----------- | --------------------------------------------- |
| Домен       | hockey-server.pestovo328.ru                   |
| ACME E-mail | [admin@example.com](mailto:admin@example.com) |
| API-ключ    | 3vXjhEr1YvFzgL6gO2fc_                         |

---

## 6. Доступ к API

### 6.1. Базовый URL

Рекомендуемый вариант:

```
https://<DOMAIN>/api/...
```

Все примеры ниже используют HTTPS и домен.

---

### 6.2. Авторизация

Все `/api/...` эндпоинты требуют заголовок:

```
X-Api-Key: <UPLOAD_API_KEY>
```

При отсутствии или неверном ключе сервер возвращает `401 Unauthorized`.

---

## 7. Основные API-эндпоинты

### 7.1. Универсальный приём JSON

**POST** `/api/upload-json`

Сохраняет любой JSON в `incoming/`.

---

### 7.2. Активная игра

**POST** `/api/upload-active-game`

Сохраняет `active_game.json`.

---

### 7.3. Корневой индекс

**POST** `/api/upload-root-index`

Сохраняет `index.json`.

---

### 7.4. Статистика игроков сезона

**POST** `/api/upload-players-stats`

Сохраняет:

```
stats/<season>/players.json
```

---

### 7.5. Базовый список игроков (ключевой для рейтингов)

**POST** `/api/upload-base-roster`

Сохраняет:

```
base_roster/base_players.json
```

#### ВАЖНО

* **full_name является основным идентификатором игрока**.
* Все внешние системы (включая Telegram-бота) **обязаны передавать full_name**.
* `user_id` может отсутствовать или меняться.

Пример:

```json
{
  "version": 1,
  "updatedAt": "2025-12-15T12:00:00",
  "players": [
    {
      "user_id": 1030619743,
      "full_name": "Алексеев Глеб",
      "role": "uni",
      "team": null,
      "rating": 4
    }
  ]
}
```

---

### 7.6. Завершённая игра

**POST** `/api/upload-finished-game`

Сохраняет игру в:

```
finished/<season>/<gameId>.json
```

Автоматически запускает пересборку индексов.

---

### 7.7. Удаление завершённой игры

**POST** `/api/delete-finished-game`

Удаляет файл и пересобирает индексы.

---

### 7.8. Ростер на игру

**POST** `/api/upload-roster`

Полностью очищает `rosters/` и создаёт `rosters/roster.json`.

---

### 7.9. Настройки приложения

**POST** `/api/upload-settings`

Сохраняет `settings/app_settings.json`.

---

### 7.10. Выгрузка всей базы

**GET** `/api/download-db`

Отдаёт ZIP-архив всей базы (`hockey-db.zip`).

---

## 8. Telegram-бот и рейтинги игроков

Telegram-бот **не работает напрямую с Android-базой**.

Его задача:

* формировать файл рейтингов игроков;
* **обязательно указывать `full_name`**;
* отправлять JSON в `/api/upload-base-roster`.

Сервер **не делает слияние**, он хранит файл как есть.
Сопоставление игроков происходит по `full_name`.

---

## 9. Итог

Этот репозиторий является **единственным источником правды** для backend-сервера
хоккейного табло.

Развёртывание нового сервера:

1. `git clone`
2. `sudo ./install.sh`
3. Ввод домена, e-mail, API-ключа
4. Проверка HTTPS и базы

Все клиенты (Android, Telegram, web) обязаны:

* работать через `/api/...`;
* передавать `X-Api-Key`;
* использовать `full_name` как основной идентификатор игрока.
