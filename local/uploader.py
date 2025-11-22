"""Upload processed podcasts to server"""
import httpx
from typing import List, Dict, Any

class PodcastUploader:
    """Podcast上传器"""
    
    def __init__(self, server_url: str):
        """
        初始化上传器
        Args:
            server_url: 服务器URL，例如 'http://localhost:8001' 或 'https://elegantfish.online'
        """
        self.server_url = server_url.rstrip('/')
        self.base_url = f'{self.server_url}/podcast'
    
    async def upload_podcast(self, podcast: Dict[str, Any]) -> bool:
        """
        上传单个podcast到服务器
        """
        try:
            async with httpx.AsyncClient(timeout=300.0) as client:
                response = await client.post(
                    f'{self.base_url}/upload',
                    json=podcast
                )
                response.raise_for_status()
                print(f'[uploader] 上传成功: {podcast.get("id")} - {podcast.get("title", "Unknown")}')
                return True
        except httpx.HTTPStatusError as e:
            print(f'[uploader] 上传失败 (HTTP {e.response.status_code}): {podcast.get("id")}')
            print(f'[uploader] 错误信息: {e.response.text}')
            return False
        except httpx.RequestError as e:
            print(f'[uploader] 请求失败: {str(e)}')
            return False
        except Exception as e:
            print(f'[uploader] 上传异常: {str(e)}')
            return False
    
    async def upload_batch(self, podcasts: List[Dict[str, Any]], use_batch_api: bool = True) -> Dict[str, int]:
        """
        批量上传podcasts
        """
        if not podcasts:
            return {'success': 0, 'failed': 0, 'total': 0}
        
        if use_batch_api:
            # 使用批量上传接口
            try:
                print(f'[uploader] 开始批量上传 {len(podcasts)} 个podcasts（使用批量接口）...')
                async with httpx.AsyncClient(timeout=600.0) as client:
                    response = await client.post(
                        f'{self.base_url}/upload/batch',
                        json=podcasts
                    )
                    response.raise_for_status()
                    result = response.json()
                    
                    success_count = result.get('success_count', 0)
                    fail_count = result.get('fail_count', 0)
                    
                    print(f'[uploader] 批量上传完成：成功 {success_count}，失败 {fail_count}')
                    
                    return {
                        'success': success_count,
                        'failed': fail_count,
                        'total': len(podcasts)
                    }
            except httpx.HTTPStatusError as e:
                print(f'[uploader] 批量上传失败 (HTTP {e.response.status_code})')
                print(f'[uploader] 错误信息: {e.response.text}')
                # 降级为单个上传
                print(f'[uploader] 降级为单个上传模式...')
                use_batch_api = False
            except Exception as e:
                print(f'[uploader] 批量上传异常: {str(e)}')
                print(f'[uploader] 降级为单个上传模式...')
                use_batch_api = False
        
        # 单个上传模式（降级或use_batch_api=False）
        if not use_batch_api:
            print(f'[uploader] 开始逐个上传 {len(podcasts)} 个podcasts...')
            success_count = 0
            fail_count = 0
            
            for podcast in podcasts:
                if await self.upload_podcast(podcast):
                    success_count += 1
                else:
                    fail_count += 1
            
            print(f'[uploader] 批量上传完成：成功 {success_count}，失败 {fail_count}')
            
            return {
                'success': success_count,
                'failed': fail_count,
                'total': len(podcasts)
            }

