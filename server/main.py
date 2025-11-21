"""Podcast Service - FastAPI服务"""
import os
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException, Query, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from .database import PodcastDatabase
from .npr_service import NPRService

# 创建FastAPI应用
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

# 路由都以 /podcast 为前缀
router = APIRouter(prefix="/podcast", tags=["podcast"])

# 初始化数据库和NPR服务
db_path = os.getenv("DB_PATH", "podcasts.db")
db = PodcastDatabase(db_path=db_path)
npr_service = NPRService()

@router.get('/npr/atc')
async def fetch_npr_atc(
    days: Optional[int] = Query(None, description='前几天的数据总和，不传等价于传1（昨天）'),
    store: bool = Query(True, description='是否存储到数据库，默认为True')
):

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
                    stored_podcast = db.get_podcast_by_id(podcast_id)
                    if stored_podcast:
                        stored_podcasts.append(stored_podcast)
                except Exception as e:
                    print(f'[podcast-service] 存储podcast失败: {e}')
        else:
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


@router.get('/query')
async def get_podcasts(
    company: str = Query(..., description='公司名称'),
    channel: str = Query(..., description='频道名称'),
    timestamp: int = Query(..., description='时间戳')
):
    try:
        podcasts = db.get_podcasts_by_timestamp(company, channel, timestamp)
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


@router.get('/channels')
async def get_all_channels():
    """
    获取所有的podcast频道列表
    Returns:
        包含所有频道（company + channel）的JSON响应
    """
    try:
        channels = db.get_all_channels()
        return JSONResponse({
            'success': True,
            'count': len(channels),
            'channels': channels
        })
    except Exception as error:
        print(f'[podcast-service] 获取频道列表失败: {error}')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@router.get('/channels/{company}/{channel}/dates')
async def get_channel_dates(company: str, channel: str):
    """
    获取某个频道的所有日期时间戳列表
    """
    try:
        timestamps = db.get_channel_dates(company, channel)
        return JSONResponse({
            'success': True,
            'company': company,
            'channel': channel,
            'count': len(timestamps),
            'timestamps': timestamps
        })
    except Exception as error:
        print(f'[podcast-service] 获取频道日期列表失败: {error}')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@router.get('/channels/{company}/{channel}/podcasts')
async def get_channel_podcasts(
    company: str,
    channel: str,
    timestamp: int = Query(..., description='时间戳')
):
    try:
        podcasts = db.get_channel_podcasts_by_timestamp(company, channel, timestamp)
        return JSONResponse({
            'success': True,
            'company': company,
            'channel': channel,
            'timestamp': timestamp,
            'count': len(podcasts),
            'podcasts': podcasts
        })
    except HTTPException:
        raise
    except Exception as error:
        print(f'[podcast-service] 获取频道podcasts失败: {error}')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@router.get('/detail/{podcast_id}')
async def get_podcast_detail_by_id(podcast_id: str):
    """
    根据ID获取podcast详情
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


# 注册路由
app.include_router(router)

# 启动服务
if __name__ == '__main__':
    import uvicorn
    port = int(os.getenv('PORT', '8001'))
    uvicorn.run(app, host='0.0.0.0', port=port)

