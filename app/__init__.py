from flask import Flask


def create_app() -> Flask:
    """
    Фабрика приложения для gunicorn / Docker.

    ВАЖНО:
    - Не создаём новый Flask здесь.
    - Просто импортируем существующий upload_api,
      где уже создан app = Flask(__name__) и навешаны все роуты.
    - Возвращаем этот же экземпляр, чтобы поведение осталось 1:1.
    """
    from . import upload_api  # noqa: F401

    return upload_api.app
