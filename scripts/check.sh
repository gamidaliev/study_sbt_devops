#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Use a fresh Compose project; this script is intended for the CI runner.
docker compose up -d --build --wait --wait-timeout 180
docker compose exec -T nginx sh -c 'test ! -x /usr/sbin/nginx'
docker compose exec -T app sh -c 'test ! -e /opt/messages/app'
docker compose exec -T ansible ansible all -m ping
docker compose exec -T ansible ansible-playbook site.yml --syntax-check
docker compose exec -T ansible ansible-playbook site.yml

recap=$(mktemp)
docker compose exec -T ansible ansible-playbook site.yml | tee "$recap"
if grep -Eq 'changed=[1-9][0-9]*|failed=[1-9][0-9]*|unreachable=[1-9][0-9]*' "$recap"; then
    echo 'Second deployment must not change the servers or fail' >&2
    exit 1
fi
rm -f "$recap"

url="http://localhost:${HTTP_PORT:-8088}"
http_code=$(curl -sS -o /tmp/hw4-message.json -w '%{http_code}' \
    -X POST "$url/messages" -H 'Content-Type: text/plain' --data 'ci-persistence-check')
test "$http_code" = 201
python3 -c 'import json; d=json.load(open("/tmp/hw4-message.json")); assert d["id"] > 0 and d["text"] == "ci-persistence-check"'

check_message() {
    curl -fsS "$url/messages" | python3 -c 'import json,sys; assert any(m["text"] == "ci-persistence-check" for m in json.load(sys.stdin))'
}
check_message

docker compose restart app nginx
docker compose exec -T ansible ansible-playbook verify.yml
check_message

docker compose down
docker compose up -d --wait --wait-timeout 180
docker compose exec -T ansible ansible-playbook site.yml
check_message
docker compose ps
