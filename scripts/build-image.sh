#!/usr/bin/env bash
# 使い方: scripts/build-image.sh <言語> [イメージ名]
# ローカルの Feature は .devcontainer/ の下にある必要があるため、一時ディレクトリに並べてからビルドする
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lang="${1:?使い方: scripts/build-image.sh <言語> [イメージ名]}"
image="${2:-ghcr.io/yumzk/devcontainers/${lang}:dev}"

if [ ! -d "$root/images/$lang" ]; then
  echo "images/$lang がありません" >&2
  exit 1
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/.devcontainer"
cp -R "$root/images/$lang/." "$stage/.devcontainer/"
cp -R "$root/features" "$stage/.devcontainer/features"

devcontainer build --workspace-folder "$stage" --image-name "$image"
