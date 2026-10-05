# Dependabot が更新できるように、uv は COPY --from に直接書かずステージとして参照する
FROM ghcr.io/astral-sh/uv:0.12.23 AS uv

FROM mcr.microsoft.com/devcontainers/python:3-trixie

# Python 本体のバージョンは各リポジトリで uv（.python-version）が管理する
COPY --from=uv /uv /uvx /usr/local/bin/
