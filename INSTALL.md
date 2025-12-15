# Установка Hockey JSON Server с нуля

Этот документ описывает, как развернуть Hockey JSON Server на любом VPS с Docker и Traefik (HTTPS + Let's Encrypt), импортировать базу и проверить работу.

Сервер принимает JSON из Android‑приложения и вспомогательных утилит, хранит их в файловой структуре, пересчитывает индексы и статистику, и раздаёт готовые JSON по HTTPS для веб‑табло и интеграций.

---

## Что нужно сделать ПОСЛЕ установки базового сервера

После развёртывания нового сервера (или переноса на другой VPS) необходимо обновить настройки в **двух клиентах**: Android‑приложении и веб‑табло (AppMorty).

Эти изменения обязательны, иначе клиенты будут обращаться к старому серверу или использовать неправильный API‑ключ.

### 1. Настроить Android‑приложение

В Android‑приложении требуется обновить:

1. **Адрес сервера (base URL)**

```
https://<твой-домен>/
```

2. **API‑ключ (UPLOAD_API_KEY)**

Это ключ, который:

* либо был задан вручную при установке;
* либо автоматически сгенерирован контейнером `hockey-api`.

Получить фактический API‑ключ после установки:

```bash
docker logs hockey-api | grep "API Key" | tail -n 1
```

Без обновления этих параметров приложение **не сможет отправлять JSON** на сервер.

---

### 2. Настроить веб‑табло (AppMorty)

Веб‑табло получает данные **напрямую с сервера по HTTPS**, по адресу `API_BASE_URL`.

Если сервер перенесён или изменился домен, нужно изменить **одну константу в коде**:

```js
// Было
const API_BASE_URL = "https://old-server.example.com";

// Стало
const API_BASE_URL = "https://<новый-домен>/";
```

После изменения — закоммитить и запушить файл в GitHub.
GitHub Pages автоматически обновит веб‑табло, и все пользователи начнут получать данные с нового сервера.

---

> ⚠️ **ВАЖНО ПРО API‑КЛЮЧ**
>
> Все запросы к HTTP API (`/api/...`) защищены заголовком:
>
> ```http
> X-Api-Key: <UPLOAD_API_KEY>
> ```
>
> Этот ключ:
>
> * задаётся при установке (через `UPLOAD_API_KEY` или `install.sh`), **или**
> * генерируется автоматически контейнером `hockey-api`.
>
> **Ключ ОБЯЗАТЕЛЬНО нужно сохранить и внести в Android‑приложение**, иначе синхронизация не будет работать.

---

## 0. Быстрая автоматическая установка (рекомендуется)

```bash
cd /opt
git clone https://github.com/Lashek531/hockey-json-server.git
cd hockey-json-server
chmod +x install.sh
sudo ./install.sh
```

Во время установки потребуется ввести:

* домен (FQDN);
* e‑mail для Let's Encrypt;
* API‑ключ (или оставить пустым);
* режим импорта базы (`none`, `local`, `url`).

После завершения:

```bash
docker compose ps
```

Проверить в браузере:

```
https://<домен>/
```

---

## 1. Предварительные требования

* VPS с Linux (Ubuntu / Debian)
* Права root / sudo
* Открыты порты **80 и 443**
* Настроена A‑запись DNS
* Docker + Docker Compose v2

Проверка:

```bash
docker --version
docker compose version
```

---

## 2. Ручной запуск (без install.sh)

```bash
cp .env.example .env
nano .env
```

Минимальные параметры:

```env
TRAEFIK_HOST=hockey.example.com
TRAEFIK_ACME_EMAIL=admin@example.com
UPLOAD_API_KEY=
DB_IMPORT_MODE=none
```

Запуск:

```bash
docker compose up -d --build
```

---

## 3. Проверка API

```bash
curl -k https://<домен>/api/upload-json \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <API_KEY>" \
  -d '{"test":"install-check"}'
```

---

## 4. Импорт базы

### Из локального ZIP

```env
DB_IMPORT_MODE=local
DB_IMPORT_SOURCE=/opt/backups/hockey-db.zip
```

### По URL

```env
DB_IMPORT_MODE=url
DB_IMPORT_SOURCE=https://example.com/hockey-db.zip
```

---

## 5. Обновление версии сервера

```bash
cd /opt/hockey-json-server
git pull
docker compose up -d --build
```

---

## Итог

1. Запустить `install.sh`
2. Проверить HTTPS
3. Сохранить API‑ключ
4. Обновить Android‑приложение
5. Обновить веб‑табло

После этого сервер полностью готов к работе.
