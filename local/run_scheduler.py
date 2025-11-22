#!/usr/bin/env python3
"""Entry point for scheduler"""
import sys
import os

project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)

from local.scheduler import start_scheduler

if __name__ == '__main__':
    start_scheduler()

