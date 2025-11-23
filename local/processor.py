"""Main processor for podcast fetching, transcription and translation"""
import asyncio
import hashlib
from typing import List, Dict, Any, Optional
from .podcast_fetcher_service import PodcastFetcherService
from .whisperx_service import transcribe_audio_url
from .translator import translate_segments, get_translator

def generate_podcast_id(company: str, channel: str, timestamp: int, audio_url: str, title: Optional[str] = None) -> str:
    normalized_company = (company or "").strip().lower()
    normalized_channel = (channel or "").strip().lower()
    normalized_title = (title or "").strip().lower()
    normalized_url = (audio_url or "").strip()
    content = f"{normalized_company}|{normalized_channel}|{timestamp}|{normalized_url}|{normalized_title}"
    hash_obj = hashlib.sha256(content.encode('utf-8'))
    return hash_obj.hexdigest()[:32]

async def process_podcast(podcast: Dict[str, Any], uploader=None) -> Dict[str, Any]:
    audio_url = podcast.get('audioURL')
    if not audio_url:
        raise ValueError('podcast必须包含audioURL字段')
    
    # 生成podcast_id用于检查
    podcast_id = generate_podcast_id(
        company=podcast.get('company', ''),
        channel=podcast.get('channel', ''),
        timestamp=podcast.get('timestamp', 0),
        audio_url=audio_url,
        title=podcast.get('title')
    )
    
    print(f'[processor] 开始处理podcast: {podcast.get("title", "Unknown")} (ID: {podcast_id})')
    
    # 检查服务端是否已有完整的podcast
    if uploader:
        is_complete = await uploader.check_podcast_complete(podcast_id)
        if is_complete:
            print(f'[processor] 服务端已有完整的podcast，跳过处理：podcast ID = {podcast_id}')
            # 返回 None 表示跳过处理
            return None
    
    # 如果没有找到完整的podcast，继续正常处理流程
    try:
        transcription_result = await transcribe_audio_url(audio_url)
        segments = transcription_result.get('segments', [])
        detected_language = transcription_result.get('language', 'en')
        print(f'[processor] 转录完成：{len(segments)} 个片段')
    except Exception as e:
        print(f'[processor] 转录失败: {e}')
        raise
    try:
        print(f'[processor] 开始翻译 {len(segments)} 个片段...')
        translations = await translate_segments(
            segments,
            source_lang=detected_language,
            target_lang='zh',
            use_context=True,
            use_full_context=True
        )
        for i, segment in enumerate(segments):
            segment['translation'] = translations[i] if i < len(translations) else ''
        success_count = sum(1 for t in translations if t)
        print(f'[processor] 翻译完成：成功 {success_count}/{len(segments)} 段')
    except Exception as e:
        print(f'[processor] 翻译失败: {e}')
        for segment in segments:
            if 'translation' not in segment:
                segment['translation'] = ''
    
    # 翻译标题
    title_translation = None
    title = podcast.get('title')
    if title:
        try:
            print(f'[processor] 开始翻译标题: {title}')
            translator = await get_translator()
            title_translations = await translator.translate_batch(
                [title],
                source_lang=detected_language,
                target_lang='zh',
                use_reflection=True,
                use_context=False,  # 标题不需要上下文
                use_full_context=False
            )
            if title_translations and title_translations[0]:
                title_translation = title_translations[0]
                print(f'[processor] 标题翻译完成: {title_translation}')
            else:
                print(f'[processor] 标题翻译为空')
        except Exception as e:
            print(f'[processor] 标题翻译失败: {e}')
    complete_podcast = {
        'id': podcast_id,
        'company': podcast.get('company', ''),
        'channel': podcast.get('channel', ''),
        'audioURL': audio_url,
        'title': podcast.get('title'),
        'titleTranslation': title_translation,
        'subtitle': podcast.get('subtitle'),
        'timestamp': podcast.get('timestamp', 0),
        'language': detected_language,
        'duration': podcast.get('duration'),
        'segments': segments
    }
    print(f'[processor] 处理完成：podcast ID = {podcast_id}')
    return complete_podcast


async def process_podcasts_batch(
    podcasts: List[Dict[str, Any]],
    max_concurrent: int = 1,
    uploader=None
) -> List[Dict[str, Any]]:
    """
    批量处理podcasts，处理完一个就上传一个（如果提供了uploader）
    
    Args:
        podcasts: podcast列表
        max_concurrent: 最大并发数，默认1
        uploader: 上传器实例，如果提供则处理完一个就上传一个
    
    Returns:
        处理完成的podcast列表
    """
    print(f'[processor] 开始批量处理 {len(podcasts)} 个podcasts（并发数: {max_concurrent}）')
    if uploader:
        print(f'[processor] 启用实时上传模式：处理完一个podcast就立即上传')
    
    semaphore = asyncio.Semaphore(max_concurrent)
    successful = []
    failed_count = 0
    skipped_count = 0
    
    async def process_with_semaphore(podcast):
        async with semaphore:
            try:
                processed = await process_podcast(podcast, uploader=uploader)
                # 如果返回 None，说明已跳过（服务端已有完整数据）
                if processed is None:
                    return 'skipped'
                
                # 如果提供了uploader，处理完立即上传
                if uploader:
                    print(f'[processor] 处理完成，立即上传: {processed.get("id")}')
                    upload_success = await uploader.upload_podcast(processed)
                    if upload_success:
                        print(f'[processor] ✓ 上传成功: {processed.get("title", "Unknown")}')
                    else:
                        print(f'[processor] ✗ 上传失败: {processed.get("title", "Unknown")}')
                
                return processed
            except Exception as e:
                print(f'[processor] 处理podcast失败: {e}')
                return 'failed'
    
    # 逐个处理（而不是并发），这样可以立即上传
    for i, podcast in enumerate(podcasts, 1):
        print(f'\n[processor] 处理进度: {i}/{len(podcasts)}')
        result = await process_with_semaphore(podcast)
        if result == 'skipped':
            skipped_count += 1
        elif result == 'failed':
            failed_count += 1
        elif result:
            successful.append(result)
    
    print(f'\n[processor] 批量处理完成：成功 {len(successful)}/{len(podcasts)} 个，跳过 {skipped_count} 个，失败 {failed_count} 个')
    return successful

async def fetch_and_process_today_podcasts(days: int = 1, uploader=None) -> List[Dict[str, Any]]:
    """
    获取并处理当天的podcasts
    
    Args:
        days: 获取前几天的数据，默认1（昨天）
        uploader: 上传器实例，如果提供则处理完一个就上传一个
    
    Returns:
        处理完成的podcast列表
    """
    print(f'[processor] 开始获取并处理前{days}天的podcasts...')
    # 1. 获取podcast列表 -> NPR All Things Considered
    podcasts = await PodcastFetcherService.fetch_npr_all_things_considered_by_days(days)
    if not podcasts:
        print(f'[processor] 未找到podcasts')
        return []
    print(f'[processor] 获取到 {len(podcasts)} 个podcasts，开始处理...')
    # 2. 批量处理（如果提供了uploader，会实时上传）
    processed = await process_podcasts_batch(podcasts, max_concurrent=1, uploader=uploader)
    return processed