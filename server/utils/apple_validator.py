"""
Apple App Store 凭证验证工具
"""
import base64
import logging
import os
import re
import ssl
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List, Tuple
import json as pyjson

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa, utils

logger = logging.getLogger('languageflow.apple')


def _base64url_decode(data: str) -> bytes:
    padding_len = (-len(data)) % 4
    if padding_len:
        data += "=" * padding_len
    return base64.urlsafe_b64decode(data)


def _load_pem_certificates(pem_data: bytes) -> List[x509.Certificate]:
    certs: List[x509.Certificate] = []
    for match in re.findall(
        b"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----",
        pem_data,
        re.DOTALL,
    ):
        cert_pem = b"-----BEGIN CERTIFICATE-----" + match + b"-----END CERTIFICATE-----"
        certs.append(x509.load_pem_x509_certificate(cert_pem))
    return certs


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
    def parse_renewal_info(jws_data: Dict[str, Any]) -> Dict[str, Any]:
        """解析订阅续费信息（通知用）"""
        return {
            'originalTransactionId': jws_data.get('originalTransactionId') or jws_data.get('original_transaction_id'),
            'autoRenewStatus': jws_data.get('autoRenewStatus') or jws_data.get('auto_renew_status'),
            'gracePeriodExpiresDate': jws_data.get('gracePeriodExpiresDate')
            or jws_data.get('grace_period_expires_date'),
            'isInBillingRetryPeriod': jws_data.get('isInBillingRetryPeriod')
            or jws_data.get('is_in_billing_retry_period'),
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


class AppleJWSVerifier:
    """
    Apple JWS 签名验证器

    参考文档:
    https://developer.apple.com/documentation/appstoreserverapi/jwstransaction
    """

    ROOT_CA_ENV_PEM = "APP_STORE_ROOT_CA_PEM"
    ROOT_CA_ENV_PATH = "APP_STORE_ROOT_CA_PATH"
    APPLE_ROOT_SUBJECT_KEYWORDS = ("Apple Root CA", "Apple Root CA - G2", "Apple Root CA - G3")

    @classmethod
    def verify_and_decode(cls, jws_token: str, require_trust: bool = True) -> Dict[str, Any]:
        header, payload, signing_input, signature = cls._decode_jws(jws_token)
        chain = cls._load_certificate_chain(header)
        if not chain:
            raise ValueError("Missing x5c certificate chain in JWS header")
        cls._verify_certificate_chain(chain, require_trust=require_trust)
        cls._verify_jws_signature(chain[0].public_key(), header.get("alg"), signing_input, signature)
        return payload

    @classmethod
    def _decode_jws(cls, jws_token: str) -> Tuple[Dict[str, Any], Dict[str, Any], bytes, bytes]:
        parts = jws_token.split(".")
        if len(parts) != 3:
            raise ValueError("Invalid JWS format")
        header_b64, payload_b64, signature_b64 = parts
        try:
            header = pyjson.loads(_base64url_decode(header_b64))
            payload = pyjson.loads(_base64url_decode(payload_b64))
        except Exception as exc:
            raise ValueError(f"Invalid JWS JSON payload: {exc}") from exc
        signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
        signature = _base64url_decode(signature_b64)
        return header, payload, signing_input, signature

    @classmethod
    def _load_certificate_chain(cls, header: Dict[str, Any]) -> List[x509.Certificate]:
        x5c_chain = header.get("x5c")
        if not x5c_chain:
            return []
        certs: List[x509.Certificate] = []
        for cert_b64 in x5c_chain:
            cert_der = base64.b64decode(cert_b64)
            certs.append(x509.load_der_x509_certificate(cert_der))
        return certs

    @classmethod
    def _verify_certificate_chain(cls, chain: List[x509.Certificate], require_trust: bool) -> None:
        now = datetime.now(timezone.utc)
        for cert in chain:
            not_before = getattr(cert, "not_valid_before_utc", None)
            if not_before is None:
                not_before = cert.not_valid_before.replace(tzinfo=timezone.utc)
            elif not_before.tzinfo is None:
                not_before = not_before.replace(tzinfo=timezone.utc)

            not_after = getattr(cert, "not_valid_after_utc", None)
            if not_after is None:
                not_after = cert.not_valid_after.replace(tzinfo=timezone.utc)
            elif not_after.tzinfo is None:
                not_after = not_after.replace(tzinfo=timezone.utc)

            if now < not_before or now > not_after:
                raise ValueError("Certificate is not valid at current time")

        for index in range(len(chain) - 1):
            cls._verify_cert_signed_by(chain[index], chain[index + 1])

        root_certs = cls._load_root_certs()
        if not root_certs:
            if require_trust:
                raise ValueError("Apple root certificate not configured")
            logger.warning("Apple root certificate not configured; skipping root trust check")
            return

        if not cls._is_chain_trusted(chain[-1], root_certs):
            raise ValueError("Certificate chain is not trusted")

    @classmethod
    def _load_root_certs(cls) -> List[x509.Certificate]:
        roots: List[x509.Certificate] = []
        pem_env = os.getenv(cls.ROOT_CA_ENV_PEM)
        if pem_env:
            roots.extend(_load_pem_certificates(pem_env.encode("utf-8")))

        path_env = os.getenv(cls.ROOT_CA_ENV_PATH)
        if path_env and os.path.exists(path_env):
            with open(path_env, "rb") as handle:
                roots.extend(_load_pem_certificates(handle.read()))

        if not roots:
            cafile = ssl.get_default_verify_paths().cafile
            if cafile and os.path.exists(cafile):
                try:
                    with open(cafile, "rb") as handle:
                        roots.extend(_load_pem_certificates(handle.read()))
                except Exception:
                    roots = []

        if not roots:
            return []

        filtered = [cert for cert in roots if cls._is_apple_root(cert)]
        return filtered

    @classmethod
    def _is_chain_trusted(cls, candidate: x509.Certificate, roots: List[x509.Certificate]) -> bool:
        candidate_fp = candidate.fingerprint(hashes.SHA256())
        for root in roots:
            if candidate_fp == root.fingerprint(hashes.SHA256()):
                return True
            try:
                cls._verify_cert_signed_by(candidate, root)
                return True
            except InvalidSignature:
                continue
            except Exception:
                continue
        return False

    @classmethod
    def _is_apple_root(cls, cert: x509.Certificate) -> bool:
        subject = cert.subject.rfc4514_string()
        return any(keyword in subject for keyword in cls.APPLE_ROOT_SUBJECT_KEYWORDS)

    @staticmethod
    def _verify_cert_signed_by(cert: x509.Certificate, issuer_cert: x509.Certificate) -> None:
        if cert.issuer != issuer_cert.subject:
            raise ValueError("Certificate issuer mismatch")
        issuer_key = issuer_cert.public_key()
        if isinstance(issuer_key, rsa.RSAPublicKey):
            issuer_key.verify(
                cert.signature,
                cert.tbs_certificate_bytes,
                padding.PKCS1v15(),
                cert.signature_hash_algorithm,
            )
            return
        if isinstance(issuer_key, ec.EllipticCurvePublicKey):
            issuer_key.verify(
                cert.signature,
                cert.tbs_certificate_bytes,
                ec.ECDSA(cert.signature_hash_algorithm),
            )
            return
        raise ValueError("Unsupported certificate key type")

    @classmethod
    def _verify_jws_signature(
        cls,
        public_key: object,
        alg: Optional[str],
        signing_input: bytes,
        signature: bytes,
    ) -> None:
        if not alg:
            raise ValueError("Missing JWS alg header")

        hash_alg = cls._hash_for_alg(alg)
        if alg.startswith("ES"):
            if not isinstance(public_key, ec.EllipticCurvePublicKey):
                raise ValueError("Unexpected public key type for ES algorithm")
            if len(signature) % 2 != 0:
                raise ValueError("Invalid ECDSA signature length")
            half_len = len(signature) // 2
            r = int.from_bytes(signature[:half_len], "big")
            s = int.from_bytes(signature[half_len:], "big")
            der_signature = utils.encode_dss_signature(r, s)
            public_key.verify(der_signature, signing_input, ec.ECDSA(hash_alg))
            return

        if alg.startswith("RS"):
            if not isinstance(public_key, rsa.RSAPublicKey):
                raise ValueError("Unexpected public key type for RS algorithm")
            public_key.verify(signature, signing_input, padding.PKCS1v15(), hash_alg)
            return

        raise ValueError(f"Unsupported JWS alg: {alg}")

    @staticmethod
    def _hash_for_alg(alg: str) -> hashes.HashAlgorithm:
        mapping = {
            "ES256": hashes.SHA256(),
            "ES384": hashes.SHA384(),
            "ES512": hashes.SHA512(),
            "RS256": hashes.SHA256(),
            "RS384": hashes.SHA384(),
            "RS512": hashes.SHA512(),
        }
        if alg not in mapping:
            raise ValueError(f"Unsupported JWS alg: {alg}")
        return mapping[alg]
