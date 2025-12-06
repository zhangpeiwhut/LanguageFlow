"""
VOA Learning English 本地处理器
处理流程：
1. 从 CSV 读取 podcast 列表
2. 下载音频到本地（支持断点续传）
3. 转录音频
4. 翻译字幕和标题
5. 保存到本地存档目录

不上传到 COS 和服务端，仅保存到本地
"""
import asyncio
import json
import hashlib
from pathlib import Path
from typing import List, Dict, Any, Optional
import pandas as pd
import httpx
import time
from whisperx_service import _process_audio_file
from translator import translate_segments, get_translator
from voa_config import (
    VOA_ARCHIVE_DIR,
    VOA_AUDIO_DIR,
    VOA_SEGMENTS_DIR,
    VOA_METADATA_FILE,
    VOA_STATE_FILE
)


def generate_podcast_id(company: str, channel: str, timestamp: int, audio_url: str, title: Optional[str] = None) -> str:
    """生成 podcast ID"""
    normalized_company = (company or "").strip().lower()
    normalized_channel = (channel or "").strip().lower()
    normalized_title = (title or "").strip().lower()
    normalized_url = (audio_url or "").strip()
    content = f"{normalized_company}|{normalized_channel}|{timestamp}|{normalized_url}|{normalized_title}"
    hash_obj = hashlib.sha256(content.encode('utf-8'))
    return hash_obj.hexdigest()[:32]

class VoaProcessor:
    """VOA 本地处理器"""

    def __init__(self, csv_path: str = "voa_podcasts.csv", max_retries: int = 3):
        """
        初始化处理器
        Args:
            csv_path: VOA podcasts CSV 文件路径
            max_retries: 最大重试次数
        """
        self.csv_path = csv_path
        self.max_retries = max_retries
        self._ensure_directories()
        self.state = self._load_state()
        self.metadata = self._load_metadata()
        # 线程安全锁
        self.state_lock = asyncio.Lock()
        self.metadata_lock = asyncio.Lock()

    def _ensure_directories(self):
        """确保目录存在"""
        VOA_ARCHIVE_DIR.mkdir(exist_ok=True)
        VOA_AUDIO_DIR.mkdir(exist_ok=True)
        VOA_SEGMENTS_DIR.mkdir(exist_ok=True)

    def _sanitize_value(self, value):
        """清理无效的浮点数值（NaN, Infinity）转为 None"""
        import math
        if value is not None and isinstance(value, float):
            if math.isnan(value) or math.isinf(value):
                return None
        return value

    def _load_state(self) -> Dict:
        """加载处理状态"""
        if VOA_STATE_FILE.exists():
            with open(VOA_STATE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {
            'downloaded': {},  # {podcast_id: audio_path}
            'processed': {},   # {podcast_id: segments_path}
        }

    async def _save_state(self):
        """保存处理状态（线程安全）"""
        async with self.state_lock:
            with open(VOA_STATE_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.state, f, ensure_ascii=False, indent=2)

    def _load_metadata(self) -> Dict:
        """加载元数据"""
        if VOA_METADATA_FILE.exists():
            with open(VOA_METADATA_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {'podcasts': []}

    async def _save_metadata(self):
        """保存元数据（线程安全）"""
        async with self.metadata_lock:
            with open(VOA_METADATA_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.metadata, f, ensure_ascii=False, indent=2)

    def load_podcasts_from_csv(self) -> List[Dict[str, Any]]:
        """从 CSV 加载 podcast 列表"""
        print(f'[voa-processor] 从 CSV 加载 podcasts: {self.csv_path}')
        df = pd.read_csv(self.csv_path)

        podcasts = []
        for _, row in df.iterrows():
            podcast = {
                'company': row.get('company', 'VOA'),
                'channel': row.get('channel', ''),
                'audioURL': row.get('audioURL', ''),
                'title': row.get('title', ''),
                'subtitle': row.get('subtitle', ''),
                'timestamp': int(row.get('timestamp', 0)),
                'language': row.get('language', 'en'),
                'duration': row.get('duration') if pd.notna(row.get('duration')) else None,
            }

            # 生成 podcast_id
            podcast_id = generate_podcast_id(
                company=podcast['company'],
                channel=podcast['channel'],
                timestamp=podcast['timestamp'],
                audio_url=podcast['audioURL'],
                title=podcast['title']
            )
            podcast['id'] = podcast_id
            podcasts.append(podcast)

        print(f'[voa-processor] 加载了 {len(podcasts)} 个 podcasts')
        return podcasts

    def _get_audio_path(self, podcast: Dict[str, Any]) -> Path:
        """获取音频文件保存路径"""
        channel = podcast['channel'].replace('/', '_').replace(' ', '_')
        channel_dir = VOA_AUDIO_DIR / channel
        channel_dir.mkdir(exist_ok=True)
        return channel_dir / f"{podcast['id']}.mp3"

    def _get_segments_path(self, podcast: Dict[str, Any]) -> Path:
        """获取 segments 文件保存路径"""
        channel = podcast['channel'].replace('/', '_').replace(' ', '_')
        channel_dir = VOA_SEGMENTS_DIR / channel
        channel_dir.mkdir(exist_ok=True)
        return channel_dir / f"{podcast['id']}.json"

    async def download_audio(self, podcast: Dict[str, Any]) -> Optional[Path]:
        """
        下载音频到本地（带重试机制）
        支持断点续传：如果已下载则跳过
        """
        podcast_id = podcast['id']
        audio_url = podcast['audioURL']
        audio_path = self._get_audio_path(podcast)

        # 检查是否已下载
        if podcast_id in self.state['downloaded']:
            existing_path = Path(self.state['downloaded'][podcast_id])
            if existing_path.exists():
                print(f'[voa-processor] 音频已存在，跳过下载: {podcast_id}')
                return existing_path

        # 下载音频（带重试）
        print(f'[voa-processor] 开始下载音频: {podcast["title"]}')
        print(f'[voa-processor] URL: {audio_url}')

        for retry in range(self.max_retries):
            try:
                async with httpx.AsyncClient(timeout=300.0) as client:
                    response = await client.get(audio_url)
                    response.raise_for_status()

                    # 保存音频文件
                    audio_path.write_bytes(response.content)
                    file_size = len(response.content)
                    print(f'[voa-processor] 音频下载完成: {file_size} bytes -> {audio_path}')

                    # 更新状态（线程安全）
                    async with self.state_lock:
                        self.state['downloaded'][podcast_id] = str(audio_path)
                    await self._save_state()

                    return audio_path
            except Exception as e:
                if retry < self.max_retries - 1:
                    wait_time = 2 ** retry  # 指数退避：1s, 2s, 4s
                    print(f'[voa-processor] 下载音频失败 (重试 {retry + 1}/{self.max_retries}): {e}')
                    print(f'[voa-processor] 等待 {wait_time}s 后重试...')
                    await asyncio.sleep(wait_time)
                else:
                    print(f'[voa-processor] 下载音频失败（已达最大重试次数）: {e}')
                    return None

    async def process_podcast(self, podcast: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        处理单个 podcast：转录 + 翻译
        保存到本地，不上传到 COS 和服务端
        """
        podcast_id = podcast['id']

        # 检查是否已处理
        if podcast_id in self.state['processed']:
            segments_path = Path(self.state['processed'][podcast_id])
            if segments_path.exists():
                print(f'[voa-processor] 已处理过，跳过: {podcast_id}')
                return None

        print(f'[voa-processor] 开始处理 podcast: {podcast["title"]} (ID: {podcast_id})')

        # 1. 下载音频
        audio_path = await self.download_audio(podcast)
        if not audio_path:
            print(f'[voa-processor] 音频下载失败，跳过处理: {podcast_id}')
            return None

        # 2. 转录音频（带重试）
        segments = None
        detected_language = 'en'
        for retry in range(self.max_retries):
            try:
                print(f'[voa-processor] 开始转录音频...')
                transcription_result = await _process_audio_file(audio_path)
                segments = transcription_result.get('segments', [])
                detected_language = transcription_result.get('language', 'en')
                print(f'[voa-processor] 转录完成：{len(segments)} 个片段')
                break
            except Exception as e:
                if retry < self.max_retries - 1:
                    wait_time = 2 ** retry
                    print(f'[voa-processor] 转录失败 (重试 {retry + 1}/{self.max_retries}): {e}')
                    print(f'[voa-processor] 等待 {wait_time}s 后重试...')
                    await asyncio.sleep(wait_time)
                else:
                    print(f'[voa-processor] 转录失败（已达最大重试次数）: {e}')
                    return None

        if not segments:
            print(f'[voa-processor] 转录结果为空')
            return None

        # 3. 翻译 segments（带重试，最多重试 5 次）
        translation_max_retries = 5
        translation_success = False
        for retry in range(translation_max_retries):
            try:
                print(f'[voa-processor] 开始翻译 {len(segments)} 个片段...')
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
                print(f'[voa-processor] 翻译完成：成功 {success_count}/{len(segments)} 段')
                translation_success = True
                break
            except Exception as e:
                if retry < translation_max_retries - 1:
                    wait_time = 2 ** retry
                    print(f'[voa-processor] 翻译失败 (重试 {retry + 1}/{translation_max_retries}): {e}')
                    print(f'[voa-processor] 等待 {wait_time}s 后重试...')
                    await asyncio.sleep(wait_time)
                else:
                    print(f'[voa-processor] 翻译失败（已达最大重试次数）: {e}')
                    # 翻译失败是致命的，返回 None
                    return None

        if not translation_success:
            print(f'[voa-processor] 翻译失败，跳过此 podcast')
            return None

        # 4. 翻译标题
        title_translation = None
        title = podcast.get('title')
        if title:
            try:
                print(f'[voa-processor] 开始翻译标题: {title}')
                translator = await get_translator()
                title_translations = await translator.translate_batch(
                    [title],
                    source_lang=detected_language,
                    target_lang='zh',
                    use_reflection=True,
                    use_context=False,
                    use_full_context=False
                )
                if title_translations and title_translations[0]:
                    title_translation = title_translations[0]
                    print(f'[voa-processor] 标题翻译完成: {title_translation}')
            except Exception as e:
                print(f'[voa-processor] 标题翻译失败: {e}')

        # 5. 保存 segments 到本地
        segments_path = self._get_segments_path(podcast)
        try:
            # 为 segments 添加 id 字段
            segments_with_id = []
            for i, segment in enumerate(segments):
                segment_with_id = segment.copy()
                segment_with_id['id'] = i + 1
                segments_with_id.append(segment_with_id)

            segments_path.write_text(
                json.dumps(segments_with_id, ensure_ascii=False, indent=2),
                encoding='utf-8'
            )
            print(f'[voa-processor] segments 保存成功: {segments_path}')

            # 更新状态（线程安全）
            async with self.state_lock:
                self.state['processed'][podcast_id] = str(segments_path)
            await self._save_state()
        except Exception as e:
            print(f'[voa-processor] 保存 segments 失败: {e}')
            return None

        # 6. 构建完整的 podcast 元数据（清理 NaN 值）
        complete_podcast = {
            'id': podcast_id,
            'company': podcast['company'],
            'channel': podcast['channel'],
            'audioURL': podcast['audioURL'],
            'localAudioPath': str(audio_path),
            'localSegmentsPath': str(segments_path),
            'title': podcast['title'],
            'titleTranslation': title_translation,
            'subtitle': self._sanitize_value(podcast.get('subtitle')),
            'timestamp': podcast['timestamp'],
            'language': detected_language,
            'duration': self._sanitize_value(podcast.get('duration')),
            'segmentCount': len(segments),
            'status': 'local_only'  # 标记为仅本地
        }

        # 7. 更新元数据（线程安全）
        async with self.metadata_lock:
            self.metadata['podcasts'].append(complete_podcast)
        await self._save_metadata()

        print(f'[voa-processor] 处理完成：podcast ID = {podcast_id}')
        return complete_podcast

    async def process_batch(
        self,
        limit: Optional[int] = None,
        channel_filter: Optional[str] = None,
        skip_processed: bool = True,
        max_concurrent: int = 3
    ) -> List[Dict[str, Any]]:
        """
        批量处理 podcasts（并行处理）

        Args:
            limit: 限制处理数量，None 表示处理全部
            channel_filter: 频道过滤，只处理指定频道
            skip_processed: 是否跳过已处理的
            max_concurrent: 最大并发数，默认 3

        Returns:
            处理完成的 podcast 列表
        """
        print(f'[voa-processor] 开始批量处理（并发数: {max_concurrent}）...')
        podcasts = self.load_podcasts_from_csv()

        # 过滤频道
        if channel_filter:
            podcasts = [p for p in podcasts if p['channel'] == channel_filter]
            print(f'[voa-processor] 频道过滤后剩余 {len(podcasts)} 个 podcasts')

        # 过滤已处理的
        if skip_processed:
            podcasts = [p for p in podcasts if p['id'] not in self.state['processed']]
            print(f'[voa-processor] 过滤已处理后剩余 {len(podcasts)} 个 podcasts')

        # 限制数量
        if limit:
            podcasts = podcasts[:limit]
            print(f'[voa-processor] 限制处理数量: {limit} 个')

        if not podcasts:
            print(f'[voa-processor] 没有需要处理的 podcasts')
            return []

        # 使用 Semaphore 控制并发数
        semaphore = asyncio.Semaphore(max_concurrent)
        successful = []
        skipped = 0
        failed = 0
        total = len(podcasts)
        completed = 0

        async def process_with_semaphore(podcast: Dict[str, Any], index: int):
            nonlocal completed, skipped, failed
            async with semaphore:
                try:
                    print(f'\n[voa-processor] [{index + 1}/{total}] 开始处理: {podcast["title"]}')
                    result = await self.process_podcast(podcast)

                    completed += 1

                    if result:
                        successful.append(result)
                        print(f'[voa-processor] [{index + 1}/{total}] ✓ 成功 (总进度: {completed}/{total})')
                        return result
                    else:
                        skipped += 1
                        print(f'[voa-processor] [{index + 1}/{total}] - 跳过 (总进度: {completed}/{total})')
                        return None
                except Exception as e:
                    completed += 1
                    failed += 1
                    print(f'[voa-processor] [{index + 1}/{total}] ✗ 失败: {e} (总进度: {completed}/{total})')
                    import traceback
                    traceback.print_exc()
                    return None

        # 并行处理所有 podcasts
        print(f'\n[voa-processor] 开始并行处理 {total} 个 podcasts...')
        tasks = [process_with_semaphore(podcast, i) for i, podcast in enumerate(podcasts)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        # 过滤出成功的结果
        for result in results:
            if result and not isinstance(result, Exception):
                pass  # 已经在 successful 中了

        # 最后保存一次状态
        await self._save_state()
        await self._save_metadata()

        print(f'\n[voa-processor] 批量处理完成：')
        print(f'  - 成功: {len(successful)} 个')
        print(f'  - 跳过: {skipped} 个')
        print(f'  - 失败: {failed} 个')

        return successful

    def get_statistics(self) -> Dict[str, Any]:
        """获取处理统计信息"""
        total_downloaded = len(self.state['downloaded'])
        total_processed = len(self.state['processed'])
        total_podcasts = len(self.load_podcasts_from_csv())

        # 按频道统计
        channel_stats = {}
        for podcast in self.metadata['podcasts']:
            channel = podcast['channel']
            if channel not in channel_stats:
                channel_stats[channel] = 0
            channel_stats[channel] += 1

        return {
            'total_podcasts': total_podcasts,
            'total_downloaded': total_downloaded,
            'total_processed': total_processed,
            'channel_stats': channel_stats,
            'download_progress': f'{total_downloaded}/{total_podcasts}',
            'process_progress': f'{total_processed}/{total_podcasts}',
        }


async def main():
    """主函数"""
    import argparse

    parser = argparse.ArgumentParser(description='VOA Learning English 本地处理器')
    parser.add_argument('--csv', type=str, default='voa_podcasts.csv', help='CSV 文件路径')
    parser.add_argument('--limit', type=int, help='限制处理数量')
    parser.add_argument('--channel', type=str, help='只处理指定频道')
    parser.add_argument('--concurrent', type=int, default=3, help='并发数量（默认 3）')
    parser.add_argument('--stats', action='store_true', help='显示统计信息')

    args = parser.parse_args()

    processor = VoaProcessor(csv_path=args.csv)

    if args.stats:
        stats = processor.get_statistics()
        print('\n=== VOA 处理统计 ===')
        print(f'总 podcasts: {stats["total_podcasts"]}')
        print(f'已下载: {stats["download_progress"]}')
        print(f'已处理: {stats["process_progress"]}')
        print('\n频道统计:')
        for channel, count in sorted(stats['channel_stats'].items()):
            print(f'  {channel}: {count}')
        return

    print('=== VOA Learning English 本地处理器 ===')
    print(f'并发数: {args.concurrent}')
    await processor.process_batch(
        limit=args.limit,
        channel_filter=args.channel,
        skip_processed=True,
        max_concurrent=args.concurrent
    )

    print('\n=== 处理完成 ===')
    stats = processor.get_statistics()
    print(f'已处理: {stats["process_progress"]}')


if __name__ == '__main__':
    asyncio.run(main())
