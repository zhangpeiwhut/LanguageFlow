class PromptBuilder:    
    @staticmethod
    def get_base_principles() -> str:
        return """【遗忘之律】忘记英文的句法。忘记英文的语序。只记住它要说的事。
【重生之律】如果你是中国作者，面对中国读者，你会怎么讲这个故事？
【地道之律】追求地道的表达，而非字面翻译。中文有自己的韵律和节奏感。"""

    @staticmethod
    def build_simple_prompt(text: str) -> str:
        return f"""你是专业的中文母语翻译者。

## 翻译原则
{PromptBuilder.get_base_principles()}

## 翻译规则
1. 只输出翻译内容，不要添加任何解释或额外说明
2. 确保翻译流畅自然，符合中文表达习惯
3. 如果是口语化内容，保持口语化风格

---

【原文】
{text}

请直接输出中文翻译，不要添加任何标记或解释。"""
    
    @staticmethod
    def build_context_prompt(text: str, context_before: str = '', context_after: str = '') -> str:
        principles = PromptBuilder.get_base_principles()
        if context_before or context_after:
            prompt = f"""你是专业的中文母语翻译者。

## 翻译原则
{principles}
【真实之锚】数据一字不改，事实纹丝不动，逻辑完整移植，术语规范标注。

## 翻译规则
1. 只输出翻译内容，不要添加任何解释或额外说明
2. 结合上下文理解代词、指代关系
3. 保持术语翻译的一致性
4. 确保翻译流畅自然，符合中文表达习惯
5. 如果是口语化内容，保持口语化风格
6. 让读者感觉"写得真好"，而非"翻译得真好"

---

"""
            if context_before:
                prompt += f"【前文】{context_before}\n\n"
            prompt += f"【当前文本】{text}\n\n"
            if context_after:
                prompt += f"【后文】{context_after}\n\n"
            prompt += "请直接输出【当前文本】的中文翻译，不要翻译上下文部分，不要添加任何标记或解释。"
        else:
            prompt = PromptBuilder.build_simple_prompt(text)
        
        return prompt
    
    @staticmethod
    def build_full_context_prompt(text: str, full_text: str) -> str:
        """构建全文背景翻译提示词
        
        Args:
            text: 待翻译的当前文本片段
            full_text: 完整的原文（作为背景）
        
        Returns:
            格式化后的提示词
        """
        return f"""你是专业的中文母语翻译者。请将以下文本片段翻译成中文。

## 翻译原则
{PromptBuilder.get_base_principles()}

## 任务
1. 阅读完整原文只是为了理解语境和术语
2. **只翻译"当前片段"这一句话**
3. 结合完整原文的语境，准确理解代词、指代关系
4. 保持术语翻译的一致性

## 输出要求
- **只输出当前片段的中文翻译**
- **不要翻译完整原文**
- **不要添加任何标记、解释或额外内容**
- **必须输出翻译结果，不能为空**

---

【完整原文】（仅作背景参考，不要翻译）
{full_text}

---

【当前片段】（只翻译这一句话）
{text}

---

请直接输出【当前片段】的中文翻译："""
    
    @staticmethod
    def build_reflection_prompt(text: str, initial_translation: str) -> str:
        """构建自我反思优化提示词
        
        Args:
            text: 原文
            initial_translation: 初步翻译结果
        
        Returns:
            格式化后的提示词
        """
        return f"""你是专业的中文母语翻译者，需要优化以下翻译。

## 优化原则
【地道之律】追求地道的表达，而非字面翻译。中文有自己的韵律和节奏感。
【重生之律】如果你是中国作者，面对中国读者，你会怎么讲这个故事？
【检验标准】让读者感觉"写得真好"，而非"翻译得真好"。

---

【原文】
{text}

【初步翻译】
{initial_translation}

请评估翻译质量，如果发现可以改进的地方（如：不够地道、有翻译腔、不符合中文表达习惯），请直接输出优化后的翻译。如果翻译已经很好，请直接输出原译文。

只输出最终的中文翻译，不要添加任何评价、解释或标记。"""
    
    @staticmethod
    def build_session_init_prompt(full_text: str) -> str:
        """构建会话初始化提示词，发送全文建立上下文
        
        Args:
            full_text: 完整原文
        
        Returns:
            格式化后的提示词
        """
        return f"""我将为你提供一篇完整的英文文章，请你先阅读并理解全文的语境和背景。

## 翻译原则
{PromptBuilder.get_base_principles()}
【真实之锚】数据一字不改，事实纹丝不动，逻辑完整移植，术语规范标注。

## 任务说明
1. 仔细阅读以下完整原文，理解全文的语境、主题和术语
2. 记住关键术语和专有名词的翻译
3. 理解文章的整体逻辑和结构
4. 准备好翻译这篇文章的各个片段

## 重要提示
- 现在只需要阅读和理解，不需要翻译
- 我会在后续消息中逐个发送片段，请你翻译每个片段
- 翻译时要结合全文语境，保持术语一致性
- 每个片段只输出该片段的中文翻译，不要添加任何标记或解释

---

【完整原文】
{full_text}

---

请回复"已理解全文，准备好开始翻译"，然后我会逐个发送片段给你翻译。"""
    
    @staticmethod
    def build_session_segment_prompt(text: str, segment_num: int, total_segments: int) -> str:
        """构建会话中单个片段的翻译提示词

        Args:
            text: 待翻译的文本片段
            segment_num: 片段序号（从1开始）
            total_segments: 总片段数

        Returns:
            格式化后的提示词
        """
        return f"""请翻译第 {segment_num}/{total_segments} 个片段：

【片段 {segment_num}】
{text}

请直接输出该片段的中文翻译，不要添加任何标记、序号或解释。"""

    @staticmethod
    def build_summary_prompt(full_text: str) -> str:
        """构建全文总结提示词

        Args:
            full_text: 完整原文

        Returns:
            格式化后的提示词
        """
        return f"""请阅读以下英文文章，并提供一个简洁的总结（150字以内），包括：
1. 文章主题和核心内容
2. 关键人物、地点、事件
3. 重要的专有名词和术语（保留英文原词）

请用中文输出总结，简明扼要即可。

---

【完整原文】
{full_text}

---

请直接输出总结："""

    @staticmethod
    def build_sliding_window_prompt(text: str, summary: str, context_before: str = '', context_after: str = '') -> str:
        """构建基于总结和滑动窗口的翻译提示词

        Args:
            text: 待翻译的当前文本片段
            summary: 全文总结
            context_before: 前文上下文（1-2段）
            context_after: 后文上下文（1-2段）

        Returns:
            格式化后的提示词
        """
        prompt = f"""你是专业的中文母语翻译者。

## 翻译原则
{PromptBuilder.get_base_principles()}

## 文章背景
{summary}

## 翻译任务
请翻译【当前文本】，结合文章背景和上下文，确保：
1. 只输出【当前文本】的中文翻译
2. 术语翻译与全文保持一致
3. 准确理解代词和指代关系
4. 保持口语化风格（如果是对话）
5. 不要添加任何标记或解释

---
"""

        if context_before:
            prompt += f"\n【前文参考】（不要翻译）\n{context_before}\n"

        prompt += f"\n【当前文本】（只翻译这部分）\n{text}\n"

        if context_after:
            prompt += f"\n【后文参考】（不要翻译）\n{context_after}\n"

        prompt += "\n---\n\n请直接输出【当前文本】的中文翻译："

        return prompt

