"""NPR All Things Considered服务"""
import httpx
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
import re

class NPRService:
    """NPR All Things Considered服务类"""
    
    # NPR Listening API
    LISTENING_API_BASE = "https://listening.api.npr.org/v2"
    RUNDOWN_ID = "2"  # All Things Considered 的 rundown ID
    API_AUTHORIZATION = "Bearer 0935c7ba75dd8f1b3fc039545bb98023dbb2212b367c5b633f1f4978c817f6d969b0660eedb25128"
    
    def __init__(self):
        self.company = "NPR"
        self.channel = "All Things Considered"
    
    async def fetch_today_episodes(self) -> List[Dict[str, Any]]:
        """
        获取昨天的All Things Considered节目（默认）
        
        Returns:
            包含podcast信息的字典列表
        """
        return await self.fetch_episodes_by_days(1)
    
    async def fetch_episodes_by_days(self, days: int) -> List[Dict[str, Any]]:
        """
        获取前N天的All Things Considered节目
        
        Args:
            days: 前几天的数据总和，1表示昨天，2表示昨天和前天，以此类推
            
        Returns:
            包含podcast信息的字典列表（按日期倒序，最新的在前）
        """
        from datetime import timedelta
        
        all_episodes = []
        now = datetime.now(timezone.utc)
        
        # 从昨天开始，往前获取N天的数据
        for i in range(1, days + 1):
            target_date = now - timedelta(days=i)
            print(f'[npr-service] 拉取 {target_date.strftime("%Y-%m-%d")} 的数据...')
            episodes = await self.fetch_episodes_by_date(target_date)
            all_episodes.extend(episodes)
        
        # 按时间戳倒序排列（最新的在前）
        all_episodes.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
        
        return all_episodes
    
    async def fetch_episodes_by_date(self, date: datetime) -> List[Dict[str, Any]]:
        """
        获取指定日期的All Things Considered完整节目
        
        Args:
            date: 目标日期
            
        Returns:
            包含podcast信息的字典列表（每个日期一个完整节目）
        """
        try:
            # 统一转换为UTC时区
            if date.tzinfo is None:
                date_utc = date.replace(tzinfo=timezone.utc)
            else:
                date_utc = date.astimezone(timezone.utc)
            target_date_str = date_utc.strftime('%Y-%m-%d')
            
            # 调用 NPR Listening API
            async with httpx.AsyncClient(timeout=30.0) as client:
                headers = {
                    'accept': 'application/json',
                    'user-agent': 'NPR/1452.1 CFNetwork/3860.300.31 Darwin/25.2.0',
                    'x-supports': 'dr,up,step,music,livestream',
                    'accept-language': 'en',
                    'authorization': self.API_AUTHORIZATION
                }
                
                # 获取最新节目
                url = f'{self.LISTENING_API_BASE}/rundowns/{self.RUNDOWN_ID}/recommendations?origin=DAILYPOD'
                response = await client.get(url, headers=headers)
                response.raise_for_status()
                
                data = response.json()
                attrs = data.get('attributes', {})
                show_date_str = attrs.get('showDate', '')
                
                # 检查最新节目的日期是否匹配，不匹配直接返回空列表
                if show_date_str:
                    try:
                        date_part = show_date_str.split('T')[0]
                        if date_part != target_date_str:
                            print(f'[npr-service] 最新节目日期 {date_part} 与目标日期 {target_date_str} 不匹配，跳过')
                            return []
                    except Exception as e:
                        print(f'[npr-service] 检查日期时出错: {e}')
                        return []
                
                items = data.get('items', [])
                
                if not items:
                    print(f'[npr-service] API返回的items为空')
                    return []
                
                podcasts = []
                
                # 遍历items数组，为每个item创建一个podcast
                for item in items:
                    item_attrs = item.get('attributes', {})
                    item_links = item.get('links', {})
                    
                    # 提取音频URL（从links.audio中找mp3格式的）
                    audio_url = None
                    audio_links = item_links.get('audio', [])
                    for link in audio_links:
                        href = link.get('href', '')
                        if href and '.mp3' in href:
                            # 去掉查询参数，只保留URL
                            audio_url = href.split('?')[0]
                            break
                    
                    if not audio_url:
                        print(f'[npr-service] 未找到音频URL，跳过item: {item_attrs.get("title", "unknown")}')
                        continue
                    
                    # 解析日期
                    item_date_str = item_attrs.get('date', '')
                    if item_date_str:
                        try:
                            # 解析日期字符串，格式：2025-11-19T16:00:00-0400
                            date_part = item_date_str.split('T')[0]
                            item_date = datetime.strptime(date_part, '%Y-%m-%d').replace(tzinfo=timezone.utc)
                            item_date_str_formatted = item_date.strftime('%Y-%m-%d')
                        except Exception as e:
                            print(f'[npr-service] 无法解析item日期: {item_date_str}, 错误: {e}')
                            item_date_str_formatted = target_date_str
                            item_date = date_utc
                    else:
                        item_date_str_formatted = target_date_str
                        item_date = date_utc
                    
                    # 如果指定了日期，只返回匹配的
                    if item_date_str_formatted != target_date_str:
                        continue
                    
                    # 提取标题和描述
                    title = item_attrs.get('title', '') or item_attrs.get('audioTitle', '')
                    description = item_attrs.get('description', '')
                    
                    # 构建podcast数据
                    podcast = {
                        'company': self.company,
                        'channel': self.channel,
                        'audioURL': audio_url,
                        'title': title,
                        'subtitle': description,
                        'timestamp': int(item_date.timestamp()),
                        'language': 'en',
                        'segments': []  # 不存储，后续通过关联获取
                    }
                    
                    podcasts.append(podcast)
                
                return podcasts
                
        except httpx.HTTPStatusError as e:
            raise Exception(f"获取NPR API失败: HTTP {e.response.status_code}")
        except httpx.RequestError as e:
            raise Exception(f"请求NPR API失败: {str(e)}")
        except Exception as e:
            raise Exception(f"解析NPR API响应失败: {str(e)}")

