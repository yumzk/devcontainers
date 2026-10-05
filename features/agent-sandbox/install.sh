#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${_REMOTE_USER:-vscode}"
EXTRA_DOMAINS="${EXTRADOMAINS:-}"
SHARE=/usr/local/share/agent-sandbox

apt-get update
apt-get install -y --no-install-recommends iptables ipset dnsmasq-base curl
rm -rf /var/lib/apt/lists/*

# remoteUser から root になる手段をなくす（なくさないとファイアウォールを自分で外せる）
rm -f "/etc/sudoers.d/${USER_NAME}"
gpasswd -d "$USER_NAME" sudo 2>/dev/null || true

install -d /etc/agent-sandbox "$SHARE"
{
  cat "$(dirname "$0")/allowed-domains"
  echo "# extraDomains"
  tr ',' '\n' <<< "$EXTRA_DOMAINS" | tr -d ' '
} | grep -Ev '^\s*(#|$)' | sort -u > /etc/agent-sandbox/allowed-domains

install -m 0755 "$(dirname "$0")/init-firewall.sh" "$SHARE/init-firewall.sh"
install -m 0755 "$(dirname "$0")/entrypoint.sh" "$SHARE/entrypoint.sh"
