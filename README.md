# devcontainers

コーディングエージェント（Claude Code / Codex）を承認なしで動かすための devcontainer 一式。
共通部分（Features と言語別イメージ）をここで管理し、各リポジトリには薄い `devcontainer.json` だけを置く。

イメージは `ghcr.io/yumzk/devcontainers/images/<言語>:latest` で公開している（amd64 と arm64）。

## 構成

```
features/
  agent-cli/       Claude Code と Codex。認証情報は devcontainer ごとの volume に保存
  agent-ssh/       公開鍵認証のみの sshd（コンテナ内 2222 番）
  agent-sandbox/   sudo の削除と、外向き通信の許可リスト化（dnsmasq + ipset + iptables）
images/
  python/          言語別イメージの定義（Python 本体は各リポジトリで uv が管理）
  go/              言語別イメージの定義（Go 本体はイメージのものを使う）
templates/
  python/ go/      各リポジトリに置く devcontainer.json の雛形
scripts/
  build-image.sh   言語別イメージのビルド
bin/
  devc             ホスト用ラッパー（起動、SSH 接続先の生成、gh へのトークン登録）
.github/
  workflows/images.yml  イメージのビルドと ghcr.io への公開
  dependabot.yml        Actions とベースイメージの更新（公開から7日待つ）
```

## イメージの公開

`main` への push と毎週月曜 3:00（JST）に、GitHub Actions がイメージを作り直して公開する。
PR ではビルドとスモークテストだけを行い、公開はしない。

| タグ | 内容 |
|---|---|
| `latest` | 最新。各リポジトリの雛形はこれを参照する |
| `sha-<コミット>` | コミットごとに固定。問題が出たときに戻す先 |
| `build-<コミット>-<arch>` | アーキテクチャごとの中間イメージ |

新しい言語のイメージを初めて公開したときは、ghcr のパッケージが private で作られるので、
パッケージの Package settings → Change visibility で public にする。

手元で作ったイメージを試すときは、`scripts/build-image.sh python ghcr.io/yumzk/devcontainers/images/python:latest`
で同じタグに上書きする。`devc rebuild` は ghcr から取得し直すので、元に戻る。

## コンテナの中でできること・できないこと

- エージェントは一般ユーザー `vscode` で動き、sudo は使えない
- 外向き通信は `features/agent-sandbox/allowed-domains` と各イメージの `extraDomains` に書いたドメインだけ
- ホストの `~/.ssh`、gh の設定、docker.sock は渡さない
- GitHub へは、エージェント用のトークンの権限の範囲で push と PR 作成ができる
- Claude Code の設定と skill は、dotfiles の `claude/` が `devc up` のたびにコピーされる
  （dotfiles の場所は `DEVC_DOTFILES`、既定は `~/go/src/github.com/yumzk/dotfiles`）。
  `settings.json` の `permissions.ask` は取り除く（bypass permissions でも確認が出て、放置したセッションが止まるため）

## 前提

- Docker（Docker Desktop など）
- devcontainer CLI（`npm install -g @devcontainers/cli`）
- jq（`brew install jq`）
- `~/.ssh/config` の先頭に `Include ~/.ssh/devc/*.conf`

## 言語ごとの方針

| 言語 | 本体のバージョン | プロジェクト固有のツール | 追加で許可するドメイン |
|---|---|---|---|
| Python | 各リポジトリの `.python-version` を uv が取得 | `pyproject.toml` と `uv.lock` | pypi.org、pythonhosted.org |
| Go | イメージの Go（最新のマイナーに追従） | `go.mod` の tool ディレクティブ（`go tool <名前>` で実行） | golang.org |

Go は `GOTOOLCHAIN=local` のまま使う。Go 本体の自動取得は storage.googleapis.com へのリダイレクトを伴い、
そこを許可すると任意のバケットへの通信経路が開くため。`go.mod` がイメージより新しい Go を要求すると
「go.mod requires go >= ...」で止まるので、そのときはイメージの更新を待つか、イメージの Go を上げる。

## GitHub のトークン

エージェント用の fine-grained PAT を1本だけ作り、macOS のキーチェーンに保存しておく。
`devc up` は、コンテナの gh が未ログインかトークンが無効なら、キーチェーンから自動で登録する。

### 最初に1回だけ

1. GitHub の Settings → Developer settings → Fine-grained tokens でトークンを作る
   - Repository access: Only select repositories（エージェントに触らせるリポジトリだけ）
   - Permissions: Contents と Pull requests を Read and write（Metadata は自動で Read-only）
   - それ以外は付けない。特に Administration と Workflows（CI の書き換えを防ぐ）
2. `bin/devc token-set` でキーチェーンに保存する

### エージェントに触らせるリポジトリを増やすとき

1. トークンの編集画面で、Repository access にそのリポジトリを追加する（トークンの値は変わらない）
2. そのリポジトリに main を守る Ruleset を作る（Settings → Rules → Rulesets）
   - Target: default branch、Bypass list は空（PAT は自分として動くため、自分を入れるとエージェントも除外される）
   - Restrict deletions、Require a pull request before merging（承認数 0）、Block force pushes

### 更新するとき

トークンを作り直したら `bin/devc token-set` で上書きする。起動中のコンテナには `bin/devc gh-login`、
次回以降の `devc up` では自動で反映される。

キーチェーン以外（Linux や 1Password など）から取り出すときは、トークンを標準出力に出すコマンドを
`DEVC_GH_TOKEN_CMD` に設定する。

## PoC の手順

```bash
# 1. イメージをビルドする
scripts/build-image.sh python

# 2. 対象リポジトリに雛形を置いて起動する（コミットが1つ以上あるリポジトリ）
cp -R templates/python/.devcontainer /path/to/repo/
bin/devc up /path/to/repo

# 3. コンテナに入ってログインする
bin/devc ssh /path/to/repo
claude            # /login でサブスクリプションにログイン
codex login --device-auth

# 4. GitHub のトークンは「GitHub のトークン」の手順で保存しておけば、up のときに自動で登録される

# 5. スマホから操作したいときは Remote Control のサーバーを起動する（Ctrl-b d で抜けても動き続ける）
bin/devc rc /path/to/repo
```

デスクトップアプリからは、環境の「+ Add SSH connection」で Host に `devc-<リポジトリ名>` を指定し、
プロジェクトのフォルダにホストと同じパスを指定する。

### 確認すること

- [x] ファイアウォール: 許可していないドメインに接続できない、許可したドメインには接続できる
- [x] SSH でログインしたセッションに `CLAUDE_CONFIG_DIR` と `CODEX_HOME` が届いている
- [x] コンテナを作り直しても `~/.claude`、`~/.codex`、`~/.config/gh` の中身が残っている
- [x] デスクトップアプリから SSH セッションで接続でき、bypass permissions で動く
- [x] デスクトップアプリの SSH セッションで worktree を選べる
- [x] コンテナ内の `claude remote-control --spawn worktree` にスマホから接続できる（コミットのあるリポジトリ内で起動する）
- [x] コンテナ内で作った worktree をホストの git でも扱える
- [ ] Codex にログインでき、作り直した後もログインが残っている（サブスクリプション未契約のため保留）
- [x] コンテナから push と PR 作成ができ、main への直接 push はブランチ保護で拒否される
- [x] デスクトップアプリの SSH セッションから、Claude Code に PR 作成まで任せられる
- [x] `devc gh-login` で登録したトークンが、作り直した後も残っている

### 運用上の注意

- 放置で走らせるセッションは Bypass permissions を選ぶ。auto mode は操作のたびにサーバー側の分類器へ問い合わせるため、分類器の障害で作業が止まる
- GitHub のトークンは `devc token-set` で保存し、`devc up` か `devc gh-login` で登録する。シェルで `GH_TOKEN` を export して起動すると、そのプロセスにしか届かず、作り直すと消える
