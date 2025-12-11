"""
设备绑定管理工具（使用 SQLite）
"""
import sqlite3
import logging
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

logger = logging.getLogger('languageflow.payment')


class DeviceManager:
    """设备绑定管理器"""

    MAX_DEVICES = 2  # 最多允许绑定的设备数

    @classmethod
    def bind_device(
        cls,
        conn: sqlite3.Connection,
        original_transaction_id: str,
        device_uuid: str,
        device_name: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        绑定设备到付费凭证

        核心逻辑：
        1. 如果是已绑定设备 → 更新最后活跃时间
        2. 如果是新设备且未满2台 → 直接绑定
        3. 如果是新设备且已有2台 → 踢掉最老的设备

        返回:
        {
            'code': 0,
            'bound_devices': List[str],
            'kicked_device': Optional[str]
        }
        """
        cursor = conn.cursor()

        # 查询当前该凭证绑定的所有设备（按活跃时间升序）
        cursor.execute("""
            SELECT device_uuid, device_name, bind_time, last_active_time
            FROM device_bindings
            WHERE original_transaction_id = ?
            ORDER BY last_active_time ASC
        """, (original_transaction_id,))
        bindings = cursor.fetchall()
        logger.info(
            "绑定设备请求 original_transaction_id=%s device_uuid=%s 当前绑定数=%s",
            original_transaction_id,
            device_uuid,
            len(bindings)
        )

        # 情况1: 该设备已绑定，更新活跃时间
        for binding in bindings:
            if binding[0] == device_uuid:
                now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
                cursor.execute("""
                    UPDATE device_bindings
                    SET last_active_time = ?
                    WHERE original_transaction_id = ? AND device_uuid = ?
                """, (now_ms, original_transaction_id, device_uuid))
                conn.commit()
                logger.info(
                    "设备已绑定，刷新活跃时间 original_transaction_id=%s device_uuid=%s",
                    original_transaction_id,
                    device_uuid
                )

                return {
                    'code': 0,
                    'bound_devices': [b[0] for b in bindings],
                    'kicked_device': None
                }

        # 情况2: 新设备，槽位未满
        if len(bindings) < cls.MAX_DEVICES:
            now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
            cursor.execute("""
                INSERT INTO device_bindings (original_transaction_id, device_uuid, device_name, bind_time, last_active_time)
                VALUES (?, ?, ?, ?, ?)
            """, (original_transaction_id, device_uuid, device_name, now_ms, now_ms))

            # 更新凭证表的设备数量
            cursor.execute("""
                UPDATE purchase_records
                SET device_count = ?
                WHERE original_transaction_id = ?
            """, (len(bindings) + 1, original_transaction_id))

            conn.commit()
            logger.info(
                "新设备绑定成功 original_transaction_id=%s device_uuid=%s device_count=%s",
                original_transaction_id,
                device_uuid,
                len(bindings) + 1
            )

            return {
                'code': 0,
                'bound_devices': [b[0] for b in bindings] + [device_uuid],
                'kicked_device': None
            }

        # 情况3: 已有2台设备，踢掉最老的
        oldest_binding = bindings[0]  # 已按 last_active_time 升序排序
        kicked_device_uuid = oldest_binding[0]

        # 删除最老设备的绑定
        cursor.execute("""
            DELETE FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, kicked_device_uuid))

        # 将被踢设备的用户状态降级
        cursor.execute("""
            UPDATE users
            SET is_vip = 0, original_transaction_id = NULL
            WHERE device_uuid = ?
        """, (kicked_device_uuid,))

        # 绑定新设备
        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        cursor.execute("""
            INSERT INTO device_bindings (original_transaction_id, device_uuid, device_name, bind_time, last_active_time)
            VALUES (?, ?, ?, ?, ?)
        """, (original_transaction_id, device_uuid, device_name, now_ms, now_ms))

        conn.commit()
        logger.info(
            "踢出旧设备并绑定新设备 original_transaction_id=%s kicked_device=%s new_device=%s",
            original_transaction_id,
            kicked_device_uuid,
            device_uuid
        )

        return {
            'code': 0,
            'kicked_device': kicked_device_uuid,
            'bound_devices': [bindings[1][0], device_uuid]
        }

    @classmethod
    def check_device_status(
        cls,
        conn: sqlite3.Connection,
        device_uuid: str,
        original_transaction_id: str
    ) -> str:
        """
        检查设备状态

        返回: 'active' 或 'kicked'
        """
        cursor = conn.cursor()
        cursor.execute("""
            SELECT 1 FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, device_uuid))

        binding = cursor.fetchone()
        return 'active' if binding else 'kicked'

    @classmethod
    def get_bound_devices(
        cls,
        conn: sqlite3.Connection,
        original_transaction_id: str,
        current_device_uuid: str
    ) -> List[Dict[str, Any]]:
        """获取已绑定的设备列表"""
        cursor = conn.cursor()
        cursor.execute("""
            SELECT device_uuid, device_name, bind_time, last_active_time
            FROM device_bindings
            WHERE original_transaction_id = ?
        """, (original_transaction_id,))

        bindings = cursor.fetchall()

        return [
            {
                'device_uuid': b[0],
                'device_name': b[1],
                'bind_time': b[2],
                'last_active_time': b[3],
                'is_current': b[0] == current_device_uuid
            }
            for b in bindings
        ]

    @classmethod
    def unbind_device(
        cls,
        conn: sqlite3.Connection,
        current_device_uuid: str,
        target_device_uuid: str,
        original_transaction_id: str
    ) -> Dict[str, Any]:
        """
        解绑设备

        注意：不允许解绑自己
        """
        if target_device_uuid == current_device_uuid:
            return {'code': 400, 'message': 'Cannot unbind current device'}

        cursor = conn.cursor()

        logger.info(
            "请求解绑设备 original_transaction_id=%s current_device=%s target_device=%s",
            original_transaction_id,
            current_device_uuid,
            target_device_uuid
        )

        # 查找目标设备绑定
        cursor.execute("""
            SELECT 1 FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, target_device_uuid))

        binding = cursor.fetchone()
        if not binding:
            return {'code': 404, 'message': 'Device not found'}

        # 删除绑定
        cursor.execute("""
            DELETE FROM device_bindings
            WHERE original_transaction_id = ? AND device_uuid = ?
        """, (original_transaction_id, target_device_uuid))

        # 更新凭证表的设备数
        cursor.execute("""
            UPDATE purchase_records
            SET device_count = CASE WHEN device_count > 0 THEN device_count - 1 ELSE 0 END
            WHERE original_transaction_id = ?
        """, (original_transaction_id,))

        # 降级被解绑设备的用户状态
        cursor.execute("""
            UPDATE users
            SET is_vip = 0, original_transaction_id = NULL
            WHERE device_uuid = ?
        """, (target_device_uuid,))

        conn.commit()
        logger.info(
            "解绑成功 original_transaction_id=%s target_device=%s",
            original_transaction_id,
            target_device_uuid
        )

        return {'code': 0, 'message': 'Device unbound successfully'}
