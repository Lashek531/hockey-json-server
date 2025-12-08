#!/usr/bin/env bash
set -e

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
BOLD="\e[1m"
RESET="\e[0m"

echo -e "${BOLD}=== Hockey JSON Server installer ===${RESET}"
echo

# 1. Проверка root / sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Запусти этот скрипт от root (например: sudo ./install.sh)${RESET}"
  exit 1
fi

# 2. Установка Docker + Docker Compose (если ещё нет)
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${YELLOW}[*] Docker не найден. Устанавливаю Docker Engine и Docker Compose...${RESET}"
  apt update
  apt install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  if ! grep -q 'download.docker.com/linux/ubuntu' /etc/apt/sources.list.d/docker.list 2>/dev/null; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list
  fi
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo -e "${GREEN}[*] Docker уже установлен, пропускаю установку.${RESET}"
fi

echo

# 3. Параметры инсталляции
echo -e "${BOLD}=== Параметры инсталляции ===${RESET}"

echo
echo "Домен (FQDN) — имя, на которое указывает A-запись DNS этого сервера."
echo "Примеры: hockey.example.com, test-server.pestovo328.ru"
read -rp "Домен (FQDN): " DOMAIN

echo
echo "E-mail для Let's Encrypt — будет использоваться для регистрации и уведомлений."
read -rp "E-mail для Let's Encrypt: " ACME_EMAIL

echo
echo "API-ключ — секрет для авторизации всех /api/... запросов."
echo "Если оставить пустым, ключ будет сгенерирован контейнером автоматически при первом старте."
echo "Этот ключ нужно будет указать в Android-приложении в настройках сервера."
read -rp "API-ключ (можно оставить пустым, чтобы сгенерировался автоматически): " API_KEY

echo
echo -e "${BOLD}=== Параметры импорта базы ===${RESET}"
echo "Режим импорта:"
echo "  none  - не импортировать (создать пустую базу)"
echo "  local - импорт из ZIP-файла, доступного на ЭТОМ сервере"
echo "  url   - импорт из ZIP по HTTP/HTTPS URL"
read -rp "DB_IMPORT_MODE [none]: " DB_MODE
DB_MODE=${DB_MODE:-none}

DB_SOURCE=""

if [ "$DB_MODE" = "local" ]; then
  echo
  echo "Укажи путь к ZIP-файлу на ЭТОМ сервере, например: /opt/backups/hockey-db.zip"
  read -rp "DB_IMPORT_SOURCE (путь к файлу, Enter — отменить импорт): " DB_SOURCE

  if [ -z "$DB_SOURCE" ]; then
    echo -e "${YELLOW}Источник не указан, импорт отключён. DB_IMPORT_MODE будет установлено в 'none'.${RESET}"
    DB_MODE="none"
    DB_SOURCE=""
  else
    if [ ! -f "$DB_SOURCE" ]; then
      echo -e "${RED}[!] Файл '$DB_SOURCE' не найден. Импорт отключён, чтобы сервис не упал.${RESET}"
      DB_MODE="none"
      DB_SOURCE=""
    else
      echo -e "${GREEN}[*] Локальный ZIP-файл найден: $DB_SOURCE${RESET}"
    fi
  fi

elif [ "$DB_MODE" = "url" ]; then
  echo
  echo "Можно указать либо:"
  echo "  - полный URL ZIP-файла (например: https://old-server.example.com/hockey-db.zip),"
  echo "  - либо просто домен старого сервера (например: old-hockey.example.com)."
  echo "Во втором случае будет использован URL: https://<домен>/api/download-db"
  read -rp "DB_IMPORT_SOURCE (URL или домен старого сервера, Enter — отменить импорт): " DB_SOURCE

  if [ -z "$DB_SOURCE" ]; then
    echo -e "${YELLOW}Источник не указан, импорт отключён. DB_IMPORT_MODE будет установлено в 'none'.${RESET}"
    DB_MODE="none"
    DB_SOURCE=""
  else
    # Нормализуем: домен → https://domain/api/download-db, если нет явного протокола
    if echo "$DB_SOURCE" | grep -Eq '^https?://'; then
      # Уже полный URL
      :
    else
      # Нет протокола — считаем, что это домен/хост
      if echo "$DB_SOURCE" | grep -q '/'; then
        # Есть слэши, но нет http — добавим https:// в начало и оставим путь как есть
        DB_SOURCE="https://$DB_SOURCE"
      else
        # Просто домен — приклеим типичный путь download-db
        DB_SOURCE="https://$DB_SOURCE/api/download-db"
      fi
      echo -e "${YELLOW}Будет использован URL для импорта: ${DB_SOURCE}${RESET}"
    fi

    echo -e "${YELLOW}[*] Проверяю доступность URL для импортa базы...${RESET}"
    if ! curl -sSf -m 10 -I "$DB_SOURCE" >/dev/null 2>&1; then
      echo -e "${RED}[!] Не удалось обратиться к '$DB_SOURCE'.${RESET}"
      echo -e "${RED}[!] Импорт базы по URL отключён, чтобы сервис не упал при старте.${RESET}"
      DB_MODE="none"
      DB_SOURCE=""
    else
      echo -e "${GREEN}[*] URL доступен, импорт по URL будет выполнен при первом старте.${RESET}"
    fi
  fi
fi

echo
echo -e "${BOLD}Резюме параметров:${RESET}"
echo "  Домен:            $DOMAIN"
echo "  E-mail (ACME):    $ACME_EMAIL"
if [ -n "$API_KEY" ]; then
  echo "  API-ключ:         (задан вручную)"
else
  echo "  API-ключ:         будет сгенерирован автоматически контейнером"
fi
echo "  DB_IMPORT_MODE:   $DB_MODE"
echo "  DB_IMPORT_SOURCE: $DB_SOURCE"
echo

# 4. Генерация .env
echo -e "${YELLOW}[*] Записываю .env...${RESET}"
cat > .env <<EOF
UPLOAD_API_KEY=${API_KEY}

TRAEFIK_HOST=${DOMAIN}
TRAEFIK_ACME_EMAIL=${ACME_EMAIL}

DB_IMPORT_MODE=${DB_MODE}
DB_IMPORT_SOURCE=${DB_SOURCE}
DB_FORCE_RESET=false
EOF

echo "[*] Содержимое .env:"
cat .env
echo

# 5. Обновление traefik/traefik.yml — подставляем домен
echo -e "${YELLOW}[*] Обновляю traefik/traefik.yml под домен ${DOMAIN}...${RESET}"
if grep -q "Host(\`hockey.example.com\`)" traefik/traefik.yml 2>/dev/null; then
  sed -i "s/Host(\`hockey.example.com\`)/Host(\`$DOMAIN\`)/g" traefik/traefik.yml
else
  echo -e "${YELLOW}[!] Внимание: в traefik/traefik.yml не найден Host(\`hockey.example.com\`). Файл не изменён.${RESET}"
fi

# 6. Первый запуск docker compose
echo -e "${YELLOW}[*] Запускаю docker compose up -d --build...${RESET}"
docker compose up -d --build

echo
echo "Проверь контейнеры:"
echo "  docker compose ps"
echo
echo "Проверь HTTPS в браузере:"
echo "  https://$DOMAIN/"
echo

# 7. ЯРКОЕ ПРЕДУПРЕЖДЕНИЕ ПРО API-КЛЮЧ
echo
echo -e "${RED}${BOLD}ВНИМАНИЕ!${RESET}"

if [ -n "$API_KEY" ]; then
  echo -e "${RED}Ты задал свой API-ключ вручную при установке.${RESET}"
  echo -e "${BOLD}Обязательно запиши его и внеси в настройки Android-приложения:${RESET}"
  echo
  echo -e "  ${BOLD}API-ключ:${RESET} $API_KEY"
  echo
else
  echo -e "${YELLOW}Ты оставил поле API-ключа пустым — ключ сгенерирован автоматически контейнером.${RESET}"
  echo -e "${BOLD}Тебе ОБЯЗАТЕЛЬНО нужно его посмотреть и сохранить для Android-приложения!${RESET}"
  echo
  echo "Команда для получения API-ключа:"
  echo "  docker logs hockey-api | grep \"API Key\" | tail -n 1"
  echo

  GENERATED_KEY=$(docker logs hockey-api 2>/dev/null | grep "API Key" | tail -n 1 | sed 's/.*API Key: //')
  if [ -n "$GENERATED_KEY" ]; then
    echo -e "${GREEN}Автоматически найден сгенерированный ключ:${RESET}"
    echo
    echo -e "  ${BOLD}API-ключ:${RESET} $GENERATED_KEY"
    echo
  else
    echo -e "${RED}Не удалось автоматически прочитать ключ из логов.${RESET}"
    echo "Выполни команду вручную и запиши ключ:"
    echo "  docker logs hockey-api | grep \"API Key\" | tail -n 1"
    echo
  fi
fi

echo -e "${BOLD}Без правильного API-ключа Android-приложение НЕ сможет синхронизировать базу.${RESET}"
echo
echo "Дальше:"
echo "  1) Запиши/сохрани API-ключ."
echo "  2) Открой приложение на Android и внеси:"
echo "     - адрес сервера: https://$DOMAIN"
echo "     - API-ключ: (тот, который записал)"
echo "  3) Проверь синхронизацию."
echo
echo -e "${GREEN}=== Установка завершена ===${RESET}"
echo
