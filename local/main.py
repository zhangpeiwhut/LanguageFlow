"""Main script for local podcast processing"""
import asyncio
import os
from typing import Optional
from .processor import fetch_and_process_today_podcasts
from .uploader import PodcastUploader

async def main(days: int = 1, upload: bool = True, server_url: Optional[str] = None):
    """
    主函数：获取、处理并上传podcasts
    
    Args:
        days: 获取前几天的数据，默认1（昨天）
        upload: 是否上传到服务器，默认True
        server_url: 服务器URL，如果不提供则从环境变量读取
    """
    print('=' * 60)
    print('Local Podcast Processor')
    print('=' * 60)
    
    # 1. 获取并处理podcasts
    print(f'\n[main] 步骤1: 获取并处理前{days}天的podcasts...')
    processed_podcasts = await fetch_and_process_today_podcasts(days=days)
    
    if not processed_podcasts:
        print('[main] 没有需要处理的podcasts，退出')
        return
    
    print(f'[main] 处理完成，共 {len(processed_podcasts)} 个podcasts')
    
    # 2. 上传到服务器（如果需要）
    if upload:
        if not server_url:
            server_url = os.getenv('SERVER_URL', 'http://localhost:8001')
        
        print(f'\n[main] 步骤2: 上传到服务器 ({server_url})...')
        uploader = PodcastUploader(server_url)
        result = await uploader.upload_batch(processed_podcasts)
        
        print(f'\n[main] 上传结果:')
        print(f'  - 成功: {result["success"]}')
        print(f'  - 失败: {result["failed"]}')
        print(f'  - 总计: {result["total"]}')
    else:
        print('\n[main] 跳过上传步骤')
    
    print('\n[main] 全部完成！')


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='本地Podcast处理脚本')
    parser.add_argument('--days', type=int, default=1, help='获取前几天的数据（默认1）')
    parser.add_argument('--no-upload', action='store_true', help='不上传到服务器')
    parser.add_argument('--server-url', type=str, help='服务器URL（默认从环境变量SERVER_URL读取）')
    
    args = parser.parse_args()
    
    asyncio.run(main(
        days=args.days,
        upload=not args.no_upload,
        server_url=args.server_url
    ))

