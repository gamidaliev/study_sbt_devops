# Скриншоты проверки

Добавить после реального запуска на Windows с Docker Desktop:

1. `01-container-healthy.png`: результат `docker compose -f docker_compose.yml ps` со статусом **healthy**.
2. `02-health-200.png`: результат `curl.exe -i http://localhost:8080/health` с **HTTP/1.1 200 OK** и JSON.
3. `03-non-root.png`: результат `docker compose -f docker_compose.yml exec app id` с UID/GID **10001**.

Можно добавить скриншот Docker Desktop вместо первого снимка, если на нём видны контейнер и статус.
Изображения должны показывать фактический запуск, а не пример ожидаемого вывода.

После сохранения файлов в эту папку из корня репозитория:

```powershell
git add screenshots
git commit -m "docs: add Docker lab verification screenshots"
git push origin hw2
```

Открытый PR обновится автоматически. На момент подготовки исходников скриншоты ещё не добавлены.
