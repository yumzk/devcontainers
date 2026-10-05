#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${_REMOTE_USER:-vscode}"
USER_HOME="${_REMOTE_USER_HOME:-/home/vscode}"
CODEX_VERSION="${CODEXVERSION:-latest}"

# mounts と containerEnv はパスを固定で書いているため、ホームが違う場合は止める
if [ "$USER_HOME" != "/home/vscode" ]; then
  echo "agent-cli: remoteUser のホームが /home/vscode である前提です（実際: ${USER_HOME}）" >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl tar tmux
rm -rf /var/lib/apt/lists/*

# volume のマウント先を所有者付きで作っておく。新しい volume は初回マウント時にこの所有者を引き継ぐ
install -d -o "$USER_NAME" -g "$USER_NAME" "$USER_HOME/.config"
for dir in .claude .codex .config/gh; do
  install -d -o "$USER_NAME" -g "$USER_NAME" "$USER_HOME/$dir"
done

# Claude Code: ネイティブインストーラでユーザー領域に入れる（自動更新がそのまま効く）
su - "$USER_NAME" -c 'curl -fsSL https://claude.ai/install.sh | bash'
ln -sf "$USER_HOME/.local/bin/claude" /usr/local/bin/claude

# Codex: GitHub Releases の単体バイナリ。更新はイメージの再ビルドで行う
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) echo "agent-cli: 未対応のアーキテクチャです: $(uname -m)" >&2; exit 1 ;;
esac
asset="codex-${arch}-unknown-linux-musl"
if [ "$CODEX_VERSION" = "latest" ]; then
  url="https://github.com/openai/codex/releases/latest/download/${asset}.tar.gz"
else
  url="https://github.com/openai/codex/releases/download/${CODEX_VERSION}/${asset}.tar.gz"
fi
tmp="$(mktemp -d)"
curl -fsSL "$url" | tar -xz -C "$tmp"
install -m 0755 "$tmp/$asset" /usr/local/bin/codex
rm -rf "$tmp"

# ホストからマウントしたリポジトリは所有者の uid がコンテナのユーザーと一致しない。
# VS Code は接続時に safe.directory を足すが、SSH 経由のセッションでは足されないためイメージ側で許可する
git config --system --add safe.directory '*'

# コンテナには SSH 鍵を置かず 22 番も閉じているので、GitHub へは常に HTTPS で gh のトークンを使う。
# ホストと共有するリポジトリの remote が SSH の URL でも、コンテナ内でだけ HTTPS に読み替える
git config --system url."https://github.com/".insteadOf "git@github.com:"
git config --system --add url."https://github.com/".insteadOf "ssh://git@github.com/"
git config --system credential."https://github.com".helper '!gh auth git-credential'

# SSH でログインしたセッションには containerEnv が届かないので、pam_env が読む /etc/environment にも書く
for kv in "CLAUDE_CONFIG_DIR=$USER_HOME/.claude" "CODEX_HOME=$USER_HOME/.codex"; do
  grep -qxF "$kv" /etc/environment || echo "$kv" >> /etc/environment
done
