# ДЗ №2. Docker-образ приложения

HTTP-приложение на Go с эндпоинтом `GET /health`. Исходники: [main.go](main.go).

Образ собирается в две стадии: `builder` — тестирование и компиляция,
`runtime` — Alpine с готовым бинарным файлом. Базовые образы
`golang:1.26.10-alpine3.23` и `alpine:3.23.7` закреплены по тегам и SHA-256 digest.
Приложение запускается от UID/GID `10001`. В Dockerfile заданы `ENV`,
`EXPOSE 8080`, `HEALTHCHECK` и `ENTRYPOINT`; команды запуска используют exec-форму.

## Сборка и запуск

Требования: Docker Desktop в режиме Linux containers, Docker Compose v2 и Git.
Команды выполняются в PowerShell.

```powershell
git clone --branch hw2 https://github.com/gamidaliev/study_sbt_devops.git
cd study_sbt_devops
docker build -t study-sbt-devops:hw2 .
docker run -d --name hw2-app -p 8080:8080 -e APP_NAME=hw2-demo study-sbt-devops:hw2
```

Переменные окружения: `APP_NAME` — название приложения (по умолчанию `hw2-demo`),
`APP_PORT` — внутренний порт (по умолчанию `8080`).

## Проверка

```powershell
curl.exe -i http://localhost:8080/health
docker ps --filter name=hw2-app
docker exec hw2-app id
```

Результат: **HTTP 200**, JSON `{"app":"hw2-demo","status":"UP"}`,
статус контейнера **healthy** после выполнения healthcheck,
UID/GID процесса **10001**.

Остановка и удаление контейнера:

```powershell
docker rm -f hw2-app
```

## Запуск через Docker Compose

Альтернативный запуск после остановки контейнера `hw2-app`:

```powershell
docker compose -f docker_compose.yml up -d --build --wait
curl.exe -i http://localhost:8080/health
docker compose -f docker_compose.yml ps
docker compose -f docker_compose.yml down
```

## Публикация образа

Скрипт [scripts/build-push.ps1](scripts/build-push.ps1) собирает образ и выполняет
`docker push`. Пример для Docker Hub; `dockerhub-user` обозначает аккаунт
с правами записи в репозиторий `study-sbt-devops`:

```powershell
$RegistryUser = 'dockerhub-user'
docker login --username $RegistryUser
.\scripts\build-push.ps1 -Image "${RegistryUser}/study-sbt-devops:hw2-v1"
```

## Результат проверки на Windows

На скриншоте: контейнер **healthy**, ответ **HTTP 200** на `/health`,
пользователь **app** с UID/GID **10001**.

![Проверка контейнера, /health и non-root](screenshots/verification-windows.png)
