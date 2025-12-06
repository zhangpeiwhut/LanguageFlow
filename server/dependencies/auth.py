from fastapi import Header, HTTPException, status
from typing import Annotated
from ..utils.jwt_helper import verify_token

async def get_current_device_uuid(
    authorization: Annotated[str | None, Header()] = None
) -> str:
    """
    从 Authorization Header 中验证 JWT Token 并返回 device_uuid

    Args:
        authorization: Authorization Header，格式为 "Bearer <token>"

    Returns:
        device_uuid

    Raises:
        HTTPException: Token 无效或过期时抛出 401 错误
    """
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
