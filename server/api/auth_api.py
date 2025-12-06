"""认证相关 API"""
from datetime import datetime, timezone
from typing import Dict, Any
from ..schemas.auth import RegisterRequest
from ..models.auth_models import AuthDatabase
from ..utils.jwt_helper import create_access_token

def _now_ms() -> int:
    return int(datetime.now(timezone.utc).timestamp() * 1000)

def register_or_login_handler(request: RegisterRequest, auth_db: AuthDatabase) -> Dict[str, Any]:
    """注册或登录处理函数"""

    # 查询该 UUID 是否已存在
    user = auth_db.get_user_by_uuid(request.device_uuid)

    # 生成 JWT Token
    access_token = create_access_token(request.device_uuid)

    if user:
        # 已存在用户，检查设备状态
        device_status = "active"

        if user.get('original_transaction_id'):
            # 检查该设备是否还在绑定列表中
            binding = auth_db.get_device_binding(
                user['original_transaction_id'],
                request.device_uuid
            )

            if not binding:
                # 设备已被踢，降级为普通用户
                auth_db.update_user_vip_status(request.device_uuid, False, None, None)
                device_status = "kicked"
                user['is_vip'] = 0

        # 检查是否过期
        if user.get('is_vip') and user.get('vip_expire_time'):
            expire_ms = user['vip_expire_time']
            if isinstance(expire_ms, (int, float)) and expire_ms < _now_ms():
                auth_db.update_user_vip_status(request.device_uuid, False, user.get('original_transaction_id'), None)
                user['is_vip'] = 0

        return {
            "code": 0,
            "message": "success",
            "data": {
                "user_id": user['id'],
                "is_vip": bool(user.get('is_vip', 0)),
                "vip_expire_time": user.get('vip_expire_time'),
                "device_status": device_status,
                "access_token": access_token
            }
        }
    else:
        # 新用户，创建记录
        user_id = auth_db.create_user(request.device_uuid)

        return {
            "code": 0,
            "message": "success",
            "data": {
                "user_id": user_id,
                "is_vip": False,
                "vip_expire_time": None,
                "device_status": "active",
                "access_token": access_token
            }
        }


