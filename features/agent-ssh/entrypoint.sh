#!/usr/bin/env bash
# コンテナ起動時に root で実行される
if [ "$(id -u)" = 0 ]; then
  ssh-keygen -A >/dev/null
  mkdir -p /run/sshd
  /usr/sbin/sshd -E /var/log/agent-ssh.log
fi

exec "$@"
