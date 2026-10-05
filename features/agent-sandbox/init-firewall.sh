#!/usr/bin/env bash
# 外向き通信を許可リストのドメインだけに絞る。
#
# - dnsmasq をコンテナ内の DNS にし、許可リストのドメインだけを上流に問い合わせる
#   （それ以外は名前解決できないので、DNS を使った持ち出しも防げる）
# - 名前解決した IP を dnsmasq が ipset に追加し、iptables はその ipset 宛てだけを通す
#   （CDN の IP が変わっても、名前解決し直せば追従する）
set -euo pipefail

DOMAINS_FILE=/etc/agent-sandbox/allowed-domains
DNSMASQ_CONF=/etc/agent-sandbox/dnsmasq.conf
IPSET=agent-allowed
SSH_PORT=2222

# 途中で失敗しても通信が開いたままにならないよう、最初に全部閉じる
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -F
iptables -X
ip6tables -P INPUT DROP 2>/dev/null || true
ip6tables -P FORWARD DROP 2>/dev/null || true
ip6tables -P OUTPUT DROP 2>/dev/null || true
ip6tables -F 2>/dev/null || true
ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

# 上流の DNS は Docker が書いた resolv.conf から取る（再実行時は保存済みの値を使う）
if [ -f /etc/agent-sandbox/upstream-dns ]; then
  upstream="$(cat /etc/agent-sandbox/upstream-dns)"
else
  upstream="$(awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf)"
  echo "$upstream" > /etc/agent-sandbox/upstream-dns
fi
if [ -z "$upstream" ] || [ "$upstream" = "127.0.0.1" ]; then
  echo "上流の DNS サーバーが見つかりません" >&2
  exit 1
fi

ipset create "$IPSET" hash:ip family inet -exist
ipset flush "$IPSET"

mapfile -t domains < "$DOMAINS_FILE"
{
  echo "no-resolv"
  echo "listen-address=127.0.0.1"
  echo "bind-interfaces"
  echo "user=root"
  echo "cache-size=1000"
  for domain in "${domains[@]}"; do
    echo "server=/${domain}/${upstream}"
  done
  printf 'ipset='
  printf '/%s' "${domains[@]}"
  echo "/${IPSET}"
} > "$DNSMASQ_CONF"

pkill -x dnsmasq 2>/dev/null || true
dnsmasq --conf-file="$DNSMASQ_CONF"
echo "nameserver 127.0.0.1" > /etc/resolv.conf

iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# sshd（ホスト側は 127.0.0.1 にだけ公開している）
iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
# 上流の DNS に問い合わせてよいのは root で動く dnsmasq だけ
iptables -A OUTPUT -d "$upstream" -p udp --dport 53 -m owner --uid-owner 0 -j ACCEPT
iptables -A OUTPUT -d "$upstream" -p tcp --dport 53 -m owner --uid-owner 0 -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m set --match-set "$IPSET" dst -j ACCEPT
# 拒否は即座に返し、タイムアウト待ちにしない
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# 動作確認
if curl -fsS --max-time 5 -o /dev/null https://example.com; then
  echo "example.com に接続できてしまいました" >&2
  exit 1
fi
if ! curl -fsS --max-time 10 -o /dev/null https://api.github.com/zen; then
  echo "api.github.com に接続できません" >&2
  exit 1
fi
echo "ファイアウォールを設定しました（上流 DNS: ${upstream}、許可ドメイン数: ${#domains[@]}）"
