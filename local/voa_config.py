"""VOA Processor 配置文件"""
from pathlib import Path

# 本地存档目录配置
VOA_ARCHIVE_DIR = Path(__file__).parent / "voa_archive"
VOA_AUDIO_DIR = VOA_ARCHIVE_DIR / "audio"
VOA_SEGMENTS_DIR = VOA_ARCHIVE_DIR / "segments"
VOA_METADATA_FILE = VOA_ARCHIVE_DIR / "metadata.json"
VOA_STATE_FILE = VOA_ARCHIVE_DIR / "processing_state.json"
