#!/usr/bin/env python3
"""Entry point for local podcast processing"""
import sys
import os

project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)

from local.main import main
import asyncio
import argparse

if __name__ == '__main__':
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

