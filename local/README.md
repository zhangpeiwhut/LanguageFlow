# Local Podcast Processor

本地Podcast处理模块，用于抓取、转录和翻译podcast，然后上传到服务器。

## 功能

1. **抓取Podcast**: 从多个来源获取podcast列表（目前支持NPR All Things Considered，可扩展）
2. **转录**: 使用WhisperX对音频进行转录和对齐
3. **翻译**: 调用大模型翻译segments（支持阿里云和XYKS提供商）
4. **上传**: 批量上传完整podcast信息到服务器

## 目录结构

```
local/
├── __init__.py                    # 模块初始化
├── podcast_fetcher_service.py    # Podcast抓取服务（支持多个company/channel）
├── whisperx_service.py            # WhisperX转录服务
├── translator/                    # 翻译服务模块
│   ├── __init__.py
│   ├── translator.py              # 翻译器主类
│   └── models/                    # 模型提供商实现
│       ├── __init__.py
│       ├── base.py                # 基类
│       ├── alibaba.py             # 阿里云模型
│       ├── xyks.py                # XYKS模型
│       ├── prompts.py             # 提示词构建
│       └── utils.py               # 工具类
├── processor.py                  # 主处理逻辑
├── uploader.py                   # 上传服务
├── main.py                       # 主脚本入口
├── scheduler.py                  # 定时任务调度器
├── run.py                        # 可执行入口脚本
├── run_scheduler.py              # 定时任务入口脚本
├── requirements.txt               # 依赖列表
└── README.md                     # 本文档
```

## 安装依赖

```bash
# 安装local模块的依赖
pip install -r local/requirements.txt

# 或者单独安装
pip install httpx whisperx torch schedule
```

## 使用方法

### 1. 手动执行

```bash
# 处理昨天的podcasts并上传
python local/run.py

# 处理前3天的podcasts
python local/run.py --days 3

# 不上传到服务器（仅本地处理）
python local/run.py --no-upload

# 指定服务器URL
python local/run.py --server-url https://elegantfish.online
```

### 2. 定时执行

有两种方式可以实现定时执行：

#### 方式A：Python进程内调度器（适合开发/测试）

```bash
# 启动定时调度器（默认每天凌晨4点30执行）
# 注意：这个进程必须一直运行，如果进程退出，定时任务就停止了
python local/run_scheduler.py
```

**工作原理**：
- 使用 Python 的 `schedule` 库
- 进程会一直运行，每分钟检查一次是否需要执行任务
- **缺点**：进程挂了或服务器重启后，需要手动重新启动

**适用场景**：
- 开发环境测试
- 短期运行
- 需要频繁修改配置

环境变量配置：

```bash
# 调度时间（24小时制）
export SCHEDULER_TIME="04:30"

# 处理天数
export SCHEDULER_DAYS=1

# 是否上传
export SCHEDULER_UPLOAD=true

# 服务器URL
export SERVER_URL="https://elegantfish.online"

# 启动时立即执行一次
export SCHEDULER_RUN_ONCE=true
```

#### 方式B：系统级 Cron（推荐生产环境）

```bash
# 编辑crontab
crontab -e

# 添加定时任务（每天凌晨4点30执行）
30 4 * * * cd /path/to/LanguageFlow && /path/to/python local/run.py >> /path/to/logs/podcast.log 2>&1
```

**工作原理**：
- 使用系统的 cron 服务
- 系统会自动管理，进程挂了或服务器重启后仍会执行
- **优点**：更可靠，适合生产环境

**适用场景**：
- 生产环境
- 需要长期稳定运行
- 服务器会自动重启的场景

**Cron 时间格式说明**：
```
分 时 日 月 周  命令
30 4  *  *  *  每天4点30分执行
0  2  *  *  *  每天2点执行
0  */6 *  *  *  每6小时执行一次
```

## 环境变量

### WhisperX配置

```bash
# WhisperX模型ID（默认: medium）
export WHISPERX_MODEL_ID="medium"

# 批处理大小（默认: 8）
export WHISPERX_BATCH_SIZE=8

# 计算类型（默认: 根据设备自动选择）
export WHISPERX_COMPUTE_TYPE="float16"  # cuda使用float16, cpu使用int8

# 设备覆盖（默认: 自动检测）
export WHISPERX_DEVICE="cuda"  # 或 "cpu"
```

### 翻译服务配置

```bash
# 翻译提供商（alibaba 或 xyks，默认: xyks
export TRANSLATOR_PROVIDER="xyks"

# 阿里云配置（如果使用 alibaba）
export QWEN_API_KEY="your-api-key"

# XYKS配置（如果使用 xyks）
export XYKS_API_KEY="your-api-key"
export XYKS_MODEL="gpt-4o-mini"  # 可选，默认 gpt-4o-mini
export XYKS_BIZ=6  # 可选，默认 6
```

### 服务器配置

```bash
# 服务器URL
export SERVER_URL="https://elegantfish.online"
```

## 输出格式

处理后的podcast包含以下字段：

```json
{
  "id": "podcast_id",
  "company": "NPR",
  "channel": "All Things Considered",
  "audioURL": "https://...",
  "title": "Podcast Title",
  "subtitle": "Description",
  "timestamp": 1234567890,
  "language": "en",
  "duration": 3600,
  "segments": [
    {
      "id": "segment_id",
      "text": "Original text",
      "start": 2.444,
      "end": 5.329,
      "translation": "翻译文本"
    }
  ]
}
```