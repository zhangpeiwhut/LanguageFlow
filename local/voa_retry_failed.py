"""
重新处理失败的 VOA podcasts
清理失败 podcasts 的状态，让它们重新处理
"""
import asyncio
import json
from pathlib import Path
from voa_processor import VoaProcessor, VOA_STATE_FILE

async def retry_failed_podcasts():
    """重新处理失败的 podcasts"""

    # 读取当前状态
    if not VOA_STATE_FILE.exists():
        print("[retry] 未找到状态文件")
        return

    with open(VOA_STATE_FILE, 'r', encoding='utf-8') as f:
        state = json.load(f)

    downloaded = set(state.get('downloaded', {}).keys())
    processed = set(state.get('processed', {}).keys())

    # 找出失败的 podcast IDs
    failed_ids = downloaded - processed

    if not failed_ids:
        print("[retry] 没有失败的 podcasts 需要重试")
        return

    print(f"[retry] 找到 {len(failed_ids)} 个失败的 podcasts")
    print(f"[retry] 失败的 IDs:")
    for podcast_id in failed_ids:
        print(f"  - {podcast_id}")

    # 询问用户确认
    print(f"\n[retry] 准备清理这些失败 podcasts 的状态并重新处理")
    confirm = input("[retry] 确认继续? (y/n): ").strip().lower()

    if confirm != 'y':
        print("[retry] 已取消")
        return

    # 清理失败 podcasts 的下载状态
    print(f"\n[retry] 清理失败 podcasts 的状态...")
    for podcast_id in failed_ids:
        if podcast_id in state['downloaded']:
            del state['downloaded'][podcast_id]
            print(f"[retry] 已清理: {podcast_id}")

    # 保存更新后的状态
    with open(VOA_STATE_FILE, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, indent=2)

    print(f"[retry] 状态已更新，共清理了 {len(failed_ids)} 个失败记录")

    # 现在重新处理这些 podcasts
    print(f"\n[retry] 开始重新处理这些 podcasts...")

    processor = VoaProcessor(csv_path="voa_podcasts.csv")

    # 加载所有 podcasts
    all_podcasts = processor.load_podcasts_from_csv()

    # 过滤出失败的 podcasts
    failed_podcasts = [p for p in all_podcasts if p['id'] in failed_ids]

    print(f"[retry] 找到 {len(failed_podcasts)} 个需要重新处理的 podcasts")

    # 逐个处理（串行，更稳定）
    successful = 0
    failed = 0

    for i, podcast in enumerate(failed_podcasts, 1):
        print(f"\n[retry] [{i}/{len(failed_podcasts)}] 处理: {podcast['title']}")

        try:
            result = await processor.process_podcast(podcast)
            if result:
                successful += 1
                print(f"[retry] ✓ 成功")
            else:
                failed += 1
                print(f"[retry] ✗ 失败")
        except Exception as e:
            failed += 1
            print(f"[retry] ✗ 异常: {e}")

    print(f"\n[retry] 重新处理完成:")
    print(f"  - 成功: {successful} 个")
    print(f"  - 失败: {failed} 个")

    if failed > 0:
        print(f"\n[retry] 注意: 仍有 {failed} 个 podcasts 处理失败")
        print(f"[retry] 可以再次运行此脚本重试")


async def main():
    """主函数"""
    print("=" * 60)
    print("VOA 失败 Podcasts 重试脚本")
    print("=" * 60)

    await retry_failed_podcasts()


if __name__ == '__main__':
    asyncio.run(main())
