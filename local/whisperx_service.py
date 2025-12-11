import os
import tempfile
import asyncio
import time
from pathlib import Path
from typing import Dict, Tuple
import torch
_real_torch_load = torch.load
def _torch_load_legacy(*args, **kwargs):
    kwargs["weights_only"] = False
    return _real_torch_load(*args, **kwargs)
torch.load = _torch_load_legacy
import whisperx
import httpx

WHISPERX_MODEL_ID = os.getenv('WHISPERX_MODEL_ID', 'large-v3')
WHISPERX_BATCH_SIZE = int(os.getenv('WHISPERX_BATCH_SIZE', '8'))
WHISPERX_COMPUTE_TYPE = os.getenv('WHISPERX_COMPUTE_TYPE')
WHISPERX_DEVICE_OVERRIDE = os.getenv('WHISPERX_DEVICE')

def _detect_device() -> Tuple[str, str]:
    default_compute = WHISPERX_COMPUTE_TYPE
    if WHISPERX_DEVICE_OVERRIDE:
        device = WHISPERX_DEVICE_OVERRIDE
        fallback = 'float16' if device == 'cuda' else 'int8'
        return device, default_compute or fallback
    if torch.cuda.is_available():
        return 'cuda', default_compute or 'float16'
    if torch.backends.mps.is_available():
        print('[info] MPS 检测到但 WhisperX 不支持，自动改用 CPU')
    return 'cpu', default_compute or 'int8'

DEVICE, COMPUTE_TYPE = _detect_device()

class WhisperResources:
    def __init__(self) -> None:
        self.model = None
        self.align_models: Dict[str, Tuple[object, dict]] = {}
        self.lock = asyncio.Lock()
        # 使用信号量限制 WhisperX 同时只能处理一个音频（因为模型不是线程安全的）
        self.semaphore = asyncio.Semaphore(1)

    async def ensure_model(self):
        if self.model:
            return
        async with self.lock:
            if self.model:
                return
            loop = asyncio.get_event_loop()
            self.model = await loop.run_in_executor(
                None, lambda: whisperx.load_model(WHISPERX_MODEL_ID, DEVICE, compute_type=COMPUTE_TYPE)
            )

    async def get_align_model(self, language_code: str):
        code = language_code or 'en'
        if code in self.align_models:
            return self.align_models[code]
        async with self.lock:
            if code in self.align_models:
                return self.align_models[code]
            loop = asyncio.get_event_loop()
            def _load_align():
                return whisperx.load_align_model(language_code=code, device=DEVICE)
            align_model, metadata = await loop.run_in_executor(None, _load_align)
            self.align_models[code] = (align_model, metadata)
            return self.align_models[code]


resources = WhisperResources()


async def transcribe_audio_url(audio_url: str) -> Dict:
    await resources.ensure_model()
    print(f'[whisperx] 开始从 URL 下载音频文件: {audio_url}')
    try:
        from urllib.parse import urlparse
        parsed_url = urlparse(audio_url)
        path = Path(parsed_url.path)
        suffix = path.suffix or '.mp3'
    except Exception:
        suffix = '.mp3'
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp_path = Path(tmp.name)
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            response = await client.get(audio_url)
            response.raise_for_status()
            tmp.write(response.content)
            tmp.flush()
            tmp.close()
            file_size = len(response.content)
            print(f'[whisperx] 音频文件下载完成 ({file_size} bytes)')
        result = await _process_audio_file(tmp_path)
        result['temp_file_path'] = str(tmp_path)
        return result
    except httpx.HTTPStatusError as e:
        _cleanup_temp_file(tmp_path)
        raise Exception(f'下载音频文件失败: {e.response.status_code}')
    except httpx.RequestError as e:
        _cleanup_temp_file(tmp_path)
        raise Exception(f'请求音频 URL 失败: {str(e)}')
    except Exception as error:
        _cleanup_temp_file(tmp_path)
        raise Exception(f'转录失败: {str(error)}')


async def _process_audio_file(tmp_path: Path) -> Dict:
    start_time = time.time()
    await resources.ensure_model()

    # 使用信号量确保同时只有一个音频在处理（WhisperX 模型不是线程安全的）
    async with resources.semaphore:
        file_size = tmp_path.stat().st_size
        print(f'[whisperx] 音频文件已保存 ({file_size} bytes)，开始转录...')
        loop = asyncio.get_event_loop()

        def _run_transcribe():
            return resources.model.transcribe(
                str(tmp_path),
                batch_size=WHISPERX_BATCH_SIZE,
            )
        transcribe_start = time.time()
        result = await loop.run_in_executor(None, _run_transcribe)
        transcribe_time = time.time() - transcribe_start
        segments = result.get('segments') or []
        language = result.get('language') or 'en'
        print(f'[whisperx] 转录完成（耗时 {transcribe_time:.2f}s）：检测到 {len(segments)} 个片段，语言: {language}')

        try:
            print(f'[whisperx] 开始对齐时间戳...')
            align_start = time.time()
            align_model, metadata = await resources.get_align_model(language)

            # 将同步的 align 操作放到 executor 中执行，避免阻塞 event loop
            def _run_align():
                return whisperx.align(
                    segments,
                    align_model,
                    metadata,
                    str(tmp_path),
                    DEVICE,
                    return_char_alignments=False,
                )

            aligned = await loop.run_in_executor(None, _run_align)
            segments = aligned.get('segments') or segments
            align_time = time.time() - align_start
            print(f'[whisperx] 对齐完成（耗时 {align_time:.2f}s）')
        except Exception as error:
            print(f'[warn] align failed: {error}')

        payload = []
        for index, segment in enumerate(segments):
            start = float(segment.get('start') or 0)
            end = float(segment.get('end') or start)
            payload.append(
                {
                    'text': segment.get('text') or '',
                    'start': max(0.0, start),
                    'end': max(start, end),
                }
            )
        total_time = time.time() - start_time
        print(f'[whisperx] 全部处理完成（总耗时 {total_time:.2f}s）')
        return {
            'segments': payload,
            'language': language,
            'stats': {
                'total_segments': len(payload),
                'processing_time': round(total_time, 2),
            }
        }
def _cleanup_temp_file(path: Path):
    try:
        path.unlink(missing_ok=True)
    except Exception:
        pass

