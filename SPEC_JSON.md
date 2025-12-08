Спецификация JSON-форматов (Hockey JSON)

Этот документ описывает структуру всех используемых JSON-файлов, которые читает и пишет backend Hockey JSON Server.

Секции:

1. Active/FinishedGame JSON (`active_game.json`, `finished/<season>/<id>.json`)
2. Корневой индекс сезонов (`index.json`)
3. Индекс игр сезона (`finished/<season>/index.json`)
4. Статистика игроков сезона (`stats/<season>/players.json`)
5. Result JSON (экспорт для TelegramBot)
6. Roster JSON (входной от TelegramBot)
7. Настройки приложения (`settings/app_settings.json`)
8. Базовый список игроков (`base_roster/base_players.json`)

---

## 1. Active/FinishedGame JSON

### 1.1. Расположение

- Активная игра:

  ```text
  /var/www/hockey-json/active_game.json


Завершённые игры:

/var/www/hockey-json/finished/<season>/<id>.json


Формат один и тот же.

1.2. Корневые поля
{
  "id": "2025-12-07_13-07-18_pestovo",
  "gameId": "2025-12-07_13-07-18_pestovo",
  "arena": "Пестово Арена",
  "date": "2025-12-07T13:07:18",
  "season": "25-26",
  "finished": true,
  "externalEventId": "11",
  "teams": { },
  "finalScore": { },
  "goals": [],
  "rosterChanges": []
}


Поля:

id — идентификатор игры; используется как имя файла <id>.json в finished/<season>/.

gameId — дублирующий идентификатор игры (совпадает с id).

arena — название арены (строка).

date — дата/время начала игры (строка, формат типа ISO 8601).

season — идентификатор сезона ("24-25", "25-26" и т. п.).

finished — признак завершённой игры (true / false).

externalEventId — строковый ID внешнего события (привязка к TelegramBot и т. п.).

teams — объект с командами (см. ниже).

finalScore — итоговый счёт (см. ниже).

goals — массив голов в хронологическом порядке.

rosterChanges — массив изменений составов.

1.3. Объект teams
"teams": {
  "RED": {
    "name": "Красные",
    "players": [
      "Павликов Олег",
      "Коптевский Юрий",
      "Павликов Вадим"
    ]
  },
  "WHITE": {
    "name": "Белые",
    "players": [
      "Павликов Сергей",
      "Третьяков Лев"
    ]
  }
}


Ключи верхнего уровня: "RED", "WHITE" (коды команд).

name — отображаемое имя команды.

players — массив строк с ФИО игроков (как показывается на табло).

1.4. Объект finalScore
"finalScore": {
  "RED": 8,
  "WHITE": 4
}


Ключи — коды команд ("RED", "WHITE").

Значения — количество заброшенных шайб (целые).

1.5. Массив goals

Каждый элемент:

{
  "team": "WHITE",
  "scoreAfter": "0:1",
  "scorer": "Павликов Сергей",
  "assist1": "Третьяков Лев",
  "assist2": null,
  "order": 1
}


Поля:

team — "RED" или "WHITE".

scoreAfter — счёт после этого гола, строкой ("7:3", "8:4" и т. п.).

scorer — имя автора гола (строка).

assist1 — имя первого ассистента или null.

assist2 — имя второго ассистента или null.

order — порядковый номер гола в матче (1, 2, 3, …).

1.6. Массив rosterChanges
"rosterChanges": [
  {
    "order": 1,
    "player": "Игрок 3",
    "fromTeam": "WHITE",
    "toTeam": "RED"
  }
]


Поля:

order — порядковый номер изменения (целое).

player — имя игрока.

fromTeam — исходная команда ("RED" / "WHITE").

toTeam — новая команда ("RED" / "WHITE").

2. Корневой индекс сезонов (index.json)
2.1. Расположение
/var/www/hockey-json/index.json

2.2. Формат
{
  "currentSeason": "25-26",
  "seasons": [
    {
      "id": "25-26",
      "name": "Сезон 25–26",
      "finishedIndex": "finished/25-26/index.json",
      "playersStats": "stats/25-26/players.json",
      "activeGame": "active_game.json"
    }
  ]
}


Поля:

currentSeason — id текущего сезона (строка).

seasons — массив описаний сезонов:

id — идентификатор сезона ("24-25", "25-26").

name — человекочитаемое имя.

finishedIndex — относительный путь к индексу завершённых игр.

playersStats — относительный путь к статистике игроков.

activeGame — относительный путь к файлу активной игры.

3. Индекс игр сезона (finished/<season>/index.json)
3.1. Расположение
/var/www/hockey-json/finished/<season>/index.json

3.2. Формат
{
  "season": "25-26",
  "updatedAt": "2025-12-07T22:00:00",
  "games": [
    {
      "id": "2025-12-07_13-07-18_pestovo",
      "date": "2025-12-07T13:07:18",
      "arena": "Пестово Арена",
      "teamRed": "Красные",
      "teamWhite": "Белые",
      "scoreRed": 8,
      "scoreWhite": 4,
      "file": "finished/25-26/2025-12-07_13-07-18_pestovo.json"
    }
  ]
}


Поля:

season — строка, id сезона.

updatedAt — дата/время последнего пересчёта индекса.

games — массив игр данного сезона, каждая запись содержит:

id — идентификатор игры (совпадает с gameId и именем файла без .json).

date — дата/время начала игры.

arena — название арены.

teamRed — имя «красной» команды.

teamWhite — имя «белой» команды.

scoreRed — заброшенные шайбы «красных».

scoreWhite — заброшенные шайбы «белых».

file — относительный путь к файлу протокола игры.

Этот формат генерируется скриптом scripts/rebuild_indexes.py и должен соответствовать ожиданиям веб-фронтенда.

4. Статистика игроков сезона (stats/<season>/players.json)
4.1. Расположение
/var/www/hockey-json/stats/<season>/players.json

4.2. Формат
{
  "season": "25-26",
  "players": [
    {
      "name": "Иванов И.",
      "games": 5,
      "goals": 7,
      "assists": 3,
      "points": 10,
      "wins": 3,
      "draws": 1,
      "losses": 1
    }
  ]
}


Поля:

season — id сезона.

players — массив записей по игрокам:

name — имя/ФИО.

games — количество игр.

goals — голы.

assists — передачи.

points — суммарные очки (goals + assists).

wins — победы.

draws — ничьи.

losses — поражения.

Дополнительные поля могут добавляться по согласованию, но базовая структура фиксирована.

5. Result JSON (экспорт для TelegramBot)
5.1. Назначение

Файл формируется на стороне Android-приложения как итог матча и используется TelegramBot.

5.2. Формат
{
  "event_id": 11,
  "score_white": 4,
  "score_red": 8,
  "players": [
    {
      "user_id": "1119463688",
      "name": "Павликов Олег",
      "team": "red",
      "goals": 4,
      "assists": 2
    }
  ],
  "goals": [
    {
      "idx": 1,
      "team": "white",
      "minute": null,
      "scorer_user_id": 946978517,
      "assist1_user_id": 129010793,
      "assist2_user_id": null,
      "scorer_name": "Павликов Сергей",
      "assist1_name": "Третьяков Лев",
      "assist2_name": null
    }
  ]
}


Поля:

event_id — внешний идентификатор события (матча), число.

score_white, score_red — итоговый счёт по цветам (числа).

players — массив статистики по игрокам:

user_id — строковый идентификатор игрока (может быть отрицательным).

name — имя/ФИО.

team — "red" или "white".

goals — голы за матч.

assists — передачи за матч.

goals — массив голов:

idx — порядковый номер гола.

team — "red" или "white".

minute — игровое время (может быть null).

scorer_user_id, assist1_user_id, assist2_user_id — ID игроков (числа, могут быть отрицательными).

scorer_name, assist1_name, assist2_name — имена игроков (строки или null).

6. Roster JSON (входной от TelegramBot)
6.1. Назначение

Входной ростер игроков на матч, поставляемый TelegramBot, используется для сопоставления имён и user_id.

6.2. Формат
[
  {
    "event_id": 11,
    "user_id": 1119463688,
    "full_name": "Павликов Олег",
    "role": "fwd",
    "team": "red",
    "line": 1
  }
]


Поля:

event_id — ID события (матча), число.

user_id — числовой ID игрока (может быть отрицательным).

full_name — полное имя.

role — роль ("fwd", "def", "gk" и т. п.).

team — "red" или "white".

line — номер звена (целое число).

7. Настройки приложения (settings/app_settings.json)
7.1. Расположение
/var/www/hockey-json/settings/app_settings.json

7.2. Пример
{
  "version": 1,
  "updatedAt": "2025-12-07T22:00:00",
  "periodDurationMinutes": 20,
  "intermissionMinutes": 5,
  "language": "ru",
  "theme": "dark",
  "soundEnabled": true
}


Поля:

version — версия формата настроек (целое число).

updatedAt — дата/время последнего изменения.

periodDurationMinutes — длительность периода (минуты).

intermissionMinutes — перерыв между периодами (минуты).

language — код языка ("ru", "en" и т. д.).

theme — тема ("dark", "light" и т. п.).

soundEnabled — включён ли звук (true / false).

8. Базовый список игроков (base_roster/base_players.json)
8.1. Расположение
/var/www/hockey-json/base_roster/base_players.json

8.2. Формат
{
  "version": 1,
  "updatedAt": "2025-12-07T22:10:00",
  "players": [
    {
      "user_id": 38962792,
      "full_name": "Чижик Сергей",
      "role": "def",
      "team": null,
      "rating": 1500
    }
  ]
}


Поля:

version — версия формата базового списка.

updatedAt — дата/время последнего обновления.

players — массив игроков:

user_id — числовой ID игрока (ключ во всех интеграциях).

full_name — полное имя.

role — позиция ("fwd", "def", вратарь и т. д.).

team — null или код команды, если игрок закреплён за цветом.

rating — числовой рейтинг игрока (например, стартовое значение 1500).

Этот файл является эталонным «справочником игроков» и синхронизируется с сервером через эндпоинт /api/upload-base-roster.
