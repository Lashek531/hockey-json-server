FROM python:3.12-slim

WORKDIR /app

# Установим системные зависимости при необходимости (сейчас минимальный набор)
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Зависимости Python
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Код приложения
COPY app /app/app
COPY scripts /app/scripts
COPY entrypoint.sh /app/entrypoint.sh

# Директория базы по умолчанию
ENV BASE_DIR=/var/www/hockey-json

# Экспортируем порт gunicorn
EXPOSE 5001

ENTRYPOINT ["/app/entrypoint.sh"]
