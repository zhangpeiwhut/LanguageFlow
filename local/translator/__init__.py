"""Translator包 - 翻译服务模块"""
from .translator import Translator, translate_segments, get_translator
from .models import BaseModelProvider, AlibabaModelProvider, XYKSModelProvider

__all__ = [
    'Translator',
    'translate_segments',
    'get_translator',
    'BaseModelProvider',
    'AlibabaModelProvider',
    'XYKSModelProvider',
]

