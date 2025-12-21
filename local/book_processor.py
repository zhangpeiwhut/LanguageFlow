"""电子书处理器
将 Gutenberg 电子书拆分成章节片段，生成 TTS 音频，转录分句，翻译，上传服务端
"""
import os

# 在导入 whisperx_service 之前设置环境变量，指定使用 medium 模型
os.environ['WHISPERX_MODEL_ID'] = 'medium'

import re
import asyncio
import argparse
from pathlib import Path
from typing import List, Dict, Any, Tuple
from datetime import datetime, timezone

# 本地模块
from cos_service import COSService
from uploader import PodcastUploader
from translator import translate_segments, get_translator
from whisperx_service import _process_audio_file, _cleanup_temp_file


# ============ 自定义异常 ============
class QuotaExceededError(Exception):
    """API 配额超限异常"""
    pass


# ============ 配置 ============
DEFAULT_WORDS_PER_SEGMENT = 3000  # 每段约3000词 ≈ 20分钟

# Edge TTS 配置
EDGE_TTS_VOICE = "en-US-GuyNeural"  # Edge TTS 语音，可选: en-US-AriaNeural, en-GB-RyanNeural
EDGE_TTS_RATE = "+0%"  # 语速调整，如 "-10%", "+20%"

# Google TTS 配置
# 传统语音 (v1 API):
#   - Wavenet: en-US-Wavenet-D (男), en-US-Wavenet-F (女)
#   - Neural2: en-US-Neural2-D (男), en-US-Neural2-F (女)
#   - Studio: en-US-Studio-O (男), en-US-Studio-Q (女)
#   - Journey: en-US-Journey-D (男), en-US-Journey-F (女)
GOOGLE_TTS_VOICE = "en-US-Journey-D"
GOOGLE_TTS_LANGUAGE = "en-US"
GOOGLE_TTS_SPEAKING_RATE = 1.0  # 语速 0.25-4.0
GOOGLE_TTS_PITCH = 0.0  # 音调 -20.0 到 20.0

# Gemini TTS 配置 (Generative Language API) - 更自然的语音
# 模型: gemini-2.5-flash-preview-tts, gemini-2.5-pro-preview-tts
# 语音名称: Achernar, Gacrux, Leda, Orus, Puck, Schedar, Achird 等
GEMINI_TTS_MODEL = "gemini-2.5-pro-preview-tts"  # 或 gemini-2.5-flash-preview-tts
GEMINI_TTS_VOICE = "Achird"  # 男声: Orus, Puck, Achird; 女声: Achernar, Leda, Schedar
GEMINI_TTS_PROMPT = "Read aloud like an audiobook narrator with clear enunciation and engaging tone."
GEMINI_KEY = 'AIzaSyA49XlZi2OLMst3Svcgup-gI2qzhajHBI8'

# TTS 引擎选择: "edge", "google", "gemini"
TTS_ENGINE = "edge"


# ============ 第一步：拆分电子书 ============

def parse_gutenberg_book(file_path: str) -> Tuple[str, str, List[Dict[str, Any]]]:
    """
    解析 Gutenberg 电子书，提取标题、作者和章节

    Returns:
        (book_title, author, chapters)
        chapters: [{"number": 1, "title": "...", "content": "..."}]
    """
    with open(file_path, 'r', encoding='utf-8-sig') as f:
        content = f.read()

    # 提取标题和作者
    title_match = re.search(r'Title:\s*(.+)', content)
    author_match = re.search(r'Author:\s*(.+)', content)

    book_title = title_match.group(1).strip() if title_match else "Unknown"
    author = author_match.group(1).strip() if author_match else "Unknown"

    # 找到正文开始位置（跳过 Gutenberg 头部）
    start_marker = re.search(r'\*\*\* START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK .+? \*\*\*', content)
    end_marker = re.search(r'\*\*\* END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK .+? \*\*\*', content)

    if start_marker:
        content = content[start_marker.end():]
    if end_marker:
        content = content[:end_marker.start()]

    # 章节标题模式：罗马数字 + 点 + 标题（全大写，可能包含撇号、连字符）
    # 例如: "II. THE RED-HEADED LEAGUE", "IX. THE ADVENTURE OF THE ENGINEER'S THUMB"
    # 注意：支持直撇号 ' (U+0027) 和弯撇号 ' (U+2019)
    chapter_pattern = r"^([IVX]+)\.\s+([A-Z][A-Z\s'\u2019\-]+)$"

    lines = content.split('\n')
    chapters = []
    current_chapter = None
    current_content = []

    for line in lines:
        match = re.match(chapter_pattern, line.strip())
        if match:
            # 保存前一章
            if current_chapter:
                current_chapter['content'] = '\n'.join(current_content).strip()
                chapters.append(current_chapter)

            # 开始新章节
            roman_num = match.group(1)
            chapter_title = match.group(2).strip()
            current_chapter = {
                'number': roman_to_int(roman_num),
                'roman': roman_num,
                'title': chapter_title,
            }
            current_content = []
        elif current_chapter:
            current_content.append(line)

    # 保存最后一章
    if current_chapter:
        current_chapter['content'] = '\n'.join(current_content).strip()
        chapters.append(current_chapter)

    print(f'[book] 解析完成: {book_title} by {author}')
    print(f'[book] 共 {len(chapters)} 章')

    return book_title, author, chapters


def roman_to_int(roman: str) -> int:
    """罗马数字转阿拉伯数字"""
    values = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000}
    result = 0
    prev = 0
    for char in reversed(roman.upper()):
        curr = values.get(char, 0)
        if curr < prev:
            result -= curr
        else:
            result += curr
        prev = curr
    return result


def split_chapter_by_words(content: str, max_words: int = DEFAULT_WORDS_PER_SEGMENT, min_words: int = 1000) -> List[str]:
    """
    按字数拆分章节内容，在段落边界切分

    Args:
        content: 章节全文
        max_words: 每段最大字数
        min_words: 最小字数，如果最后一段太短则合并到前一段

    Returns:
        拆分后的文本列表
    """
    # 按段落分割（双换行）
    paragraphs = re.split(r'\n\s*\n', content)
    paragraphs = [p.strip() for p in paragraphs if p.strip()]

    segments = []
    current_segment = []
    current_word_count = 0

    for para in paragraphs:
        para_words = len(para.split())

        # 如果当前段落加上之前的超过限制，先保存之前的
        if current_word_count + para_words > max_words and current_segment:
            segments.append('\n\n'.join(current_segment))
            current_segment = []
            current_word_count = 0

        current_segment.append(para)
        current_word_count += para_words

    # 保存最后一段
    if current_segment:
        last_segment = '\n\n'.join(current_segment)
        last_word_count = len(last_segment.split())

        # 如果最后一段太短且有前面的段，合并到前一段
        if last_word_count < min_words and segments:
            segments[-1] = segments[-1] + '\n\n' + last_segment
        else:
            segments.append(last_segment)

    return segments


def clean_text_for_tts(text: str) -> str:
    """
    清理文本以便 TTS 朗读
    - 移除 markdown 格式（如 _斜体_）
    - 处理特殊字符
    """
    # 移除 _斜体_ 标记，保留文字
    text = re.sub(r'_([^_]+)_', r'\1', text)
    # 移除多余空白
    text = re.sub(r'\s+', ' ', text)
    # 保留段落分隔
    text = re.sub(r' ?\n ?', '\n', text)
    return text.strip()


def split_book(file_path: str, output_dir: str, max_words: int = DEFAULT_WORDS_PER_SEGMENT, split_chapters: bool = False) -> List[Dict[str, Any]]:
    """
    拆分整本书为多个片段

    Args:
        file_path: 电子书文件路径
        output_dir: 输出目录
        max_words: 每段最大字数（仅当 split_chapters=True 时生效）
        split_chapters: 是否按字数拆分章节，False 则每章一个文件

    Returns:
        [{"id": "sherlock_ch01", "chapter": 1, "title": "...", "content": "...", "word_count": 8000}]
    """
    book_title, author, chapters = parse_gutenberg_book(file_path)

    # 创建输出目录
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    all_segments = []

    for chapter in chapters:
        chapter_num = chapter['number']
        chapter_title = chapter['title']
        chapter_content = chapter['content']

        if split_chapters:
            # 按字数拆分章节
            parts = split_chapter_by_words(chapter_content, max_words)
            print(f'[book] 第 {chapter_num} 章 "{chapter_title}" 拆分为 {len(parts)} 段')

            for part_idx, part_content in enumerate(parts, 1):
                cleaned_content = clean_text_for_tts(part_content)
                word_count = len(cleaned_content.split())

                segment_id = f"sherlock_{chapter_num:02d}_{part_idx:02d}"

                segment = {
                    'id': segment_id,
                    'chapter': chapter_num,
                    'part': part_idx,
                    'total_parts': len(parts),
                    'chapter_title': chapter_title,
                    'title': f"{chapter['roman']}. {chapter_title}" + (f" (Part {part_idx})" if len(parts) > 1 else ""),
                    'content': cleaned_content,
                    'word_count': word_count,
                }

                txt_path = output_path / f"{segment_id}.txt"
                with open(txt_path, 'w', encoding='utf-8') as f:
                    f.write(cleaned_content)

                segment['txt_path'] = str(txt_path)
                all_segments.append(segment)
        else:
            # 整章作为一个片段
            cleaned_content = clean_text_for_tts(chapter_content)
            word_count = len(cleaned_content.split())
            est_minutes = word_count / 765  # Edge TTS 实际速度

            segment_id = f"sherlock_ch{chapter_num:02d}"

            segment = {
                'id': segment_id,
                'chapter': chapter_num,
                'part': 1,
                'total_parts': 1,
                'chapter_title': chapter_title,
                'title': f"{chapter['roman']}. {chapter_title}",
                'content': cleaned_content,
                'word_count': word_count,
            }

            txt_path = output_path / f"{segment_id}.txt"
            with open(txt_path, 'w', encoding='utf-8') as f:
                f.write(cleaned_content)

            segment['txt_path'] = str(txt_path)
            all_segments.append(segment)

            print(f'[book] 第 {chapter_num} 章 "{chapter_title}" ({word_count} 词, 约 {est_minutes:.1f} 分钟)')

    print(f'[book] 全书处理完成，共 {len(all_segments)} 个片段')
    return all_segments


# ============ 第二步：TTS 生成音频 ============

async def generate_tts_audio_edge(text: str, output_path: str, voice: str = EDGE_TTS_VOICE, rate: str = EDGE_TTS_RATE) -> bool:
    """
    使用 Edge TTS 生成音频

    Args:
        text: 要朗读的文本
        output_path: 输出音频文件路径
        voice: 语音名称
        rate: 语速调整

    Returns:
        是否成功
    """
    try:
        import edge_tts

        communicate = edge_tts.Communicate(text, voice, rate=rate)
        await communicate.save(output_path)

        # 验证文件大小
        file_size = os.path.getsize(output_path)
        print(f'[tts-edge] 生成音频: {output_path} ({file_size / 1024 / 1024:.2f} MB)')
        return True

    except ImportError:
        print('[tts-edge] 错误: 需要安装 edge-tts: pip install edge-tts')
        return False
    except Exception as e:
        print(f'[tts-edge] 生成音频失败: {e}')
        return False


async def generate_tts_audio_google(
    text: str,
    output_path: str,
    voice: str = GOOGLE_TTS_VOICE,
    language: str = GOOGLE_TTS_LANGUAGE,
    speaking_rate: float = GOOGLE_TTS_SPEAKING_RATE,
    pitch: float = GOOGLE_TTS_PITCH,
) -> bool:
    """
    使用 Google Cloud TTS SDK 生成音频

    需要设置环境变量 GOOGLE_APPLICATION_CREDENTIALS 指向服务账号 JSON 文件

    Args:
        text: 要朗读的文本
        output_path: 输出音频文件路径
        voice: 语音名称 (如 en-US-Journey-D)
        language: 语言代码 (如 en-US)
        speaking_rate: 语速 0.25-4.0
        pitch: 音调 -20.0 到 20.0

    Returns:
        是否成功
    """
    try:
        from google.cloud import texttospeech
    except ImportError:
        print('[tts-google] 错误: 需要安装 google-cloud-texttospeech: pip install google-cloud-texttospeech')
        return False

    # 检查认证
    if not os.getenv('GOOGLE_APPLICATION_CREDENTIALS'):
        print('[tts-google] 错误: 需要设置 GOOGLE_APPLICATION_CREDENTIALS 环境变量指向服务账号 JSON 文件')
        return False

    try:
        client = texttospeech.TextToSpeechClient()

        # Google TTS 有 5000 字节的限制，需要分块处理
        chunks = split_text_for_google_tts(text, max_bytes=4500)
        print(f'[tts-google] 文本分为 {len(chunks)} 块，语音: {voice}')

        audio_segments = []

        for i, chunk in enumerate(chunks):
            synthesis_input = texttospeech.SynthesisInput(text=chunk)

            voice_params = texttospeech.VoiceSelectionParams(
                language_code=language,
                name=voice,
            )

            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,
                speaking_rate=speaking_rate,
                pitch=pitch,
            )

            response = client.synthesize_speech(
                input=synthesis_input,
                voice=voice_params,
                audio_config=audio_config
            )

            audio_segments.append(response.audio_content)

            if (i + 1) % 10 == 0 or i == len(chunks) - 1:
                print(f'[tts-google] 已处理 {i + 1}/{len(chunks)} 块')

        # 合并音频
        if len(audio_segments) == 1:
            with open(output_path, 'wb') as f:
                f.write(audio_segments[0])
        else:
            try:
                from pydub import AudioSegment
                import io
                combined = AudioSegment.empty()
                for seg_data in audio_segments:
                    seg = AudioSegment.from_mp3(io.BytesIO(seg_data))
                    combined += seg
                combined.export(output_path, format='mp3')
            except ImportError:
                print('[tts-google] 警告: pydub 未安装，直接拼接音频')
                with open(output_path, 'wb') as f:
                    for seg_data in audio_segments:
                        f.write(seg_data)

        file_size = os.path.getsize(output_path)
        print(f'[tts-google] 生成音频: {output_path} ({file_size / 1024 / 1024:.2f} MB)')
        return True

    except Exception as e:
        print(f'[tts-google] 生成音频失败: {e}')
        return False


def _save_audio_segments(audio_segments: List[Tuple[bytes, str]], output_path: str) -> bool:
    """保存音频片段为 MP3 文件"""
    try:
        from pydub import AudioSegment
        import io

        combined = AudioSegment.empty()
        for seg_data, mime_type in audio_segments:
            sample_rate = 24000
            if 'rate=' in mime_type:
                try:
                    rate_str = mime_type.split('rate=')[1].split(';')[0]
                    sample_rate = int(rate_str)
                except:
                    pass

            seg = AudioSegment.from_raw(
                io.BytesIO(seg_data),
                sample_width=2,
                frame_rate=sample_rate,
                channels=1
            )
            combined += seg

        combined.export(output_path, format='mp3', bitrate='192k')
        return True
    except Exception as e:
        print(f'[tts-gemini] 保存音频失败: {e}')
        return False


async def generate_tts_audio_gemini(
    text: str,
    output_path: str,
    model: str = GEMINI_TTS_MODEL,
    voice: str = GEMINI_TTS_VOICE,
    prompt: str = GEMINI_TTS_PROMPT,
) -> bool:
    """
    使用 Gemini TTS (Generative Language API) 生成音频

    Args:
        text: 要朗读的文本
        output_path: 输出音频文件路径
        model: 模型名称 (gemini-2.5-flash-tts 或 gemini-2.5-pro-tts)
        voice: 语音名称 (Orus, Puck, Achird, Achernar, Leda, Schedar 等)
        prompt: 朗读风格提示

    Returns:
        是否成功
    """
    import base64
    import httpx

    api_key = os.getenv('GOOGLE_API_KEY') or GEMINI_KEY
    if not api_key:
        print('[tts-gemini] 错误: 需要设置 GOOGLE_API_KEY 环境变量或 GEMINI_KEY')
        return False

    # Gemini TTS 通过 generateContent API，限制较宽松但仍需分块
    # 每块 3000 字节，保持语速稳定
    chunks = split_text_for_google_tts(text, max_bytes=3000)
    print(f'[tts-gemini] 文本分为 {len(chunks)} 块，模型: {model}, 语音: {voice}')

    audio_segments = []

    async with httpx.AsyncClient(timeout=300.0) as client:
        for i, chunk in enumerate(chunks):
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"

            # 构建请求体
            text_with_prompt = f"{prompt}\n\n{chunk}" if prompt else chunk

            request_body = {
                "contents": [{
                    "parts": [{
                        "text": text_with_prompt
                    }]
                }],
                "generationConfig": {
                    "response_modalities": ["AUDIO"],
                    "speech_config": {
                        "voice_config": {
                            "prebuilt_voice_config": {
                                "voice_name": voice
                            }
                        }
                    }
                }
            }

            # 重试机制
            max_retries = 3
            for retry in range(max_retries):
                try:
                    response = await client.post(url, json=request_body)
                    response.raise_for_status()

                    result = response.json()

                    # 提取音频数据
                    candidates = result.get('candidates', [])
                    if not candidates:
                        print(f'[tts-gemini] 块 {i + 1}: 无返回结果')
                        break

                    parts = candidates[0].get('content', {}).get('parts', [])
                    for part in parts:
                        if 'inlineData' in part:
                            audio_data = part['inlineData'].get('data', '')
                            mime_type = part['inlineData'].get('mimeType', '')
                            if audio_data:
                                audio_content = base64.b64decode(audio_data)
                                audio_segments.append((audio_content, mime_type))
                                break

                    if (i + 1) % 5 == 0 or i == len(chunks) - 1:
                        print(f'[tts-gemini] 已处理 {i + 1}/{len(chunks)} 块')
                    break  # 成功，跳出重试循环

                except httpx.HTTPStatusError as e:
                    status_code = e.response.status_code
                    print(f'[tts-gemini] API 错误 (块 {i + 1}): {status_code}')
                    print(f'[tts-gemini] 响应: {e.response.text[:500]}')

                    # 429 配额超限：保存已完成的块并抛出特殊异常
                    if status_code == 429:
                        if audio_segments:
                            print(f'[tts-gemini] 429 配额超限，保存已完成的 {len(audio_segments)} 块...')
                            partial_path = output_path.replace('.mp3', '_partial.mp3')
                            _save_audio_segments(audio_segments, partial_path)
                            print(f'[tts-gemini] 已保存部分进度: {partial_path}')
                        raise QuotaExceededError(f'配额超限，已完成 {len(audio_segments)}/{len(chunks)} 块')
                    return False
                except Exception as e:
                    if retry < max_retries - 1:
                        print(f'[tts-gemini] 块 {i + 1} 失败，重试 {retry + 2}/{max_retries}: {e}')
                        await asyncio.sleep(2)  # 等待 2 秒后重试
                    else:
                        print(f'[tts-gemini] 请求失败 (块 {i + 1}): {e}')
                        return False

    if not audio_segments:
        print('[tts-gemini] 错误: 未获取到任何音频数据')
        return False

    # Gemini TTS 返回 PCM 原始音频 (audio/L16;codec=pcm;rate=24000)
    # 需要转换为 MP3
    try:
        from pydub import AudioSegment
        import io

        combined = AudioSegment.empty()
        for seg_data, mime_type in audio_segments:
            # 解析采样率 (从 mime_type 提取，如 "audio/L16;codec=pcm;rate=24000")
            sample_rate = 24000  # 默认值
            if 'rate=' in mime_type:
                try:
                    rate_str = mime_type.split('rate=')[1].split(';')[0]
                    sample_rate = int(rate_str)
                except:
                    pass

            # PCM 16-bit 单声道
            seg = AudioSegment.from_raw(
                io.BytesIO(seg_data),
                sample_width=2,  # 16-bit = 2 bytes
                frame_rate=sample_rate,
                channels=1
            )
            combined += seg

        combined.export(output_path, format='mp3', bitrate='192k')

    except ImportError:
        print('[tts-gemini] 错误: 需要安装 pydub: pip install pydub')
        return False
    except Exception as e:
        print(f'[tts-gemini] 转换音频失败: {e}')
        return False

    file_size = os.path.getsize(output_path)
    print(f'[tts-gemini] 生成音频: {output_path} ({file_size / 1024 / 1024:.2f} MB)')
    return True


def split_text_for_google_tts(text: str, max_bytes: int = 4500) -> List[str]:
    """
    将文本按句子分割，每块不超过 max_bytes 字节

    Google TTS API 限制每次请求最多 5000 字节
    """
    import re

    # 按句子分割（句号、问号、感叹号后跟空格或换行）
    sentences = re.split(r'(?<=[.!?])\s+', text)

    chunks = []
    current_chunk = ""

    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue

        # 检查添加这个句子后是否超过限制
        test_chunk = current_chunk + " " + sentence if current_chunk else sentence

        if len(test_chunk.encode('utf-8')) <= max_bytes:
            current_chunk = test_chunk
        else:
            # 保存当前块，开始新块
            if current_chunk:
                chunks.append(current_chunk)
            # 如果单个句子就超过限制，需要强制分割
            if len(sentence.encode('utf-8')) > max_bytes:
                # 按字符分割
                words = sentence.split()
                current_chunk = ""
                for word in words:
                    test = current_chunk + " " + word if current_chunk else word
                    if len(test.encode('utf-8')) <= max_bytes:
                        current_chunk = test
                    else:
                        if current_chunk:
                            chunks.append(current_chunk)
                        current_chunk = word
            else:
                current_chunk = sentence

    # 保存最后一块
    if current_chunk:
        chunks.append(current_chunk)

    return chunks


async def generate_tts_audio(text: str, output_path: str, engine: str = None) -> bool:
    """
    生成 TTS 音频（统一入口）

    Args:
        text: 要朗读的文本
        output_path: 输出音频文件路径
        engine: TTS 引擎，"edge"、"google" 或 "gemini"，默认使用 TTS_ENGINE 配置

    Returns:
        是否成功
    """
    engine = engine or TTS_ENGINE

    if engine == "gemini":
        return await generate_tts_audio_gemini(text, output_path)
    elif engine == "google":
        return await generate_tts_audio_google(text, output_path)
    else:
        return await generate_tts_audio_edge(text, output_path)


async def generate_all_tts(segments: List[Dict[str, Any]], output_dir: str, engine: str = None) -> List[Dict[str, Any]]:
    """
    为所有片段生成 TTS 音频

    Args:
        segments: 片段列表
        output_dir: 输出目录
        engine: TTS 引擎 ("edge" 或 "google")
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    engine = engine or TTS_ENGINE
    print(f'[tts] 使用引擎: {engine}')

    for segment in segments:
        audio_path = output_path / f"{segment['id']}.mp3"

        if audio_path.exists():
            print(f'[tts] 跳过已存在: {audio_path}')
            segment['audio_path'] = str(audio_path)
            continue

        print(f'[tts] 正在生成: {segment["id"]} ({segment["word_count"]} 词)...')
        success = await generate_tts_audio(segment['content'], str(audio_path), engine=engine)

        if success:
            segment['audio_path'] = str(audio_path)
        else:
            print(f'[tts] 失败: {segment["id"]}')

    return segments


# ============ 第三步：WhisperX 转录 ============

async def transcribe_audio(audio_path: str) -> List[Dict[str, Any]]:
    """
    使用 WhisperX 转录音频，获取分句和时间戳

    Returns:
        [{"text": "...", "start": 0.0, "end": 1.5}, ...]
    """
    try:
        result = await _process_audio_file(Path(audio_path))
        return result.get('segments', [])
    except Exception as e:
        print(f'[whisperx] 转录失败: {e}')
        return []


async def transcribe_all(segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    转录所有音频片段
    """
    for segment in segments:
        audio_path = segment.get('audio_path')
        if not audio_path:
            print(f'[whisperx] 跳过无音频: {segment["id"]}')
            continue

        print(f'[whisperx] 正在转录: {segment["id"]}...')
        transcription = await transcribe_audio(audio_path)

        if transcription:
            segment['segments'] = transcription
            print(f'[whisperx] 完成: {segment["id"]} ({len(transcription)} 句)')
        else:
            print(f'[whisperx] 失败: {segment["id"]}')

    return segments


# ============ 第四步：翻译 ============

async def translate_all(segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    翻译所有片段的 segments
    """
    for segment in segments:
        whisper_segments = segment.get('segments', [])
        if not whisper_segments:
            print(f'[translate] 跳过无转录: {segment["id"]}')
            continue

        print(f'[translate] 正在翻译: {segment["id"]} ({len(whisper_segments)} 句)...')

        try:
            translations = await translate_segments(whisper_segments)

            # 将翻译结果合并到 segments
            for i, trans in enumerate(translations):
                if i < len(whisper_segments):
                    whisper_segments[i]['translation'] = trans

            print(f'[translate] 完成: {segment["id"]}')
        except Exception as e:
            print(f'[translate] 失败: {segment["id"]}: {e}')

    return segments


# ============ 第五步：上传 ============



def get_audio_duration(audio_path: str) -> int:
    """获取音频时长（秒）"""
    try:
        from pydub import AudioSegment
        audio = AudioSegment.from_file(audio_path)
        return int(len(audio) / 1000)
    except Exception:
        try:
            from mutagen import File
            audio = File(audio_path)
            return int(audio.info.length) if audio else 0
        except Exception:
            return 0

async def upload_segment(
    segment: Dict[str, Any],
    company: str,
    channel: str,
    server_url: str
) -> bool:
    """
    上传单个片段到 COS 和服务端
    """
    try:
        segment_id = segment['id']
        audio_path = segment.get('audio_path')
        whisper_segments = segment.get('segments', [])

        if not audio_path or not whisper_segments:
            print(f'[upload] 跳过不完整: {segment_id}')
            return False

        print(f'\n[upload] 开始上传: {segment_id}')

        # 获取音频时长
        duration = get_audio_duration(audio_path)

        # 初始化服务
        cos_service = COSService()
        current_timestamp = int(datetime.now(timezone.utc).timestamp())

        # 上传音频
        audio_key = cos_service.upload_audio_from_file(
            file_path=audio_path,
            podcast_id=segment_id,
            channel=channel,
            timestamp=current_timestamp
        )

        # 准备 segments（添加 id）
        final_segments = []
        for i, seg in enumerate(whisper_segments):
            final_segments.append({
                'id': i,
                'start': seg.get('start', 0),
                'end': seg.get('end', 0),
                'text': seg.get('text', ''),
                'translation': seg.get('translation', ''),
            })

        # 上传 segments JSON
        segments_key = cos_service.upload_segments_json(
            podcast_id=segment_id,
            segments=final_segments,
            channel=channel,
            timestamp=current_timestamp
        )

        # 翻译标题
        title_en = segment.get('title', '')
        title_cn = None
        try:
            print(f'[upload] 翻译标题: {title_en}')
            translator = await get_translator()
            title_translations = await translator.translate_batch(
                [title_en],
                source_lang='en',
                target_lang='zh',
                use_reflection=True,
                use_context=False,
                use_full_context=False
            )
            if title_translations and title_translations[0]:
                title_cn = title_translations[0]
                print(f'[upload] 标题翻译完成: {title_cn}')
        except Exception as e:
            print(f'[upload] 标题翻译失败: {e}')
            title_cn = title_en  # 失败时使用原标题

        # 如果有多个部分，添加 Part 标记
        if segment.get('total_parts', 1) > 1:
            title_cn = f"{title_cn} (第{segment.get('part', 1)}部分)"

        podcast_data = {
            'id': segment_id,
            'company': company,
            'channel': channel,
            'audioKey': audio_key,
            'rawAudioUrl': '',
            'title': segment.get('title', ''),
            'titleTranslation': title_cn,
            'subtitle': '',
            'timestamp': current_timestamp,
            'language': 'en',
            'duration': duration,
            'segmentsKey': segments_key,
            'segmentCount': len(final_segments),
        }

        # 上传到服务端
        uploader = PodcastUploader(server_url=server_url)
        success = await uploader.upload_podcast(podcast_data)

        if success:
            print(f'[upload] 完成: {segment_id}')
        else:
            print(f'[upload] 上传服务端失败: {segment_id}')

        return success

    except Exception as e:
        print(f'[upload] 异常: {segment.get("id")}: {e}')
        return False


async def upload_all(
    segments: List[Dict[str, Any]],
    company: str,
    channel: str,
    server_url: str
) -> Dict[str, int]:
    """
    上传所有片段
    """
    success_count = 0
    fail_count = 0

    for segment in segments:
        if await upload_segment(segment, company, channel, server_url):
            success_count += 1
        else:
            fail_count += 1

    print(f'\n[upload] 上传完成: 成功 {success_count}, 失败 {fail_count}')
    return {'success': success_count, 'failed': fail_count}


# ============ 主流程 ============

async def process_book(
    book_path: str,
    output_dir: str,
    company: str = "Gutenberg",
    channel: str = "SherlockHolmes",
    server_url: str = None,
    max_words: int = DEFAULT_WORDS_PER_SEGMENT,
    split_chapters: bool = False,
    tts_engine: str = "edge",
    skip_tts: bool = False,
    skip_transcribe: bool = False,
    skip_translate: bool = False,
    skip_upload: bool = False,
    start_chapter: int = 1,
) -> bool:
    """
    处理整本书的主流程

    Args:
        book_path: 电子书文件路径
        output_dir: 输出目录
        company: 公司/来源
        channel: 频道名称
        server_url: 服务端 URL
        max_words: 每段最大字数（仅当 split_chapters=True 时生效）
        split_chapters: 是否按字数拆分章节
        skip_*: 跳过指定步骤
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    print(f'\n{"="*60}')
    print(f'电子书处理器')
    print(f'{"="*60}')
    print(f'输入: {book_path}')
    print(f'输出: {output_dir}')
    print(f'模式: {"按字数拆分章节 (~" + str(max_words) + " 词/段)" if split_chapters else "每章一个文件"}')
    print(f'{"="*60}\n')

    # 第一步：拆分
    print('[步骤 1] 拆分电子书...')
    segments = split_book(book_path, output_dir, max_words, split_chapters)

    # 获取 server_url
    if not server_url:
        server_url = os.getenv('SERVER_URL')

    # 逐章处理：TTS -> 转录 -> 翻译 -> 上传
    total = len(segments)
    success_count = 0
    fail_count = 0
    skipped_count = 0

    if start_chapter > 1:
        print(f'[info] 从第 {start_chapter} 章开始处理')

    for i, segment in enumerate(segments):
        chapter_num = i + 1

        # 跳过已完成的章节
        if chapter_num < start_chapter:
            skipped_count += 1
            continue

        segment_id = segment['id']
        print(f'\n{"="*60}')
        print(f'[{chapter_num}/{total}] 处理: {segment_id}')
        print(f'{"="*60}')

        audio_path = output_path / f"{segment_id}.mp3"

        # TTS
        if not skip_tts:
            if audio_path.exists():
                print(f'[tts] 跳过已存在: {audio_path}')
                segment['audio_path'] = str(audio_path)
            else:
                print(f'[tts] 生成音频 ({segment["word_count"]} 词)...')
                try:
                    success = await generate_tts_audio(segment['content'], str(audio_path), engine=tts_engine)
                    if success:
                        segment['audio_path'] = str(audio_path)
                    else:
                        print(f'[tts] 失败，跳过此章')
                        fail_count += 1
                        continue
                except QuotaExceededError as e:
                    print(f'\n{"!"*60}')
                    print(f'[tts] 配额超限，停止处理')
                    print(f'[tts] {e}')
                    print(f'[tts] 已完成 {success_count} 章，明天继续运行即可')
                    print(f'{"!"*60}')
                    return False
        else:
            if audio_path.exists():
                segment['audio_path'] = str(audio_path)
            else:
                print(f'[tts] 无音频文件，跳过此章')
                fail_count += 1
                continue

        # 转录
        if not skip_transcribe:
            print(f'[whisperx] 转录...')
            transcription = await transcribe_audio(segment['audio_path'])
            if transcription:
                segment['segments'] = transcription
                print(f'[whisperx] 完成: {len(transcription)} 句')
            else:
                print(f'[whisperx] 转录失败，跳过此章')
                fail_count += 1
                continue

        # 翻译
        if not skip_translate:
            whisper_segments = segment.get('segments', [])
            if whisper_segments:
                print(f'[translate] 翻译 {len(whisper_segments)} 句...')
                try:
                    translations = await translate_segments(whisper_segments)
                    for j, trans in enumerate(translations):
                        if j < len(whisper_segments):
                            whisper_segments[j]['translation'] = trans
                    print(f'[translate] 完成')
                except Exception as e:
                    print(f'[translate] 翻译失败: {e}，跳过此章')
                    fail_count += 1
                    continue

        # 上传
        if not skip_upload and server_url:
            print(f'[upload] 上传...')
            success = await upload_segment(segment, company, channel, server_url)
            if success:
                success_count += 1
                print(f'[{i+1}/{total}] ✓ 完成')
            else:
                fail_count += 1
                print(f'[{i+1}/{total}] ✗ 上传失败')
        else:
            success_count += 1
            print(f'[{i+1}/{total}] ✓ 完成（跳过上传）')

    print(f'\n{"="*60}')
    print(f'全部处理完成: 成功 {success_count}, 失败 {fail_count}')
    print(f'{"="*60}')

    print(f'\n{"="*60}')
    print(f'处理完成!')
    print(f'{"="*60}\n')

    return True


async def main():
    """命令行入口"""
    parser = argparse.ArgumentParser(
        description='电子书处理器 - 拆分、TTS、转录、翻译、上传',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument('book', help='电子书文件路径')
    parser.add_argument('--output', '-o', default='./book_output', help='输出目录')
    parser.add_argument('--company', default='Gutenberg', help='公司/来源')
    parser.add_argument('--channel', default='SherlockHolmes', help='频道名称')
    parser.add_argument('--server-url', help='服务端 URL')
    parser.add_argument('--max-words', type=int, default=DEFAULT_WORDS_PER_SEGMENT, help='每段最大字数（需配合 --split-chapters）')
    parser.add_argument('--split-chapters', action='store_true', help='按字数拆分章节（默认每章一个文件）')
    parser.add_argument('--tts-engine', choices=['edge', 'google', 'gemini'], default='edge', help='TTS 引擎: edge (免费), google (传统), gemini (最新)')
    parser.add_argument('--skip-tts', action='store_true', help='跳过 TTS 生成')
    parser.add_argument('--skip-transcribe', action='store_true', help='跳过转录')
    parser.add_argument('--skip-translate', action='store_true', help='跳过翻译')
    parser.add_argument('--skip-upload', action='store_true', help='跳过上传')
    parser.add_argument('--only-split', action='store_true', help='只做拆分，跳过其他所有步骤')
    parser.add_argument('--start-chapter', type=int, default=1, help='从第几章开始处理（默认1）')

    args = parser.parse_args()

    if not os.path.exists(args.book):
        print(f'错误: 文件不存在: {args.book}')
        return 1

    # --only-split 相当于跳过所有后续步骤
    if args.only_split:
        args.skip_tts = True
        args.skip_transcribe = True
        args.skip_translate = True
        args.skip_upload = True

    success = await process_book(
        book_path=args.book,
        output_dir=args.output,
        company=args.company,
        channel=args.channel,
        server_url=args.server_url,
        max_words=args.max_words,
        split_chapters=args.split_chapters,
        tts_engine=args.tts_engine,
        skip_tts=args.skip_tts,
        skip_transcribe=args.skip_transcribe,
        skip_translate=args.skip_translate,
        skip_upload=args.skip_upload,
        start_chapter=args.start_chapter,
    )

    return 0 if success else 1


if __name__ == '__main__':
    exit_code = asyncio.run(main())
    exit(exit_code)
