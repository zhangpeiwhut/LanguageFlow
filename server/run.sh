#!/usr/bin/env bash
# Server 启动脚本

set -eu

ROOT_DIR="$(
  cd -- "$(dirname "$0")/.." >/dev/null 2>&1
  pwd
)"
VENV_PATH="${VENV_PATH:-$ROOT_DIR/.venv}"
UVICORN_BIN="${UVICORN_BIN:-$VENV_PATH/bin/uvicorn}"
ENV="${SERVER_ENV:-development}"
WORKERS="${UVICORN_WORKERS:-4}"
PORT="${PORT:-8001}"

check_and_free_port() {
  local port=$1
  local pid
  pid=$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN)
  if [ -n "$pid" ]; then
    echo "[Server] 检测到端口 ${port} 已被占用（PID: ${pid}），正在释放..."
    kill -9 "$pid" 2>/dev/null || true
    sleep 1
    if lsof -ti:"$port" >/dev/null 2>&1; then
      echo "[Server] 警告：无法释放端口 ${port}，请手动检查"
      return 1
    else
      echo "[Server] 端口 ${port} 已释放"
    fi
  fi
  return 0
}

main() {
  if [ ! -x "$UVICORN_BIN" ]; then
    cat <<'EOF'
[Server] 找不到 uvicorn 可执行文件。
请先运行以下命令准备虚拟环境：

  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt

如已安装到其它路径，可设置 VENV_PATH 环境变量指向虚拟环境目录。
EOF
    exit 1
  fi
  
  check_and_free_port "$PORT" || exit 1
  
  echo "[Server] 环境模式: ${ENV}"
  echo "[Server] 工作目录: ${ROOT_DIR}"
  echo "[Server] 启动服务（端口 ${PORT}）..."
  
  cd "$ROOT_DIR" || exit 1
  
  if [ "$ENV" = "production" ]; then
    # 生产环境：多worker，无reload
    exec "$UVICORN_BIN" server.main:app \
      --host 0.0.0.0 \
      --port "$PORT" \
      --workers "$WORKERS" \
      --log-level info \
      --access-log
  else
    # 开发环境：单worker，启用reload
    exec "$UVICORN_BIN" server.main:app \
      --reload \
      --host 0.0.0.0 \
      --port "$PORT"
  fi
}

main "$@"
