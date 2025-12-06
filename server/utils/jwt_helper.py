"""JWT Token 工具类"""
import jwt
from datetime import datetime, timedelta, timezone
from typing import Optional
import os

# 从环境变量读取，如果没有则使用默认值（生产环境必须设置环境变量）
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
TOKEN_EXPIRE_DAYS = 7


def create_access_token(device_uuid: str) -> str:
    """
    生成 JWT Access Token

    Args:
        device_uuid: 设备 UUID

    Returns:
        JWT Token 字符串
    """
    expire = datetime.now(timezone.utc) + timedelta(days=TOKEN_EXPIRE_DAYS)
    payload = {
        "device_uuid": device_uuid,
        "exp": expire,
        "iat": datetime.now(timezone.utc)
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> Optional[str]:
    """
    验证 JWT Token

    Args:
        token: JWT Token 字符串

    Returns:
        如果验证成功返回 device_uuid，否则返回 None
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        device_uuid = payload.get("device_uuid")
        return device_uuid
    except jwt.ExpiredSignatureError:
        print("[Warning] JWT token expired")
        return None
    except jwt.InvalidTokenError as e:
        print(f"[Warning] JWT token invalid: {e}")
        return None
