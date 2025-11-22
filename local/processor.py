"""Main processor for podcast fetching, transcription and translation"""
import asyncio
import hashlib
from typing import List, Dict, Any, Optional
from .podcast_fetcher_service import PodcastFetcherService
from .whisperx_service import transcribe_audio_url
from .translator import translate_segments

def generate_podcast_id(company: str, channel: str, timestamp: int, audio_url: str, title: Optional[str] = None) -> str:
    normalized_company = (company or "").strip().lower()
    normalized_channel = (channel or "").strip().lower()
    normalized_title = (title or "").strip().lower()
    normalized_url = (audio_url or "").strip()
    content = f"{normalized_company}|{normalized_channel}|{timestamp}|{normalized_url}|{normalized_title}"
    hash_obj = hashlib.sha256(content.encode('utf-8'))
    return hash_obj.hexdigest()[:32]

async def process_podcast(podcast: Dict[str, Any]) -> Dict[str, Any]:
    audio_url = podcast.get('audioURL')
    if not audio_url:
        raise ValueError('podcast必须包含audioURL字段')
    print(f'[processor] 开始处理podcast: {podcast.get("title", "Unknown")}')
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
    podcast_id = generate_podcast_id(
        company=podcast.get('company', ''),
        channel=podcast.get('channel', ''),
        timestamp=podcast.get('timestamp', 0),
        audio_url=audio_url,
        title=podcast.get('title')
    )
    complete_podcast = {
        'id': podcast_id,
        'company': podcast.get('company', ''),
        'channel': podcast.get('channel', ''),
        'audioURL': audio_url,
        'title': podcast.get('title'),
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
    max_concurrent: int = 1
) -> List[Dict[str, Any]]:
    print(f'[processor] 开始批量处理 {len(podcasts)} 个podcasts（并发数: {max_concurrent}）')
    semaphore = asyncio.Semaphore(max_concurrent)
    async def process_with_semaphore(podcast):
        async with semaphore:
            try:
                return await process_podcast(podcast)
            except Exception as e:
                print(f'[processor] 处理podcast失败: {e}')
                return None
    tasks = [process_with_semaphore(podcast) for podcast in podcasts]
    results = await asyncio.gather(*tasks)
    successful = [r for r in results if r is not None]
    print(f'[processor] 批量处理完成：成功 {len(successful)}/{len(podcasts)} 个')
    return successful

async def fetch_and_process_today_podcasts(days: int = 1) -> List[Dict[str, Any]]:
    print(f'[processor] 开始获取并处理前{days}天的podcasts...')
    # 1. 获取podcast列表 -> NPR All Things Considered
    podcasts = await PodcastFetcherService.fetch_npr_all_things_considered_by_days(days)
    if not podcasts:
        print(f'[processor] 未找到podcasts')
        return []
    print(f'[processor] 获取到 {len(podcasts)} 个podcasts，开始处理...')
    # 2. 批量处理
    processed = await process_podcasts_batch(podcasts, max_concurrent=1)
    return processed