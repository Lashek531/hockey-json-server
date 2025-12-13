
FROM debian:12-slim

# Базовые утилиты + cron + Python/pip для awscli
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        cron \
        python3 \
        python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Устанавливаем AWS CLI (будем работать с Selectel через него)
RUN pip3 install --no-cache-dir awscli

# Скрипт бэкапа и crontab
COPY backup.sh /usr/local/bin/backup.sh
COPY crontab /etc/cron.d/hockey-backup

RUN chmod +x /usr/local/bin/backup.sh && \
    chmod 0644 /etc/cron.d/hockey-backup && \
    crontab /etc/cron.d/hockey-backup

# Запускаем cron в foreground, чтобы контейнер не завершался
CMD ["cron", "-f"]
