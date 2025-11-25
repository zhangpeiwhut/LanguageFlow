"""腾讯云COS服务（用于server端生成CDN URL鉴权链接）"""
import os
import time
import hashlib

class COSService:
    """腾讯云COS服务类（server端）- 使用CDN URL鉴权"""
    
    def __init__(self):
        """
        初始化COS服务
        需要设置以下环境变量：
        - COS_CDN_DOMAIN: CDN域名（如 https://cdn.elegantfish.online）
        - COS_CDN_AUTH_KEY: CDN防盗链密钥（在CDN控制台配置的鉴权密钥）
        """
        self.cdn_domain = os.getenv('COS_CDN_DOMAIN')
        self.cdn_auth_key = os.getenv('COS_CDN_AUTH_KEY')
        
        if not self.cdn_domain or not self.cdn_auth_key:
            # 如果缺少配置，不抛出异常，而是允许服务启动（但生成URL时会失败）
            print('[cos-service] 警告：缺少CDN配置，URL生成功能将不可用')
            print('[cos-service] 需要设置: COS_CDN_DOMAIN 和 COS_CDN_AUTH_KEY')
            self.cdn_domain = None
            self.cdn_auth_key = None
            return
        
        # 确保CDN域名不以/结尾
        self.cdn_domain = self.cdn_domain.rstrip('/')
    
    def get_cdn_url(self, key: str, expires: int = 180) -> str:
        """
        生成CDN URL鉴权链接（Type A算法）
        
        CDN URL鉴权算法（Type A）：
        - t = 过期时间戳（Unix时间戳，秒）
        - sign = md5(防盗链key + path + t).lower()
        - URL格式：https://cdn-domain.com/path?t=timestamp&sign=sign
        
        Args:
            key: COS对象Key（如 audio/channel/2023-11-15/podcast_id.mp3）
            expires: URL有效期（秒），默认180秒（3分钟）
            
        Returns:
            CDN鉴权URL
        """
        if not self.cdn_domain or not self.cdn_auth_key:
            raise Exception('CDN服务未配置，无法生成URL。请设置 COS_CDN_DOMAIN 和 COS_CDN_AUTH_KEY')
        
        # 计算过期时间戳
        expire_timestamp = int(time.time()) + expires
        
        # 确保path以/开头
        path = '/' + key.lstrip('/')
        
        # 计算签名：md5(防盗链key + path + t)
        sign_string = self.cdn_auth_key + path + str(expire_timestamp)
        sign = hashlib.md5(sign_string.encode('utf-8')).hexdigest().lower()
        
        # 构建URL
        url = f"{self.cdn_domain}{path}?t={expire_timestamp}&sign={sign}"
        
        return url

