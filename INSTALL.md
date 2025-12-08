# Установка Hockey JSON Server с нуля

Этот документ описывает, как развернуть Hockey JSON Server на любом VPS с Docker и Traefik (HTTPS + Let's Encrypt), импортировать базу и проверить работу.

Сервер принимает JSON из Android-приложения и вспомогательных утилит, хранит их в файловой структуре, пересчитывает индексы и статистику, и раздаёт готовые JSON по HTTPS для веб‑табло и интеграций.

---

> ⚠️ **ВАЖНО ПРО API-КЛЮЧ**
>
> Все запросы к HTTP API (`/api/...`) защищены заголовком:
>
> ```http
> X-Api-Key: <UPLOAD_API_KEY>
> ```
>
> Этот ключ:
>
> * задаётся при установке (через переменную `UPLOAD_API_KEY` или через `install.sh`), **или**
> * генерируется автоматически контейнером `hockey-api`, если `UPLOAD_API_KEY` не указан.
>
> **Этот ключ ОБЯЗАТЕЛЬНО нужно сохранить и внести в Android‑приложение**, иначе синхронизация работать не будет.
>
> Получить фактический API‑ключ после первого запуска:
>
> ```bash
> docker logs hockey-api | grep "API Key" | tail -n 1
> ```

---

# 0. Быстрая автоматическая установка (рекомендуется)

1. Перейти в `/opt` и клонировать репозиторий:

```bash
dd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server
```

2. Убедиться, что установщик исполняемый:

```bash
chmod +x install.sh
```

3. Запустить установку:

```bash
sudo ./install.sh
```

4. Ввести необходимые параметры:

   * домен (FQDN), например `hockey.example.com`;
   * e-mail для Let's Encrypt;
   * API‑ключ или оставить пустым (будет сгенерирован);
   * режим импорта базы (`none`, `local`, `url`).

Скрипт:

* установит Docker (если нужно),
* создаст `.env`,
* пропишет домен в Traefik,
* запустит сервер командой `docker compose up -d --build`.

5. Проверить контейнеры:

```bash
docker compose ps
```

6. Проверить доступность HTTPS в браузере:

```
https://<твой‑домен>/
```

7. **Обязательно сохранить API‑ключ.**
   Если ключ автоматически сгенерирован:

```bash
docker logs hockey-api | grep "API Key" | tail -n 1
```

8. Внести в Android‑приложение:

* адрес сервера: `https://<домен>/`
* API‑ключ.

---

# 1. Предварительные требования (ручная установка)

1. VPS на Linux (Ubuntu/Debian).
2. Права root / доступ через sudo.
3. Открыты порты 80 и 443.
4. Настроена A‑запись DNS.
5. Установлен Docker + Docker Compose.

Проверка:

```bash
docker --version
docker compose version
```

---

# 2. Клонирование репозитория

```bash
cd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server
```

---

# 3. Настройка окружения (.env)

Создать `.env`:

```bash
cp .env.example .env
nano .env
```

### 3.1. Настройка домена и почты

```env
TRAEFIK_HOST=hockey.example.com
TRAEFIK_ACME_EMAIL=admin@example.com
```

### 3.2. API‑ключ

```env
UPLOAD_API_KEY=
```

Если пустой — будет сгенерирован.

### 3.3. Импорт базы

```env
DB_IMPORT_MODE=none
DB_IMPORT_SOURCE=
```

Варианты:

* `none` — пустая база;
* `local` — путь к ZIP внутри контейнера;
* `url` — скачивание ZIP.

---

# 4. Первый запуск вручную

```bash
docker compose up -d --build
```

Проверить:

```bash
docker compose ps
```

Если контейнеры `Exited` — смотреть логи:

```bash
docker logs traefik
docker logs hockey-api
docker logs hockey-nginx
```

---

# 5. API‑ключ и инициализация

Получение ключа:

```bash
docker logs hockey-api | grep "API Key" | tail -n 1
```

Пример:

```
API Key: hockey_XXXXXX_KEY
```

Обязательно внести его в Android‑приложение.

---

# 6. Проверка HTTPS и API

### 6.1. Проверка HTTPS

Открыть:

```
https://<домен>/
```

Должен быть Let’s Encrypt.

### 6.2. Проверка API

```bash
curl "https://<домен>/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <API_KEY>" \
  -d '{"test": "install-check"}'
```

### 6.3. Проверка выгрузки базы

```bash
curl -H "X-Api-Key: <API_KEY>" \
  "https://<домен>/api/download-db" \
  --output hockey-db-test.zip
```

---

# 7. Импорт базы при первом запуске

### 7.1. Импорт из локального ZIP

```bash
DB_IMPORT_MODE=local
DB_IMPORT_SOURCE=/opt/backups/hockey-db.zip
```

### 7.2. Импорт по URL

```bash
DB_IMPORT_MODE=url
DB_IMPORT_SOURCE=https://example.com/hockey-db.zip
```

### 7.3. Повторный импорт

```bash
docker compose down
docker volume rm hockey-json-server_hockey-data
docker compose up -d --build
```

---

# 8. Обновление версии сервера

```bash
cd /opt/hockey-json-server
git pull
docker compose up -d --build
```

---

# 9. Краткая памятка

### Быстрая установка

```bash
cd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server
sudo ./install.sh
```

### Проверка API

```bash
curl "https://<DOMAIN>/api/upload-json" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <API_KEY>" \
  -d '{"test": "ok"}'
```

### Экспорт базы

```
GET /api/download-db
```

Все форматы JSON описаны в `SPEC_JSON.md`.
