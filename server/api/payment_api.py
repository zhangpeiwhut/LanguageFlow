"""支付和设备管理相关 API"""
import sqlite3
import logging
from datetime import datetime, timezone
from fastapi import HTTPException
from typing import Dict, Any

from ..schemas.payment import VerifyPurchaseRequest
from ..models.auth_models import AuthDatabase
from ..utils.apple_validator import AppleReceiptValidator
from ..utils.device_manager import DeviceManager

logger = logging.getLogger('languageflow.payment')

def verify_purchase_handler(
    request: VerifyPurchaseRequest,
    device_uuid: str,
    auth_db: AuthDatabase,
    conn: sqlite3.Connection
) -> Dict[str, Any]:
    """
    处理购买凭证验证

    核心流程:
    1. 验证 JWS Token
    2. 提取交易信息（originalTransactionId、expiresDate 等）
    3. 创建/更新购买记录
    4. 绑定设备（最多2台，超出则踢掉最老的）
    5. 更新用户会员状态
    6. 返回会员信息和绑定设备列表
    """

    try:
        # 1. 验证并解析 JWS
        transaction_info = AppleReceiptValidator.verify_and_parse(request.jws_token)
        logger.info(
            "解析凭证成功 device_uuid=%s event=%s original_transaction_id=%s product_id=%s environment=%s",
            device_uuid,
            request.event_type,
            transaction_info.get('originalTransactionId'),
            transaction_info.get('productId'),
            transaction_info.get('environment'),
        )

        original_transaction_id = transaction_info['originalTransactionId']
        product_id = transaction_info['productId']
        expires_date_ms = transaction_info.get('expiresDate')

        # 2. 转换过期时间
        expires_date = None
        expires_ts_ms = None
        if expires_date_ms is not None:
            expires_ts_ms = int(expires_date_ms)
            expires_date = AppleReceiptValidator.timestamp_to_datetime(expires_ts_ms)

        purchase_date_ms = transaction_info.get('purchaseDate')
        if purchase_date_ms is None:
            purchase_date_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

        # 3. 创建或更新购买记录
        existing_record = auth_db.get_purchase_record(original_transaction_id)
        logger.info(
            "购买记录查询 device_uuid=%s original_transaction_id=%s found=%s expire_ms=%s purchase_ms=%s",
            device_uuid,
            original_transaction_id,
            bool(existing_record),
            expires_date_ms,
            purchase_date_ms,
        )

        if not existing_record:
            # 新购买记录
            auth_db.create_purchase_record(
                original_transaction_id=original_transaction_id,
                product_id=product_id,
                purchase_date=AppleReceiptValidator.timestamp_to_datetime(purchase_date_ms),
                expire_date=expires_date,
                event_type=request.event_type
            )
            logger.info(
                "创建购买记录 device_uuid=%s original_transaction_id=%s product_id=%s expire_ms=%s",
                device_uuid,
                original_transaction_id,
                product_id,
                expires_date_ms,
            )
        else:
            # 更新过期时间（续费场景）
            if expires_date is not None:
                auth_db.update_purchase_record_expiry(original_transaction_id, expires_date)
                logger.info(
                    "更新过期时间 device_uuid=%s original_transaction_id=%s new_expire_ms=%s",
                    device_uuid,
                    original_transaction_id,
                    expires_date_ms,
                )

        # 4. 绑定设备
        bind_result = DeviceManager.bind_device(
            conn=conn,
            original_transaction_id=original_transaction_id,
            device_uuid=device_uuid,
            device_name=request.device_name
        )

        kicked_device = bind_result.get('kicked_device')
        bound_devices = bind_result.get('bound_devices', [])
        logger.info(
            "绑定设备完成 device_uuid=%s original_transaction_id=%s bound=%s kicked=%s",
            device_uuid,
            original_transaction_id,
            bound_devices,
            kicked_device,
        )

        # 5. 更新用户会员状态
        is_vip = True
        if expires_date and expires_date < datetime.now(timezone.utc):
            is_vip = False

        auth_db.update_user_vip_status(
            device_uuid=device_uuid,
            is_vip=is_vip,
            original_transaction_id=original_transaction_id,
            vip_expire_time=expires_date
        )
        logger.info(
            "更新用户会员状态 device_uuid=%s is_vip=%s expire_ms=%s original_transaction_id=%s",
            device_uuid,
            is_vip,
            expires_ts_ms,
            original_transaction_id,
        )

        # 6. 记录交易日志
        transaction_id = transaction_info.get('transactionId') or original_transaction_id
        auth_db.create_transaction_log(
            original_transaction_id=original_transaction_id,
            transaction_id=transaction_id,
            event_type=request.event_type,
            device_uuid=device_uuid,
            jws_token=request.jws_token
        )
        logger.info(
            "交易日志已记录 device_uuid=%s original_transaction_id=%s transaction_id=%s event=%s",
            device_uuid,
            original_transaction_id,
            transaction_id,
            request.event_type,
        )

        # 7. 返回结果
        return {
            "code": 0,
            "message": "success",
            "data": {
                "is_vip": is_vip,
                "vip_expire_time": expires_ts_ms,
                "bound_devices": bound_devices,
                "kicked_device": kicked_device
            }
        }

    except ValueError as e:
        logger.warning(
            "JWS 解析失败 device_uuid=%s event=%s error=%s token_prefix=%s",
            device_uuid,
            request.event_type,
            str(e),
            request.jws_token[:12] if request.jws_token else None,
        )
        raise HTTPException(status_code=400, detail=f"Invalid JWS token: {str(e)}")
    except Exception as e:
        logger.exception(
            "内购校验异常 device_uuid=%s event=%s original_transaction_id=%s",
            device_uuid,
            request.event_type,
            transaction_info.get('originalTransactionId') if 'transaction_info' in locals() else None,
        )
        raise HTTPException(status_code=500, detail=f"Verification failed: {str(e)}")


def get_devices_handler(device_uuid: str, auth_db: AuthDatabase, conn: sqlite3.Connection) -> Dict[str, Any]:
    """
    获取用户绑定的设备列表
    """

    # 获取用户信息
    user = auth_db.get_user_by_uuid(device_uuid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 如果不是会员，返回空列表
    if not user.get('is_vip'):
        return {
            "code": 0,
            "message": "success",
            "data": {
                "devices": []
            }
        }

    # 获取绑定的设备列表
    original_transaction_id = user.get('original_transaction_id')
    if not original_transaction_id:
        return {
            "code": 0,
            "message": "success",
            "data": {
                "devices": []
            }
        }

    devices = DeviceManager.get_bound_devices(
        conn=conn,
        original_transaction_id=original_transaction_id,
        current_device_uuid=device_uuid
    )

    return {
        "code": 0,
        "message": "success",
        "data": {
            "devices": devices
        }
    }


def unbind_device_handler(
    device_uuid: str,
    target_device_uuid: str,
    auth_db: AuthDatabase,
    conn: sqlite3.Connection
) -> Dict[str, Any]:
    """
    解绑设备
    """

    # 获取用户信息
    user = auth_db.get_user_by_uuid(device_uuid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # 检查是否是会员
    if not user.get('is_vip'):
        raise HTTPException(status_code=403, detail="Only VIP users can manage devices")

    # 获取原始交易ID
    original_transaction_id = user.get('original_transaction_id')
    if not original_transaction_id:
        raise HTTPException(status_code=400, detail="No subscription found")

    # 执行解绑
    result = DeviceManager.unbind_device(
        conn=conn,
        current_device_uuid=device_uuid,
        target_device_uuid=target_device_uuid,
        original_transaction_id=original_transaction_id
    )

    if result['code'] != 0:
        raise HTTPException(status_code=result['code'], detail=result['message'])

    return {
        "code": 0,
        "message": "Device unbound successfully",
        "data": {}
    }
