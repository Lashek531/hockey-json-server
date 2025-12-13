
FROM debian:12-slim

# Базовые утилиты + cron + awscli (через apt)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        cron \
        awscli && \
    rm -rf /var/lib/apt/lists/*


# Скрипт бэкапа и crontab
COPY backup.sh /usr/local/bin/backup.sh
COPY crontab /etc/cron.d/hockey-backup

RUN chmod +x /usr/local/bin/backup.sh && \
    chmod 0644 /etc/cron.d/hockey-backup && \
    crontab /etc/cron.d/hockey-backup

# Запускаем cron в foreground, чтобы контейнер не завершался
CMD ["cron", "-f"]
