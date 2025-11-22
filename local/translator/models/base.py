"""模型提供器基类，定义模型调用接口和翻译业务逻辑"""
import asyncio
from abc import ABC, abstractmethod
from .prompts import PromptBuilder
from .utils import TranslationLogger

class BaseModelProvider(ABC):    
    def __init__(self):
        self.logger = TranslationLogger()
    
    @abstractmethod
    async def call_model(self, prompt: str) -> str:
        """
        调用模型API（抽象方法，子类必须实现）
        
        这是唯一需要子类实现的方法，负责：
        - 调用具体的模型API
        - 解析API响应
        - 返回模型生成的文本
        
        Args:
            prompt: 完整的提示词（已包含所有翻译指令和上下文）
        
        Returns:
            模型生成的文本
        """
        pass
    
    async def translate(self, text: str, source_lang: str = 'auto', target_lang: str = 'zh') -> str:
        prompt = PromptBuilder.build_simple_prompt(text)
        return await self.call_model(prompt)
    
    async def translate_batch(self, texts: list[str], source_lang: str = 'auto', 
                             target_lang: str = 'zh', use_reflection: bool = True,
                             use_context: bool = True, context_window: int = 2,
                             use_full_context: bool = True, **kwargs) -> list[str]:
        if not texts:
            return []
        # 如果禁用上下文或只有一段文本，使用逐句翻译
        if not use_context or len(texts) == 1:
            semaphore = asyncio.Semaphore(5)
            
            async def translate_one(text: str):
                async with semaphore:
                    if use_reflection:
                        # 使用自我反思机制
                        initial_prompt = PromptBuilder.build_simple_prompt(text)
                        initial = await self.call_model(initial_prompt)
                        if len(text) < 50:
                            return initial.strip()
                        try:
                            reflection_prompt = PromptBuilder.build_reflection_prompt(text, initial)
                            optimized = await self.call_model(reflection_prompt)
                            if optimized and len(optimized) > len(initial) * 0.8:
                                return optimized.strip()
                            return initial.strip()
                        except Exception as e:
                            self.logger.log('warn', f'翻译反思步骤失败，使用初步翻译: {e}')
                            return initial.strip()
                    else:
                        prompt = PromptBuilder.build_simple_prompt(text)
                        return await self.call_model(prompt)
            
            tasks = [translate_one(text) for text in texts]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            return self._process_batch_results(results, texts)
        
        # 使用全文背景模式
        if use_full_context:
            full_text = ' '.join(texts)
            
            # 优先使用"总结+滑动窗口"模式
            self.logger.log('info', f'使用"总结+滑动窗口"翻译模式（全文长度: {len(full_text)}字符，{len(texts)}个片段）')
            try:
                return await self._translate_with_summary_and_window(
                    texts, full_text, source_lang, target_lang, context_window=context_window
                )
            except Exception as e:
                self.logger.log('warn', f'总结+滑动窗口翻译失败，回退到传统模式: {e}')
            
            # 传统模式：每个片段都发送全文（或使用滑动窗口）
            semaphore = asyncio.Semaphore(3)
            
            async def translate_with_full_ctx(idx: int, txt: str):
                async with semaphore:
                    if not txt or not txt.strip():
                        return ''
                    
                    if len(full_text) > 5000:
                        if idx == 0:
                            self.logger.log('info', f'全文较长（{len(full_text)}字符），使用滑动窗口上下文模式')
                        start_idx = max(0, idx - 3)
                        end_idx = min(len(texts), idx + 4)
                        context_before = ' '.join(texts[start_idx:idx]) if idx > 0 else ''
                        context_after = ' '.join(texts[idx+1:end_idx]) if idx < len(texts) - 1 else ''
                        prompt = PromptBuilder.build_context_prompt(txt, context_before, context_after)
                        return await self.call_model(prompt)
                    else:
                        prompt = PromptBuilder.build_full_context_prompt(txt, full_text)
                        return await self.call_model(prompt)
            
            tasks = [translate_with_full_ctx(i, text) for i, text in enumerate(texts)]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            return self._process_batch_results(results, texts)
        
        # 使用滑动窗口上下文模式
        translated = []
        semaphore = asyncio.Semaphore(3)
        
        for i, text in enumerate(texts):
            if not text or not text.strip():
                translated.append('')
                continue
            
            start_idx = max(0, i - context_window)
            end_idx = min(len(texts), i + context_window + 1)
            context_before = ' '.join(texts[start_idx:i]) if i > 0 else ''
            context_after = ' '.join(texts[i+1:end_idx]) if i < len(texts) - 1 else ''
            
            async def translate_with_ctx(idx: int, txt: str, before: str, after: str):
                async with semaphore:
                    prompt = PromptBuilder.build_context_prompt(txt, before, after)
                    return await self.call_model(prompt)
            
            result = await translate_with_ctx(i, text, context_before, context_after)
            translated.append(result.strip() if result else '')
        
        return translated
    
    async def _translate_with_summary_and_window(self, texts: list[str], full_text: str,
                                                 source_lang: str, target_lang: str,
                                                 context_window: int = 2) -> list[str]:
        """使用总结+滑动窗口的翻译方式（通用实现）"""
        if not texts:
            return []
        
        self.logger.log('info', f'开始"总结+滑动窗口"翻译模式（共{len(texts)}段，全文{len(full_text)}字符）')
        
        # 生成全文总结
        summary_prompt = PromptBuilder.build_summary_prompt(full_text)
        try:
            summary = await self.call_model(summary_prompt)
            self.logger.log('info', f'全文总结生成成功（长度: {len(summary)}字符）')
        except Exception as e:
            self.logger.log('warn', f'全文总结生成失败: {e}，将使用空总结继续翻译')
            summary = "（无法生成总结，直接翻译）"
        
        if not summary:
            summary = "（无法生成总结，直接翻译）"
        
        # 使用总结+滑动窗口并发翻译所有片段
        semaphore = asyncio.Semaphore(5)
        
        async def translate_with_window(idx: int, txt: str):
            async with semaphore:
                if not txt or not txt.strip():
                    return ''
                
                start_idx = max(0, idx - context_window)
                end_idx = min(len(texts), idx + context_window + 1)
                context_before = ' '.join(texts[start_idx:idx]) if idx > 0 else ''
                context_after = ' '.join(texts[idx+1:end_idx]) if idx < len(texts) - 1 else ''
                
                prompt = PromptBuilder.build_sliding_window_prompt(
                    txt, summary, context_before, context_after
                )
                
                try:
                    result = await self.call_model(prompt)
                    if result and result.strip():
                        return result.strip()
                    else:
                        self.logger.log('warn', f'第 {idx+1} 段翻译返回空结果')
                        return ''
                except Exception as e:
                    self.logger.log('warn', f'第 {idx+1} 段翻译失败: {e}')
                    return ''
        
        tasks = [translate_with_window(i, text) for i, text in enumerate(texts)]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        translated = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                self.logger.log('warn', f'第 {i+1} 段翻译异常: {result}')
                translated.append('')
            else:
                translated.append(result)
        
        success_count = sum(1 for t in translated if t)
        self.logger.log('info', f'总结+滑动窗口翻译完成：{success_count}/{len(texts)} 段成功')
        
        return translated
    
    def _process_batch_results(self, results: list, texts: list[str]) -> list[str]:
        """处理批量翻译结果，统计并记录日志（通用实现）"""
        translated = []
        success_count = 0
        fail_count = 0
        
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                translated.append('')
                fail_count += 1
            elif result and result.strip():
                translated.append(result.strip())
                success_count += 1
            else:
                translated.append('')
                fail_count += 1
        
        total = len(texts)
        self.logger.log('info', f'翻译完成：成功 {success_count}/{total} ({success_count*100//total if total > 0 else 0}%)，失败 {fail_count}/{total}')
        
        if fail_count > 0:
            failed_indices = [i+1 for i, r in enumerate(results) if isinstance(r, Exception) or not (r and r.strip())]
            self.logger.log('warn', f'失败的段落索引: {failed_indices[:10]}{"..." if len(failed_indices) > 10 else ""}')
        
        return translated
    
    async def close(self):
        """关闭模型提供器，释放资源"""
        pass
