# Server Service

统一的 server 服务，提供 Podcast 数据存储和查询功能。

**注意**：Podcast 抓取功能已移至 `local/` 目录，server 端只负责接收和存储已处理的数据。

## 📋 目录

- [快速开始](#快速开始)
- [Ubuntu 服务器部署](#ubuntu-服务器部署)
  - [基础部署](#基础部署)
  - [域名和 HTTPS 配置](#域名和-https-配置)
  - [进程管理](#进程管理)
- [服务配置](#服务配置)
- [故障排查](#故障排查)
- [快速参考](#快速参考)

---

## 🚀 快速开始

### 本地开发

```bash
# 启动服务（开发环境）
sh server/run.sh

# 或指定生产环境
SERVER_ENV=production sh server/run.sh
```

---

## 📦 Ubuntu 服务器部署

### 基础部署

#### 1. 前置要求

- Ubuntu 18.04+
- Python 3.8+
- Git

#### 2. 安装依赖

```bash
# 更新系统并安装 Python
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

# 进入项目目录
cd /path/to/LanguageFlow

# 创建虚拟环境
python3 -m venv .venv
source .venv/bin/activate

# 安装项目依赖
pip install --upgrade pip
pip install -r requirements.txt
```

#### 3. 启动服务

```bash
# 开发环境（测试用）
source .venv/bin/activate
sh server/run.sh

# 生产环境
SERVER_ENV=production sh server/run.sh
```

#### 4. 配置防火墙

```bash
# 开放服务端口
sudo ufw allow 8001/tcp

# 如果使用域名和 HTTPS
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
```

---

### 域名和 HTTPS 配置

#### 步骤 1：配置 DNS 解析

在域名服务商添加 A 记录：

```
类型: A
主机记录: @ 或 api
记录值: 服务器公网 IP
TTL: 600
```

示例：`api.yourdomain.com` → 服务器 IP

#### 步骤 2：安装 Nginx

```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

#### 步骤 3：配置 Nginx 反向代理

创建配置文件：

```bash
sudo nano /etc/nginx/sites-available/languageflow
```

添加配置（替换 `your-domain.com`）：

```nginx
# HTTP - 重定向到 HTTPS
server {
    listen 80;
    server_name your-domain.com api.your-domain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name your-domain.com api.your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

启用配置：

```bash
sudo ln -s /etc/nginx/sites-available/languageflow /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default  # 可选
sudo nginx -t
sudo systemctl reload nginx
```

#### 步骤 4：配置 SSL 证书

```bash
# 安装 Certbot
sudo apt install certbot python3-certbot-nginx -y

# 获取证书（自动配置）
sudo certbot --nginx -d your-domain.com --email your-email@example.com --agree-tos --non-interactive

# 测试自动续期
sudo certbot renew --dry-run
```

#### 步骤 5：验证配置

```bash
# 测试 HTTPS
curl https://your-domain.com/health

# 查看证书信息
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
```

---

### 进程管理

#### 方式 1：systemd（推荐）

创建服务文件 `/etc/systemd/system/languageflow.service`：

```ini
[Unit]
Description=LanguageFlow Server Service
After=network.target

[Service]
Type=simple
User=your-username
Group=your-group
WorkingDirectory=/path/to/LanguageFlow
Environment="SERVER_ENV=production"
Environment="UVICORN_WORKERS=4"
Environment="PORT=8001"
Environment="VENV_PATH=/path/to/LanguageFlow/.venv"
Environment="PATH=/path/to/LanguageFlow/.venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/bin/bash /path/to/LanguageFlow/server/run.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**重要**：替换 `your-username`、`your-group` 和 `/path/to/LanguageFlow` 为实际值。

管理服务：

```bash
sudo systemctl daemon-reload
sudo systemctl start languageflow
sudo systemctl enable languageflow
sudo systemctl status languageflow
```

#### 方式 2：Supervisor

安装并配置：

```bash
# 安装
sudo apt install supervisor -y

# 创建配置
sudo nano /etc/supervisor/conf.d/languageflow.conf
```

配置内容：

```ini
[program:languageflow]
command=/bin/bash /path/to/LanguageFlow/server/run.sh
directory=/path/to/LanguageFlow
user=your-username
autostart=true
autorestart=true
stderr_logfile=/path/to/LanguageFlow/logs/server_error.log
stdout_logfile=/path/to/LanguageFlow/logs/server.log
environment=SERVER_ENV="production",UVICORN_WORKERS="4",PORT="8001",VENV_PATH="/path/to/LanguageFlow/.venv"
```

启动服务：

```bash
mkdir -p /path/to/LanguageFlow/logs
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start languageflow
```

---

## ⚙️ 服务配置

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `SERVER_ENV` | 环境模式：`development` 或 `production` | `development` |
| `UVICORN_WORKERS` | Worker 数量（生产环境） | `4` |
| `PORT` | 服务端口 | `8001` |
| `VENV_PATH` | 虚拟环境路径 | `.venv` |
| `COS_SECRET_ID` | 腾讯云COS SecretId（用于生成预签名URL） | - |
| `COS_SECRET_KEY` | 腾讯云COS SecretKey（用于生成预签名URL） | - |
| `COS_REGION` | COS地域，如 ap-beijing | `ap-beijing` |
| `COS_BUCKET` | COS存储桶名称 | - |

**注意**：如果未配置COS相关环境变量，`/podcast/detail/{podcast_id}` 接口将返回503错误。

### API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/` | GET | 服务信息和端点列表 |
| `/podcast/channels` | GET | 获取所有频道列表 |
| `/podcast/channels/{company}/{channel}/dates` | GET | 获取频道日期列表 |
| `/podcast/channels/{company}/{channel}/podcasts` | GET | 获取频道某日期的podcasts |
| `/podcast/detail/{podcast_id}` | GET | 根据ID获取podcast详情（自动包含临时URL） |
| `/podcast/upload` | POST | 上传单个podcast（包含segmentsKey和segmentCount） |
| `/podcast/upload/batch` | POST | 批量上传podcasts（包含segmentsURL） |
| `/docs` | GET | API 文档（Swagger UI） |

**注意**：
- Podcast 抓取和转录功能在 `local/` 目录中处理，然后通过 `/podcast/upload` 接口上传到服务器。
- segments数据存储在COS，客户端通过 `/podcast/detail/{podcast_id}` 获取podcast详情时会自动包含临时URL。

---

## 🔧 故障排查

### 服务无法启动

```bash
# 检查 Python 和依赖
which python3
which uvicorn
pip list | grep -E "fastapi|uvicorn"

# 检查端口占用
sudo lsof -i:8001

# 手动测试
cd /path/to/LanguageFlow
source .venv/bin/activate
sh server/run.sh
```

### 虚拟环境问题

```bash
# 重新创建虚拟环境
rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 查看日志

```bash
# systemd
sudo journalctl -u languageflow -f

# supervisor
tail -f /path/to/LanguageFlow/logs/server.log

# Nginx
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### DNS/SSL 问题

```bash
# 检查 DNS 解析
nslookup your-domain.com
dig your-domain.com

# 检查端口占用
sudo lsof -i:80
sudo lsof -i:443

# 检查防火墙
sudo ufw status

# 测试 Nginx 配置
sudo nginx -t

# 查看证书
sudo certbot certificates
```

---

## 📖 快速参考

### 常用命令

```bash
# 启动服务
sh server/run.sh

# 查看服务状态（systemd）
sudo systemctl status languageflow

# 重启服务
sudo systemctl restart languageflow

# 查看日志
sudo journalctl -u languageflow -f
```

### 测试服务

```bash
# 本地测试
curl http://localhost:8001/health
curl http://localhost:8001/

# 域名测试（如果已配置）
curl https://your-domain.com/health
curl https://your-domain.com/

# API 文档
# 浏览器访问：http://localhost:8001/docs
# 或：https://your-domain.com/docs
```

### 获取实际路径

```bash
# 当前用户名
whoami

# 当前用户组
groups

# 项目路径
pwd
```

---

## 📝 注意事项

1. **路径替换**：所有文档中的 `/path/to/LanguageFlow` 需要替换为实际项目路径
2. **用户名替换**：`your-username` 和 `your-group` 需要替换为实际值
3. **域名替换**：`your-domain.com` 需要替换为实际域名
4. **生产环境**：建议使用 systemd 或 Supervisor 管理服务
5. **HTTPS**：生产环境强烈建议配置 HTTPS
6. **防火墙**：确保必要端口已开放

---

## 🔗 相关资源

- [FastAPI 文档](https://fastapi.tiangolo.com/)
- [Uvicorn 文档](https://www.uvicorn.org/)
- [Nginx 文档](https://nginx.org/en/docs/)
- [Let's Encrypt 文档](https://letsencrypt.org/docs/)
