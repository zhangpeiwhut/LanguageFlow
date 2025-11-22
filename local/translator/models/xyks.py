"""XYKS 模型提供器实现"""
import asyncio
import json
import os
from typing import Optional

import httpx

from .base import BaseModelProvider
from .utils import ResponseParser

XYKS_API_KEY = os.getenv('XYKS_API_KEY', '')
XYKS_API_ENDPOINT = 'https://leo.zhenguanyu.com/leo-cms-python/llm/chat'
XYKS_MODEL = os.getenv('XYKS_MODEL', 'gpt-4o-mini')
XYKS_BIZ = int(os.getenv('XYKS_BIZ', '6'))


class XYKSModelProvider(BaseModelProvider):    
    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None, biz: Optional[int] = None):
        super().__init__()
        self.api_key = api_key or XYKS_API_KEY
        self.model = model or XYKS_MODEL
        self.biz = biz or XYKS_BIZ
        self.client = httpx.AsyncClient(timeout=30.0)
    
    async def close(self):
        """关闭 HTTP 客户端"""
        await self.client.aclose()
    
    async def call_model(self, prompt: str, max_retries: int = 5) -> str:
        """
        调用 XYKS 模型API（实现基类的抽象方法）
        
        这是唯一需要实现的方法，负责：
        - 调用 XYKS API
        - 解析响应
        - 返回模型生成的文本
        
        Args:
            prompt: 完整的提示词
            max_retries: 最大重试次数
        
        Returns:
            模型生成的文本
        """
        system_prompt = "你是专业的中文母语翻译者。"
        
        payload = {
            "biz": self.biz,
            "requestContext": [],
            "temperature": 0,
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ]
        }
        
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*"
        }
        
        last_error = None
        for attempt in range(max_retries):
            start_time = asyncio.get_event_loop().time()
            try:
                if attempt > 0:
                    wait_time = min(5 * attempt, 15)
                    self.logger.log('warn', f'第 {attempt + 1}/{max_retries} 次重试，等待 {wait_time} 秒...')
                    await asyncio.sleep(wait_time)
                
                response = await self.client.post(
                    XYKS_API_ENDPOINT,
                    json=payload,
                    headers=headers,
                    timeout=30.0
                )
                duration = asyncio.get_event_loop().time() - start_time
                
                if response.status_code == 200:
                    text = response.text
                    
                    try:
                        response_json = json.loads(text)
                        
                        # 记录 API 调用日志
                        self.logger.log_api_call(
                            XYKS_API_ENDPOINT,
                            payload,
                            response_json,
                            duration,
                            success=True
                        )
                        
                        # 解析响应
                        raw_translated_text = response_json.get('choices', [{}])[0].get('message', {}).get('content', '')
                        
                        if not raw_translated_text:
                            last_error = "API 返回空内容"
                            self.logger.log('warn', f'API 返回了空内容（尝试 {attempt + 1}/{max_retries}）')
                            if attempt < max_retries - 1:
                                continue
                            else:
                                raise Exception("API 返回空内容，无法获取翻译结果")
                        
                        # 处理响应文本：移除可能的 JSON 代码块标记
                        processed_text = raw_translated_text.replace('```json\n', '').replace('\n```', '').replace('\n', '').replace(',]', ']')
                        
                        # 尝试解析为 JSON（如果响应是 JSON 格式）
                        try:
                            parsed_json = json.loads(processed_text)
                            # 如果是数组格式 [{'t': '翻译'}, ...]，提取第一个元素的 't' 字段
                            if isinstance(parsed_json, list) and len(parsed_json) > 0:
                                if isinstance(parsed_json[0], dict) and 't' in parsed_json[0]:
                                    translated_text = parsed_json[0]['t']
                                else:
                                    translated_text = str(parsed_json[0])
                            elif isinstance(parsed_json, dict) and 't' in parsed_json:
                                translated_text = parsed_json['t']
                            else:
                                translated_text = processed_text
                        except json.JSONDecodeError:
                            # 如果不是 JSON 格式，直接使用原始文本
                            translated_text = raw_translated_text.strip()
                        
                        if translated_text and translated_text.strip():
                            if attempt > 0:
                                self.logger.log('warn', f'✓ 重试成功（第 {attempt + 1} 次尝试）')
                            return translated_text.strip()
                        
                        last_error = "解析后的文本为空"
                        self.logger.log('warn', f'解析后的文本为空（尝试 {attempt + 1}/{max_retries}）')
                        if attempt < max_retries - 1:
                            continue
                        else:
                            raise Exception("解析后的文本为空，无法获取翻译结果")
                            
                    except json.JSONDecodeError as e:
                        duration = asyncio.get_event_loop().time() - start_time
                        self.logger.log_api_call(
                            XYKS_API_ENDPOINT,
                            payload,
                            {'error': f'JSON解析错误: {str(e)}', 'response_text': text[:500]},
                            duration,
                            success=False
                        )
                        last_error = f"JSON解析错误: {str(e)}"
                        if attempt < max_retries - 1:
                            continue
                        else:
                            raise Exception(f"JSON解析失败: {last_error}")
                else:
                    duration = asyncio.get_event_loop().time() - start_time
                    error_text = response.text
                    error_detail = {'status': response.status_code, 'text': error_text[:500]}
                    
                    self.logger.log_api_call(
                        XYKS_API_ENDPOINT,
                        payload,
                        error_detail,
                        duration,
                        success=False
                    )
                    
                    last_error = f"HTTP {response.status_code}: {error_text[:200]}"
                    if response.status_code == 429 or response.status_code >= 500:
                        if attempt < max_retries - 1:
                            continue
                        else:
                            raise Exception(f"API请求失败: {last_error}")
                    else:
                        raise Exception(f"API请求失败: {last_error}")
                            
            except (httpx.TimeoutException, httpx.NetworkError) as e:
                duration = asyncio.get_event_loop().time() - start_time
                self.logger.log_api_call(
                    XYKS_API_ENDPOINT,
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
                    XYKS_API_ENDPOINT,
                    payload,
                    {'error': str(e)},
                    duration,
                    success=False
                )
                last_error = f"模型调用异常: {str(e)}"
                if attempt < max_retries - 1:
                    continue
                else:
                    raise Exception(f"模型调用失败: {last_error}")
        
        raise Exception(f"模型调用失败（已重试 {max_retries} 次）: {last_error or '未知错误'}")

