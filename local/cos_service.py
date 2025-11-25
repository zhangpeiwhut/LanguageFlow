"""腾讯云COS上传服务"""
import os
import json
from typing import Dict, Any, Optional
from pathlib import Path
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
    
    def upload_segments_json(self, podcast_id: str, segments: list, channel: str, timestamp: int) -> str:
        """
        上传segments JSON到COS
        
        Args:
            podcast_id: podcast的ID
            segments: segments列表
            channel: 频道名称（用于构建目录结构，必需）
            timestamp: 时间戳（用于构建目录结构，必需）
            
        Returns:
            segments JSON的对象Key（segments/{channel}/{YYYY-MM-DD}/{podcast_id}.json）
        """
        if not channel or not timestamp:
            raise ValueError('channel和timestamp是必需参数，用于构建目录结构')
        
        # 将channel中的特殊字符替换为安全字符（用于路径）
        # 替换斜杠、反斜杠、空格等特殊字符
        safe_channel = channel.replace('/', '_').replace('\\', '_').replace(' ', '_')
        # 将timestamp转换为日期字符串（YYYY-MM-DD格式）
        from datetime import datetime, timezone
        date_str = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime('%Y-%m-%d')
        key = f'segments/{safe_channel}/{date_str}/{podcast_id}.json'
        
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
    
    def upload_audio_from_file(self, file_path: str, podcast_id: str, channel: str, timestamp: int) -> str:
        """
        从本地文件上传音频到COS
        
        Args:
            file_path: 本地音频文件路径
            podcast_id: podcast的ID
            channel: 频道名称（用于构建目录结构，必需）
            timestamp: 时间戳（用于构建目录结构，必需）
            
        Returns:
            音频文件的对象Key（audio/{channel}/{YYYY-MM-DD}/{podcast_id}.mp3）
        """
        if not channel or not timestamp:
            raise ValueError('channel和timestamp是必需参数，用于构建目录结构')
        
        if not os.path.exists(file_path):
            raise FileNotFoundError(f'音频文件不存在: {file_path}')
        
        # 构建COS中的key路径
        safe_channel = channel.replace('/', '_').replace('\\', '_').replace(' ', '_')
        from datetime import datetime, timezone
        date_str = datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime('%Y-%m-%d')
        
        # 从文件路径中获取文件扩展名
        file_path_obj = Path(file_path)
        suffix = file_path_obj.suffix or '.mp3'
        # 确保扩展名是音频格式
        if suffix.lower() not in ['.mp3', '.m4a', '.wav', '.aac', '.ogg']:
            suffix = '.mp3'
        
        key = f'audio/{safe_channel}/{date_str}/{podcast_id}{suffix}'
        
        # 获取文件大小
        file_size = os.path.getsize(file_path)
        print(f'[cos] 开始上传音频文件到COS: {key} (大小: {file_size} bytes)')
        
        try:
            # 对于大于20MB的文件，使用分片上传；否则使用普通上传
            if file_size > 20 * 1024 * 1024:  # 20MB
                response = self.client.upload_file(
                    Bucket=self.bucket,
                    LocalFilePath=file_path,
                    Key=key,
                    PartSize=10 * 1024 * 1024,  # 分片大小10MB
                    MAXThread=5  # 最大并发线程数
                )
            else:
                # 小文件直接上传
                with open(file_path, 'rb') as f:
                    response = self.client.put_object(
                        Bucket=self.bucket,
                        Body=f.read(),
                        Key=key,
                        ContentType=self._get_content_type(suffix)
                    )
            
            print(f'[cos] 成功上传音频文件: {key}')
            return key
            
        except CosClientError as e:
            print(f'[cos] 客户端错误: {e}')
            raise Exception(f'COS上传失败（客户端错误）: {str(e)}')
        except CosServiceError as e:
            print(f'[cos] 服务端错误: {e.get_error_code()}, {e.get_error_msg()}')
            raise Exception(f'COS上传失败（服务端错误）: {e.get_error_msg()}')
        except Exception as e:
            print(f'[cos] 未知错误: {e}')
            raise Exception(f'音频上传失败: {str(e)}')
    
    def _get_content_type(self, suffix: str) -> str:
        """根据文件扩展名返回Content-Type"""
        content_types = {
            '.mp3': 'audio/mpeg',
            '.m4a': 'audio/mp4',
            '.wav': 'audio/wav',
            '.aac': 'audio/aac',
            '.ogg': 'audio/ogg'
        }
        return content_types.get(suffix.lower(), 'audio/mpeg')