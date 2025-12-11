import os
import sqlite3
import logging
import time
from fastapi import FastAPI, HTTPException, Query, APIRouter, Body, Header, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from typing import List, Dict, Any, Annotated
from .database import PodcastDatabase
from .cos_service import COSService
from .models.auth_models import AuthDatabase
from .api.auth_api import register_or_login_handler
from .api.payment_api import verify_purchase_handler, get_devices_handler, unbind_device_handler
from .schemas.auth import RegisterRequest
from .schemas.payment import VerifyPurchaseRequest
from .dependencies.auth import get_current_device_uuid

app = FastAPI(
    title='LanguageFlow Service',
    description='LanguageFlow Service',
    version='1.0.0',
)

# 统一日志格式，方便本地调试购买流程
log_level = os.getenv("LOG_LEVEL", "INFO").upper()
if not logging.getLogger().hasHandlers():
    logging.basicConfig(
        level=getattr(logging, log_level, logging.INFO),
        format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
    )

logger = logging.getLogger('languageflow')
payment_logger = logging.getLogger('languageflow.payment')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """简单请求日志：方法、路径、状态码与耗时"""
    start_time = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start_time) * 1000
    logger.info(
        "HTTP %s %s status=%s duration=%.1fms",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response

podcast_router = APIRouter(prefix="/podcast/info", tags=["podcast"])
auth_router = APIRouter(prefix="/podcast/auth", tags=["authentication"])
payment_router = APIRouter(prefix="/podcast/payment", tags=["payment"])
user_router = APIRouter(prefix="/podcast/user", tags=["user"])

# 初始化数据库
db_path = os.getenv("DB_PATH", "podcasts.db")
podcast_db = PodcastDatabase(db_path=db_path)
auth_db = AuthDatabase(db_path=db_path)

# 获取数据库连接的辅助函数
def get_db_connection():
    """获取数据库连接"""
    conn = sqlite3.connect(db_path)
    return conn

# 初始化COS服务（用于生成预签名URL）
try:
    cos_service = COSService()
    logger.info(
        "COS 服务初始化成功 cdn_domain=%s bucket=%s",
        getattr(cos_service, "cdn_domain", None),
        getattr(cos_service, "bucket", None)
    )
except Exception as e:
    logger.error('[podcast-service] COS服务初始化失败: %s', e)
    cos_service = None

def _validate_and_insert_podcast(podcast: Dict[str, Any]) -> tuple[str, bool]:
    """
    验证并插入单个podcast的内部函数
    
    Returns:
        (podcast_id, success) 元组
    """
    # 验证必需字段
    required_fields = ['company', 'channel', 'audioKey', 'timestamp', 'segmentsKey', 'segmentCount']
    missing_fields = [f for f in required_fields if f not in podcast]
    if missing_fields:
        raise ValueError(f'缺少必需字段: {missing_fields}')
    podcast_id = podcast_db.insert_podcast(podcast)
    return podcast_id, True


@podcast_router.get('/query')
async def get_podcasts(
    _: Annotated[str, Depends(get_current_device_uuid)],  # 仅用于 token 验证
    company: str = Query(..., description='公司名称'),
    channel: str = Query(..., description='频道名称'),
    timestamp: int = Query(..., description='时间戳')
):
    try:
        podcasts = podcast_db.get_podcasts_by_timestamp(company, channel, timestamp)
        logger.info(
            "查询podcasts company=%s channel=%s timestamp=%s count=%s",
            company, channel, timestamp, len(podcasts)
        )
        return JSONResponse({
            'success': True,
            'count': len(podcasts),
            'podcasts': podcasts
        })
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[podcast-service] 查询podcasts失败')
        raise HTTPException(status_code=500, detail=f'查询失败: {str(error)}')


@podcast_router.get('/channels')
async def get_all_channels():
    """
    获取所有的podcast频道列表
    Returns:
        包含所有频道（company + channel）的JSON响应
    """
    try:
        channels = podcast_db.get_all_channels()
        logger.info("获取频道列表 count=%s", len(channels))
        return JSONResponse({
            'success': True,
            'count': len(channels),
            'channels': channels
        })
    except Exception as error:
        logger.exception('[podcast-service] 获取频道列表失败')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@podcast_router.get('/channels/{company}/{channel}/dates')
async def get_channel_dates(
    _: Annotated[str, Depends(get_current_device_uuid)],
    company: str,
    channel: str,
):
    """
    获取某个频道的所有日期时间戳列表
    """
    try:
        timestamps = podcast_db.get_channel_dates(company, channel)
        logger.info(
            "获取频道日期 company=%s channel=%s count=%s",
            company, channel, len(timestamps)
        )
        return JSONResponse({
            'success': True,
            'company': company,
            'channel': channel,
            'count': len(timestamps),
            'timestamps': timestamps
        })
    except Exception as error:
        logger.exception('[podcast-service] 获取频道日期列表失败')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@podcast_router.get('/channels/{company}/{channel}/podcasts')
async def get_channel_podcasts(
    _: Annotated[str, Depends(get_current_device_uuid)],
    company: str,
    channel: str,
    timestamp: int = Query(..., description='时间戳'),
):
    try:
        podcasts = podcast_db.get_channel_podcasts_by_timestamp(company, channel, timestamp)
        logger.info(
            "获取频道podcasts company=%s channel=%s timestamp=%s count=%s",
            company, channel, timestamp, len(podcasts)
        )
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
        logger.exception('[podcast-service] 获取频道podcasts失败')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')

@podcast_router.get('/channels/{company}/{channel}/podcasts/paged')
async def get_channel_podcasts_paginated(
    _: Annotated[str, Depends(get_current_device_uuid)],
    company: str,
    channel: str,
    page: int = Query(1, ge=1, description='页码，从1开始'),
    limit: int = Query(20, ge=1, le=200, description='每页数量，默认20')
):
    """
    获取某个频道的podcasts列表（分页）
    说明：
    - 按 timestamp DESC，再按 id DESC 保证稳定顺序
    - 日期数据不变动时可用 page+limit
    """
    try:
        data = podcast_db.get_channel_podcasts_paginated(company, channel, page, limit)
        total = data['total']
        podcasts = data['podcasts']
        total_pages = (total + limit - 1) // limit if limit > 0 else 1
        logger.info(
            "分页获取频道podcasts company=%s channel=%s page=%s limit=%s count=%s total=%s",
            company, channel, page, limit, len(podcasts), total
        )
        return JSONResponse({
            'success': True,
            'company': company,
            'channel': channel,
            'page': page,
            'limit': limit,
            'count': len(podcasts),
            'total': total,
            'total_pages': total_pages,
            'podcasts': podcasts
        })
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[podcast-service] 获取频道podcasts（分页）失败')
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@podcast_router.get('/check/{podcast_id}')
async def check_podcast_complete(
    _: Annotated[str, Depends(get_current_device_uuid)],
    podcast_id: str
):
    """
    检查podcast是否完整
    """
    try:
        is_complete = podcast_db.is_podcast_complete(podcast_id)
        logger.info(
            "检查podcast完整性 podcast_id=%s exists=%s is_complete=%s",
            podcast_id,
            podcast_db.podcast_exists(podcast_id),
            is_complete
        )
        return JSONResponse({
            'success': True,
            'exists': podcast_db.podcast_exists(podcast_id),
            'is_complete': is_complete
        })
    except Exception as error:
        logger.exception('[podcast-service] 检查podcast失败')
        raise HTTPException(status_code=500, detail=f'检查失败: {str(error)}')


@podcast_router.get('/detail/{podcast_id}')
async def get_podcast_detail_by_id(
    device_uuid: Annotated[str, Depends(get_current_device_uuid)],
    podcast_id: str,
    expires: int = Query(180, description='URL有效期（秒），默认180秒（3分钟）', ge=60, le=3600),
):
    """
    根据ID获取podcast详情
    会自动生成临时URL（预签名URL）并返回
    需要VIP权限（免费试听除外）
    """
    try:
        podcast = podcast_db.get_podcast_by_id(podcast_id)

        if not podcast:
            raise HTTPException(status_code=404, detail='Podcast not found')
        logger.info("查询podcast详情 podcast_id=%s device_uuid=%s", podcast_id, device_uuid)

        # 权限检查：判断是否免费
        company = podcast.get('company')
        channel = podcast.get('channel')
        is_free = podcast_db.is_podcast_free(company, channel, podcast_id)
        user = None

        if not is_free:
            # 检查用户是否是 VIP
            user = auth_db.get_user_by_uuid(device_uuid)
            if not user or not user.get('is_vip'):
                logger.warning(
                    "非VIP用户尝试访问付费内容 device_uuid=%s podcast_id=%s",
                    device_uuid, podcast_id
                )
                raise HTTPException(
                    status_code=403,
                    detail="VIP membership required"
                )

        logger.info(
            "权限检查通过 device_uuid=%s podcast_id=%s is_free=%s is_vip=%s",
            device_uuid, podcast_id, is_free, user.get('is_vip') if not is_free else 'N/A'
        )
        
        # 检查CDN服务是否可用
        if not cos_service or not cos_service.cdn_domain:
            raise HTTPException(
                status_code=503,
                detail='CDN service not configured. Please set COS_CDN_DOMAIN and COS_CDN_AUTH_KEY environment variables.'
            )
        
        # 生成segments CDN URL
        segments_key = podcast.get('segmentsKey')
        if not segments_key:
            raise HTTPException(status_code=500, detail='Podcast missing segmentsKey')
        
        try:
            segments_url = cos_service.get_cdn_url(segments_key, expires=expires)
        except Exception as e:
            logger.exception('[podcast-service] 生成segments CDN URL失败')
            raise HTTPException(status_code=500, detail=f'生成segments URL失败: {str(e)}')
        
        # 生成音频CDN URL
        audio_key = podcast.get('audioKey')
        if not audio_key:
            raise HTTPException(status_code=500, detail='Podcast missing audioKey')
        
        try:
            audio_url = cos_service.get_cdn_url(audio_key, expires=expires)
        except Exception as e:
            logger.exception('[podcast-service] 生成音频CDN URL失败')
            raise HTTPException(status_code=500, detail=f'生成音频URL失败: {str(e)}')
        
        # 返回podcast详情，包含CDN URL
        result = dict(podcast)
        result['segmentsURL'] = segments_url
        result['audioURL'] = audio_url
        result['isFree'] = is_free
        result.pop('segmentsKey', None)
        result.pop('audioKey', None)
        
        return JSONResponse({
            'success': True,
            'podcast': result
        })
        
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[podcast-service] 查询podcast失败')
        raise HTTPException(status_code=500, detail=f'查询失败: {str(error)}')


@podcast_router.post('/upload')
async def upload_podcast(podcast: Dict[str, Any] = Body(...)):
    """
    上传完整的podcast数据
    
    请求体格式:
    {
        "id": "podcast_id",
        "company": "NPR",
        "channel": "All Things Considered",
        "audioKey": "audio/channel/2023-11-15/podcast_id.mp3",
        "title": "Title",
        "subtitle": "Description",
        "timestamp": 1234567890,
        "language": "en",
        "duration": 3600,
        "segmentsKey": "segments/channel/2023-11-15/podcast_id.json",
        "segmentCount": 100
    }
    """
    try:
        podcast_id, _ = _validate_and_insert_podcast(podcast)
        logger.info(
            '成功上传podcast id=%s title=%s company=%s channel=%s',
            podcast_id,
            podcast.get("title", "Unknown"),
            podcast.get("company"),
            podcast.get("channel"),
        )
        return JSONResponse({
            'success': True,
            'message': 'Podcast上传成功',
            'id': podcast_id,
            'segmentsKey': podcast.get('segmentsKey')
        })
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[podcast-service] 上传podcast失败')
        raise HTTPException(status_code=500, detail=f'上传失败: {str(error)}')


@podcast_router.post('/upload/batch')
async def upload_podcasts_batch(podcasts: List[Dict[str, Any]] = Body(...)):
    """
    批量上传podcasts（包含segmentsKey和segmentCount）
    请求体格式:
    [
        {
            "id": "podcast_id",
            "company": "NPR",
            ...
            "segmentsKey": "segments/podcast_id.json",
            "segmentCount": 100
        },
        ...
    ]
    """
    try:
        if not podcasts:
            raise HTTPException(status_code=400, detail='podcasts列表不能为空')
        success_count = 0
        fail_count = 0
        failed_ids = []
        for podcast in podcasts:
            try:
                podcast_id, _ = _validate_and_insert_podcast(podcast)
                success_count += 1
                logger.info(
                    '批量上传成功 podcast_id=%s company=%s channel=%s',
                    podcast_id,
                    podcast.get("company"),
                    podcast.get("channel"),
                )
            except ValueError as e:
                fail_count += 1
                podcast_id = podcast.get('id', 'unknown')
                failed_ids.append(podcast_id)
                logger.warning('[podcast-service] 跳过podcast (%s): %s', podcast_id, e)
            except Exception as e:
                fail_count += 1
                podcast_id = podcast.get('id', 'unknown')
                failed_ids.append(podcast_id)
                logger.exception('[podcast-service] 上传podcast失败 (%s)', podcast_id)
        
        return JSONResponse({
            'success': True,
            'message': f'批量上传完成：成功 {success_count}，失败 {fail_count}',
            'success_count': success_count,
            'fail_count': fail_count,
            'total': len(podcasts),
            'failed_ids': failed_ids
        })
        
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[podcast-service] 批量上传失败')
        raise HTTPException(status_code=500, detail=f'批量上传失败: {str(error)}')

@auth_router.post('/register')
async def register_or_login(request: RegisterRequest):
    """注册或登录"""
    try:
        result = register_or_login_handler(request, auth_db)
        logger.info(
            "注册/登录完成 device_uuid=%s is_vip=%s device_status=%s",
            request.device_uuid,
            result["data"].get("is_vip"),
            result["data"].get("device_status"),
        )
        return JSONResponse(result)
    except Exception as error:
        logger.exception('[server] 注册失败')
        raise HTTPException(status_code=500, detail=f'注册失败: {str(error)}')


@payment_router.post('/verify')
async def verify_purchase(
    request: VerifyPurchaseRequest,
    device_uuid: Annotated[str, Depends(get_current_device_uuid)]
):
    """验证购买凭证"""
    try:
        payment_logger.info(
            "收到内购校验请求 device_uuid=%s event=%s device_name=%s",
            device_uuid, request.event_type, request.device_name
        )
        with get_db_connection() as conn:
            result = verify_purchase_handler(request, device_uuid, auth_db, conn)
            payment_logger.info(
                "内购校验完成 device_uuid=%s event=%s vip=%s expire=%s kicked=%s bound=%s",
                device_uuid,
                request.event_type,
                result["data"].get("is_vip"),
                result["data"].get("vip_expire_time"),
                result["data"].get("kicked_device"),
                result["data"].get("bound_devices"),
            )
            return JSONResponse(result)
    except HTTPException:
        raise
    except Exception as error:
        payment_logger.exception('[server] 验证购买失败 device_uuid=%s', device_uuid)
        raise HTTPException(status_code=500, detail=f'验证失败: {str(error)}')


@user_router.get('/devices')
async def get_devices(
    device_uuid: Annotated[str, Depends(get_current_device_uuid)]
):
    """获取绑定的设备列表"""
    try:
        with get_db_connection() as conn:
            result = get_devices_handler(device_uuid, auth_db, conn)
            logger.info(
                "查询绑定设备 device_uuid=%s count=%s",
                device_uuid,
                len(result.get("data", {}).get("devices", [])),
            )
            return JSONResponse(result)
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[server] 获取设备列表失败 device_uuid=%s', device_uuid)
        raise HTTPException(status_code=500, detail=f'获取失败: {str(error)}')


@user_router.delete('/devices/{target_device_uuid}')
async def unbind_device(
    target_device_uuid: str,
    device_uuid: Annotated[str, Depends(get_current_device_uuid)]
):
    """解绑设备"""
    try:
        with get_db_connection() as conn:
            result = unbind_device_handler(device_uuid, target_device_uuid, auth_db, conn)
            logger.info(
                "解绑设备完成 device_uuid=%s target_device=%s code=%s",
                device_uuid,
                target_device_uuid,
                result.get("code"),
            )
            return JSONResponse(result)
    except HTTPException:
        raise
    except Exception as error:
        logger.exception('[server] 解绑设备失败 device_uuid=%s target_device=%s', device_uuid, target_device_uuid)
        raise HTTPException(status_code=500, detail=f'解绑失败: {str(error)}')


app.include_router(podcast_router)
app.include_router(auth_router)
app.include_router(payment_router)
app.include_router(user_router)

# 根路径
@app.get("/")
async def root():
    return {
        "message": "LanguageFlow Service",
        "version": "1.0.0",
        "features": ["podcasts", "authentication", "in-app-purchase"]
    }

# 启动服务
if __name__ == '__main__':
    import uvicorn
    port = int(os.getenv('PORT', '8001'))
    uvicorn.run(app, host='0.0.0.0', port=port)
