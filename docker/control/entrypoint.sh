#!/bin/sh
set -eu
mkdir -p /root/.ssh /public
chmod 0700 /root/.ssh
if [ ! -s /root/.ssh/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
fi
cp /root/.ssh/id_ed25519.pub /public/id_ed25519.pub
chmod 0644 /public/id_ed25519.pub
exec "$@"
