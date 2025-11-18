"""Podcast Service - 独立的FastAPI服务"""
import os
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from .database import PodcastDatabase
from .npr_service import NPRService

# 创建独立的FastAPI应用
app = FastAPI(
    title='Podcast Service',
    description='Podcast音频拉取和存储服务（支持NPR All Things Considered等）',
    version='1.0.0',
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

# 初始化数据库和NPR服务
db = PodcastDatabase()
npr_service = NPRService()


@app.get('/')
async def root():
    """服务根路径"""
    return {
        'service': 'Podcast Service',
        'version': '1.0.0',
        'endpoints': {
            'fetch_npr': '/api/podcasts/npr/atc',
            'query': '/api/podcasts',
            'get_by_id': '/api/podcasts/{id}',
            'health': '/health',
            'docs': '/docs'
        }
    }


@app.get('/health')
async def health():
    """健康检查"""
    return {'status': 'healthy', 'service': 'Podcast Service'}


@app.get('/api/podcasts/npr/atc')
async def fetch_npr_atc(
    days: Optional[int] = Query(None, description='前几天的数据总和，不传等价于传1（昨天），传2表示昨天和前天，传3表示昨天、前天和大前天'),
    store: bool = Query(True, description='是否存储到数据库，默认为True')
):
    """
    拉取NPR All Things Considered的音频链接和标题，并存储到数据库
    
    Args:
        days: 可选，前几天的数据总和，不传等价于传1（昨天），传2表示昨天和前天，传3表示昨天、前天和大前天
        store: 是否存储到数据库，默认为True
        
    Returns:
        包含拉取和存储结果的JSON响应
    """
    try:
        # 解析天数参数（统一使用UTC时区）
        from datetime import timezone, timedelta
        
        # 默认值为1（昨天）
        if days is None:
            days = 1
        
        if days < 1:
            raise HTTPException(status_code=400, detail='days参数必须大于等于1')
        
        if days > 30:
            raise HTTPException(status_code=400, detail='days参数不能超过30')
        
        print(f'[podcast-service] 开始拉取NPR All Things Considered（前{days}天）')
        
        # 拉取多天的episodes
        all_episodes = await npr_service.fetch_episodes_by_days(days)
        
        if not all_episodes:
            return JSONResponse({
                'success': True,
                'message': f'未找到前{days}天的节目',
                'count': 0,
                'episodes': []
            })
        
        # 存储到数据库（如果需要）
        stored_podcasts = []
        if store:
            for episode in all_episodes:
                try:
                    podcast_id = db.insert_podcast(episode)
                    # 获取存储后的完整podcast数据
                    stored_podcast = db.get_podcast_by_id(podcast_id)
                    if stored_podcast:
                        stored_podcasts.append(stored_podcast)
                except Exception as e:
                    print(f'[podcast-service] 存储podcast失败: {e}')
        else:
            # 如果不存储，直接返回拉取的数据（需要生成ID）
            for episode in all_episodes:
                episode['id'] = db.generate_id(
                    company=episode['company'],
                    channel=episode['channel'],
                    timestamp=episode['timestamp'],
                    audio_url=episode['audioURL'],
                    title=episode.get('title')
                )
            stored_podcasts = all_episodes
        
        print(f'[podcast-service] 成功拉取 {"并存储" if store else ""} {len(stored_podcasts)}/{len(all_episodes)} 个episodes')
        
        return JSONResponse({
            'success': True,
            'message': f'成功拉取{"并存储" if store else ""}{len(stored_podcasts)}个episodes',
            'count': len(stored_podcasts),
            'stored': store,
            'episodes': [
                {
                    'id': podcast.get('id'),
                    'title': podcast.get('title'),
                    'audioURL': podcast.get('audioURL'),
                    'timestamp': podcast.get('timestamp'),
                    'subtitle': podcast.get('subtitle')
                }
                for podcast in stored_podcasts
            ]
        })
        
    except HTTPException:
        raise
    except Exception as error:
        print(f'[podcast-service] 拉取NPR All Things Considered失败: {error}')
        raise HTTPException(status_code=500, detail=f'拉取失败: {str(error)}')


@app.get('/api/podcasts')
async def get_podcasts(
    company: str = Query(..., description='公司名称，如：NPR'),
    channel: str = Query(..., description='频道名称，如：All Things Considered'),
    date: Optional[str] = Query(None, description='日期，格式：YYYY-MM-DD，默认为前一天')
):
    """
    查询已存储的podcasts
    
    Args:
        company: 公司名称
        channel: 频道名称
        date: 可选，日期字符串，格式为YYYY-MM-DD，默认为前一天
        
    Returns:
        包含podcast列表的JSON响应
    """
    try:
        # 解析日期（统一使用UTC时区）
        from datetime import timezone, timedelta
        target_date = None
        if date:
            try:
                # 解析为本地时区的日期，然后转换为UTC
                naive_date = datetime.strptime(date, '%Y-%m-%d')
                target_date = naive_date.replace(tzinfo=timezone.utc)
            except ValueError:
                raise HTTPException(status_code=400, detail='日期格式错误，请使用YYYY-MM-DD格式')
        else:
            # 默认查询前一天的节目
            target_date = datetime.now(timezone.utc) - timedelta(days=1)
        
        # 从数据库查询
        podcasts = db.get_podcasts_by_date(company, channel, target_date)
        
        return JSONResponse({
            'success': True,
            'count': len(podcasts),
            'podcasts': podcasts
        })
        
    except HTTPException:
        raise
    except Exception as error:
        print(f'[podcast-service] 查询podcasts失败: {error}')
        raise HTTPException(status_code=500, detail=f'查询失败: {str(error)}')


@app.get('/api/podcasts/{podcast_id}')
async def get_podcast_by_id(podcast_id: str):
    """
    根据ID获取podcast详情
    
    Args:
        podcast_id: podcast的ID
        
    Returns:
        包含podcast详情的JSON响应
    """
    try:
        podcast = db.get_podcast_by_id(podcast_id)
        
        if not podcast:
            raise HTTPException(status_code=404, detail='Podcast not found')
        
        return JSONResponse({
            'success': True,
            'podcast': podcast
        })
        
    except HTTPException:
        raise
    except Exception as error:
        print(f'[podcast-service] 查询podcast失败: {error}')
        raise HTTPException(status_code=500, detail=f'查询失败: {str(error)}')


# 如果直接运行此文件，启动独立服务
if __name__ == '__main__':
    import uvicorn
    port = int(os.getenv('PODCAST_SERVICE_PORT', '8001'))
    uvicorn.run(app, host='0.0.0.0', port=port)

