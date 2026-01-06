#!/usr/bin/env sh
set -eu

# Cron может не наследовать env контейнера.
# Забираем S3_* из окружения PID1 (cron -f), где они гарантированно есть.
if [ -r /proc/1/environ ]; then
  export $(tr '\0' '\n' < /proc/1/environ | grep '^S3_' | xargs -r)
fi

exec /usr/local/bin/backup.sh
