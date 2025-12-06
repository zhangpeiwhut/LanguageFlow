"""
Apple App Store 凭证验证工具
"""
import base64
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import json as pyjson


class AppleReceiptValidator:
    """Apple 收据验证器"""

    @staticmethod
    def decode_jws(jws_token: str) -> Dict[str, Any]:
        """
        解码 JWS Token
        
        根据苹果 StoreKit 2 文档，jwsRepresentation 返回的是 JWS (JSON Web Signature) 格式的字符串
        JWS 格式：header.payload.signature（各部分都是 Base64 URL 编码）
        
        这里我们解析 payload 部分来获取交易信息
        """
        # JWS token 格式：header.payload.signature
        parts = jws_token.split('.')
        if len(parts) != 3:
            # 如果不是标准 JWS 格式，尝试作为 Base64 编码的 JSON（向后兼容）
            try:
                decoded_bytes = base64.b64decode(jws_token)
                return pyjson.loads(decoded_bytes)
            except Exception:
                # 最后尝试直接 JSON 解析
                try:
                    return pyjson.loads(jws_token)
                except Exception as e:
                    raise ValueError(f"Invalid JWS token format: {str(e)}")
        
        # 解析 JWS token 的 payload 部分
        payload_part = parts[1]
        
        # Base64 URL 解码（需要处理 padding）
        # Base64 URL 编码不使用 '=' padding，需要手动添加
        padding = 4 - len(payload_part) % 4
        if padding != 4:
            payload_part += '=' * padding
        
        # 替换 URL-safe 字符
        payload_part = payload_part.replace('-', '+').replace('_', '/')
        
        try:
            decoded_bytes = base64.b64decode(payload_part)
            return pyjson.loads(decoded_bytes)
        except Exception as e:
            raise ValueError(f"Failed to decode JWS payload: {str(e)}")

    @staticmethod
    def parse_transaction(jws_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        解析交易信息

        返回格式:
        {
            'originalTransactionId': str,
            'transactionId': str,
            'productId': str,
            'purchaseDate': int (timestamp in milliseconds),
            'expiresDate': int (timestamp in milliseconds, 订阅才有),
            'environment': str ('Production' or 'Sandbox')
        }
        """
        return {
            'originalTransactionId': jws_data.get('originalTransactionId') or jws_data.get('original_transaction_id'),
            'transactionId': jws_data.get('transactionId') or jws_data.get('transaction_id'),
            'productId': jws_data.get('productId') or jws_data.get('product_id'),
            'purchaseDate': jws_data.get('purchaseDate') or jws_data.get('purchase_date'),
            'expiresDate': jws_data.get('expiresDate') or jws_data.get('expires_date'),  # 订阅才有
            'environment': jws_data.get('environment', 'Production')
        }

    @staticmethod
    def timestamp_to_datetime(timestamp_ms: Optional[int]) -> Optional[datetime]:
        """将 Apple 的毫秒时间戳转换为 datetime 对象（UTC，带时区）"""
        if timestamp_ms is None:
            return None
        return datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)

    @classmethod
    def verify_and_parse(cls, jws_token: str) -> Dict[str, Any]:
        """
        验证并解析 JWS Token

        注意：这个实现仅做简单解析，不验证签名
        生产环境必须：
        1. 验证 JWS 签名（使用 Apple 的公钥）
        2. 验证证书链
        3. 或者调用 Apple Server API 验证
        """
        decoded = cls.decode_jws(jws_token)
        transaction_info = cls.parse_transaction(decoded)

        # 验证必要字段
        if not transaction_info.get('originalTransactionId'):
            raise ValueError("Missing originalTransactionId")
        if not transaction_info.get('productId'):
            raise ValueError("Missing productId")

        return transaction_info


# 生产环境的签名验证（示例，需要完整实现）
class AppleJWSVerifier:
    """
    Apple JWS 签名验证器（生产环境必须使用）

    步骤：
    1. 从 JWS header 中提取证书链 (x5c)
    2. 验证证书链的有效性
    3. 使用公钥验证签名
    4. 验证 bundle ID 等关键字段

    参考文档:
    https://developer.apple.com/documentation/appstoreserverapi/jwstransaction
    """

    @staticmethod
    def verify_signature(jws_token: str) -> bool:
        """
        验证 JWS 签名（需要实现）

        TODO: 实现完整的签名验证逻辑
        - 解析 x5c 证书链
        - 验证证书有效性
        - 使用公钥验证签名
        """
        # 这里需要使用 cryptography 库实现完整的验证
        # 生产环境必须实现此方法
        raise NotImplementedError("Production signature verification not implemented")
