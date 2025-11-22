"""翻译服务主模块"""
import os
from typing import Optional
from .models import BaseModelProvider, AlibabaModelProvider, XYKSModelProvider

class Translator:
    """翻译器类，支持多个提供商"""
    
    def __init__(self, provider: Optional[str] = None, **kwargs):
        """
        初始化翻译器
        
        Args:
            provider: 翻译提供商（'alibaba' 或 'xyks'），默认从环境变量读取
            **kwargs: 传递给具体提供商的参数
        """
        provider = provider or os.getenv('TRANSLATOR_PROVIDER', 'xyks')
        if provider == 'alibaba':
            self._impl: BaseModelProvider = AlibabaModelProvider(**kwargs)
        elif provider == 'xyks':
            self._impl: BaseModelProvider = XYKSModelProvider(**kwargs)
        else:
            raise ValueError(f"不支持的翻译器提供商: {provider}。支持的提供商: alibaba, xyks")
        self.provider = provider
    
    async def close(self):
        """关闭翻译器，释放资源"""
        await self._impl.close()
    
    async def translate_batch(
        self, 
        texts: list[str], 
        source_lang: str = 'auto', 
        target_lang: str = 'zh', 
        use_reflection: bool = True,
        use_context: bool = True, 
        context_window: int = 2,
        use_full_context: bool = True, 
        **kwargs
    ) -> list[str]:
        """
        批量翻译文本
        
        Args:
            texts: 待翻译的文本列表
            source_lang: 源语言，默认'auto'（自动检测）
            target_lang: 目标语言，默认'zh'（中文）
            use_reflection: 是否使用自我反思机制，默认True
            use_context: 是否使用上下文，默认True
            context_window: 上下文窗口大小，默认2
            use_full_context: 是否使用全文上下文，默认True
            **kwargs: 其他参数
        
        Returns:
            翻译后的文本列表
        """
        return await self._impl.translate_batch(
            texts,
            source_lang,
            target_lang,
            use_reflection=use_reflection,
            use_context=use_context,
            context_window=context_window,
            use_full_context=use_full_context,
            **kwargs
        )


# 全局翻译器实例（单例模式）
_translator: Optional[Translator] = None


async def get_translator() -> Translator:
    """
    获取全局翻译器实例（单例模式）
    
    Returns:
        Translator实例
    """
    global _translator
    if _translator is None:
        provider = os.getenv('TRANSLATOR_PROVIDER', 'xyks')
        _translator = Translator(provider=provider)
    return _translator


async def translate_segments(
    segments: list[dict], 
    source_lang: str = 'auto', 
    target_lang: str = 'zh', 
    use_context: bool = True,
    use_full_context: bool = True, 
    context_window: int = 2
) -> list[str]:
    """
    翻译segments中的文本（便捷函数）
    
    Args:
        segments: 包含text字段的segment字典列表
        source_lang: 源语言，默认'auto'
        target_lang: 目标语言，默认'zh'
        use_context: 是否使用上下文，默认True
        use_full_context: 是否使用全文上下文，默认True
        context_window: 上下文窗口大小，默认2
    
    Returns:
        翻译后的文本列表，与segments顺序对应
    """
    texts = [seg.get('text', '') for seg in segments]
    translator = await get_translator()
    return await translator.translate_batch(
        texts, 
        source_lang, 
        target_lang, 
        use_reflection=True,
        use_context=use_context,
        use_full_context=use_full_context,
        context_window=context_window
    )

