#!/usr/bin/env bash
# コンテナ起動時に root で実行される
if [ "$(id -u)" = 0 ]; then
  if ! /usr/local/share/agent-sandbox/init-firewall.sh > /var/log/agent-sandbox.log 2>&1; then
    echo "agent-sandbox: ファイアウォールの設定に失敗しました。外向き通信はすべて遮断されています（/var/log/agent-sandbox.log を参照）" >&2
  fi
fi

exec "$@"
