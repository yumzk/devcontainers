#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${_REMOTE_USER:-vscode}"
USER_HOME="${_REMOTE_USER_HOME:-/home/vscode}"

apt-get update
apt-get install -y --no-install-recommends openssh-server
rm -rf /var/lib/apt/lists/*

# ホスト鍵はイメージに含めず、コンテナごとに起動時に生成する
rm -f /etc/ssh/ssh_host_*

# Debian の sshd_config は sshd_config.d を先頭で読み込み、最初に書かれた値が優先される
cat > /etc/ssh/sshd_config.d/agent-ssh.conf <<EOF
Port 2222
AllowUsers ${USER_NAME}
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowAgentForwarding no
X11Forwarding no
PermitUserEnvironment no
EOF

install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$USER_HOME/.ssh"
install -d /usr/local/share/agent-ssh
install -m 0755 "$(dirname "$0")/entrypoint.sh" /usr/local/share/agent-ssh/entrypoint.sh
