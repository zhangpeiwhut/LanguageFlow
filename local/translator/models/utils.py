import json
from datetime import datetime
from pathlib import Path
from typing import Optional

LOG_DIR = Path('logs/translator')
LOG_DIR.mkdir(parents=True, exist_ok=True)

class TranslationLogger:    
    def __init__(self):
        self.log_file = LOG_DIR / f"translation_{datetime.now().strftime('%Y%m%d')}.log"
        self.api_log_file = LOG_DIR / f"api_calls_{datetime.now().strftime('%Y%m%d')}.log"
    
    def log(self, level: str, message: str):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"[{timestamp}] [{level}] {message}\n"

        try:
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write(log_entry)
        except Exception as e:
            print(f'[error] 写入日志失败: {e}')
        
        if level in ('error', 'warn'):
            print(f'[{level}] {message}')
    
    def log_api_call(self, endpoint: str, payload: dict, response: dict, duration: float, success: bool):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = {
            'timestamp': timestamp,
            'endpoint': endpoint,
            'payload_size': len(json.dumps(payload)),
            'response_size': len(json.dumps(response)) if response else 0,
            'duration_ms': round(duration * 1000, 2),
            'success': success,
            'payload': payload,
            'response': response,
        }
        
        try:
            with open(self.api_log_file, 'a', encoding='utf-8') as f:
                f.write(json.dumps(log_entry, ensure_ascii=False) + '\n')
        except Exception as e:
            print(f'[error] 写入 API 日志失败: {e}')


class ResponseParser:    
    @staticmethod
    def parse_response(result: dict) -> Optional[str]:
        translated_text = None
        # 格式1: output.choices[0].message.content
        if 'output' in result and 'choices' in result['output']:
            if result['output']['choices']:
                translated_text = result['output']['choices'][0].get('message', {}).get('content', '')
        # 格式2: output.text 或 output.translated_text
        if not translated_text and 'output' in result:
            if isinstance(result['output'], str):
                translated_text = result['output']
            elif isinstance(result['output'], dict):
                translated_text = result['output'].get('text') or result['output'].get('translated_text', '')
        # 格式3: data.translated_text
        if not translated_text and 'data' in result:
            translated_text = result['data'].get('translated_text', '')
        # 格式4: 直接 text 字段
        if not translated_text:
            translated_text = result.get('text', '')
        return translated_text.strip() if translated_text else None
