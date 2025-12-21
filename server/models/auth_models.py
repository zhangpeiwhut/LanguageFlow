"""认证和内购相关数据库模型"""
import sqlite3
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any


def _to_timestamp_ms(dt: Optional[datetime]) -> Optional[int]:
    """将 datetime 转为毫秒级时间戳（UTC）"""
    if dt is None:
        return None
    return int(dt.astimezone(timezone.utc).timestamp() * 1000)


def _now_ms() -> int:
    """当前时间的毫秒级时间戳"""
    return int(datetime.now(timezone.utc).timestamp() * 1000)


class AuthDatabase:
    """认证数据库操作类"""

    def __init__(self, db_path: str = "podcasts.db"):
        self.db_path = db_path
        self._init_tables()

    def _init_tables(self):
        """初始化认证相关表"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # 用户表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_uuid TEXT UNIQUE NOT NULL,
                original_transaction_id TEXT,
                is_vip INTEGER DEFAULT 0,
                vip_expire_time INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 付费凭证表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS purchase_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original_transaction_id TEXT UNIQUE NOT NULL,
                product_id TEXT NOT NULL,
                purchase_date INTEGER NOT NULL,
                expire_date INTEGER,
                status TEXT DEFAULT 'active',
                environment TEXT DEFAULT 'production',
                device_count INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 设备绑定表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS device_bindings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original_transaction_id TEXT NOT NULL,
                device_uuid TEXT NOT NULL,
                device_name TEXT,
                bind_time INTEGER,
                last_active_time INTEGER,
                UNIQUE(original_transaction_id, device_uuid)
            )
        """)

        # 交易日志表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS transaction_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original_transaction_id TEXT NOT NULL,
                transaction_id TEXT NOT NULL,
                jws_token TEXT,
                event_type TEXT,
                device_uuid TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # App Store 通知日志表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS notification_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                notification_uuid TEXT UNIQUE NOT NULL,
                notification_type TEXT,
                subtype TEXT,
                original_transaction_id TEXT,
                transaction_id TEXT,
                environment TEXT,
                signed_payload TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        # 创建索引
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_uuid ON users(device_uuid)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_users_trans_id ON users(original_transaction_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_purchase_trans_id ON purchase_records(original_transaction_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_device_trans_id ON device_bindings(original_transaction_id)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_device_active ON device_bindings(last_active_time)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_notification_uuid ON notification_logs(notification_uuid)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_notification_trans_id ON notification_logs(original_transaction_id)")

        conn.commit()
        conn.close()

    # 用户相关操作
    def get_user_by_uuid(self, device_uuid: str) -> Optional[Dict[str, Any]]:
        """根据设备UUID获取用户"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE device_uuid = ?", (device_uuid,))
        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return None

        return dict(row)

    def create_user(self, device_uuid: str) -> int:
        """创建新用户"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO users (device_uuid, is_vip) VALUES (?, 0)",
            (device_uuid,)
        )
        user_id = cursor.lastrowid
        conn.commit()
        conn.close()
        return user_id

    def update_user_vip_status(self, device_uuid: str, is_vip: bool,
                                original_transaction_id: Optional[str] = None,
                                vip_expire_time: Optional[datetime] = None):
        """更新用户VIP状态"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE users
            SET is_vip = ?, original_transaction_id = ?, vip_expire_time = ?, updated_at = CURRENT_TIMESTAMP
            WHERE device_uuid = ?
        """, (1 if is_vip else 0, original_transaction_id, _to_timestamp_ms(vip_expire_time), device_uuid))
        conn.commit()
        conn.close()

    def update_users_vip_status_by_original_transaction_id(
        self,
        original_transaction_id: str,
        is_vip: bool,
        vip_expire_time: Optional[datetime] = None,
    ):
        """按 original_transaction_id 批量更新用户VIP状态"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE users
            SET is_vip = ?, vip_expire_time = ?, updated_at = CURRENT_TIMESTAMP
            WHERE original_transaction_id = ?
        """, (1 if is_vip else 0, _to_timestamp_ms(vip_expire_time), original_transaction_id))
        conn.commit()
        conn.close()

    # 付费凭证相关操作
    def get_purchase_record(self, original_transaction_id: str) -> Optional[Dict[str, Any]]:
        """获取付费凭证"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM purchase_records WHERE original_transaction_id = ?",
                      (original_transaction_id,))
        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return None

        return dict(row)

    def create_purchase_record(self, original_transaction_id: str, product_id: str,
                               purchase_date: datetime, expire_date: Optional[datetime] = None,
                               environment: str = 'production', status: str = 'active',
                               event_type: str = 'purchase'):
        """创建付费凭证记录（支持空过期时间）"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            INSERT INTO purchase_records
            (original_transaction_id, product_id, purchase_date, expire_date, status, environment, device_count)
            VALUES (?, ?, ?, ?, ?, ?, 0)
        """, (
            original_transaction_id,
            product_id,
            _to_timestamp_ms(purchase_date),
            _to_timestamp_ms(expire_date),
            status,
            environment
        ))
        conn.commit()
        conn.close()

    def update_purchase_record(self, original_transaction_id: str, expire_date: Optional[datetime]):
        """更新付费凭证（续费）"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE purchase_records
            SET expire_date = ?, status = 'active', updated_at = CURRENT_TIMESTAMP
            WHERE original_transaction_id = ?
        """, (_to_timestamp_ms(expire_date), original_transaction_id))
        conn.commit()
        conn.close()

    def update_purchase_record_expiry(self, original_transaction_id: str, expire_date: Optional[datetime]):
        """更新付费凭证过期时间（续费场景的别名方法）"""
        self.update_purchase_record(original_transaction_id, expire_date)

    def update_purchase_record_status(
        self,
        original_transaction_id: str,
        status: str,
        expire_date: Optional[datetime] = None,
        environment: Optional[str] = None,
    ):
        """更新付费凭证状态（可选更新过期时间与环境）"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        updates = ["status = ?", "updated_at = CURRENT_TIMESTAMP"]
        params: List[Any] = [status]

        if expire_date is not None:
            updates.append("expire_date = ?")
            params.append(_to_timestamp_ms(expire_date))

        if environment is not None:
            updates.append("environment = ?")
            params.append(environment)

        params.append(original_transaction_id)
        cursor.execute(
            f"UPDATE purchase_records SET {', '.join(updates)} WHERE original_transaction_id = ?",
            params,
        )
        conn.commit()
        conn.close()

    def update_device_count(self, original_transaction_id: str, count: int):
        """更新设备数量"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE purchase_records
            SET device_count = ?
            WHERE original_transaction_id = ?
        """, (count, original_transaction_id))
        conn.commit()
        conn.close()

    # 设备绑定相关操作
    def get_device_bindings(self, original_transaction_id: str) -> List[Dict[str, Any]]:
        """获取所有绑定设备"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM device_bindings
            WHERE original_transaction_id = ?
            ORDER BY last_active_time ASC
        """, (original_transaction_id,))

        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]

    def get_device_binding(self, original_transaction_id: str, device_uuid: str) -> Optional[Dict[str, Any]]:
        """获取特定设备绑定"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, device_uuid))

        row = cursor.fetchone()
        conn.close()
        
        if not row:
            return None

        return dict(row)

    def create_device_binding(self, original_transaction_id: str, device_uuid: str,
                             device_name: Optional[str] = None):
        """创建设备绑定"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        now_ms = _now_ms()
        cursor.execute("""
            INSERT INTO device_bindings (original_transaction_id, device_uuid, device_name, bind_time, last_active_time)
            VALUES (?, ?, ?, ?, ?)
        """, (original_transaction_id, device_uuid, device_name, now_ms, now_ms))
        conn.commit()
        conn.close()

    def update_device_active_time(self, original_transaction_id: str, device_uuid: str):
        """更新设备最后活跃时间"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE device_bindings
            SET last_active_time = ?
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (_now_ms(), original_transaction_id, device_uuid))
        conn.commit()
        conn.close()

    def delete_device_binding(self, original_transaction_id: str, device_uuid: str):
        """删除设备绑定"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            DELETE FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, device_uuid))
        conn.commit()
        conn.close()

    # 交易日志相关操作
    def create_transaction_log(self, original_transaction_id: str, transaction_id: str,
                               event_type: str, device_uuid: str, jws_token: Optional[str] = None):
        """创建交易日志"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO transaction_logs
            (original_transaction_id, transaction_id, jws_token, event_type, device_uuid)
            VALUES (?, ?, ?, ?, ?)
        """, (original_transaction_id, transaction_id, jws_token, event_type, device_uuid))
        conn.commit()
        conn.close()

    def log_transaction(self, device_uuid: str, original_transaction_id: str,
                       event_type: str, jws_token: Optional[str] = None):
        """记录交易日志（简化版本，transaction_id 使用 original_transaction_id）"""
        self.create_transaction_log(
            original_transaction_id=original_transaction_id,
            transaction_id=original_transaction_id,  # 使用 original_transaction_id 作为 transaction_id
            event_type=event_type,
            device_uuid=device_uuid,
            jws_token=jws_token
        )

    def get_notification_log(self, notification_uuid: str) -> Optional[Dict[str, Any]]:
        """获取通知日志"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM notification_logs WHERE notification_uuid = ?
        """, (notification_uuid,))
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else None

    def create_notification_log(
        self,
        notification_uuid: str,
        notification_type: Optional[str],
        subtype: Optional[str],
        original_transaction_id: Optional[str],
        transaction_id: Optional[str],
        environment: Optional[str],
        signed_payload: str,
    ) -> bool:
        """写入通知日志（幂等），成功返回 True，重复返回 False"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        try:
            cursor.execute("""
                INSERT INTO notification_logs
                (notification_uuid, notification_type, subtype, original_transaction_id,
                 transaction_id, environment, signed_payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                notification_uuid,
                notification_type,
                subtype,
                original_transaction_id,
                transaction_id,
                environment,
                signed_payload
            ))
            conn.commit()
            return True
        except sqlite3.IntegrityError:
            return False
        finally:
            conn.close()
