#!/bin/sh
set -eu
test -s /public/id_ed25519.pub
install -m 0600 /public/id_ed25519.pub /root/.ssh/authorized_keys
ssh-keygen -A
mkdir -p /run/sshd
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
