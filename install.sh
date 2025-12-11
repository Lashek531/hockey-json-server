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
    # === Интерактивная проверка URL источника базы ===
    while true; do
      SRC="$DB_SOURCE"

      # Приведение к корректному URL
      if echo "$SRC" | grep -Eq '^https?://'; then
        : # уже полный URL
      else
        # если нет протокола — считаем, что это домен
        if echo "$SRC" | grep -q '/'; then
          SRC="https://$SRC"
        else
          SRC="https://$SRC/api/download-db"
        fi
      fi

      echo -e "${YELLOW}[*] Проверяю доступность: $SRC ...${RESET}"

      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 12 "$SRC" || echo "000")

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

# 5.1. Жёсткий перезапуск стека Docker
restart_stack() {
  echo -e "${YELLOW}[*] Полный перезапуск docker compose (down + up --build)...${RESET}"
  docker compose down
  docker compose up -d --build
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
  # Информационная строка в stderr, чтобы не мешать возвращаемому значению
  echo -e "${YELLOW}[*] Проверяю выпуск HTTPS-сертификата для домена ${dom}...${RESET}" >&2

  local ok=0
  # даём до 24 попыток (до ~2 минут с паузами)
  for i in $(seq 1 24); do
    if curl -sS --max-time 5 "https://$dom/" -o /dev/null; then
      ok=1
      break
    fi
    sleep 5
  done
  echo "$ok"
}

# 6.1. Первая проверка HTTPS
CERT_OK=$(check_https_once "$DOMAIN")

if [ "$CERT_OK" -eq 1 ]; then
  echo -e "${GREEN}[+] HTTPS для https://$DOMAIN/ работает, сертификат принят клиентом.${RESET}"
else
  echo -e "${RED}[!] Не удалось подтвердить работу HTTPS для https://$DOMAIN/ в отведённое время.${RESET}"
  echo
  echo -e "${YELLOW}Проверь, пожалуйста:${RESET}"
  echo "  1) Правильно ли введён домен: $DOMAIN"
  echo "  2) Указывает ли A-запись домена на IP этого сервера"
  echo "  3) Не слишком ли недавно зарегистрирован/изменён домен (нужно время на обновление DNS)"
  echo
  echo -e "${YELLOW}Текущие логи Traefik по ACME/Let's Encrypt (последние 20 строк):${RESET}"
  docker logs traefik 2>/dev/null | grep -Ei 'acme|cert|error' | tail -n 20 || true
  echo

  read -rp "Изменить домен и e-mail и попробовать снова? [y/N]: " RETRY
  case "$RETRY" in
    y|Y|д|Д)
      echo
      echo "Введите НОВЫЙ домен (FQDN), который реально указывает на этот сервер:"
      read -rp "Домен (FQDN): " DOMAIN

      echo
      echo "Введите НОВЫЙ корректный e-mail для Let's Encrypt:"
      while true; do
        read -rp "E-mail для Let's Encrypt: " ACME_EMAIL
        if echo "$ACME_EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; then
          break
        fi
        echo -e "${RED}[!] Похоже, адрес e-mail некорректен. Попробуй ещё раз.${RESET}"
      done

      echo
      echo -e "${BOLD}Новые параметры для HTTPS:${RESET}"
      echo "  Домен:  $DOMAIN"
      echo "  E-mail: $ACME_EMAIL"
      echo

      # Перезаписываем .env с новым доменом и e-mail (API_KEY / DB_* сохраняются)
      write_env
      update_traefik_host

      echo -e "${YELLOW}[*] Перезапускаю docker compose с новыми параметрами домена (full recreate)...${RESET}"
      restart_stack

      CERT_OK=$(check_https_once "$DOMAIN")
      if [ "$CERT_OK" -eq 1 ]; then
        echo -e "${GREEN}[+] HTTPS для https://$DOMAIN/ работает, сертификат принят клиентом.${RESET}"
      else
        echo -e "${RED}[!] Даже после изменения домена/e-mail не удалось подтвердить работу HTTPS.${RESET}"
        echo -e "${YELLOW}Логи Traefik по ACME/Let's Encrypt (последние 20 строк):${RESET}"
        docker logs traefik 2>/dev/null | grep -Ei 'acme|cert|error' | tail -n 20 || true
        echo
        echo "Проверь DNS, настройки домена и логи Traefik:"
        echo "  docker logs traefik | grep -Ei 'acme|cert|error'"
      fi
      ;;
    *)
      echo -e "${YELLOW}Параметры домена не менялись. Продолжаю установку, но HTTPS может быть некорректен.${RESET}"
      ;;
  esac
fi

# 6.2. Краткий отчёт о статусе импорта базы по логам hockey-api
if [ "$DB_MODE" != "none" ]; then
  echo
  echo -e "${YELLOW}[*] Проверяю статус импорта базы по логам hockey-api...${RESET}"
  IMPORT_LOG=$(docker logs hockey-api 2>/dev/null | grep -E "Импорт ZIP" | tail -n 1 || true)

  if echo "$IMPORT_LOG" | grep -qi "успеш"; then
    echo -e "${GREEN}[+] Импорт базы данных (режим ${DB_MODE}) из источника:${RESET}"
    echo "    ${DB_SOURCE}"
    echo -e "${GREEN}    завершился УСПЕШНО.${RESET}"
  elif echo "$IMPORT_LOG" | grep -qi "ошибк"; then
    echo -e "${RED}[!] В логах hockey-api есть сообщение об ошибке при импорте базы.${RESET}"
    echo "    Последняя строка:"
    echo "    $IMPORT_LOG"
    echo
    echo "Рекомендуется проверить логи подробнее:"
    echo "  docker logs hockey-api | grep 'Импорт ZIP' -n"
  else
    echo -e "${YELLOW}[?] Не удалось однозначно определить статус импорта по логам hockey-api.${RESET}"
    echo "При необходимости выполни:"
    echo "  docker logs hockey-api | grep 'Импорт ZIP' -n"
  fi
fi

# 7. ЯРКОЕ ПРЕДУПРЕЖДЕНИЕ ПРО API-КЛЮЧ
echo
echo -e "${RED}${BOLD}ВНИМАНИЕ!${RESET}"

if [ -n "$API_KEY" ]; then
  echo -e "${RED}Ты задал свой API-ключ вручную при установке.${RESET}"
  echo -е "${BOLD}Обязательно запиши его и внеси в настройки Android-приложения:${RESET}"
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
