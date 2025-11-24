"""腾讯云COS服务（用于server端生成预签名URL）"""
import os
from qcloud_cos import CosConfig
from qcloud_cos import CosS3Client
from qcloud_cos.cos_exception import CosClientError, CosServiceError

class COSService:
    """腾讯云COS服务类（server端）"""
    
    def __init__(self):
        """
        初始化COS服务
        需要设置以下环境变量：
        - COS_SECRET_ID: 腾讯云SecretId
        - COS_SECRET_KEY: 腾讯云SecretKey
        - COS_REGION: COS地域，如 ap-beijing
        - COS_BUCKET: COS存储桶名称
        """
        self.secret_id = os.getenv('COS_SECRET_ID')
        self.secret_key = os.getenv('COS_SECRET_KEY')
        self.region = os.getenv('COS_REGION', 'ap-beijing')
        self.bucket = os.getenv('COS_BUCKET')
        
        if not all([self.secret_id, self.secret_key, self.bucket]):
            # 如果缺少配置，不抛出异常，而是允许服务启动（但生成URL时会失败）
            print('[cos-service] 警告：缺少COS配置，预签名URL功能将不可用')
            self.client = None
            return
        
        # 初始化COS客户端
        config = CosConfig(
            Region=self.region,
            SecretId=self.secret_id,
            SecretKey=self.secret_key,
            Scheme='https'
        )
        self.client = CosS3Client(config)
    
    def get_presigned_url(self, segments_key: str, expires: int = 300) -> str:
        """
        生成segments JSON的预签名URL（临时访问链接）
        
        Args:
            segments_key: segments JSON的对象Key（如 segments/{podcast_id}.json）
            expires: URL有效期（秒），默认300秒（5分钟）
            
        Returns:
            预签名URL
        """
        if not self.client:
            raise Exception('COS服务未配置，无法生成预签名URL')
        
        try:
            # 生成预签名URL
            url = self.client.get_presigned_download_url(
                Bucket=self.bucket,
                Key=segments_key,
                Expired=expires
            )
            return url
        except CosClientError as e:
            print(f'[cos-service] 生成预签名URL失败（客户端错误）: {e}')
            raise Exception(f'生成预签名URL失败: {str(e)}')
        except CosServiceError as e:
            print(f'[cos-service] 生成预签名URL失败（服务端错误）: {e.get_error_code()}, {e.get_error_msg()}')
            raise Exception(f'生成预签名URL失败: {e.get_error_msg()}')
        except Exception as e:
            print(f'[cos-service] 生成预签名URL失败（未知错误）: {e}')
            raise Exception(f'生成预签名URL失败: {str(e)}')

