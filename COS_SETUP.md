# COS配置说明

## 概述

现在segments分句结果会上传到腾讯云COS（对象存储）保存为JSON文件，而不是存储在数据库中。这样可以：
- 减少数据库大小
- 提升查询性能
- 支持按需加载segments

## 环境变量配置

### 必需的环境变量

#### 1. 本地处理服务 (`local/processor.py`)

在运行`local/processor.py`之前，需要设置以下环境变量：

```bash
# 腾讯云COS配置
export COS_SECRET_ID="your-secret-id"
export COS_SECRET_KEY="your-secret-key"
export COS_REGION="ap-beijing"  # 你的COS地域，如 ap-beijing, ap-shanghai 等
export COS_BUCKET="your-bucket-name"  # 你的COS存储桶名称

# 可选：自定义域名（如果不设置，会使用默认格式）
export COS_DOMAIN="https://your-custom-domain.com"  # 可选
```

#### 2. 后端服务器 (`server/main.py`)

后端服务器也需要相同的COS配置，用于生成预签名URL：

```bash
# 腾讯云COS配置（与local服务相同）
export COS_SECRET_ID="your-secret-id"
export COS_SECRET_KEY="your-secret-key"
export COS_REGION="ap-beijing"
export COS_BUCKET="your-bucket-name"
```

**注意**：如果后端服务器未配置COS，`/podcast/detail/{podcast_id}` 接口将返回503错误。

### 获取COS配置信息

1. 登录[腾讯云控制台](https://console.cloud.tencent.com/)
2. 进入[对象存储COS](https://console.cloud.tencent.com/cos)
3. 创建存储桶（如果还没有）
4. 在[访问管理](https://console.cloud.tencent.com/cam)中创建API密钥，获取SecretId和SecretKey
5. 记录存储桶的地域和名称

## 文件结构

segments JSON文件会保存在COS的以下路径：
```
segments/{podcast_id}.json
```

例如：
```
segments/abc123def456.json
```

## 数据格式

segments JSON文件格式：
```json
[
  {
    "id": 1,
    "text": "Original text",
    "start": 2.444,
    "end": 5.329,
    "translation": "翻译文本"
  },
  {
    "id": 2,
    "text": "Another segment",
    "start": 5.329,
    "end": 8.123,
    "translation": "另一个片段"
  }
]
```

## 工作流程

1. **处理阶段** (`local/processor.py`):
   - 转录音频生成segments
   - 翻译segments
   - 上传segments JSON到COS
   - 获取segmentsURL（永久URL，存储在数据库）
   - 上传podcast数据（包含segmentsURL）到服务器

2. **查询阶段** (`server/main.py`):
   - 返回podcast详情（自动包含临时URL）
   - 不返回segments数组

3. **客户端加载** (`iOS App`):
   - 获取podcast详情（自动包含临时URL）
   - 使用返回的临时URL从COS加载segments JSON
   - 显示segments数据

## 安全架构

### 临时URL机制

为了安全，iOS客户端不直接访问COS的永久URL，而是：
1. 客户端请求podcast详情时，服务器返回`segmentsURL`（永久URL，仅用于标识）
2. 客户端需要加载segments时，调用 `/podcast/segments-url/{podcast_id}` 获取临时URL
3. 服务器使用COS密钥生成**预签名URL**（有效期5分钟）
4. 客户端使用临时URL下载segments JSON

**优势**：
- ✅ 不暴露COS的永久访问URL
- ✅ 临时URL有时效性（默认5分钟）
- ✅ 服务器可以控制访问权限
- ✅ 可以记录访问日志

## API端点

### 获取Podcast详情（自动包含临时URL）

```
GET /podcast/detail/{podcast_id}?expires=300
```

**参数**：
- `podcast_id` (路径参数): podcast的ID
- `expires` (查询参数，可选): 临时URL有效期（秒），范围60-3600，默认300秒（5分钟）

**响应**：
```json
{
  "success": true,
  "podcast": {
    "id": "podcast_id",
    "title": "Title",
    "segmentsKey": "segments/podcast_id.json",
    "segmentsTempURL": "https://bucket.cos.region.myqcloud.com/segments/podcast_id.json?sign=...",
    "segmentsTempURLExpiresIn": 300,
    ...
  }
}
```

**错误响应**：
- `404`: Podcast不存在
- `503`: COS服务未配置
- `500`: 生成临时URL失败

## 注意事项

1. **数据库迁移**：如果已有数据，需要手动迁移：
   - 旧数据：segments存储在`segments`表中
   - 新数据：segments存储在COS，数据库只存储segmentsURL

2. **错误处理**：
   - 如果COS上传失败，processor会抛出异常，不会继续处理
   - 如果获取临时URL失败，客户端会显示错误信息
   - 如果临时URL过期，客户端需要重新请求

3. **权限设置**：
   - COS存储桶不需要公开读取权限（使用预签名URL）
   - 建议设置CDN加速以提升加载速度

4. **成本考虑**：
   - COS存储费用：按存储量计费
   - COS流量费用：按下载流量计费
   - 建议启用CDN以降低流量成本

5. **临时URL有效期**：
   - 默认5分钟（300秒）
   - 最短60秒，最长3600秒（1小时）
   - 客户端应在URL过期前完成下载，或实现自动刷新机制

## 测试

测试COS配置是否正确：

```bash
# 设置环境变量
export COS_SECRET_ID="your-secret-id"
export COS_SECRET_KEY="your-secret-key"
export COS_REGION="ap-beijing"
export COS_BUCKET="your-bucket-name"

# 运行处理脚本
python local/run.py --days 1
```

检查COS中是否生成了segments文件：
- 登录腾讯云COS控制台
- 查看`segments/`目录下是否有JSON文件

