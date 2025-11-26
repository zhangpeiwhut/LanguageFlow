"""腾讯云COS服务（用于server端生成CDN URL鉴权链接）"""
import os
import time
import hashlib
import random
import string

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
        
        根据腾讯云CDN TypeA鉴权文档：
        https://cloud.tencent.com/document/product/228/41623
        
        URL格式：http://DomainName/FileName?sign=timestamp-rand-uid-md5hash
        
        签名算法：md5hash = md5sum(uri-timestamp-rand-uid-pkey)
        - uri: 资源访问路径以正斜线（/）开头
        - timestamp: Unix时间戳（秒）
        - rand: 0-100位随机字符串（大小写字母与数字）
        - uid: 用户ID，暂未使用，设置为0
        - pkey: 自定义密钥
        
        Args:
            key: COS对象Key（如 audio/channel/2023-11-15/podcast_id.mp3）
            expires: URL有效期（秒），默认180秒（3分钟）
            
        Returns:
            CDN鉴权URL
        """
        if not self.cdn_domain or not self.cdn_auth_key:
            raise Exception('CDN服务未配置，无法生成URL。请设置 COS_CDN_DOMAIN 和 COS_CDN_AUTH_KEY')
        
        # 计算过期时间戳（Unix时间戳，秒）
        expire_timestamp = int(time.time()) + expires
        
        # 确保path以/开头（TypeA要求FileName需以正斜线开头）
        uri = '/' + key.lstrip('/')
        
        # 生成随机字符串（0-100位，大小写字母与数字）
        rand_length = random.randint(10, 20)  # 生成10-20位随机字符串
        rand = ''.join(random.choices(string.ascii_letters + string.digits, k=rand_length))
        
        # uid设置为0（暂未使用）
        uid = '0'
        
        # 计算签名：md5sum(uri-timestamp-rand-uid-pkey)
        sign_string = f"{uri}-{expire_timestamp}-{rand}-{uid}-{self.cdn_auth_key}"
        md5hash = hashlib.md5(sign_string.encode('utf-8')).hexdigest()
        
        # 构建URL：http://DomainName/FileName?sign=timestamp-rand-uid-md5hash
        url = f"{self.cdn_domain}{uri}?sign={expire_timestamp}-{rand}-{uid}-{md5hash}"
        
        return url

