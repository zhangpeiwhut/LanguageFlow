"""腾讯云COS上传服务"""
import os
import json
from typing import Dict, Any, Optional
from qcloud_cos import CosConfig
from qcloud_cos import CosS3Client
from qcloud_cos.cos_exception import CosClientError, CosServiceError

class COSService:    
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
            raise ValueError('缺少COS配置：需要设置 COS_SECRET_ID, COS_SECRET_KEY, COS_BUCKET 环境变量')
        
        config = CosConfig(
            Region=self.region,
            SecretId=self.secret_id,
            SecretKey=self.secret_key,
            Token=None,
            Scheme='https'
        )
        self.client = CosS3Client(config)
    
    def upload_segments_json(self, podcast_id: str, segments: list) -> str:
        """
        上传segments JSON到COS
        
        Args:
            podcast_id: podcast的ID
            segments: segments列表
            
        Returns:
            segments JSON的对象Key（如 segments/{podcast_id}.json）
        """
        # 构建文件路径：segments/{podcast_id}.json
        key = f'segments/{podcast_id}.json'
        
        json_data = json.dumps(segments, ensure_ascii=False, indent=2)
        json_bytes = json_data.encode('utf-8')
        
        try:
            response = self.client.put_object(
                Bucket=self.bucket,
                Body=json_bytes,
                Key=key,
                ContentType='application/json; charset=utf-8'
            )
            print(f'[cos] 成功上传segments JSON: {podcast_id} -> {key}')
            return key
        except CosClientError as e:
            print(f'[cos] 客户端错误: {e}')
            raise Exception(f'COS上传失败（客户端错误）: {str(e)}')
        except CosServiceError as e:
            print(f'[cos] 服务端错误: {e.get_error_code()}, {e.get_error_msg()}')
            raise Exception(f'COS上传失败（服务端错误）: {e.get_error_msg()}')
        except Exception as e:
            print(f'[cos] 未知错误: {e}')
            raise Exception(f'COS上传失败: {str(e)}')