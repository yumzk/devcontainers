FROM mcr.microsoft.com/devcontainers/go:1.27-trixie

# Go 本体はこのイメージのものを使う（ベースイメージの既定の GOTOOLCHAIN=local のまま）。
# Go 本体の自動取得は storage.googleapis.com へのリダイレクトを伴い、そこを許可すると
# 任意のバケットへの通信経路が開くため使わない。イメージは Dependabot と毎週の再ビルドで最新の Go に追従する。
#
# リンターなどのプロジェクト固有のツールは、各リポジトリの go.mod の tool ディレクティブで固定する
