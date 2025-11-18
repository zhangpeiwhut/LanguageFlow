# 生产环境部署指南

## 快速启动

### 方式1：直接运行脚本（不推荐用于生产）

```bash
# 设置生产环境模式
export PODCAST_ENV=production
export PODCAST_SERVICE_PORT=8001
export UVICORN_WORKERS=4

# 启动服务
sh server/podcast_service/run.sh
```

**注意**：这种方式服务会在前台运行，终端关闭后服务会停止。

### 方式2：使用 systemd（推荐）

#### 1. 创建 systemd 服务文件

创建 `/etc/systemd/system/podcast-service.service`：

```ini
[Unit]
Description=Podcast Service
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/LanguageFlow
Environment="PODCAST_ENV=production"
Environment="PODCAST_SERVICE_PORT=8001"
Environment="UVICORN_WORKERS=4"
Environment="LOG_FILE=/path/to/LanguageFlow/logs/podcast_service.log"
ExecStart=/path/to/LanguageFlow/.venv/bin/uvicorn server.podcast_service.main:app \
    --host 0.0.0.0 \
    --port 8001 \
    --workers 4 \
    --log-level info \
    --access-log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### 2. 启动服务

```bash
# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start podcast-service

# 设置开机自启
sudo systemctl enable podcast-service

# 查看状态
sudo systemctl status podcast-service

# 查看日志
sudo journalctl -u podcast-service -f
```

### 方式3：使用 Supervisor（推荐）

#### 1. 安装 Supervisor

```bash
# Ubuntu/Debian
sudo apt-get install supervisor

# macOS
brew install supervisor
```

#### 2. 创建配置文件

创建 `/etc/supervisor/conf.d/podcast-service.conf`：

```ini
[program:podcast-service]
command=/path/to/LanguageFlow/.venv/bin/uvicorn server.podcast_service.main:app --host 0.0.0.0 --port 8001 --workers 4 --log-level info --access-log
directory=/path/to/LanguageFlow
user=your-user
autostart=true
autorestart=true
stderr_logfile=/path/to/LanguageFlow/logs/podcast_service_error.log
stdout_logfile=/path/to/LanguageFlow/logs/podcast_service.log
environment=PODCAST_ENV="production"
```

#### 3. 启动服务

```bash
# 重新加载配置
sudo supervisorctl reread
sudo supervisorctl update

# 启动服务
sudo supervisorctl start podcast-service

# 查看状态
sudo supervisorctl status podcast-service
```

## 环境变量配置

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `PODCAST_ENV` | 环境模式：`development` 或 `production` | `development` |
| `PODCAST_SERVICE_PORT` | 服务端口 | `8001` |
| `UVICORN_WORKERS` | Worker数量（生产环境） | `4` |
| `LOG_FILE` | 日志文件路径 | `logs/podcast_service.log` |

## 生产环境配置建议

### Worker 数量

- **CPU密集型**：`workers = CPU核心数`
- **IO密集型**：`workers = CPU核心数 * 2 + 1`
- **一般建议**：4-8个workers

### 日志管理

生产环境建议配置日志轮转，创建 `/etc/logrotate.d/podcast-service`：

```
/path/to/LanguageFlow/logs/podcast_service*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 your-user your-group
}
```

### 反向代理

生产环境建议使用 Nginx 作为反向代理：

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 安全建议

1. **使用 HTTPS**：配置 SSL 证书
2. **防火墙**：只开放必要端口
3. **限制访问**：使用 Nginx 限制访问频率
4. **监控**：配置监控和告警
5. **备份**：定期备份数据库文件

## 监控和健康检查

### 健康检查端点

```bash
curl http://localhost:8001/health
```

### 查看服务状态

```bash
# systemd
sudo systemctl status podcast-service

# supervisor
sudo supervisorctl status podcast-service
```

## 故障排查

### 查看日志

```bash
# systemd
sudo journalctl -u podcast-service -n 100 -f

# supervisor
tail -f /path/to/LanguageFlow/logs/podcast_service.log
```

### 检查端口占用

```bash
lsof -i:8001
```

### 重启服务

```bash
# systemd
sudo systemctl restart podcast-service

# supervisor
sudo supervisorctl restart podcast-service
```

