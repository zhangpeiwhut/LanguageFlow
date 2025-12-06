from fastapi import Header, HTTPException, status, Request
from typing import Annotated, Optional
from ..utils.jwt_helper import verify_token

# 不需要鉴权的接口白名单（路径前缀）
AUTH_WHITELIST = [
    "/podcast/info/channels",  # 获取频道列表
    "/podcast/auth/register",   # 注册/登录接口
]

def is_path_whitelisted(path: str) -> bool:
    """检查路径是否在白名单中"""
    return any(path.startswith(whitelist_path) for whitelist_path in AUTH_WHITELIST)

async def get_current_device_uuid(
    request: Request,
    authorization: Annotated[str | None, Header()] = None
) -> str:
    """
    从 Authorization Header 中验证 JWT Token 并返回 device_uuid

    Args:
        request: FastAPI Request 对象（用于获取路径）
        authorization: Authorization Header，格式为 "Bearer <token>"

    Returns:
        device_uuid

    Raises:
        HTTPException: Token 无效或过期时抛出 401 错误
    """
    # 如果路径在白名单中，允许不提供 token
    if is_path_whitelisted(request.url.path):
        if not authorization:
            return ""  # 返回空字符串表示未认证但允许访问
        
        # 如果提供了 token，仍然验证它
        parts = authorization.split()
        if len(parts) == 2 and parts[0].lower() == "bearer":
            token = parts[1]
            device_uuid = verify_token(token)
            if device_uuid:
                return device_uuid
        return ""  # token 无效但路径在白名单中，允许访问
    
    # 不在白名单中，必须提供有效的 token
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header format. Expected 'Bearer <token>'",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = parts[1]
    device_uuid = verify_token(token)

    if not device_uuid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    # 先不添加数据库检查
    return device_uuid

async def get_optional_device_uuid(
    authorization: Annotated[str | None, Header()] = None
) -> Optional[str]:
    """
    可选的设备 UUID 获取函数，用于不需要强制鉴权的接口
    
    如果提供了有效的 token，返回 device_uuid；否则返回 None
    """
    if not authorization:
        return None
    
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    
    token = parts[1]
    device_uuid = verify_token(token)
    return device_uuid if device_uuid else None
