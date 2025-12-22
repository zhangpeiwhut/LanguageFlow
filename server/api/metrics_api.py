"""后台指标查询 API"""
import os
from typing import Any, Dict, Optional
from fastapi import HTTPException

from ..models.auth_models import AuthDatabase

_ADMIN_TOKEN_ENV = "ADMIN_METRICS_TOKEN"


def _require_admin_token(token: Optional[str]) -> None:
    expected = os.getenv(_ADMIN_TOKEN_ENV)
    if not expected:
        raise HTTPException(status_code=503, detail="ADMIN_METRICS_TOKEN not configured")
    if not token or token != expected:
        raise HTTPException(status_code=403, detail="Invalid admin token")


def get_metrics_handler(
    auth_db: AuthDatabase,
    days: int,
    admin_token: Optional[str],
    db_path: Optional[str] = None,
) -> Dict[str, Any]:
    _require_admin_token(admin_token)
    snapshot = auth_db.get_metrics_snapshot(days=days)
    if db_path and os.path.exists(db_path):
        snapshot["db_size_bytes"] = os.path.getsize(db_path)
    return {
        "code": 0,
        "message": "success",
        "data": snapshot,
    }
