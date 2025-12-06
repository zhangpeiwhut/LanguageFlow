from typing import Optional
from pydantic import BaseModel, Field


class RegisterRequest(BaseModel):
    device_uuid: str = Field(..., min_length=1, max_length=64)
    device_name: Optional[str] = Field(None, max_length=128)
    app_version: Optional[str] = Field(None, max_length=32)
