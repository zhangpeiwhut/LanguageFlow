"""数据库模型和操作"""
import sqlite3
import json
import hashlib
import uuid
from datetime import datetime
from typing import Optional, List, Dict, Any


class PodcastDatabase:
    """Podcast数据库操作类"""
    def __init__(self, db_path: str = "podcasts.db"):
        self.db_path = db_path
        self._init_database()
    
    def _init_database(self):
        """初始化数据库表结构"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 创建podcasts表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS podcasts (
                id TEXT PRIMARY KEY,
                company TEXT NOT NULL,
                channel TEXT NOT NULL,
                audioURL TEXT NOT NULL,
                title TEXT,
                subtitle TEXT,
                timestamp INTEGER NOT NULL,
                language TEXT NOT NULL DEFAULT 'en',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # 创建索引
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_company_channel 
            ON podcasts(company, channel)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON podcasts(timestamp)
        """)
        
        conn.commit()
        conn.close()
    
    def _generate_id(self, company: str, channel: str, timestamp: int, audio_url: str, title: Optional[str] = None) -> str:
        """
        生成唯一ID，基于内容的hash
        
        使用 company + channel + timestamp + audioURL + title 的hash值
        这样相同内容的podcast会生成相同的ID，便于去重
        
        Args:
            company: 公司名称
            channel: 频道名称
            timestamp: 时间戳
            audio_url: 音频URL
            title: 标题（可选）
            
        Returns:
            生成的32位hash ID
        """
        # 规范化输入
        normalized_company = (company or "").strip().lower()
        normalized_channel = (channel or "").strip().lower()
        normalized_title = (title or "").strip().lower()
        normalized_url = (audio_url or "").strip()
        
        # 组合内容生成hash
        content = f"{normalized_company}|{normalized_channel}|{timestamp}|{normalized_url}|{normalized_title}"
        hash_obj = hashlib.sha256(content.encode('utf-8'))
        return hash_obj.hexdigest()[:32]  # 使用32位hash作为ID
    
    def insert_podcast(self, podcast_data: Dict[str, Any]) -> str:
        """
        插入或更新podcast数据
        
        Args:
            podcast_data: 包含podcast信息的字典
            
        Returns:
            podcast的ID
        """
        # 生成ID（基于内容，相同内容会生成相同ID）
        podcast_id = self._generate_id(
            company=podcast_data['company'],
            channel=podcast_data['channel'],
            timestamp=podcast_data['timestamp'],
            audio_url=podcast_data['audioURL'],
            title=podcast_data.get('title')
        )
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 使用INSERT OR REPLACE来避免重复
        cursor.execute("""
            INSERT OR REPLACE INTO podcasts 
            (id, company, channel, audioURL, title, subtitle, timestamp, language, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            podcast_id,
            podcast_data['company'],
            podcast_data['channel'],
            podcast_data['audioURL'],
            podcast_data.get('title'),
            podcast_data.get('subtitle'),
            podcast_data['timestamp'],
            podcast_data.get('language', 'en'),
            datetime.now().isoformat()
        ))
        
        conn.commit()
        conn.close()
        
        return podcast_id
    
    def get_podcast_by_id(self, podcast_id: str) -> Optional[Dict[str, Any]]:
        """根据ID获取podcast"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("SELECT * FROM podcasts WHERE id = ?", (podcast_id,))
        row = cursor.fetchone()
        conn.close()
        
        if row:
            result = dict(row)
            return result
        return None
    
    def get_podcasts_by_date(self, company: str, channel: str, date: Optional[datetime] = None) -> List[Dict[str, Any]]:
        """
        根据日期获取podcasts
        
        Args:
            company: 公司名称
            channel: 频道名称
            date: 日期，如果为None则使用当天（UTC时区）
        """
        from datetime import timezone
        if date is None:
            date = datetime.now(timezone.utc)
        
        # 统一转换为UTC时区
        if date.tzinfo is None:
            date = date.replace(tzinfo=timezone.utc)
        else:
            date = date.astimezone(timezone.utc)
        
        # 获取当天的开始和结束时间戳（UTC时区）
        start_datetime = datetime(date.year, date.month, date.day, tzinfo=timezone.utc)
        start_timestamp = int(start_datetime.timestamp())
        end_timestamp = start_timestamp + 86400  # 24小时后
        
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM podcasts 
            WHERE company = ? AND channel = ? 
            AND timestamp >= ? AND timestamp < ?
            ORDER BY timestamp DESC
        """, (company, channel, start_timestamp, end_timestamp))
        
        rows = cursor.fetchall()
        conn.close()
        
        results = []
        for row in rows:
            result = dict(row)
            results.append(result)
        
        return results
    
    def podcast_exists(self, podcast_id: str) -> bool:
        """检查podcast是否存在"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("SELECT COUNT(*) FROM podcasts WHERE id = ?", (podcast_id,))
        count = cursor.fetchone()[0]
        conn.close()
        
        return count > 0
    
    def generate_id(self, company: str, channel: str, timestamp: int, audio_url: str, title: Optional[str] = None) -> str:
        """
        公开方法：生成唯一ID，基于内容的hash
        
        Args:
            company: 公司名称
            channel: 频道名称
            timestamp: 时间戳
            audio_url: 音频URL
            title: 标题（可选）
            
        Returns:
            生成的32位hash ID
        """
        return self._generate_id(company, channel, timestamp, audio_url, title)
    
    def get_all_channels(self) -> List[Dict[str, str]]:
        """
        获取所有的podcast频道（company + channel组合）
        
        Returns:
            包含company和channel的字典列表
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT DISTINCT company, channel 
            FROM podcasts 
            ORDER BY company, channel
        """)
        
        rows = cursor.fetchall()
        conn.close()
        
        return [{'company': row[0], 'channel': row[1]} for row in rows]
    
    def get_channel_dates(self, company: str, channel: str) -> List[str]:
        """
        获取某个频道的所有日期列表
        
        Args:
            company: 公司名称
            channel: 频道名称
            
        Returns:
            日期字符串列表，格式：YYYY-MM-DD
        """
        from datetime import timezone
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT DISTINCT timestamp 
            FROM podcasts 
            WHERE company = ? AND channel = ?
            ORDER BY timestamp DESC
        """, (company, channel))
        
        rows = cursor.fetchall()
        conn.close()
        
        dates = []
        for row in rows:
            timestamp = row[0]
            date_obj = datetime.fromtimestamp(timestamp, tz=timezone.utc)
            dates.append(date_obj.strftime('%Y-%m-%d'))
        
        return dates
    
    def get_channel_podcasts_by_date(self, company: str, channel: str, date: str) -> List[Dict[str, Any]]:
        """
        获取某个频道某个日期的所有podcasts
        
        Args:
            company: 公司名称
            channel: 频道名称
            date: 日期字符串，格式：YYYY-MM-DD
            
        Returns:
            包含podcast信息的字典列表
        """
        from datetime import timezone
        
        try:
            # 解析日期
            target_date = datetime.strptime(date, '%Y-%m-%d').replace(tzinfo=timezone.utc)
        except ValueError:
            return []
        
        # 获取当天的开始和结束时间戳（UTC时区）
        start_datetime = datetime(target_date.year, target_date.month, target_date.day, tzinfo=timezone.utc)
        start_timestamp = int(start_datetime.timestamp())
        end_timestamp = start_timestamp + 86400  # 24小时后
        
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT * FROM podcasts 
            WHERE company = ? AND channel = ? 
            AND timestamp >= ? AND timestamp < ?
            ORDER BY timestamp DESC
        """, (company, channel, start_timestamp, end_timestamp))
        
        rows = cursor.fetchall()
        conn.close()
        
        results = []
        for row in rows:
            result = dict(row)
            results.append(result)
        
        return results

