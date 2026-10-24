# Проверка стека

Скриншоты добавляются после фактического запуска на Windows:

- `docker compose ps` — три сервиса, опубликован только порт Nginx `80:80`.
- `curl.exe -i http://localhost/health` — HTTP 200 через Nginx, PostgreSQL доступен.
- `GET /messages` до и после `docker compose down` / `docker compose up -d --wait` — сохранённая запись присутствует в обоих ответах.

Фактические скриншоты в этой ветке пока отсутствуют.
