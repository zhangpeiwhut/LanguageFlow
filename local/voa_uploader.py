"""
VOA Learning English 批量上传脚本
从本地存档上传到 COS 和服务端

使用场景：
1. 本地处理完 VOA podcasts 后
2. 质量检查通过
3. 批量上传到 COS 和服务端
"""
import asyncio
import json
from pathlib import Path
from typing import List, Dict, Any, Optional
from cos_service import COSService
from uploader import PodcastUploader
from voa_processor import (
    VOA_ARCHIVE_DIR,
    VOA_METADATA_FILE,
    VOA_STATE_FILE
)


class VoaUploader:
    """VOA 批量上传器"""

    def __init__(self, server_url: str):
        """
        初始化上传器
        Args:
            server_url: 服务器 URL
        """
        self.server_url = server_url
        self.cos_service = COSService()
        self.podcast_uploader = PodcastUploader(server_url)
        self.upload_state_file = VOA_ARCHIVE_DIR / "upload_state.json"
        self.upload_state = self._load_upload_state()

    def _load_upload_state(self) -> Dict:
        """加载上传状态"""
        if self.upload_state_file.exists():
            with open(self.upload_state_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {
            'uploaded_to_cos': {},  # {podcast_id: {'audioKey': ..., 'segmentsKey': ...}}
            'uploaded_to_server': [],  # [podcast_id, ...]
        }

    def _save_upload_state(self):
        """保存上传状态"""
        with open(self.upload_state_file, 'w', encoding='utf-8') as f:
            json.dump(self.upload_state, f, ensure_ascii=False, indent=2)

    def _load_metadata(self) -> Dict:
        """加载元数据"""
        if VOA_METADATA_FILE.exists():
            with open(VOA_METADATA_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {'podcasts': []}

    async def upload_podcast_to_cos(self, podcast: Dict[str, Any]) -> Optional[Dict[str, str]]:
        """
        上传单个 podcast 的音频和 segments 到 COS

        Returns:
            {'audioKey': ..., 'segmentsKey': ...} 或 None
        """
        podcast_id = podcast['id']

        # 检查是否已上传
        if podcast_id in self.upload_state['uploaded_to_cos']:
            print(f'[voa-uploader] 已上传到 COS，跳过: {podcast_id}')
            return self.upload_state['uploaded_to_cos'][podcast_id]

        print(f'[voa-uploader] 开始上传到 COS: {podcast["title"]}')

        local_audio_path = podcast.get('localAudioPath')
        local_segments_path = podcast.get('localSegmentsPath')

        if not local_audio_path or not local_segments_path:
            print(f'[voa-uploader] 缺少本地文件路径，跳过: {podcast_id}')
            return None

        audio_path = Path(local_audio_path)
        segments_path = Path(local_segments_path)

        if not audio_path.exists() or not segments_path.exists():
            print(f'[voa-uploader] 本地文件不存在，跳过: {podcast_id}')
            return None

        # 1. 上传音频到 COS
        audio_key = None
        try:
            print(f'[voa-uploader] 上传音频文件到 COS...')
            audio_key = self.cos_service.upload_audio_from_file(
                file_path=str(audio_path),
                podcast_id=podcast_id,
                channel=podcast.get('channel'),
                timestamp=podcast.get('timestamp')
            )
            print(f'[voa-uploader] 音频上传成功: {audio_key}')
        except Exception as e:
            print(f'[voa-uploader] 音频上传到 COS 失败: {e}')
            return None

        # 2. 上传 segments 到 COS
        segments_key = None
        try:
            print(f'[voa-uploader] 上传 segments 到 COS...')
            # 读取 segments
            with open(segments_path, 'r', encoding='utf-8') as f:
                segments = json.load(f)

            segments_key = self.cos_service.upload_segments_json(
                podcast_id,
                segments,
                channel=podcast.get('channel'),
                timestamp=podcast.get('timestamp')
            )
            print(f'[voa-uploader] segments 上传成功: {segments_key}')
        except Exception as e:
            print(f'[voa-uploader] segments 上传到 COS 失败: {e}')
            return None

        # 3. 保存上传状态
        cos_keys = {
            'audioKey': audio_key,
            'segmentsKey': segments_key
        }
        self.upload_state['uploaded_to_cos'][podcast_id] = cos_keys
        self._save_upload_state()

        return cos_keys

    async def upload_podcast_to_server(self, podcast: Dict[str, Any], cos_keys: Dict[str, str]) -> bool:
        """
        上传 podcast 元数据到服务端

        Args:
            podcast: podcast 元数据
            cos_keys: COS 上传后的 keys {'audioKey': ..., 'segmentsKey': ...}

        Returns:
            是否上传成功
        """
        podcast_id = podcast['id']

        # 检查是否已上传
        if podcast_id in self.upload_state['uploaded_to_server']:
            print(f'[voa-uploader] 已上传到服务端，跳过: {podcast_id}')
            return True

        # 构建上传数据（不包含本地路径）
        upload_data = {
            'id': podcast_id,
            'company': podcast['company'],
            'channel': podcast['channel'],
            'audioKey': cos_keys['audioKey'],
            'rawAudioUrl': podcast['audioURL'],
            'title': podcast['title'],
            'titleTranslation': podcast.get('titleTranslation'),
            'subtitle': podcast.get('subtitle'),
            'timestamp': podcast['timestamp'],
            'language': podcast['language'],
            'duration': podcast.get('duration'),
            'segmentsKey': cos_keys['segmentsKey'],
            'segmentCount': podcast['segmentCount']
        }

        # 上传到服务端
        try:
            success = await self.podcast_uploader.upload_podcast(upload_data)
            if success:
                self.upload_state['uploaded_to_server'].append(podcast_id)
                self._save_upload_state()
                return True
            return False
        except Exception as e:
            print(f'[voa-uploader] 上传到服务端失败: {e}')
            return False

    async def upload_single_podcast(self, podcast: Dict[str, Any]) -> bool:
        """
        上传单个 podcast（COS + 服务端）

        Returns:
            是否上传成功
        """
        podcast_id = podcast['id']
        print(f'\n[voa-uploader] 开始上传: {podcast["title"]} (ID: {podcast_id})')

        # 1. 上传到 COS
        cos_keys = await self.upload_podcast_to_cos(podcast)
        if not cos_keys:
            print(f'[voa-uploader] 上传到 COS 失败，跳过上传到服务端')
            return False

        # 2. 上传到服务端
        success = await self.upload_podcast_to_server(podcast, cos_keys)
        if success:
            print(f'[voa-uploader] ✓ 上传完成: {podcast["title"]}')
            return True
        else:
            print(f'[voa-uploader] ✗ 上传到服务端失败: {podcast["title"]}')
            return False

    async def upload_batch(
        self,
        limit: Optional[int] = None,
        channel_filter: Optional[str] = None,
        skip_uploaded: bool = True
    ) -> Dict[str, int]:
        """
        批量上传 podcasts

        Args:
            limit: 限制上传数量
            channel_filter: 频道过滤
            skip_uploaded: 是否跳过已上传的

        Returns:
            {'success': ..., 'failed': ..., 'skipped': ...}
        """
        print(f'[voa-uploader] 开始批量上传...')

        # 加载元数据
        metadata = self._load_metadata()
        podcasts = metadata.get('podcasts', [])

        if not podcasts:
            print(f'[voa-uploader] 没有找到 podcasts 元数据')
            return {'success': 0, 'failed': 0, 'skipped': 0}

        print(f'[voa-uploader] 加载了 {len(podcasts)} 个 podcasts')

        # 过滤频道
        if channel_filter:
            podcasts = [p for p in podcasts if p['channel'] == channel_filter]
            print(f'[voa-uploader] 频道过滤后剩余 {len(podcasts)} 个')

        # 限制数量
        if limit:
            podcasts = podcasts[:limit]
            print(f'[voa-uploader] 限制上传数量: {limit} 个')

        success_count = 0
        failed_count = 0
        skipped_count = 0

        for i, podcast in enumerate(podcasts, 1):
            print(f'\n[voa-uploader] 进度: {i}/{len(podcasts)}')

            # 跳过已上传
            if skip_uploaded and podcast['id'] in self.upload_state['uploaded_to_server']:
                print(f'[voa-uploader] 跳过已上传: {podcast["id"]}')
                skipped_count += 1
                continue

            # 上传
            success = await self.upload_single_podcast(podcast)
            if success:
                success_count += 1
            else:
                failed_count += 1

            # 每上传 10 个保存一次状态
            if i % 10 == 0:
                self._save_upload_state()

        # 最后保存一次
        self._save_upload_state()

        print(f'\n[voa-uploader] 批量上传完成：')
        print(f'  - 成功: {success_count} 个')
        print(f'  - 失败: {failed_count} 个')
        print(f'  - 跳过: {skipped_count} 个')

        return {
            'success': success_count,
            'failed': failed_count,
            'skipped': skipped_count
        }

    def get_upload_statistics(self) -> Dict[str, Any]:
        """获取上传统计信息"""
        metadata = self._load_metadata()
        total_podcasts = len(metadata.get('podcasts', []))
        total_uploaded_cos = len(self.upload_state['uploaded_to_cos'])
        total_uploaded_server = len(self.upload_state['uploaded_to_server'])

        return {
            'total_podcasts': total_podcasts,
            'uploaded_to_cos': total_uploaded_cos,
            'uploaded_to_server': total_uploaded_server,
            'cos_progress': f'{total_uploaded_cos}/{total_podcasts}',
            'server_progress': f'{total_uploaded_server}/{total_podcasts}',
        }


async def main():
    """主函数"""
    import argparse
    import os

    parser = argparse.ArgumentParser(description='VOA Learning English 批量上传脚本')
    parser.add_argument('--server-url', type=str, help='服务器 URL')
    parser.add_argument('--limit', type=int, help='限制上传数量')
    parser.add_argument('--channel', type=str, help='只上传指定频道')
    parser.add_argument('--stats', action='store_true', help='显示上传统计信息')

    args = parser.parse_args()

    # 获取服务器 URL
    server_url = args.server_url or os.getenv('SERVER_URL', 'http://localhost:8001')

    uploader = VoaUploader(server_url=server_url)

    if args.stats:
        stats = uploader.get_upload_statistics()
        print('\n=== VOA 上传统计 ===')
        print(f'总 podcasts: {stats["total_podcasts"]}')
        print(f'已上传到 COS: {stats["cos_progress"]}')
        print(f'已上传到服务端: {stats["server_progress"]}')
        return

    print('=== VOA Learning English 批量上传 ===')
    print(f'服务器: {server_url}')

    result = await uploader.upload_batch(
        limit=args.limit,
        channel_filter=args.channel,
        skip_uploaded=True
    )

    print('\n=== 上传完成 ===')
    print(f'成功: {result["success"]} 个')
    print(f'失败: {result["failed"]} 个')
    print(f'跳过: {result["skipped"]} 个')


if __name__ == '__main__':
    asyncio.run(main())
