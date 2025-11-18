# Podcast Service

独立的Podcast服务，用于拉取和存储podcast音频信息。

## 功能特性

- 支持NPR All Things Considered节目拉取
- SQLite数据库存储
- 基于音频属性的唯一ID生成
- RESTful API接口
- 健康检查

## 快速开始

### 1. 安装依赖

确保已安装以下依赖：
- fastapi
- uvicorn
- httpx
- feedparser

```bash
pip install fastapi uvicorn httpx feedparser
```

### 2. 启动服务

```bash
cd /Users/zhangpeibj01/Documents/projects/playmp3
./server/podcast_service/run.sh
```

或者直接使用uvicorn：

```bash
cd /Users/zhangpeibj01/Documents/projects/playmp3
uvicorn server.podcast_service.main:app --reload --port 8001
```

服务将在 `http://localhost:8001` 启动

### 3. 查看API文档

打开浏览器访问：
```
http://localhost:8001/docs
```

## API接口

### 1. 服务信息
```
GET /
```

### 2. 健康检查
```
GET /health
```

### 3. 拉取NPR All Things Considered节目
```
GET /api/podcasts/npr/atc?date=YYYY-MM-DD&store=true
```
- `date`: 可选，日期格式YYYY-MM-DD，默认为今天
- `store`: 可选，是否存储到数据库，默认为true

示例：
```bash
# 拉取当天的节目
curl http://localhost:8001/api/podcasts/npr/atc

# 拉取指定日期的节目（不存储）
curl "http://localhost:8001/api/podcasts/npr/atc?date=2025-11-20&store=false"
```

### 4. 查询podcasts
```
GET /api/podcasts?company=NPR&channel=All%20Things%20Considered&date=YYYY-MM-DD
```
- `company`: 必需，公司名称
- `channel`: 必需，频道名称
- `date`: 可选，日期格式YYYY-MM-DD，默认为今天

示例：
```bash
curl "http://localhost:8001/api/podcasts?company=NPR&channel=All%20Things%20Considered"
```

### 5. 根据ID查询podcast
```
GET /api/podcasts/{podcast_id}
```

## 数据库

数据库文件：`podcasts.db`（在项目根目录）

### 表结构

```sql
CREATE TABLE podcasts (
    id TEXT PRIMARY KEY,
    company TEXT NOT NULL,
    channel TEXT NOT NULL,
    audioURL TEXT NOT NULL,
    title TEXT,
    subtitle TEXT,
    timestamp INTEGER NOT NULL,
    language TEXT NOT NULL DEFAULT 'en',
    segments TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### ID生成规则

ID基于内容的hash生成：
- 使用 `company + channel + timestamp + audioURL + title` 的SHA256 hash
- 取hash的前32位作为ID
- **优点**：
  - 相同内容的podcast会生成相同的ID，自动去重
  - 配合 `INSERT OR REPLACE`，可以避免重复数据
  - ID具有确定性，便于调试和追踪
  - 不需要外部依赖，简单可靠

## 配置

### 环境变量

- `PODCAST_SERVICE_PORT`: 服务端口（默认：8001）
- `DB_PATH`: 数据库文件路径（默认：podcasts.db）

## 项目结构

```
podcast_service/
├── __init__.py
├── main.py           # FastAPI应用入口
├── database.py       # 数据库操作
├── npr_service.py    # NPR服务
├── run.sh           # 启动脚本
└── README.md        # 说明文档
```

## 使用示例

### Python调用示例

```python
import httpx

async def fetch_podcasts():
    async with httpx.AsyncClient() as client:
        # 拉取当天的节目
        response = await client.get("http://localhost:8001/api/podcasts/npr/atc")
        data = response.json()
        print(f"拉取了 {data['count']} 个episodes")
        
        # 查询已存储的podcasts
        response = await client.get(
            "http://localhost:8001/api/podcasts",
            params={
                "company": "NPR",
                "channel": "All Things Considered"
            }
        )
        podcasts = response.json()
        print(f"查询到 {podcasts['count']} 个podcasts")
```

## 故障排查

### 问题1：无法连接到NPR RSS feed
- 检查网络连接
- 确认RSS feed URL是否正确
- 如果在中国大陆，可能需要配置代理

### 问题2：数据库权限错误
确保数据库文件有写权限：
```bash
chmod 666 podcasts.db
```

### 问题3：端口被占用
修改端口：
```bash
PODCAST_SERVICE_PORT=8002 ./server/podcast_service/run.sh
```

