
#!/usr/bin/env bash
set -e

echo "[backup] Запуск бэкапа $(date)"

# Проверяем обязательные переменные
: "${S3_ENDPOINT:?S3_ENDPOINT is required}"
: "${S3_REGION:?S3_REGION is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_PREFIX:?S3_PREFIX is required}"
: "${S3_ACCESS_KEY_ID:?S3_ACCESS_KEY_ID is required}"
: "${S3_SECRET_ACCESS_KEY:?S3_SECRET_ACCESS_KEY is required}"

DATE_STR="$(date +%F)"   # YYYY-MM-DD
TMP_FILE="/tmp/hockey-db-${DATE_STR}.zip"

# 1. Скачиваем архив базы с hockey-api по внутреннему адресу Docker-сети
echo "[backup] Скачиваю архив базы с hockey-api..."
curl -fSL "http://hockey-api:5001/api/download-db" -o "${TMP_FILE}"

# 2. Загружаем в Selectel S3
S3_URL="s3://${S3_BUCKET}/${S3_PREFIX}hockey-db-${DATE_STR}.zip"
echo "[backup] Загружаю архив в ${S3_URL}..."

AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
AWS_DEFAULT_REGION="${S3_REGION}" \
aws s3 cp "${TMP_FILE}" "${S3_URL}" \
  --endpoint-url "https://${S3_ENDPOINT}"

echo "[backup] Успешно загружено."

# 3. Удаляем временный файл
rm -f "${TMP_FILE}"

echo "[backup] Бэкап завершён."
