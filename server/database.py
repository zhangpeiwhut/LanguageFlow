"""数据库模型和操作"""
import sqlite3
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
                audioKey TEXT NOT NULL,
                rawAudioUrl TEXT,
                title TEXT,
                titleTranslation TEXT,
                subtitle TEXT,
                timestamp INTEGER NOT NULL,
                language TEXT NOT NULL DEFAULT 'en',
                duration INTEGER,
                segmentsKey TEXT,
                segmentCount INTEGER,
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
            CREATE INDEX IF NOT EXISTS idx_company_channel_timestamp_id
            ON podcasts(company, channel, timestamp DESC, id DESC)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON podcasts(timestamp)
        """)
        
        conn.commit()
        conn.close()
    
    def insert_podcast(self, podcast_data: Dict[str, Any]) -> str:
        # id 由客户端提供
        if 'id' not in podcast_data:
            raise ValueError('podcast_data必须包含id字段')
        podcast_id = podcast_data['id']
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 使用INSERT OR REPLACE来避免重复
        cursor.execute("""
            INSERT OR REPLACE INTO podcasts 
            (id, company, channel, audioKey, rawAudioUrl, title, titleTranslation, subtitle, timestamp, language, duration, segmentsKey, segmentCount, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            podcast_id,
            podcast_data['company'],
            podcast_data['channel'],
            podcast_data['audioKey'],
            podcast_data.get('rawAudioUrl'),
            podcast_data.get('title'),
            podcast_data.get('titleTranslation'),
            podcast_data.get('subtitle'),
            podcast_data['timestamp'],
            podcast_data.get('language', 'en'),
            podcast_data.get('duration'),
            podcast_data.get('segmentsKey'),
            podcast_data.get('segmentCount'),
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
        if not row:
            conn.close()
            return None
        result = dict(row)
        conn.close()
        return result
    
    def get_podcasts_by_timestamp(self, company: str, channel: str, timestamp: int) -> List[Dict[str, Any]]:
        """
        根据时间戳获取podcasts
        """
        from datetime import timezone
        
        start_timestamp = timestamp
        end_timestamp = start_timestamp + 86400
        
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
    
    def is_podcast_complete(self, podcast_id: str) -> bool:
        """
        检查podcast是否完整
        
        Args:
            podcast_id: podcast的ID
            
        Returns:
            如果podcast存在，返回True；否则返回False
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT COUNT(*) FROM podcasts 
            WHERE id = ? AND segmentsKey IS NOT NULL
        """, (podcast_id,))
        count = cursor.fetchone()[0]
        
        conn.close()
        
        return count > 0
    
    def get_all_channels(self) -> List[Dict[str, str]]:
        """
        获取所有的podcast频道（company + channel组合）
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
    
    def get_channel_dates(self, company: str, channel: str) -> List[int]:
        """
        获取某个频道的所有日期时间戳列表
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

        timestamps = []
        seen_dates = set()
        for row in rows:
            timestamp = row[0]
            date_obj = datetime.fromtimestamp(timestamp, tz=timezone.utc)
            date_str = date_obj.strftime('%Y-%m-%d')
            if date_str not in seen_dates:
                seen_dates.add(date_str)
                start_datetime = datetime(date_obj.year, date_obj.month, date_obj.day, tzinfo=timezone.utc)
                timestamps.append(int(start_datetime.timestamp()))
        return timestamps

    def get_channel_podcasts_by_timestamp(self, company: str, channel: str, timestamp: int) -> List[Dict[str, Any]]:
        """
        获取某个频道某个日期的所有podcasts摘要
        若请求的日期是该频道最新日期，则当日列表首条为免费试听
        """
        start_timestamp = timestamp
        end_timestamp = start_timestamp + 86400  # 24小时后
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT MAX(timestamp) FROM podcasts
            WHERE company = ? AND channel = ?
        """, (company, channel))
        latest_ts = cursor.fetchone()[0]
        latest_date_start = None
        if latest_ts is not None:
            latest_date = datetime.utcfromtimestamp(latest_ts)
            latest_date_start = int(datetime(latest_date.year, latest_date.month, latest_date.day).timestamp())

        cursor.execute("""
            SELECT id, title, titleTranslation, duration, segmentCount
            FROM podcasts
            WHERE company = ? AND channel = ? 
            AND timestamp >= ? AND timestamp < ?
            ORDER BY timestamp DESC
        """, (company, channel, start_timestamp, end_timestamp))
        
        rows = cursor.fetchall()
        conn.close()
        
        results = []
        for index, row in enumerate(rows):
            is_free = (
                latest_date_start is not None
                and start_timestamp == latest_date_start
                and index == 0
            )
            results.append({
                'id': row[0],
                'title': row[1],
                'titleTranslation': row[2],
                'duration': row[3],
                'segmentCount': row[4],  # 从数据库读取实际数量
                'isFree': is_free,
            })
        
        return results

    def get_channel_podcasts_paginated(
        self,
        company: str,
        channel: str,
        page: int,
        limit: int
    ) -> Dict[str, Any]:
        """
        按频道分页获取podcast摘要，按时间倒序+id倒序保证稳定顺序
        第一页的第一条标记为免费试听
        """
        offset = (page - 1) * limit
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        cursor.execute("""
            SELECT COUNT(*) AS total
            FROM podcasts
            WHERE company = ? AND channel = ?
        """, (company, channel))
        total = cursor.fetchone()["total"]

        cursor.execute("""
            SELECT id, title, titleTranslation, duration, segmentCount, timestamp
            FROM podcasts
            WHERE company = ? AND channel = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT ? OFFSET ?
        """, (company, channel, limit, offset))

        rows = cursor.fetchall()
        conn.close()

        podcasts = []
        for index, row in enumerate(rows):
            # 只有第一页的第一条是免费的
            is_free = (page == 1 and index == 0)

            podcasts.append({
                'id': row['id'],
                'title': row['title'],
                'titleTranslation': row['titleTranslation'],
                'duration': row['duration'],
                'segmentCount': row['segmentCount'],
                'timestamp': row['timestamp'],
                'isFree': is_free,
            })

        return {
            'total': total,
            'podcasts': podcasts,
        }

    def is_podcast_free(self, company: str, channel: str, podcast_id: str) -> bool:
        """
        判断某个 podcast 是否免费
        规则：该频道下按时间倒序排列的第一条是免费的
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT timestamp, id
            FROM podcasts
            WHERE id = ? AND company = ? AND channel = ?
        """, (podcast_id, company, channel))

        current = cursor.fetchone()
        if not current:
            conn.close()
            return False

        current_ts, current_id = current

        # 如果存在更“新”的一条，则当前不是免费的
        cursor.execute("""
            SELECT 1
            FROM podcasts
            WHERE company = ?
              AND channel = ?
              AND (
                    timestamp > ?
                 OR (timestamp = ? AND id > ?)
              )
            LIMIT 1
        """, (company, channel, current_ts, current_ts, current_id))

        has_newer = cursor.fetchone() is not None
        conn.close()

        return not has_newer
