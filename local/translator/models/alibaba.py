import asyncio
import os
from typing import Optional
import httpx

from .base import BaseModelProvider
from .utils import ResponseParser

QWEN_API_KEY = os.getenv('QWEN_API_KEY', 'sk-9b13c38aaf14432dae7bd830d2396169')
QWEN_API_ENDPOINT = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation'


class AlibabaModelProvider(BaseModelProvider):    
    def __init__(self, api_key: Optional[str] = None):
        super().__init__()
        self.api_key = api_key or QWEN_API_KEY
        self.client = httpx.AsyncClient(timeout=30.0)
    
    async def close(self):
        await self.client.aclose()
    
    def _build_payload(self, prompt: str) -> dict:
        return {
            'model': 'qwen-mt-plus',
            'input': {
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            },
            'parameters': {
                'temperature': 0.3,
                'result_format': 'message',
            }
        }
    
    async def call_model(self, prompt: str, max_retries: int = 5) -> str:
        """
        调用阿里云模型API（实现基类的抽象方法）
        
        这是唯一需要实现的方法，负责：
        - 调用阿里云API
        - 解析响应
        - 返回模型生成的文本
        
        Args:
            prompt: 完整的提示词
            max_retries: 最大重试次数
        
        Returns:
            模型生成的文本
        """
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json',
            'X-DashScope-SSE': 'disable',
        }
        
        payload = self._build_payload(prompt)
        last_error = None
        for attempt in range(max_retries):
            start_time = asyncio.get_event_loop().time()
            try:
                if attempt > 0:
                    wait_time = min(5 * attempt, 15)
                    self.logger.log('warn', f'第 {attempt + 1}/{max_retries} 次重试，等待 {wait_time} 秒...')
                    await asyncio.sleep(wait_time)
                
                response = await self.client.post(
                    QWEN_API_ENDPOINT,
                    headers=headers,
                    json=payload,
                    timeout=30.0,
                )
                
                result = response.json()
                duration = asyncio.get_event_loop().time() - start_time
                # 检查API返回的错误码
                if 'code' in result:
                    error_code = result.get('code', '')
                    error_message = result.get('message', '')
                    
                    self.logger.log_api_call(
                        QWEN_API_ENDPOINT,
                        payload,
                        result,
                        duration,
                        success=False
                    )
                    
                    if error_code == 'AllocationQuota.FreeTierOnly':
                        error_msg = f"免费额度已用完: {error_message}"
                        self.logger.log('error', error_msg)
                        raise Exception(error_msg)
                    
                    last_error = f"API错误 ({error_code}): {error_message}"
                    if attempt < max_retries - 1:
                        continue
                    else:
                        raise Exception(f"API调用失败: {last_error}")
                
                response.raise_for_status()
                
                self.logger.log_api_call(
                    QWEN_API_ENDPOINT,
                    payload,
                    result,
                    duration,
                    success=True
                )
                
                translated_text = ResponseParser.parse_response(result)
                
                if translated_text and translated_text.strip():
                    if attempt > 0:
                        self.logger.log('warn', f'✓ 重试成功（第 {attempt + 1} 次尝试）')
                    return translated_text
                
                last_error = "API 返回空字符串"
                self.logger.log('warn', f'API 返回了空字符串（尝试 {attempt + 1}/{max_retries}）')
                if attempt < max_retries - 1:
                    continue
                else:
                    raise Exception("API 返回空字符串，无法获取翻译结果")
                        
            except httpx.HTTPStatusError as e:
                duration = asyncio.get_event_loop().time() - start_time
                error_detail = None
                try:
                    error_detail = e.response.json()
                except:
                    error_detail = {'text': e.response.text}
                
                self.logger.log_api_call(
                    QWEN_API_ENDPOINT,
                    payload,
                    error_detail,
                    duration,
                    success=False
                )
                
                if isinstance(error_detail, dict) and error_detail.get('code') == 'AllocationQuota.FreeTierOnly':
                    error_msg = f"免费额度已用完: {error_detail.get('message', '')}"
                    self.logger.log('error', error_msg)
                    raise Exception(error_msg)
                
                if e.response.status_code == 429 or e.response.status_code >= 500:
                    last_error = f"HTTP {e.response.status_code}: {error_detail}"
                    if attempt < max_retries - 1:
                        continue
                    else:
                        raise Exception(f"API请求失败: {last_error}")
                else:
                    last_error = f"HTTP {e.response.status_code}: {error_detail}"
                    raise Exception(f"API请求失败: {last_error}")
                        
            except (httpx.TimeoutException, httpx.NetworkError) as e:
                duration = asyncio.get_event_loop().time() - start_time
                self.logger.log_api_call(
                    QWEN_API_ENDPOINT,
                    payload,
                    {'error': str(e)},
                    duration,
                    success=False
                )
                last_error = f"网络错误: {str(e)}"
                if attempt < max_retries - 1:
                    continue
                else:
                    raise Exception(f"网络错误: {last_error}")
                    
            except Exception as e:
                duration = asyncio.get_event_loop().time() - start_time
                self.logger.log_api_call(
                    QWEN_API_ENDPOINT,
                    payload,
                    {'error': str(e)},
                    duration,
                    success=False
                )
                if 'AllocationQuota' in str(e) or '免费额度' in str(e):
                    raise
                last_error = f"模型调用异常: {str(e)}"
                if attempt < max_retries - 1:
                    continue
                else:
                    raise Exception(f"模型调用失败: {last_error}")
        
        raise Exception(f"模型调用失败（已重试 {max_retries} 次）: {last_error or '未知错误'}")
