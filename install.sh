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

# 2.2. openssl нужен для проверки сертификата
if ! command -v openssl >/dev/null 2>&1; then
  echo -e "${YELLOW}[*] openssl не найден. Устанавливаю openssl...${RESET}"
  apt update
  apt install -y openssl
fi

echo

# 2.1. Определяем публичный IP этого сервера (для проверки A-записи домена)
SERVER_IP=""
if command -v curl >/dev/null 2>&1; then
  SERVER_IP=$(curl -s https://ifconfig.me 2>/dev/null || curl -s https://api.ipify.org 2>/dev/null || echo "")
fi

if [ -n "$SERVER_IP" ]; then
  echo -e "${YELLOW}[*] Определён публичный IP этого сервера:${RESET} ${BOLD}${SERVER_IP}${RESET}"
else
  echo -e "${YELLOW}[!] Не удалось автоматически определить публичный IP сервера. Проверка A-записи домена будет поверхностной.${RESET}"
fi

# Вспомогательное: имя compose-проекта (если не задано явно)
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$(pwd)")}"
VOLUME_NAME="${PROJECT_NAME}_hockey-data"

# 3. Параметры инсталляции
echo -e "${BOLD}=== Параметры инсталляции ===${RESET}"
echo
echo "Домен (FQDN) — имя, на которое указывает A-запись DNS этого сервера."
echo "Примеры: hockey.example.com, test-server.pestovo328.ru"
read -rp "Домен (FQDN): " DOMAIN

echo
echo "E-mail для Let's Encrypt — будет использоваться для регистрации и уведомлений."
while true; do
  read -rp "E-mail для Let's Encrypt: " ACME_EMAIL
  if echo "$ACME_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
    break
  fi
  echo -e "${RED}[!] Похоже, адрес e-mail некорректен. Попробуй ещё раз (формат: что-то@домен.tld).${RESET}"
done

echo
echo "API-ключ — секрет для авторизации всех /api/... запросов."
echo "Если оставить пустым, ключ будет сгенерирован контейнером автоматически при первом старте."
echo "Этот ключ нужно будет указать в Android-приложении в настройках сервера."
read -rp "API-ключ (можно оставить пустым, чтобы сгенерировался автоматически): " API_KEY

echo
echo -e "${BOLD}=== Параметры импорта базы ===${RESET}"
echo "Выбери режим импорта:"
echo "  1) Не импортировать (создать пустую базу)"
echo "  2) Импорт из локального ZIP-файла на этом сервере"
echo "  3) Импорт по HTTP/HTTPS (download-db с другого сервера)"
read -rp "Режим импорта [1]: " DB_MODE_CHOICE

case "$DB_MODE_CHOICE" in
  2) DB_MODE="local" ;;
  3) DB_MODE="url" ;;
  ""|1) DB_MODE="none" ;;
  *)
    echo -e "${YELLOW}Неизвестный выбор, будет использован режим 'none'.${RESET}"
    DB_MODE="none"
    ;;
esac

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
  echo "Укажи источник базы:"
  echo "  - либо ПОЛНЫЙ URL ZIP-файла,"
  echo "  - либо просто домен старого сервера (например: hockey.ch73210.keenetic.pro:8443)."
  echo "Если введён домен — будет использован URL вида:"
  echo "    https://<домен>/api/download-db"
  echo
  echo "Enter — отмена импорта."
  read -rp "DB_IMPORT_SOURCE: " DB_SOURCE

  if [ -z "$DB_SOURCE" ]; then
    echo -e "${YELLOW}Импорт отключён по выбору пользователя.${RESET}"
    DB_MODE="none"
    DB_SOURCE=""
  else
    while true; do
      SRC="$DB_SOURCE"

      if echo "$SRC" | grep -Eq '^https?://'; then
        :
      else
        if echo "$SRC" | grep -q '/'; then
          SRC="https://$SRC"
        else
          SRC="https://$SRC/api/download-db"
        fi
      fi

      echo -e "${YELLOW}[*] Проверяю доступность: $SRC ...${RESET}"
      HTTP_CODE=$(curl -s -L -k -o /dev/null -w "%{http_code}" -m 15 "$SRC" || echo "000")

      if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
        echo -e "${GREEN}URL доступен (HTTP $HTTP_CODE). Импорт будет выполнен.${RESET}"
        DB_SOURCE="$SRC"
        break
      fi

      echo -e "${RED}[!] URL недоступен. Код ответа: $HTTP_CODE${RESET}"
      echo
      echo "  1) Ввести другой URL/домен"
      echo "  2) Отменить импорт"
      read -rp "Выбор [1/2]: " CH

      case "$CH" in
        1)
          read -rp "Новый URL или домен: " DB_SOURCE
          if [ -z "$DB_SOURCE" ]; then
            echo -e "${YELLOW}Пустая строка — импорт отменён.${RESET}"
            DB_MODE="none"
            DB_SOURCE=""
            break
          fi
          ;;
        2)
          echo -e "${YELLOW}Импорт отключён по выбору пользователя.${RESET}"
          DB_MODE="none"
          DB_SOURCE=""
          break
          ;;
        *)
          echo "Введите 1 или 2."
          ;;
      esac
    done
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
write_env() {
  echo -e "${YELLOW}[*] Записываю .env...${RESET}"

  local FORCE_RESET="false"
  if [ "$DB_MODE" != "none" ]; then
    FORCE_RESET="true"
  fi

  cat > .env <<EOF
UPLOAD_API_KEY=${API_KEY}

TRAEFIK_HOST=${DOMAIN}
TRAEFIK_ACME_EMAIL=${ACME_EMAIL}

DB_IMPORT_MODE=${DB_MODE}
DB_IMPORT_SOURCE=${DB_SOURCE}
DB_FORCE_RESET=${FORCE_RESET}
EOF

  echo "[*] Содержимое .env:"
  cat .env
  echo
}

# 5. Обновляем traefik/*.yml под домен
update_traefik_host() {
  echo -e "${YELLOW}[*] Обновляю traefik/*.yml под домен ${DOMAIN}...${RESET}"

  local changed=0
  for f in traefik/*.yml; do
    [ -f "$f" ] || continue
    if grep -q "Host(\`" "$f" 2>/dev/null; then
      sed -i "s/Host(\`[^\\\`]*\`)/Host(\`$DOMAIN\`)/g" "$f"
      echo -e "${GREEN}  - Обновлён файл:${RESET} $f"
      grep -n "Host(\`" "$f" || true
      changed=1
    fi
  done

  if [ "$changed" -eq 0 ]; then
    echo -e "${YELLOW}[!] Внимание: ни в одном из traefik/*.yml не найдено Host(\`...\`). Нечего обновлять.${RESET}"
  fi
}

# Ожидание, пока контейнер существует в docker (после up)
wait_container() {
  local name="$1"
  local tries=40
  while [ "$tries" -gt 0 ]; do
    if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
      return 0
    fi
    sleep 0.5
    tries=$((tries-1))
  done
  return 1
}

# 5.1. Полный перезапуск стека Docker + (если выбран импорт) принудительный запуск импорта
restart_stack() {
  echo -e "${YELLOW}[*] Полный перезапуск docker compose (down + up --build)...${RESET}"
  docker compose down
  docker compose up -d --build

  if [ "$DB_MODE" != "none" ]; then
    echo -e "${YELLOW}[*] Выбран импорт базы: сбрасываю флаг /var/www/hockey-json/.initialized...${RESET}"

    if ! wait_container "hockey-api"; then
      echo -e "${RED}[!] Контейнер hockey-api не появился после запуска. Проверь docker compose ps.${RESET}"
      return 1
    fi

    docker exec -it hockey-api sh -lc 'rm -f /var/www/hockey-json/.initialized || true'
    echo -e "${YELLOW}[*] Перезапускаю hockey-api для выполнения импорта...${RESET}"
    docker compose restart hockey-api
    sleep 2
  fi
}

write_env
update_traefik_host

# 6. Первый запуск docker compose
echo -e "${YELLOW}[*] Запускаю docker compose (полный перезапуск)...${RESET}"
restart_stack

echo
echo "Проверь контейнеры:"
echo "  docker compose ps"
echo

check_https_once() {
  local dom="$1"

  echo -e "${YELLOW}[*] Проверяю выпуск HTTPS-сертификата для домена ${dom}...${RESET}" >&2

  # Проверяем A-запись домена
  if [ -n "$SERVER_IP" ]; then
    local dom_ip
    dom_ip=$(getent ahostsv4 "$dom" 2>/dev/null | awk 'NR==1 {print $1}' || true)

    if [ -z "$dom_ip" ]; then
      echo -e "${RED}[!] Домен ${dom} не резолвится в IPv4-адрес.${RESET}" >&2
      echo 0
      return
    fi

    if [ "$dom_ip" != "$SERVER_IP" ]; then
      echo -e "${RED}[!] Домен ${dom} указывает на IP ${dom_ip}, а этот сервер имеет IP ${SERVER_IP}.${RESET}" >&2
      echo 0
      return
    fi
  fi

  # 1) Ждём, пока HTTPS вообще начнёт отвечать (без требований к доверию)
  local reachable=0
  for _ in $(seq 1 24); do
    if curl -sS -k --max-time 5 "https://$dom/" -o /dev/null; then
      reachable=1
      break
    fi
    sleep 5
  done

  if [ "$reachable" -ne 1 ]; then
    echo -e "${RED}[!] HTTPS не отвечает (даже с -k).${RESET}" >&2
    echo 0
    return
  fi

  # 2) Проверяем, что сертификат УЖЕ доверенный (без -k)
  if curl -sS --max-time 8 "https://$dom/" -o /dev/null; then
    # 3) Дополнительно проверяем, что не отдан дефолтный TRAEFIK DEFAULT CERT
    local cert_subj
    cert_subj=$(echo | openssl s_client -connect "$dom:443" -servername "$dom" 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null | tr -d '\r' || true)

    if echo "$cert_subj" | grep -q "TRAEFIK DEFAULT CERT"; then
      echo -e "${RED}[!] HTTPS отвечает, но выдан TRAEFIK DEFAULT CERT (не Let's Encrypt).${RESET}" >&2
      echo 0
      return
    fi

    echo 1
    return
  fi

  # Если доверенная проверка не прошла — печатаем диагностику сертификата
  echo -e "${YELLOW}[!] HTTPS отвечает, но доверенная проверка (без -k) не прошла.${RESET}" >&2
  echo -e "${YELLOW}    Диагностика сертификата:${RESET}" >&2
  echo | openssl s_client -connect "$dom:443" -servername "$dom" 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates 2>/dev/null >&2 || true

  echo 0
}

# 6.1. Проверка HTTPS (строго: доверенный сертификат и не дефолтный)
CERT_OK=$(check_https_once "$DOMAIN")

if [ "$CERT_OK" -eq 1 ]; then
  echo -e "${GREEN}[+] HTTPS для https://$DOMAIN/ в порядке: сертификат доверенный, не TRAEFIK DEFAULT CERT.${RESET}"
else
  echo -e "${RED}[!] HTTPS для https://$DOMAIN/ НЕ подтверждён как доверенный сертификат.${RESET}"
  echo
  echo -e "${YELLOW}Логи Traefik по ACME/Let's Encrypt (последние 50 строк):${RESET}"
  docker logs traefik 2>/dev/null | grep -Ei 'acme|let.?s encrypt|challenge|cert|error|unable|timeout|forbidden|Register|new-order' | tail -n 50 || true
  echo
fi

# 6.2. Надёжная проверка базы (истина) — по /var/www/hockey-json/index.json внутри контейнера
echo
echo -e "${YELLOW}[*] Проверяю наличие базы по корневому index.json...${RESET}"

if docker exec -it hockey-api sh -lc '[ -s /var/www/hockey-json/index.json ]'; then
  echo -e "${GREEN}[+] База обнаружена: /var/www/hockey-json/index.json существует и не пустой.${RESET}"

  CUR_SEASON=$(docker exec -it hockey-api sh -lc 'python -c "import json; print(json.load(open(\"/var/www/hockey-json/index.json\",\"r\",encoding=\"utf-8\")).get(\"currentSeason\",\"\"))" 2>/dev/null' | tr -d '\r' || true)
  if [ -n "$CUR_SEASON" ]; then
    echo -e "${GREEN}    currentSeason:${RESET} $CUR_SEASON"
  fi
else
  echo -e "${RED}[!] База НЕ обнаружена: /var/www/hockey-json/index.json отсутствует или пустой.${RESET}"
  echo
  echo -e "${YELLOW}Диагностика (последние 200 строк хоккей-api):${RESET}"
  docker logs hockey-api --tail=200 || true
  echo
  echo -e "${YELLOW}Содержимое /var/www/hockey-json внутри контейнера:${RESET}"
  docker exec -it hockey-api ls -la /var/www/hockey-json || true
fi

# 6.3. Подсказка: где физически лежит volume (для WinSCP)
echo
echo -e "${YELLOW}[*] Где лежит база на хосте (для WinSCP):${RESET}"
if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  MP=$(docker volume inspect "$VOLUME_NAME" --format '{{.Mountpoint}}' | tr -d '\r')
  echo -e "  Volume: ${BOLD}${VOLUME_NAME}${RESET}"
  echo -e "  Mountpoint: ${BOLD}${MP}${RESET}"
else
  echo -e "${YELLOW}[!] Volume ${VOLUME_NAME} не найден. Проверь docker volume ls.${RESET}"
fi

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
  echo "  docker logs хоккей-api | grep \"API Key\" | tail -n 1"
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
