"""Scheduler for periodic podcast processing"""
import schedule
import time
import asyncio
import os
from .main import main


def run_scheduled_task():
    print(f'[scheduler] 执行定时任务: {time.strftime("%Y-%m-%d %H:%M:%S")}')    
    days = int(os.getenv('SCHEDULER_DAYS', '1'))
    upload = os.getenv('SCHEDULER_UPLOAD', 'true').lower() == 'true'
    server_url = os.getenv('SERVER_URL', 'http://localhost:8001')
    asyncio.run(main(
        days=days,
        upload=upload,
        server_url=server_url
    ))


def start_scheduler():
    """启动定时调度器"""
    schedule_time = os.getenv('SCHEDULER_TIME', '04:30')
    print(f'[scheduler] 启动定时调度器，执行时间: 每天 {schedule_time}')
    print(f'[scheduler] 配置:')
    print(f'  - 处理天数: {os.getenv("SCHEDULER_DAYS", "1")}')
    print(f'  - 是否上传: {os.getenv("SCHEDULER_UPLOAD", "true")}')
    print(f'  - 服务器URL: {os.getenv("SERVER_URL", "http://localhost:8001")}')
    schedule.every().day.at(schedule_time).do(run_scheduled_task)    
    if os.getenv('SCHEDULER_RUN_ONCE', 'false').lower() == 'true':
        print('[scheduler] 立即执行一次...')
        run_scheduled_task()
    print('[scheduler] 调度器运行中，按 Ctrl+C 退出...')
    try:
        while True:
            schedule.run_pending()
            time.sleep(60)  # 每分钟检查一次
    except KeyboardInterrupt:
        print('\n[scheduler] 调度器已停止')

if __name__ == '__main__':
    start_scheduler()

