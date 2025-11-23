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
                audioURL TEXT NOT NULL,
                title TEXT,
                titleTranslation TEXT,
                subtitle TEXT,
                timestamp INTEGER NOT NULL,
                language TEXT NOT NULL DEFAULT 'en',
                duration INTEGER,
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
        
        # 创建segments表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                podcast_id TEXT NOT NULL,
                text TEXT NOT NULL,
                start REAL NOT NULL,
                end REAL NOT NULL,
                translation TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (podcast_id) REFERENCES podcasts(id) ON DELETE CASCADE
            )
        """)
        
        # 创建segments索引
        # 复合索引：优化按podcast_id查询并按start排序的性能
        # 这个索引可以同时用于：
        # 1. WHERE podcast_id = ? (使用索引前缀)
        # 2. WHERE podcast_id = ? ORDER BY start (完美匹配)
        # 3. DELETE FROM segments WHERE podcast_id = ? (使用索引前缀)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_segments_podcast_id_start 
            ON segments(podcast_id, start)
        """)
        
        conn.commit()
        conn.close()
    
    def insert_podcast(self, podcast_data: Dict[str, Any]) -> str:
        """
        插入或更新podcast数据（包含segments）
        
        Args:
            podcast_data: 包含podcast信息的字典，可以包含segments字段
            
        Returns:
            podcast的ID
        """
        # id 由客户端提供
        if 'id' not in podcast_data:
            raise ValueError('podcast_data必须包含id字段')
        podcast_id = podcast_data['id']
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 使用INSERT OR REPLACE来避免重复
        cursor.execute("""
            INSERT OR REPLACE INTO podcasts 
            (id, company, channel, audioURL, title, titleTranslation, subtitle, timestamp, language, duration, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            podcast_id,
            podcast_data['company'],
            podcast_data['channel'],
            podcast_data['audioURL'],
            podcast_data.get('title'),
            podcast_data.get('titleTranslation'),
            podcast_data.get('subtitle'),
            podcast_data['timestamp'],
            podcast_data.get('language', 'en'),
            podcast_data.get('duration'),
            datetime.now().isoformat()
        ))
        
        # 如果有segments，插入segments
        segments = podcast_data.get('segments', [])
        if segments:
            # 先删除旧的segments
            cursor.execute("DELETE FROM segments WHERE podcast_id = ?", (podcast_id,))
            # 插入新的segments（使用自增ID，不指定id字段）
            for segment in segments:
                cursor.execute("""
                    INSERT INTO segments (podcast_id, text, start, end, translation)
                    VALUES (?, ?, ?, ?, ?)
                """, (
                    podcast_id,
                    segment.get('text', ''),
                    segment.get('start', 0.0),
                    segment.get('end', 0.0),
                    segment.get('translation')
                ))
        
        conn.commit()
        conn.close()
        
        return podcast_id
    
    def get_podcast_by_id(self, podcast_id: str) -> Optional[Dict[str, Any]]:
        """根据ID获取podcast（包含segments）"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM podcasts WHERE id = ?", (podcast_id,))
        row = cursor.fetchone()
        if not row:
            conn.close()
            return None
        result = dict(row)
        # 获取segments
        cursor.execute("""
            SELECT id, text, start, end, translation 
            FROM segments 
            WHERE podcast_id = ? 
            ORDER BY start ASC
        """, (podcast_id,))
        segment_rows = cursor.fetchall()
        result['segments'] = [
            {
                'id': seg['id'],
                'text': seg['text'],
                'start': seg['start'],
                'end': seg['end'],
                'translation': seg['translation']
            }
            for seg in segment_rows
        ]
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
        检查podcast是否完整（存在且有segments）
        暂时忽略segments翻译检查
        
        Args:
            podcast_id: podcast的ID
            
        Returns:
            如果podcast存在且有segments，返回True；否则返回False
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # 检查podcast是否存在
        cursor.execute("SELECT COUNT(*) FROM podcasts WHERE id = ?", (podcast_id,))
        if cursor.fetchone()[0] == 0:
            conn.close()
            return False
        
        # 检查是否有segments
        cursor.execute("SELECT COUNT(*) FROM segments WHERE podcast_id = ?", (podcast_id,))
        segment_count = cursor.fetchone()[0]
        
        conn.close()
        
        # 如果有segments，返回True（暂时忽略翻译检查）
        return segment_count > 0
        
        # TODO: 后续可以添加翻译检查
        # 检查是否所有segments都有翻译（非空）
        # cursor.execute("""
        #     SELECT COUNT(*) FROM segments 
        #     WHERE podcast_id = ? AND (translation IS NULL OR translation = '' OR trim(translation) = '')
        # """, (podcast_id,))
        # untranslated_count = cursor.fetchone()[0]
        # return untranslated_count == 0
    
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
        """
        start_timestamp = timestamp
        end_timestamp = start_timestamp + 86400  # 24小时后
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT p.id, p.title, p.titleTranslation, p.duration,
                   COUNT(s.id) as segmentCount
            FROM podcasts p
            LEFT JOIN segments s ON p.id = s.podcast_id
            WHERE p.company = ? AND p.channel = ? 
            AND p.timestamp >= ? AND p.timestamp < ?
            GROUP BY p.id, p.title, p.titleTranslation, p.duration
            ORDER BY p.timestamp DESC
        """, (company, channel, start_timestamp, end_timestamp))
        
        rows = cursor.fetchall()
        conn.close()
        
        results = []
        for row in rows:
            results.append({
                'id': row[0],
                'title': row[1],
                'titleTranslation': row[2],
                'duration': row[3],
                'segmentCount': row[4]
            })
        
        return results

