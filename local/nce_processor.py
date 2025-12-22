"""
新概念英语音频处理器
处理 xingainian 目录下的音频：转录、翻译、上传到 COS 和服务端
"""
import os
import re
import json
import asyncio
import argparse
import hashlib
from pathlib import Path
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

# 在导入 whisperx_service 之前设置环境变量，指定使用 medium 模型
os.environ['WHISPERX_MODEL_ID'] = 'medium'

from whisperx_service import _process_audio_file
from translator import translate_segments, get_translator
from cos_service import COSService
from uploader import PodcastUploader


# ============ 配置 ============
AUDIO_DIR = Path("xingainian")
OUTPUT_DIR = Path("xingainian_output")
STATE_FILE = OUTPUT_DIR / "state.json"

COMPANY = "Longman"
CHANNEL = "New Concept English"
SERVER_URL = os.getenv("SERVER_URL", "https://elegantfish.online")


def get_audio_duration(audio_path: str) -> int:
    """获取音频时长（秒，整数）"""
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(audio_path)
        return int(len(audio) / 1000)  # 毫秒转秒，向下取整
    except Exception:
        try:
            from mutagen import File
            audio = File(audio_path)
            return int(audio.info.length) if audio else 0
        except Exception:
            return 0


def generate_podcast_id(filename: str) -> str:
    """根据文件名生成 podcast ID"""
    # 提取编号和标题，如 "01－Finding Fossil Man.mp3" -> "nce4_01"
    match = re.match(r'^(\d+)－(.+)\.mp3$', filename)
    if match:
        num = match.group(1)
        return f"nce4_{num}"
    # fallback: 用文件名 hash
    return hashlib.md5(filename.encode()).hexdigest()[:16]


def parse_title_from_filename(filename: str) -> tuple[str, str]:
    """从文件名解析标题，返回 (编号, 标题)"""
    match = re.match(r'^(\d+)－(.+)\.mp3$', filename)
    if match:
        return match.group(1), match.group(2)
    return "", filename.replace('.mp3', '')


def scan_audio_files() -> List[Dict[str, Any]]:
    """扫描音频目录，返回 podcast 列表"""
    if not AUDIO_DIR.exists():
        print(f'[nce] 错误: 音频目录不存在: {AUDIO_DIR}')
        return []

    podcasts = []
    for audio_file in sorted(AUDIO_DIR.glob("*.mp3")):
        filename = audio_file.name
        num, title = parse_title_from_filename(filename)
        podcast_id = generate_podcast_id(filename)

        podcasts.append({
            'id': podcast_id,
            'num': num,
            'title': title,
            'audio_path': str(audio_file),
            'filename': filename,
        })

    print(f'[nce] 扫描到 {len(podcasts)} 个音频文件')
    return podcasts


class NCEProcessor:
    """新概念英语处理器"""

    def __init__(self, max_retries: int = 3, server_url: str = None):
        self.max_retries = max_retries
        self.server_url = server_url or SERVER_URL
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        self.state = self._load_state()

    def _load_state(self) -> Dict:
        """加载处理状态"""
        if STATE_FILE.exists():
            with open(STATE_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {'processed': {}}  # {podcast_id: True}

    def _save_state(self):
        """保存处理状态"""
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump(self.state, f, ensure_ascii=False, indent=2)

    async def process_single(self, podcast: Dict[str, Any]) -> bool:
        """处理单个音频：转录 -> 翻译 -> 上传"""
        podcast_id = podcast['id']
        title = podcast['title']
        audio_path = podcast['audio_path']

        print(f'\n{"="*60}')
        print(f'处理: {podcast["num"]}. {title}')
        print(f'{"="*60}')

        # 检查是否已处理
        if podcast_id in self.state['processed']:
            print(f'[nce] 已处理过，跳过: {podcast_id}')
            return True

        # 1. 获取音频时长
        print('[步骤 1/5] 获取音频时长...')
        duration = get_audio_duration(audio_path)
        print(f'  时长: {duration} 秒 ({duration // 60}分{duration % 60}秒)')

        # 2. 转录音频
        print('\n[步骤 2/5] WhisperX 转录 (medium)...')
        segments = None
        detected_language = 'en'

        for retry in range(self.max_retries):
            try:
                result = await _process_audio_file(Path(audio_path))
                segments = result.get('segments', [])
                detected_language = result.get('language', 'en')
                print(f'  转录完成: {len(segments)} 句')
                break
            except Exception as e:
                if retry < self.max_retries - 1:
                    wait_time = 2 ** retry
                    print(f'  转录失败，{wait_time}s 后重试: {e}')
                    await asyncio.sleep(wait_time)
                else:
                    print(f'  转录失败: {e}')
                    return False

        if not segments:
            print('  转录结果为空')
            return False

        # 3. 翻译 segments
        print('\n[步骤 3/5] 翻译...')
        for retry in range(self.max_retries):
            try:
                translations = await translate_segments(
                    segments,
                    source_lang=detected_language,
                    target_lang='zh',
                    use_context=True,
                    use_full_context=True
                )
                for i, seg in enumerate(segments):
                    seg['translation'] = translations[i] if i < len(translations) else ''
                print(f'  翻译完成: {len(translations)} 句')
                break
            except Exception as e:
                if retry < self.max_retries - 1:
                    wait_time = 2 ** retry
                    print(f'  翻译失败，{wait_time}s 后重试: {e}')
                    await asyncio.sleep(wait_time)
                else:
                    print(f'  翻译失败: {e}')
                    return False

        # 4. 翻译标题
        print('\n[步骤 4/5] 翻译标题...')
        title_translation = None
        try:
            translator = await get_translator()
            title_translations = await translator.translate_batch(
                [title],
                source_lang='en',
                target_lang='zh',
                use_reflection=True,
                use_context=False,
                use_full_context=False
            )
            if title_translations and title_translations[0]:
                title_translation = title_translations[0]
                print(f'  {title} -> {title_translation}')
        except Exception as e:
            print(f'  标题翻译失败: {e}')
            title_translation = title

        # 5. 上传到 COS 和服务端
        print('\n[步骤 5/5] 上传...')
        try:
            cos_service = COSService()
            current_timestamp = int(datetime.now(timezone.utc).timestamp())

            # 上传音频
            print('  上传音频到 COS...')
            audio_key = cos_service.upload_audio_from_file(
                file_path=audio_path,
                podcast_id=podcast_id,
                channel=CHANNEL,
                timestamp=current_timestamp
            )

            # 准备 segments（添加 id）
            final_segments = []
            for i, seg in enumerate(segments):
                final_segments.append({
                    'id': i,
                    'start': seg.get('start', 0),
                    'end': seg.get('end', 0),
                    'text': seg.get('text', ''),
                    'translation': seg.get('translation', ''),
                })

            # 上传 segments JSON
            print('  上传 segments 到 COS...')
            segments_key = cos_service.upload_segments_json(
                podcast_id=podcast_id,
                segments=final_segments,
                channel=CHANNEL,
                timestamp=current_timestamp
            )

            # 上传到服务端
            print('  上传元数据到服务端...')
            podcast_data = {
                'id': podcast_id,
                'company': COMPANY,
                'channel': CHANNEL,
                'audioKey': audio_key,
                'rawAudioUrl': '',
                'title': f"{podcast['num']}. {title}",
                'titleTranslation': title_translation,
                'subtitle': '',
                'timestamp': current_timestamp,
                'language': 'en',
                'duration': duration,  # int 类型
                'segmentsKey': segments_key,
                'segmentCount': len(final_segments),
            }

            uploader = PodcastUploader(server_url=self.server_url)
            success = await uploader.upload_podcast(podcast_data)

            if success:
                # 标记为已处理
                self.state['processed'][podcast_id] = True
                self._save_state()
                print(f'\n✓ 完成: {podcast_id}')
                return True
            else:
                print('  上传服务端失败')
                return False

        except Exception as e:
            print(f'  上传失败: {e}')
            return False

    async def process_all(
        self,
        start: int = 1,
        limit: Optional[int] = None,
        skip_processed: bool = True
    ):
        """处理所有音频"""
        podcasts = scan_audio_files()

        if not podcasts:
            print('[nce] 没有找到音频文件')
            return

        # 过滤
        if skip_processed:
            podcasts = [p for p in podcasts if p['id'] not in self.state['processed']]
            print(f'[nce] 过滤已处理后: {len(podcasts)} 个待处理')

        # 从第几个开始
        if start > 1:
            podcasts = [p for p in podcasts if int(p.get('num', '0') or '0') >= start]
            print(f'[nce] 从第 {start} 课开始: {len(podcasts)} 个')

        # 限制数量
        if limit:
            podcasts = podcasts[:limit]
            print(f'[nce] 限制处理: {limit} 个')

        if not podcasts:
            print('[nce] 没有需要处理的音频')
            return

        success_count = 0
        fail_count = 0

        for i, podcast in enumerate(podcasts):
            print(f'\n[{i+1}/{len(podcasts)}]', end='')
            if await self.process_single(podcast):
                success_count += 1
            else:
                fail_count += 1

        print(f'\n{"="*60}')
        print(f'处理完成: 成功 {success_count}, 失败 {fail_count}')
        print(f'{"="*60}')


async def main():
    parser = argparse.ArgumentParser(description='新概念英语音频处理器')
    parser.add_argument('--start', type=int, default=1, help='从第几课开始（默认1）')
    parser.add_argument('--limit', type=int, help='限制处理数量')
    parser.add_argument('--no-skip', action='store_true', help='不跳过已处理的')
    parser.add_argument('--server-url', default=None, help='服务端 URL')

    args = parser.parse_args()

    server_url = args.server_url or SERVER_URL

    processor = NCEProcessor(server_url=server_url)
    await processor.process_all(
        start=args.start,
        limit=args.limit,
        skip_processed=not args.no_skip
    )


if __name__ == '__main__':
    asyncio.run(main())
