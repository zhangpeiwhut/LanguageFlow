# Server Services

统一的 server 服务管理。

## 快速开始

### 启动所有 service

```bash
# 开发环境（默认）
sh server/run.sh
# 或
bash server/run.sh

# 或指定环境
SERVER_ENV=production sh server/run.sh
```

## Service 配置

当前配置的 service：

| Service | 端口 | 说明 |
|---------|------|------|
| podcast_service | 8001 | Podcast 音频拉取和存储服务 |

## 添加新 Service

在 `server/run.sh` 的 `main()` 函数中添加新的 `start_service` 调用：

```bash
start_service "your_service" "8002" "server.your_service.main:app"
```

## 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `SERVER_ENV` | 环境模式：`development` 或 `production` | `development` |
| `UVICORN_WORKERS` | Worker数量（生产环境） | `4` |
| `VENV_PATH` | 虚拟环境路径 | `.venv` |

## 单独启动 Service

每个 service 也可以单独启动：

```bash
# 启动 podcast_service
sh server/podcast_service/run.sh
```

## 端口分配

- **8001**: podcast_service（固定）
- **8002+**: 其他 service（按需分配）

