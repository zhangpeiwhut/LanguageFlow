"""
诊断失败的 VOA podcasts
测试处理一个失败的 podcast，查看具体失败原因
"""
import asyncio
import json
from pathlib import Path
from voa_processor import VoaProcessor, VOA_STATE_FILE
import traceback

async def diagnose_failed_podcast():
    """诊断一个失败的 podcast"""

    # 读取当前状态
    if not VOA_STATE_FILE.exists():
        print("[diagnose] 未找到状态文件")
        return

    with open(VOA_STATE_FILE, 'r', encoding='utf-8') as f:
        state = json.load(f)

    downloaded = set(state.get('downloaded', {}).keys())
    processed = set(state.get('processed', {}).keys())

    # 找出失败的 podcast IDs
    failed_ids = list(downloaded - processed)

    if not failed_ids:
        print("[diagnose] 没有失败的 podcasts")
        return

    print(f"[diagnose] 找到 {len(failed_ids)} 个失败的 podcasts")

    # 选择第一个失败的 podcast 进行诊断
    test_id = failed_ids[0]
    print(f"\n[diagnose] 选择诊断: {test_id}")

    processor = VoaProcessor(csv_path="voa_podcasts.csv")

    # 加载所有 podcasts
    all_podcasts = processor.load_podcasts_from_csv()

    # 找到这个 podcast
    test_podcast = None
    for p in all_podcasts:
        if p['id'] == test_id:
            test_podcast = p
            break

    if not test_podcast:
        print(f"[diagnose] 未找到 podcast: {test_id}")
        return

    print(f"\n[diagnose] Podcast 信息:")
    print(f"  标题: {test_podcast.get('title')}")
    print(f"  频道: {test_podcast.get('channel')}")
    print(f"  时长: {test_podcast.get('duration')} 秒")
    print(f"  URL: {test_podcast.get('audioURL')}")

    # 检查音频文件
    audio_path = Path(state['downloaded'][test_id])
    if audio_path.exists():
        file_size = audio_path.stat().st_size / 1024 / 1024  # MB
        print(f"  音频文件: ✓ 存在 ({file_size:.2f} MB)")
    else:
        print(f"  音频文件: ✗ 不存在")
        return

    print(f"\n[diagnose] 开始测试处理...\n")
    print("=" * 60)

    # 尝试处理并捕获详细错误
    try:
        # 1. 测试转录
        print("\n[diagnose] 步骤 1: 测试转录...")
        from whisperx_service import _process_audio_file

        try:
            transcription_result = await _process_audio_file(audio_path)
            segments = transcription_result.get('segments', [])
            detected_language = transcription_result.get('language', 'en')
            print(f"[diagnose] ✓ 转录成功：{len(segments)} 个片段，语言: {detected_language}")

            # 显示前 3 个 segment
            print(f"\n[diagnose] 前 3 个 segments:")
            for i, seg in enumerate(segments[:3]):
                print(f"  [{i+1}] {seg.get('text', '')[:80]}")

        except Exception as e:
            print(f"[diagnose] ✗ 转录失败:")
            print(f"  错误类型: {type(e).__name__}")
            print(f"  错误信息: {str(e)}")
            print(f"\n[diagnose] 详细堆栈:")
            traceback.print_exc()
            return

        # 2. 测试翻译
        print(f"\n[diagnose] 步骤 2: 测试翻译 {len(segments)} 个片段...")
        from translator import translate_segments

        try:
            translations = await translate_segments(
                segments,
                source_lang=detected_language,
                target_lang='zh',
                use_context=True,
                use_full_context=True
            )
            success_count = sum(1 for t in translations if t)
            print(f"[diagnose] ✓ 翻译成功：{success_count}/{len(segments)} 段")

            # 显示前 3 个翻译
            print(f"\n[diagnose] 前 3 个翻译:")
            for i in range(min(3, len(translations))):
                print(f"  [{i+1}] 原文: {segments[i].get('text', '')[:60]}")
                print(f"      译文: {translations[i][:60] if translations[i] else '(空)'}")

        except Exception as e:
            print(f"[diagnose] ✗ 翻译失败:")
            print(f"  错误类型: {type(e).__name__}")
            print(f"  错误信息: {str(e)}")
            print(f"\n[diagnose] 详细堆栈:")
            traceback.print_exc()
            return

        # 3. 测试标题翻译
        print(f"\n[diagnose] 步骤 3: 测试标题翻译...")
        title = test_podcast.get('title')
        if title:
            try:
                from translator import get_translator
                translator = await get_translator()
                title_translations = await translator.translate_batch(
                    [title],
                    source_lang=detected_language,
                    target_lang='zh',
                    use_reflection=True,
                    use_context=False,
                    use_full_context=False
                )
                if title_translations and title_translations[0]:
                    print(f"[diagnose] ✓ 标题翻译成功:")
                    print(f"  原标题: {title}")
                    print(f"  译标题: {title_translations[0]}")
                else:
                    print(f"[diagnose] ⚠ 标题翻译为空")
            except Exception as e:
                print(f"[diagnose] ✗ 标题翻译失败:")
                print(f"  错误类型: {type(e).__name__}")
                print(f"  错误信息: {str(e)}")

        print(f"\n[diagnose] 所有步骤测试完成！")
        print(f"[diagnose] 结论: 这个 podcast 现在可以成功处理")
        print(f"\n[diagnose] 建议: 运行 'python voa_retry_failed.py' 重新处理所有失败的 podcasts")

    except Exception as e:
        print(f"\n[diagnose] ✗ 处理过程中出现未预期的错误:")
        print(f"  错误类型: {type(e).__name__}")
        print(f"  错误信息: {str(e)}")
        print(f"\n[diagnose] 详细堆栈:")
        traceback.print_exc()


async def main():
    """主函数"""
    print("=" * 60)
    print("VOA 失败 Podcasts 诊断工具")
    print("=" * 60)

    await diagnose_failed_podcast()


if __name__ == '__main__':
    asyncio.run(main())
