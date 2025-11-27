"""
VOA Learning English RSS Feed Scraper
抓取VOA Learning English各个频道的RSS feed并导出到CSV
使用RSS feed方式抓取
"""
import asyncio
import feedparser
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
import pandas as pd
import re

# VOA Learning English频道列表
# 排除还在更新的"VOA Learning English Podcast"和视频频道
# 排除实事新闻频道 "As It Is"
# 视频频道: Everyday Grammar Video, English @ the Movies, English in a Minute, News Words, How to Pronounce, Talk2Us
VOA_CHANNELS = [
    "Arts & Culture",
    "American Stories",
    "Ask a Teacher",
    "Everyday Grammar",
    "Education Tips",
    "Health & Lifestyle",
    "Science & Technology",
    "Words and Their Stories",
    "America's Presidents",
    "America's National Parks",
    "Early Literacy",
    "Education",
    "What's Trending Today?",
    "What It Takes",
    "English on the Job",
    "U.S. History",
]

# 频道名称到zoneId的映射（从VOA网站获取）
CHANNEL_ZONEID_MAP = {
    "As It Is": "3521",
    "Arts & Culture": "986",
    "American Stories": "1581",
    "Ask a Teacher": "5535",
    "Everyday Grammar": "4456",
    "Education Tips": "7468",
    "Health & Lifestyle": "955",
    "Science & Technology": "1579",
    "Words and Their Stories": "987",
    "America's Presidents": "5091",
    "America's National Parks": "4791",
    "Early Literacy": "7467",
    "Education": "959",
    "What's Trending Today?": "1689",
    "What It Takes": "4652",
    "English on the Job": "5254",
    "U.S. History": "979",
}

def parse_duration(duration_str: str) -> Optional[int]:
    """解析时长字符串（如"00:15:30"或"930"秒）返回秒数"""
    if not duration_str:
        return None
    
    try:
        # 如果是纯数字，假设是秒数
        if duration_str.isdigit():
            return int(duration_str)
        
        # 如果是HH:MM:SS格式
        if ':' in duration_str:
            parts = duration_str.split(':')
            if len(parts) == 3:
                hours, minutes, seconds = map(int, parts)
                return hours * 3600 + minutes * 60 + seconds
            elif len(parts) == 2:
                minutes, seconds = map(int, parts)
                return minutes * 60 + seconds
        
        # 尝试直接转换为整数
        return int(float(duration_str))
    except:
        return None


def parse_rss_feed(rss_url: str, channel_name: str) -> List[Dict[str, Any]]:
    """使用feedparser解析RSS feed，提取episode信息"""
    episodes = []
    
    try:
        # feedparser可以直接解析URL
        feed = feedparser.parse(rss_url)
        
        # 检查是否有错误
        if feed.bozo and feed.bozo_exception:
            print(f"  警告: RSS feed解析有警告: {feed.bozo_exception}")
        
        # 遍历所有条目
        for entry in feed.entries:
            # 获取标题
            title = entry.get('title', '').strip()
            
            # 获取描述（优先使用itunes:summary，然后是description）
            description = ''
            if hasattr(entry, 'itunes_summary'):
                description = entry.itunes_summary
            elif hasattr(entry, 'summary'):
                description = entry.summary
            elif hasattr(entry, 'description'):
                description = entry.description
            
            # 清理HTML标签
            if description:
                description = re.sub(r'<[^>]+>', '', description)
                description = description.strip()
            
            # 获取音频URL
            audio_url = None
            
            # 优先查找enclosures（RSS标准）
            if hasattr(entry, 'enclosures') and entry.enclosures:
                for enclosure in entry.enclosures:
                    href = enclosure.get('href', '')
                    if href and (enclosure.get('type', '').startswith('audio/') or '.mp3' in href):
                        audio_url = href
                        break
            
            # 如果没有找到，尝试media:content
            if not audio_url and hasattr(entry, 'media_content'):
                for media in entry.media_content:
                    if media.get('type', '').startswith('audio/') or '.mp3' in media.get('url', ''):
                        audio_url = media.get('url', '')
                        break
            
            # 如果还是没有找到，尝试从links中查找
            if not audio_url and hasattr(entry, 'links'):
                for link in entry.links:
                    href = link.get('href', '')
                    if '.mp3' in href or link.get('type', '').startswith('audio/'):
                        audio_url = href
                        break
            
            # 最后尝试从description中提取
            if not audio_url and description:
                urls = re.findall(r'https?://[^\s<>"]+\.mp3[^\s<>"]*', description)
                if urls:
                    audio_url = urls[0]
            
            if not audio_url:
                continue
            
            # 解析日期（feedparser自动处理）
            item_date = None
            if hasattr(entry, 'published_parsed') and entry.published_parsed:
                # published_parsed是time.struct_time，转换为datetime
                import time
                item_date = datetime.fromtimestamp(time.mktime(entry.published_parsed), tz=timezone.utc)
            elif hasattr(entry, 'updated_parsed') and entry.updated_parsed:
                import time
                item_date = datetime.fromtimestamp(time.mktime(entry.updated_parsed), tz=timezone.utc)
            
            if not item_date:
                item_date = datetime.now(timezone.utc)
            
            # 解析时长（itunes:duration）
            duration = None
            if hasattr(entry, 'itunes_duration'):
                duration = parse_duration(entry.itunes_duration)
            
            episode = {
                'company': 'VOA',
                'channel': channel_name,
                'audioURL': audio_url,
                'title': title,
                'subtitle': description,
                'timestamp': int(item_date.timestamp()),
                'language': 'en',
                'duration': duration,
            }
            episodes.append(episode)
    
    except Exception as e:
        print(f"  错误: 解析RSS feed失败: {e}")
        import traceback
        traceback.print_exc()
    
    return episodes


def get_rss_url_for_channel(channel_name: str) -> Optional[str]:
    """获取频道的RSS feed URL"""
    zone_id = CHANNEL_ZONEID_MAP.get(channel_name)
    if not zone_id:
        print(f"  警告: 未找到频道 '{channel_name}' 的zoneId")
        return None
    
    return f"https://learningenglish.voanews.com/podcast/?zoneId={zone_id}&format=rss"


async def scrape_voa_channel(channel_name: str) -> List[Dict[str, Any]]:
    """抓取单个VOA频道的所有episodes（使用feedparser解析RSS feed）"""
    print(f"\n正在处理频道: {channel_name}")
    
    rss_url = get_rss_url_for_channel(channel_name)
    if not rss_url:
        print(f"  警告: 无法找到频道 '{channel_name}' 的RSS feed URL")
        return []
    
    print(f"  RSS Feed URL: {rss_url}")
    
    # 使用feedparser解析RSS feed（可以直接传入URL）
    episodes = parse_rss_feed(rss_url, channel_name)
    
    print(f"  找到 {len(episodes)} 个episodes")
    return episodes


async def scrape_all_voa_channels() -> List[Dict[str, Any]]:
    """抓取所有VOA频道的episodes"""
    all_episodes = []
    
    for channel in VOA_CHANNELS:
        episodes = await scrape_voa_channel(channel)
        all_episodes.extend(episodes)
        # 添加小延迟避免请求过快
        await asyncio.sleep(1)
    
    return all_episodes


def export_to_csv(episodes: List[Dict[str, Any]], output_file: str = "voa_podcasts.csv"):
    """导出episodes到CSV文件"""
    if not episodes:
        print("没有episodes可导出")
        return
    
    # 转换为DataFrame
    df = pd.DataFrame(episodes)
    
    # 按频道和时间戳排序
    df = df.sort_values(['channel', 'timestamp'], ascending=[True, False])
    
    # 导出到CSV（使用UTF-8编码，Mac可以正常打开）
    df.to_csv(output_file, index=False, encoding='utf-8-sig')  # utf-8-sig添加BOM，Excel可以正确识别
    print(f"\n成功导出 {len(episodes)} 个episodes到 {output_file}")
    
    # 打印统计信息
    print_statistics(df)


def print_statistics(df: pd.DataFrame):
    """打印统计信息"""
    print(f"\n{'='*60}")
    print("频道统计:")
    print(f"{'='*60}")
    channel_counts = df.groupby('channel').size().sort_values(ascending=False)
    total = 0
    for channel, count in channel_counts.items():
        print(f"  {channel:30s}: {count:4d} 个episodes")
        total += count
    
    print(f"{'='*60}")
    print(f"总计: {total} 个episodes，共 {len(channel_counts)} 个频道")
    
    # 检查是否有0个episodes的频道
    all_channels = set(VOA_CHANNELS)
    found_channels = set(channel_counts.index)
    missing_channels = all_channels - found_channels
    if missing_channels:
        print(f"\n警告: 以下频道没有找到任何episodes:")
        for channel in sorted(missing_channels):
            print(f"  - {channel}")

async def main():
    """主函数"""
    print("开始抓取VOA Learning English所有频道的RSS feeds...")
    print(f"共 {len(VOA_CHANNELS)} 个频道")
    
    episodes = await scrape_all_voa_channels()
    
    if episodes:
        export_to_csv(episodes, "voa_podcasts.csv")
        print(f"\n✓ 导出完成！")
        print(f"  - CSV文件: voa_podcasts.csv (Mac可以直接打开)")
    else:
        print("未找到任何episodes")


if __name__ == "__main__":
    asyncio.run(main())

