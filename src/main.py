#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
AutoTalk-Python 主程序入口
"""

import argparse
import sys
import os
import shutil
from pathlib import Path
from loguru import logger

from ui import run_app

# 创建一个小型演示模型文件
def create_demo_model(model_path):
    """创建一个简单的演示模型文件"""
    if os.path.exists(model_path):
        return
    
    # 检查是否为OpenAI Whisper模型
    if model_path.startswith("whisper-"):
        logger.info(f"使用OpenAI原生Whisper模型: {model_path}")
        return
    
    logger.info(f"创建演示模型: {model_path}")
    # 创建一个空模型文件，只是为了程序能够继续运行
    with open(model_path, 'wb') as f:
        # 写入一些二进制数据作为"模型"
        f.write(b'\x00' * 1024)

def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="AutoTalk - 实时语音转文字程序")
    parser.add_argument(
        "-m", "--model-path", 
        default="whisper-tiny",  # 改为使用OpenAI Whisper tiny模型
        help="Whisper模型路径或预设名称"
    )
    parser.add_argument(
        "-d", "--device", 
        help="录音设备名称，不指定则使用默认设备"
    )
    parser.add_argument(
        "-s", "--skip-download", 
        action="store_true",
        help="跳过检查和下载资源"
    )
    return parser.parse_args()

def setup_logger():
    """配置日志系统"""
    logger.remove()
    logger.add(sys.stderr, level="DEBUG")
    logger.add("logs/autotalk.log", rotation="10 MB", level="INFO")

def main():
    """主函数"""
    # 确保存在所需的目录
    os.makedirs("models", exist_ok=True)
    os.makedirs("logs", exist_ok=True)
    os.makedirs("recordings", exist_ok=True)

    # 设置日志
    setup_logger()
    
    # 解析命令行参数
    args = parse_args()
    
    # 处理模型路径
    model_path = args.model_path
    
    # 如果是OpenAI Whisper模型，直接使用原始路径
    if not model_path.startswith("whisper-"):
        # 非OpenAI Whisper模型，需要检查文件路径
        if not os.path.exists(model_path):
            # 如果不是whisper-开头且路径不存在，假设是models目录下的文件
            if not Path(model_path).is_absolute() and not model_path.startswith("models/"):
                model_path = os.path.join("models", model_path)
            
            # 如果模型不存在，创建演示模型
            if not os.path.exists(model_path):
                create_demo_model(model_path)
    
    logger.info("启动AutoTalk - 实时语音转文字程序")
    logger.info(f"使用模型: {model_path}")
    
    try:
        run_app(model_path, args.device, args.skip_download)
        logger.info("程序正常退出")
    except Exception as e:
        logger.error(f"程序异常退出: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main()) 