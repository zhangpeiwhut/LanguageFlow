#!/usr/bin/env bash
# Podcast Service 启动脚本

set -euo pipefail

ROOT_DIR="$(
  cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1
  pwd
)"
VENV_PATH="${VENV_PATH:-$ROOT_DIR/.venv}"
UVICORN_BIN="${UVICORN_BIN:-$VENV_PATH/bin/uvicorn}"
PORT="${PODCAST_SERVICE_PORT:-8001}"
ENV="${SERVER_ENV:-development}"
WORKERS="${UVICORN_WORKERS:-4}"

if [ "$ENV" = "production" ]; then
  echo "[Podcast Service] 启动（生产环境，端口 ${PORT}，${WORKERS} workers）"
  cd "$ROOT_DIR" || exit 1
  exec "$UVICORN_BIN" server.podcast_service.main:app \
    --host 0.0.0.0 \
    --port "$PORT" \
    --workers "$WORKERS" \
    --log-level info \
    --access-log
else
  echo "[Podcast Service] 启动（开发环境，端口 ${PORT}）"
  cd "$ROOT_DIR" || exit 1
  exec "$UVICORN_BIN" server.podcast_service.main:app --reload --port "$PORT"
fi

