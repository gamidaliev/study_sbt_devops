# ДЗ №4. Деплой приложения с Ansible

Ansible устанавливает nginx на чистый сервер и разворачивает HTTP-приложение
на другом сервере. Серверы и управляющая машина представлены Docker-контейнерами.
Использовано Go-приложение из ДЗ №3: оно сохраняет сообщения в PostgreSQL.
Исходники и тесты находятся в [app](app).

## Состав стенда

Все четыре контейнера подключены к одной bridge-сети `lab`.

| Сервис | Назначение | Доступ с компьютера |
| --- | --- | --- |
| `ansible` | Управляющая машина, inventory, роли и архив приложения | Через `docker compose exec` |
| `nginx` | Управляемый сервер с reverse proxy | `http://localhost:8088` |
| `app` | Управляемый сервер с Go-приложением | Только внутри сети, порт 8080 |
| `db` | PostgreSQL, данные в томе `pgdata` | Только внутри сети, порт 5432 |

Образ управляемого сервера — Ubuntu 24.04 с SSH, Python и Supervisor.
До выполнения playbook в нём нет nginx и приложения. Supervisor заменяет
systemd внутри контейнера: управляет SSH и процессом, который добавляет Ansible.
Контейнеры не требуют `privileged` или доступа к Docker socket.

Образ управляющей машины собирает и тестирует приложение, затем упаковывает
статический бинарный файл в `/artifacts/app.tar.gz`. Роль `application` переносит
этот архив по SSH, распаковывает его в `/opt/messages`, создаёт конфигурацию
и shell-скрипт `start.sh`. Go на управляемом сервере не нужен: приложение
собрано с `CGO_ENABLED=0`.

## Структура Ansible

- [inventory.ini](ansible/inventory.ini) — группы `web` и `application`.
- [group_vars/all.yml](ansible/group_vars/all.yml) — параметры приложения и БД.
- [site.yml](ansible/site.yml) — основной playbook.
- [common](ansible/roles/common) — проверка ОС, архитектуры, памяти,
  Supervisor и установка утилит для деплоя.
- [application](ansible/roles/application) — проверка доступности БД,
  пользователь приложения, распаковка, шаблоны конфигурации и запуска.
- [nginx](ansible/roles/nginx) — установка, конфигурация reverse proxy,
  проверка `nginx -t` перед применением.
- [verify.yml](ansible/verify.yml) — проверка HTTP API и БД через nginx.

Конфигурации создаются из Jinja2-шаблонов. Handlers перезапускают процессы
при изменении файлов. Приложение работает от пользователя `messages`.
При повторном выполнении с прежними параметрами playbook не меняет конфигурацию.

## Сборка и запуск на Windows

Требования: Git, Docker Desktop с запущенным Linux engine, Docker Compose v2.
Команды выполняются в PowerShell. Локальные Ansible, Go и SSH не требуются.
Первый запуск требует доступа к Docker Hub, репозиториям Ubuntu и Go-модулям.

Для нового клона:

```powershell
git clone --branch hw4 https://github.com/gamidaliev/study_sbt_devops.git
cd study_sbt_devops
```

Если репозиторий уже есть, перейдите в него и переключитесь на `hw4`:

```powershell
git fetch origin
git switch hw4
git pull --ff-only
```

Создайте настройки и случайный пароль БД (только при первом запуске):

```powershell
Copy-Item .env.example .env
(Get-Content .env) -replace '^POSTGRES_PASSWORD=$', ('POSTGRES_PASSWORD=' + [guid]::NewGuid().ToString('N')) | Set-Content .env -Encoding ascii
```

`.env` исключён из Git и контекста сборки. Не меняйте пароль при сохранённом
томе PostgreSQL: переменные `POSTGRES_*` инициализируют БД только на пустом томе.
Если порт 8088 занят, измените `HTTP_PORT` в `.env` и используйте его в запросах.

Поднимите управляющую машину, БД и два чистых сервера:

```powershell
docker compose up -d --build --wait
docker compose ps
docker compose exec -T ansible ansible all -m ping
```

Оба управляемых узла должны ответить `SUCCESS` и `pong`.
Здесь `healthy` у `nginx` и `app` означает готовность SSH, а не установленное
приложение. Его работоспособность проверяется после деплоя отдельным playbook.

Убедитесь, что nginx и приложение ещё не установлены (только для нового стенда):

```powershell
docker compose exec -T nginx sh -c 'test ! -x /usr/sbin/nginx && echo nginx-not-installed'
docker compose exec -T app sh -c 'test ! -e /opt/messages/app && echo app-not-deployed'
```

Проверьте синтаксис и выполните деплой:

```powershell
docker compose exec -T ansible ansible-playbook site.yml --syntax-check
docker compose exec -T ansible ansible-playbook site.yml
```

В конце `PLAY RECAP` для всех узлов ожидаются `failed=0` и `unreachable=0`.
Playbook завершается проверкой приложения и БД через nginx.

## Проверка работы

```powershell
curl.exe --fail-with-body -i http://localhost:8088/health
curl.exe --fail-with-body http://localhost:8088/
curl.exe --fail-with-body -X POST http://localhost:8088/messages -H "Content-Type: text/plain" --data "saved-from-ansible"
curl.exe --fail-with-body http://localhost:8088/messages
docker compose exec -T app supervisorctl status
docker compose exec -T nginx supervisorctl status
```

`/health` возвращает HTTP 200 и `{"db":"UP","status":"UP"}`.
POST возвращает HTTP 201 и сохранённое сообщение с `id`; GET — список сообщений.
Supervisor показывает `application`/`nginx` и `sshd` в состоянии `RUNNING`.
На компьютере опубликован только HTTP-порт nginx, привязанный к localhost.

Повторный деплой и отдельная проверка:

```powershell
docker compose exec -T ansible ansible-playbook site.yml
docker compose exec -T ansible ansible-playbook verify.yml
```

При повторном деплое без изменений ожидается `changed=0`.
Обновление устаревшего кеша apt спустя час может учитываться как изменение.

## Перезапуск, обновление и остановка

Проверка запуска процессов после перезапуска контейнеров:

```powershell
docker compose restart app nginx
docker compose exec -T ansible ansible-playbook verify.yml
curl.exe --fail-with-body http://localhost:8088/messages
```

После изменения исходников, ролей или шаблонов пересоберите управляющую машину
и повторите деплой:

```powershell
docker compose up -d --build --wait
docker compose exec -T ansible ansible-playbook site.yml
```

Остановить и удалить контейнеры, сохранив сообщения и SSH-ключ:

```powershell
docker compose down
```

После `down` управляемые серверы будут созданы заново, поэтому нужны обе команды:

```powershell
docker compose up -d --wait
docker compose exec -T ansible ansible-playbook site.yml
```

Полностью удалить стенд **вместе с данными БД и SSH-ключами**:

```powershell
docker compose down -v
```

## Диагностика и автоматическая проверка

```powershell
docker compose logs --tail 100 ansible app nginx db
docker compose exec -T nginx nginx -t
```

[GitHub Actions](.github/workflows/lab.yml) проверяет сборку и тесты приложения,
деплой на чистые контейнеры, повторный запуск без изменений, запись и чтение
сообщения, перезапуск сервисов и сохранение данных при пересоздании контейнеров.

SSH-ключ создаётся автоматически и хранится в отдельном томе управляющей машины;
управляемым узлам передаётся только публичная часть. Парольный SSH-вход отключён.
Проверка SSH host keys отключена только для этого локального стенда с пересоздаваемыми
контейнерами. Внешние SSH-порты не публикуются. Для настоящих серверов следует
использовать проверенные host keys и отдельного пользователя с `become`.

## Скриншоты для отчёта

Для проверки лабораторной нужны:

1. `docker compose ps` с четырьмя запущенными контейнерами и итог `PLAY RECAP`.
2. HTTP 200 для `/health`, создание и чтение сообщения через nginx.
3. Повторный `PLAY RECAP` с `changed=0`.
