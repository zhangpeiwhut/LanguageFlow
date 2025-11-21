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
        通过prev链接遍历获取历史数据
        
        Args:
            days: 前几天的数据总和，1表示昨天，2表示昨天和前天，以此类推
            
        Returns:
            包含podcast信息的字典列表（按日期倒序，最新的在前）
        """
        from datetime import timedelta
        
        # 计算目标日期列表
        now = datetime.now(timezone.utc)
        target_dates = []
        for i in range(1, days + 1):
            target_date = now - timedelta(days=i)
            target_dates.append(target_date.strftime('%Y-%m-%d'))
        
        print(f'[npr-service] 需要获取的日期: {target_dates}')
        
        all_episodes = []
        url = f'{self.LISTENING_API_BASE}/rundowns/{self.RUNDOWN_ID}/recommendations?origin=DAILYPOD'
        max_iterations = 30  # 最多遍历30天
        iteration = 0
        found_dates = set()
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            headers = {
                'accept': 'application/json',
                'user-agent': 'NPR/1452.1 CFNetwork/3860.300.31 Darwin/25.2.0',
                'x-supports': 'dr,up,step,music,livestream',
                'accept-language': 'en',
                'authorization': self.API_AUTHORIZATION
            }
            
            while iteration < max_iterations and len(found_dates) < len(target_dates):
                iteration += 1
                response = await client.get(url, headers=headers)
                response.raise_for_status()
                
                data = response.json()
                attrs = data.get('attributes', {})
                show_date_str = attrs.get('showDate', '')
                
                # 解析当前响应的日期
                current_date_str = None
                if show_date_str:
                    try:
                        current_date_str = show_date_str.split('T')[0]
                    except:
                        pass
                
                print(f'[npr-service] 当前API返回的日期: {current_date_str}')
                
                items = data.get('items', [])
                if not items:
                    print(f'[npr-service] API返回的items为空')
                    break
                
                # 如果当前日期在目标日期列表中，处理items
                if current_date_str and current_date_str in target_dates:
                    print(f'[npr-service] 找到目标日期 {current_date_str}，处理items...')
                    found_dates.add(current_date_str)
                    
                    for item in items:
                        item_attrs = item.get('attributes', {})
                        item_links = item.get('links', {})
                        
                        # 提取音频URL
                        audio_url = None
                        audio_links = item_links.get('audio', [])
                        for link in audio_links:
                            href = link.get('href', '')
                            if href and '.mp3' in href:
                                audio_url = href.split('?')[0]
                                break
                        
                        if not audio_url:
                            continue
                        
                        # 解析日期
                        item_date_str = item_attrs.get('date', '')
                        if item_date_str:
                            try:
                                date_part = item_date_str.split('T')[0]
                                item_date = datetime.strptime(date_part, '%Y-%m-%d').replace(tzinfo=timezone.utc)
                                item_date_str_formatted = item_date.strftime('%Y-%m-%d')
                            except:
                                item_date_str_formatted = current_date_str
                                item_date = datetime.strptime(current_date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
                        else:
                            item_date_str_formatted = current_date_str
                            item_date = datetime.strptime(current_date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
                        
                        # 只处理匹配当前日期的items
                        if item_date_str_formatted == current_date_str:
                            title = item_attrs.get('title', '') or item_attrs.get('audioTitle', '')
                            description = item_attrs.get('description', '')
                            
                            podcast = {
                                'company': self.company,
                                'channel': self.channel,
                                'audioURL': audio_url,
                                'title': title,
                                'subtitle': description,
                                'timestamp': int(item_date.timestamp()),
                                'language': 'en',
                                'segments': []
                            }
                            
                            all_episodes.append(podcast)
                
                # 获取prev链接，继续遍历
                links = data.get('links', {})
                prev_links = links.get('prev', [])
                if not prev_links:
                    print(f'[npr-service] 没有prev链接，无法获取更早的数据')
                    break
                
                # 使用第一个prev链接
                prev_link = prev_links[0]
                url = prev_link.get('href', '')
                if not url:
                    break
        
        # 按时间戳倒序排列（最新的在前）
        all_episodes.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
        print(f'[npr-service] 成功获取 {len(all_episodes)} 个episodes，覆盖日期: {sorted(found_dates)}')
        
        return all_episodes

