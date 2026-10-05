FROM mcr.microsoft.com/devcontainers/python:3-trixie

# Python 本体のバージョンは各リポジトリで uv（.python-version）が管理する
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/
