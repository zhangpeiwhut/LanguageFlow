"""通用双语SRT音频处理器
用于处理带有双语字幕的音频内容，上传到COS和服务端
"""
import os
import re
import asyncio
import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any

from cos_service import COSService
from uploader import PodcastUploader


def parse_timestamp(timestamp: str) -> float:
    """
    解析SRT时间戳为秒数

    Args:
        timestamp: SRT格式的时间戳，如 "00:00:55,775"

    Returns:
        浮点数秒数，如 55.775
    """
    # 格式: HH:MM:SS,mmm
    time_parts = timestamp.strip().split(':')
    if len(time_parts) != 3:
        raise ValueError(f'无效的时间戳格式: {timestamp}')

    hours = int(time_parts[0])
    minutes = int(time_parts[1])

    # 处理秒和毫秒
    seconds_parts = time_parts[2].split(',')
    if len(seconds_parts) != 2:
        raise ValueError(f'无效的秒数格式: {time_parts[2]}')

    seconds = int(seconds_parts[0])
    milliseconds = int(seconds_parts[1])

    total_seconds = hours * 3600 + minutes * 60 + seconds + milliseconds / 1000.0
    return total_seconds


def clean_html_tags(text: str) -> str:
    """
    清理HTML标签和特殊字符

    Args:
        text: 可能包含HTML标签的文本

    Returns:
        清理后的纯文本
    """
    # 移除HTML标签
    text = re.sub(r'<[^>]+>', '', text)
    # 移除多余的空白字符
    text = ' '.join(text.split())
    return text.strip()


def parse_srt(srt_path: str) -> List[Dict[str, Any]]:
    """
    解析双语SRT文件为segments列表

    SRT格式：
    [序号]
    [起始时间] --> [结束时间]
    [英文文本]
    [中文翻译]
    [空行]

    Args:
        srt_path: SRT文件路径

    Returns:
        segments列表，每个segment包含: id, start, end, text, translation
    """
    if not os.path.exists(srt_path):
        raise FileNotFoundError(f'SRT文件不存在: {srt_path}')

    print(f'[srt-parser] 开始解析SRT文件: {srt_path}')

    # 读取文件内容
    with open(srt_path, 'r', encoding='utf-8-sig') as f:  # utf-8-sig处理BOM
        content = f.read()

    # 按双换行符分割字幕块
    blocks = re.split(r'\n\s*\n', content.strip())

    segments = []
    for block in blocks:
        lines = block.strip().split('\n')
        if len(lines) < 4:
            # 跳过格式不完整的块
            continue

        try:
            # 第1行: 序号
            sequence_num = int(lines[0].strip())

            # 第2行: 时间轴
            time_line = lines[1].strip()
            time_match = re.match(r'(\S+)\s*-->\s*(\S+)', time_line)
            if not time_match:
                print(f'[srt-parser] 警告: 跳过无效的时间轴格式: {time_line}')
                continue

            start_time = parse_timestamp(time_match.group(1))
            end_time = parse_timestamp(time_match.group(2))

            # 第3行: 英文文本
            english_text = clean_html_tags(lines[2])

            # 第4行: 中文翻译
            chinese_text = clean_html_tags(lines[3])

            # 创建segment对象
            segment = {
                'id': len(segments),  # 使用列表索引作为ID
                'start': start_time,
                'end': end_time,
                'text': english_text,
                'translation': chinese_text
            }

            segments.append(segment)

        except Exception as e:
            print(f'[srt-parser] 警告: 解析字幕块失败，跳过: {e}')
            print(f'[srt-parser] 问题块内容: {block[:200]}')
            continue

    print(f'[srt-parser] 解析完成: 共 {len(segments)} 个字幕片段')
    return segments


def get_audio_duration(audio_path: str) -> int:
    """
    获取音频文件的时长（秒，向下取整）

    Args:
        audio_path: 音频文件路径

    Returns:
        音频时长（秒，整数）
    """
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(audio_path)
        duration = int(len(audio) / 1000)  # 毫秒转秒，向下取整
        print(f'[audio] 音频时长: {duration} 秒')
        return duration
    except ImportError:
        print('[audio] 警告: pydub未安装，尝试使用mutagen...')
        try:
            from mutagen import File
            audio = File(audio_path)
            if audio is None or not hasattr(audio.info, 'length'):
                raise Exception('无法读取音频信息')
            duration = int(audio.info.length)  # 向下取整
            print(f'[audio] 音频时长: {duration} 秒')
            return duration
        except ImportError:
            raise Exception('需要安装 pydub 或 mutagen 来获取音频时长: pip install pydub mutagen')
        except Exception as e:
            raise Exception(f'获取音频时长失败: {str(e)}')


async def process_audio_with_bilingual_srt(
    srt_path: str,
    audio_path: str,
    podcast_id: str,
    company: str,
    channel: str,
    title: str,
    title_translation: str,
    server_url: str = None
) -> bool:
    """
    处理带有双语SRT的音频内容

    流程：
    1. 解析SRT文件为segments
    2. 获取音频时长
    3. 上传音频到COS
    4. 上传segments到COS
    5. 构造元数据并上传到服务端

    Args:
        srt_path: SRT文件路径
        audio_path: 音频文件路径
        podcast_id: podcast唯一ID
        company: 公司/来源（如: Disney, VOA, Netflix）
        channel: 频道/系列（如: Zootopia, Frozen）
        title: 标题（英文）
        title_translation: 标题翻译（中文）
        server_url: 服务端URL（如: https://elegantfish.online），如果为None则从环境变量SERVER_URL读取

    Returns:
        处理是否成功
    """
    try:
        print(f'\n{"="*60}')
        print(f'开始处理: {title}')
        print(f'{"="*60}\n')

        # 1. 解析SRT文件
        print('[步骤 1/5] 解析SRT文件...')
        segments = parse_srt(srt_path)
        if not segments:
            raise Exception('SRT文件解析结果为空')

        # 2. 获取音频时长
        print('\n[步骤 2/5] 获取音频时长...')
        duration = get_audio_duration(audio_path)

        # 3. 初始化服务
        print('\n[步骤 3/5] 上传音频到COS...')
        cos_service = COSService()

        # 获取当前时间戳（用于构建COS路径）
        current_timestamp = int(datetime.now(timezone.utc).timestamp())

        # 上传音频文件
        audio_key = cos_service.upload_audio_from_file(
            file_path=audio_path,
            podcast_id=podcast_id,
            channel=channel,
            timestamp=current_timestamp
        )

        # 4. 上传segments JSON
        print('\n[步骤 4/5] 上传segments到COS...')
        segments_key = cos_service.upload_segments_json(
            podcast_id=podcast_id,
            segments=segments,
            channel=channel,
            timestamp=current_timestamp
        )

        # 5. 构造元数据并上传到服务端
        print('\n[步骤 5/5] 上传元数据到服务端...')

        podcast_data = {
            'id': podcast_id,
            'company': company,
            'channel': channel,
            'audioKey': audio_key,
            'rawAudioUrl': '',  # 本地文件，留空
            'title': title,
            'titleTranslation': title_translation,
            'subtitle': '',
            'timestamp': current_timestamp,
            'language': 'en',
            'duration': duration,
            'segmentsKey': segments_key,
            'segmentCount': len(segments)
        }

        # 获取服务端URL
        if server_url is None:
            server_url = os.getenv('SERVER_URL')
            if not server_url:
                raise ValueError('未提供服务端URL，请通过--server-url参数或SERVER_URL环境变量指定')

        uploader = PodcastUploader(server_url=server_url)
        success = await uploader.upload_podcast(podcast_data)

        if success:
            print(f'\n{"="*60}')
            print(f'处理完成: {title}')
            print(f'{"="*60}')
            print(f'Podcast ID: {podcast_id}')
            print(f'音频路径: {audio_key}')
            print(f'字幕路径: {segments_key}')
            print(f'字幕数量: {len(segments)}')
            print(f'音频时长: {duration} 秒')
            print(f'{"="*60}\n')
        else:
            raise Exception('上传到服务端失败')

        return True

    except Exception as e:
        print(f'\n{"!"*60}')
        print(f'处理失败: {str(e)}')
        print(f'{"!"*60}\n')
        return False


async def main():
    """命令行入口"""
    parser = argparse.ArgumentParser(
        description='处理带有双语SRT字幕的音频内容',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例用法:
  python bilingual_srt_processor.py \\
    --srt local/srt/zootopia_1.srt \\
    --audio /path/to/zootopia_1.mp3 \\
    --podcast-id zootopia_1 \\
    --company Disney \\
    --channel Zootopia \\
    --title "Zootopia 1" \\
    --title-translation "疯狂动物城1" \\
    --server-url https://elegantfish.online

环境变量:
  COS_SECRET_ID     - 腾讯云SecretId
  COS_SECRET_KEY    - 腾讯云SecretKey
  COS_REGION        - COS地域（默认: ap-beijing）
  COS_BUCKET        - COS存储桶名称
  SERVER_URL        - 服务端URL（可选，可通过--server-url指定）
        """
    )

    parser.add_argument('--srt', required=True, help='SRT文件路径')
    parser.add_argument('--audio', required=True, help='音频文件路径')
    parser.add_argument('--podcast-id', required=True, help='Podcast唯一ID')
    parser.add_argument('--company', required=True, help='公司/来源（如: Disney, Netflix）')
    parser.add_argument('--channel', required=True, help='频道/系列（如: Zootopia, Frozen）')
    parser.add_argument('--title', required=True, help='标题（英文）')
    parser.add_argument('--title-translation', required=True, help='标题翻译（中文）')
    parser.add_argument('--server-url', help='服务端URL（如: https://elegantfish.online），不指定则从环境变量SERVER_URL读取')

    args = parser.parse_args()

    # 验证文件存在
    if not os.path.exists(args.srt):
        print(f'错误: SRT文件不存在: {args.srt}')
        return 1

    if not os.path.exists(args.audio):
        print(f'错误: 音频文件不存在: {args.audio}')
        return 1

    # 执行处理
    success = await process_audio_with_bilingual_srt(
        srt_path=args.srt,
        audio_path=args.audio,
        podcast_id=args.podcast_id,
        company=args.company,
        channel=args.channel,
        title=args.title,
        title_translation=args.title_translation,
        server_url=args.server_url
    )

    return 0 if success else 1


if __name__ == '__main__':
    exit_code = asyncio.run(main())
    exit(exit_code)
