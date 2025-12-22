"""支付和设备管理相关 API"""
import os
import sqlite3
import logging
from datetime import datetime, timezone
from fastapi import HTTPException
from typing import Dict, Any, Optional

from ..schemas.payment import VerifyPurchaseRequest, AppStoreNotificationRequest
from ..models.auth_models import AuthDatabase
from ..utils.apple_validator import AppleReceiptValidator, AppleJWSVerifier
from ..utils.device_manager import DeviceManager

logger = logging.getLogger('languageflow.payment')

APP_STORE_ACTIVE_TYPES = {
    "SUBSCRIBED",
    "DID_RENEW",
    "DID_RECOVER",
    "INTERACTIVE_RENEWAL",
    "RENEWAL_EXTENSION",
    "RENEWAL_EXTENDED",
    "REFUND_REVERSED",
}
APP_STORE_TRANSACTION_TYPES = {
    "SUBSCRIBED",
    "DID_RENEW",
    "DID_RECOVER",
    "INTERACTIVE_RENEWAL",
}
APP_STORE_RETRY_TYPES = {"DID_FAIL_TO_RENEW"}
APP_STORE_EXPIRED_TYPES = {"EXPIRED", "GRACE_PERIOD_EXPIRED"}
APP_STORE_REVOKE_TYPES = {"REFUND", "REVOKE"}
APP_STORE_IGNORE_TYPES = {
    "DID_CHANGE_RENEWAL_STATUS",
    "DID_CHANGE_RENEWAL_PREF",
    "PRICE_INCREASE",
    "OFFER_REDEEMED",
    "CONSUMPTION_REQUEST",
}


def _require_trust() -> bool:
    return os.getenv("SERVER_ENV", "development").lower() == "production"


def _max_ms(*values: Optional[int]) -> Optional[int]:
    filtered = [value for value in values if value is not None]
    return max(filtered) if filtered else None


def _coerce_ms(value: Optional[Any]) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError("Invalid timestamp")
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("Invalid timestamp") from exc


def _load_app_store_config() -> Dict[str, Optional[str]]:
    return {
        "bundle_id": os.getenv("APP_STORE_BUNDLE_ID", "zhangpei.com.LanguageFlow"),
        "app_apple_id": os.getenv("APP_STORE_APPLE_ID", "6755928466"),
        "environment": os.getenv("APP_STORE_ENVIRONMENT"),
    }


def _validate_notification_data(data: Dict[str, Any], config: Dict[str, Optional[str]]) -> None:
    expected_bundle_id = config.get("bundle_id")
    expected_app_apple_id = config.get("app_apple_id")
    expected_env = config.get("environment")

    bundle_id = data.get("bundleId")
    app_apple_id = data.get("appAppleId")
    environment = data.get("environment")

    if expected_bundle_id and bundle_id != expected_bundle_id:
        raise ValueError("bundleId mismatch")
    if expected_app_apple_id and str(app_apple_id) != str(expected_app_apple_id):
        raise ValueError("appAppleId mismatch")
    if expected_env and str(environment).lower() != str(expected_env).lower():
        raise ValueError("environment mismatch")


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
        if _require_trust():
            payload = AppleJWSVerifier.verify_and_decode(request.jws_token, require_trust=True)
            transaction_info = AppleReceiptValidator.parse_transaction(payload)
            if not transaction_info.get('originalTransactionId'):
                raise ValueError("Missing originalTransactionId")
            if not transaction_info.get('productId'):
                raise ValueError("Missing productId")
        else:
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
        incoming_expires_ms = _coerce_ms(transaction_info.get('expiresDate'))

        purchase_date_ms = _coerce_ms(transaction_info.get('purchaseDate'))
        if purchase_date_ms is None:
            purchase_date_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        purchase_date_dt = AppleReceiptValidator.timestamp_to_datetime(purchase_date_ms)
        incoming_expires_dt = AppleReceiptValidator.timestamp_to_datetime(incoming_expires_ms)

        # 3. 创建或更新购买记录
        existing_record = auth_db.get_purchase_record(original_transaction_id)
        existing_expire_ms = None
        if existing_record:
            existing_expire_ms = _coerce_ms(existing_record.get("expire_date"))

        inserted = False
        if not existing_record:
            inserted = auth_db.create_purchase_record(
                original_transaction_id=original_transaction_id,
                product_id=product_id,
                purchase_date=purchase_date_dt,
                expire_date=incoming_expires_dt,
                event_type=request.event_type
            )
            if inserted:
                logger.info(
                    "创建购买记录 device_uuid=%s original_transaction_id=%s product_id=%s expire_ms=%s",
                    device_uuid,
                    original_transaction_id,
                    product_id,
                    incoming_expires_ms,
                )
            else:
                existing_record = auth_db.get_purchase_record(original_transaction_id)
                if existing_record:
                    existing_expire_ms = _coerce_ms(existing_record.get("expire_date"))

        record_exists = bool(existing_record) or inserted
        effective_expire_ms = _max_ms(incoming_expires_ms, existing_expire_ms)

        if (
            existing_expire_ms is not None
            and incoming_expires_ms is not None
            and existing_expire_ms > incoming_expires_ms
        ):
            logger.info(
                "收到较旧凭证，使用已有过期时间 device_uuid=%s original_transaction_id=%s incoming_expire_ms=%s existing_expire_ms=%s",
                device_uuid,
                original_transaction_id,
                incoming_expires_ms,
                existing_expire_ms,
            )

        expires_date = None
        expires_ts_ms = None
        if effective_expire_ms is not None:
            expires_ts_ms = int(effective_expire_ms)
            expires_date = AppleReceiptValidator.timestamp_to_datetime(expires_ts_ms)

        logger.info(
            "购买记录查询 device_uuid=%s original_transaction_id=%s found=%s expire_ms=%s purchase_ms=%s",
            device_uuid,
            original_transaction_id,
            record_exists,
            effective_expire_ms,
            purchase_date_ms,
        )

        if existing_record:
            # 更新过期时间（续费场景）
            if (
                incoming_expires_ms is not None
                and (existing_expire_ms is None or incoming_expires_ms > existing_expire_ms)
            ):
                auth_db.update_purchase_record_expiry(original_transaction_id, incoming_expires_dt)
                logger.info(
                    "更新过期时间 device_uuid=%s original_transaction_id=%s new_expire_ms=%s",
                    device_uuid,
                    original_transaction_id,
                    incoming_expires_ms,
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
        if transaction_id:
            auth_db.record_purchase_event(
                transaction_id=transaction_id,
                original_transaction_id=original_transaction_id,
                event_type=request.event_type,
                device_uuid=device_uuid,
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


def app_store_notification_handler(
    request: AppStoreNotificationRequest,
    auth_db: AuthDatabase,
) -> Dict[str, Any]:
    """
    处理 App Store Server Notifications v2
    """
    try:
        signed_payload = request.signedPayload
        require_trust = _require_trust()
        notification = AppleJWSVerifier.verify_and_decode(signed_payload, require_trust=require_trust)

        notification_type = notification.get("notificationType")
        notification_uuid = notification.get("notificationUUID")
        subtype = notification.get("subtype")

        if not notification_uuid:
            raise ValueError("Missing notificationUUID")
        if not notification_type:
            raise ValueError("Missing notificationType")

        if notification_type == "TEST":
            inserted = auth_db.create_notification_log(
                notification_uuid=notification_uuid,
                notification_type=notification_type,
                subtype=subtype,
                original_transaction_id=None,
                transaction_id=None,
                environment=None,
                signed_payload=signed_payload,
            )
            return {
                "code": 0,
                "message": "success",
                "data": {"test": True, "duplicate": not inserted},
            }

        data = notification.get("data") or {}
        if not data:
            raise ValueError("Missing notification data")

        config = _load_app_store_config()
        _validate_notification_data(data, config)

        signed_transaction_info = data.get("signedTransactionInfo")
        signed_renewal_info = data.get("signedRenewalInfo")

        transaction_info: Dict[str, Any] = {}
        renewal_info: Dict[str, Any] = {}

        if signed_transaction_info:
            transaction_payload = AppleJWSVerifier.verify_and_decode(
                signed_transaction_info,
                require_trust=require_trust,
            )
            transaction_info = AppleReceiptValidator.parse_transaction(transaction_payload)

        if signed_renewal_info:
            renewal_payload = AppleJWSVerifier.verify_and_decode(
                signed_renewal_info,
                require_trust=require_trust,
            )
            renewal_info = AppleReceiptValidator.parse_renewal_info(renewal_payload)

        original_transaction_id = (
            transaction_info.get("originalTransactionId")
            or renewal_info.get("originalTransactionId")
        )

        if notification_type in APP_STORE_IGNORE_TYPES:
            inserted = auth_db.create_notification_log(
                notification_uuid=notification_uuid,
                notification_type=notification_type,
                subtype=subtype,
                original_transaction_id=original_transaction_id,
                transaction_id=transaction_info.get("transactionId"),
                environment=data.get("environment"),
                signed_payload=signed_payload,
            )
            return {
                "code": 0,
                "message": "success",
                "data": {"ignored": True, "duplicate": not inserted},
            }

        if notification_type not in (
            APP_STORE_ACTIVE_TYPES
            | APP_STORE_RETRY_TYPES
            | APP_STORE_EXPIRED_TYPES
            | APP_STORE_REVOKE_TYPES
        ):
            inserted = auth_db.create_notification_log(
                notification_uuid=notification_uuid,
                notification_type=notification_type,
                subtype=subtype,
                original_transaction_id=original_transaction_id,
                transaction_id=transaction_info.get("transactionId"),
                environment=data.get("environment"),
                signed_payload=signed_payload,
            )
            return {
                "code": 0,
                "message": "success",
                "data": {"ignored": True, "duplicate": not inserted},
            }

        if not original_transaction_id:
            raise ValueError("Missing originalTransactionId")

        product_id = transaction_info.get("productId")
        purchase_date_ms = _coerce_ms(transaction_info.get("purchaseDate"))
        if purchase_date_ms is None:
            purchase_date_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

        expires_date_ms = _coerce_ms(transaction_info.get("expiresDate"))
        grace_expires_ms = _coerce_ms(renewal_info.get("gracePeriodExpiresDate"))
        effective_expire_ms = _max_ms(expires_date_ms, grace_expires_ms)

        environment = data.get("environment") or transaction_info.get("environment")

        if notification_type in APP_STORE_ACTIVE_TYPES:
            status = "active"
            is_vip = True
        elif notification_type in APP_STORE_RETRY_TYPES:
            status = "in_retry"
            is_vip = True
        elif notification_type in APP_STORE_EXPIRED_TYPES:
            status = "expired"
            is_vip = False
        else:
            status = "revoked"
            is_vip = False

        expire_dt = AppleReceiptValidator.timestamp_to_datetime(effective_expire_ms)
        purchase_dt = AppleReceiptValidator.timestamp_to_datetime(purchase_date_ms)

        existing_record = auth_db.get_purchase_record(original_transaction_id)
        existing_expire_ms = None
        if existing_record:
            existing_expire_ms = _coerce_ms(existing_record.get("expire_date"))

        record_inserted = False
        if not existing_record:
            if not product_id:
                raise ValueError("Missing productId")
            record_inserted = auth_db.create_purchase_record(
                original_transaction_id=original_transaction_id,
                product_id=product_id,
                purchase_date=purchase_dt,
                expire_date=expire_dt,
                environment=environment or "production",
                status=status,
            )
            if not record_inserted:
                existing_record = auth_db.get_purchase_record(original_transaction_id)
                if existing_record:
                    existing_expire_ms = _coerce_ms(existing_record.get("expire_date"))

        if (
            existing_expire_ms is not None
            and effective_expire_ms is not None
            and effective_expire_ms < existing_expire_ms
            and notification_type in (APP_STORE_EXPIRED_TYPES | APP_STORE_RETRY_TYPES)
        ):
            inserted = auth_db.create_notification_log(
                notification_uuid=notification_uuid,
                notification_type=notification_type,
                subtype=subtype,
                original_transaction_id=original_transaction_id,
                transaction_id=transaction_info.get("transactionId"),
                environment=environment,
                signed_payload=signed_payload,
            )
            return {
                "code": 0,
                "message": "success",
                "data": {"stale": True, "duplicate": not inserted},
            }

        if existing_record:
            if effective_expire_ms is not None:
                if existing_expire_ms is None or effective_expire_ms > existing_expire_ms:
                    auth_db.update_purchase_record_expiry(original_transaction_id, expire_dt)
            status_expire_dt = None
            if notification_type in (APP_STORE_EXPIRED_TYPES | APP_STORE_REVOKE_TYPES):
                status_expire_dt = expire_dt
            auth_db.update_purchase_record_status(
                original_transaction_id=original_transaction_id,
                status=status,
                expire_date=status_expire_dt,
                environment=environment,
            )

        auth_db.update_users_vip_status_by_original_transaction_id(
            original_transaction_id=original_transaction_id,
            is_vip=is_vip,
            vip_expire_time=expire_dt,
        )

        transaction_id = transaction_info.get("transactionId")
        if transaction_id and notification_type in APP_STORE_TRANSACTION_TYPES:
            auth_db.record_purchase_event(
                transaction_id=transaction_id,
                original_transaction_id=original_transaction_id,
                event_type=notification_type,
                device_uuid=None,
            )

        inserted = auth_db.create_notification_log(
            notification_uuid=notification_uuid,
            notification_type=notification_type,
            subtype=subtype,
            original_transaction_id=original_transaction_id,
            transaction_id=transaction_info.get("transactionId"),
            environment=environment,
            signed_payload=signed_payload,
        )

        return {
            "code": 0,
            "message": "success",
            "data": {
                "notification_type": notification_type,
                "is_vip": is_vip,
                "vip_expire_time": effective_expire_ms,
                "duplicate": not inserted,
            },
        }
    except ValueError as exc:
        logger.warning("App Store 通知校验失败 error=%s", exc)
        raise HTTPException(status_code=400, detail=str(exc))
