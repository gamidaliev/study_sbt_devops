# Скриншот проверки на Windows

Файл [verification-windows.png](verification-windows.png) содержит результат реального запуска в PowerShell с Docker Desktop:

1. `docker compose -f docker_compose.yml ps` — контейнер **healthy**, порт **8080** опубликован.
2. `curl.exe -i http://localhost:8080/health` — **HTTP/1.1 200 OK**, `{"app":"hw2-demo","status":"UP"}`.
3. `docker compose -f docker_compose.yml exec app id` — **uid=10001(app) gid=10001(app)**.

![Результаты проверки](verification-windows.png)

Один скриншот подтверждает все три проверки. Публикация образа в registry этим скриншотом не подтверждается.
