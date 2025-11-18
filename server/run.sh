#!/usr/bin/env sh
# Server 统一启动脚本 - 启动所有 service

set -eu

ROOT_DIR="$(
  cd -- "$(dirname "$0")/.." >/dev/null 2>&1
  pwd
)"
VENV_PATH="${VENV_PATH:-$ROOT_DIR/.venv}"
UVICORN_BIN="${UVICORN_BIN:-$VENV_PATH/bin/uvicorn}"
ENV="${SERVER_ENV:-development}"
WORKERS="${UVICORN_WORKERS:-4}"

check_and_free_port() {
  local port=$1
  local pid=$(lsof -ti:"$port" 2>/dev/null)
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

start_service() {
  local service_name=$1
  local port=$2
  local app_path=$3
  
  check_and_free_port "$port" || return 1
  
  echo "[Server] 启动 ${service_name}（端口 ${port}）"
  cd "$ROOT_DIR" || exit 1
  
  if [ "$ENV" = "production" ]; then
    # 生产环境：多worker，无reload
    "$UVICORN_BIN" "$app_path" \
      --host 0.0.0.0 \
      --port "$port" \
      --workers "$WORKERS" \
      --log-level info \
      --access-log &
  else
    # 开发环境：单worker，启用reload
    "$UVICORN_BIN" "$app_path" \
      --reload \
      --port "$port" &
  fi
  echo "[Server] ${service_name} 已启动（PID: $!）"
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
  
  echo "[Server] 环境模式: ${ENV}"
  echo "[Server] 工作目录: ${ROOT_DIR}"
  echo "[Server] 启动所有 service..."
  
  # 启动所有 service（手动添加新的 service 在这里）
  start_service "podcast_service" "8001" "server.podcast_service.main:app"
  # start_service "your_service" "8002" "server.your_service.main:app"  # 添加新 service 时取消注释
  
  echo "[Server] 所有 service 已启动"
  echo "[Server] 按 Ctrl+C 停止所有 service"
  wait
}

cleanup() {
  echo "[Server] 正在停止所有 service..."
  local pids
  pids=$(jobs -p)
  if [ -n "$pids" ]; then
    echo "$pids" | while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done
  fi
  exit
}
trap cleanup INT TERM

main "$@"

