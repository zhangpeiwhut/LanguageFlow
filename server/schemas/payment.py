from typing import Optional, List
from pydantic import BaseModel, Field


class VerifyPurchaseRequest(BaseModel):
    jws_token: str = Field(..., min_length=1)
    device_name: Optional[str] = Field(None, max_length=128)
    event_type: str = Field(..., pattern="^(purchase|restore|renew)$")


class AppStoreNotificationRequest(BaseModel):
    signedPayload: str = Field(..., min_length=1)


class VerifyPurchaseResponse(BaseModel):
    is_vip: bool
    vip_expire_time: Optional[int] = None  # 毫秒级时间戳
    bound_devices: List[str] = []
    kicked_device: Optional[str] = None


class DeviceInfo(BaseModel):
    device_uuid: str
    device_name: Optional[str] = None
    bind_time: int  # 毫秒级时间戳
    last_active_time: int  # 毫秒级时间戳
    is_current: bool


class DevicesListResponse(BaseModel):
    devices: List[DeviceInfo] = []
