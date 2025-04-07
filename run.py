#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
AutoTalk-Python 启动脚本
"""

import os
import sys
from pathlib import Path

# 设置编码确保正确处理中文
if sys.platform == 'win32':
    os.environ['PYTHONIOENCODING'] = 'utf-8'
    try:
        import ctypes
        k_handle = ctypes.windll.kernel32
        k_handle.SetConsoleCP(65001)  # 设置控制台输入代码页为UTF-8
        k_handle.SetConsoleOutputCP(65001)  # 设置控制台输出代码页为UTF-8
        
        # 设置stdin/stdout为阻塞模式，避免Windows控制台的EOF问题
        import msvcrt
        msvcrt.setmode(sys.stdin.fileno(), os.O_BINARY)
        msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)
        
        # 重新配置I/O
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stdin.reconfigure(encoding='utf-8')
    except Exception as e:
        print(f"设置控制台编码失败: {e}")

# 确保可以导入src目录
sys.path.append(str(Path(__file__).parent / "src"))

# 导入main模块
from src.main import main

if __name__ == "__main__":
    # 确保存在所需的目录
    os.makedirs("models", exist_ok=True)
    os.makedirs("logs", exist_ok=True)
    os.makedirs("recordings", exist_ok=True)
    
    # 启动程序
    sys.exit(main()) 