#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
下载器模块，负责下载语音模型
"""

import os
import requests
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Callable
from tqdm import tqdm
from loguru import logger

# 模型信息
MODEL_INFO = {
    "ggml-tiny.bin": {
        "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
        "size": 75000000,  # 约75MB
        "description": "最小模型，速度最快但精度较低"
    },
    "ggml-base.bin": {
        "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
        "size": 142000000,  # 约142MB
        "description": "基础模型，速度和精度平衡"
    },
    "ggml-small.bin": {
        "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
        "size": 466000000,  # 约466MB
        "description": "小型模型，更高精度"
    },
    "ggml-medium.bin": {
        "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
        "size": 1500000000,  # 约1.5GB
        "description": "中型模型，更高精度"
    },
    "whisper-tiny": {
        "url": "dummy-url-for-downloading-via-whisper-cli",
        "size": 150000000,  # 约150MB
        "description": "OpenAI官方tiny模型，支持多语言"
    },
    "whisper-base": {
        "url": "dummy-url-for-downloading-via-whisper-cli", 
        "size": 290000000,  # 约290MB
        "description": "OpenAI官方base模型，支持多语言"
    },
    "whisper-small": {
        "url": "dummy-url-for-downloading-via-whisper-cli",
        "size": 970000000,  # 约970MB
        "description": "OpenAI官方small模型，支持多语言"
    }
}

class ModelDownloader:
    """模型下载器，负责下载和管理语音模型"""
    
    def __init__(self, models_dir: str = "models"):
        """初始化下载器
        
        Args:
            models_dir: 模型存储目录
        """
        self.models_dir = Path(models_dir)
        os.makedirs(self.models_dir, exist_ok=True)
    
    def get_available_models(self) -> Dict[str, Dict]:
        """获取可用的模型列表
        
        Returns:
            模型信息字典，包括是否已下载
        """
        result = {}
        
        for model_name, info in MODEL_INFO.items():
            model_path = self.models_dir / model_name
            result[model_name] = {
                **info,
                "downloaded": model_path.exists(),
                "path": str(model_path)
            }
        
        return result
    
    def download_model(self, model_name: str, progress_callback: Optional[Callable[[float], None]] = None) -> bool:
        """下载指定模型
        
        Args:
            model_name: 模型名称
            progress_callback: 进度回调函数，参数为0-1之间的下载进度
        
        Returns:
            下载是否成功
        """
        if model_name not in MODEL_INFO:
            logger.error(f"未知模型: {model_name}")
            return False
        
        model_info = MODEL_INFO[model_name]
        
        # 处理OpenAI Whisper原生模型
        if model_name.startswith("whisper-"):
            try:
                # 检查是否已存在
                whisper_size = model_name.split("-")[1]  # tiny, base, small等
                import whisper
                whisper_model_dir = os.path.join(os.path.expanduser("~"), ".cache", "whisper")
                
                if os.path.exists(whisper_model_dir):
                    pattern = f"*{whisper_size}*.pt"
                    import glob
                    existing_models = glob.glob(os.path.join(whisper_model_dir, pattern))
                    
                    if existing_models:
                        logger.info(f"已找到OpenAI Whisper {whisper_size}模型: {existing_models[0]}")
                        return True
                
                # 使用whisper库下载模型
                logger.info(f"使用whisper库下载{whisper_size}模型...")
                if progress_callback:
                    progress_callback(0.1)  # 模拟开始下载进度
                
                # 下载模型
                whisper.load_model(whisper_size)
                
                if progress_callback:
                    progress_callback(1.0)  # 完成下载进度
                
                logger.info(f"Whisper {whisper_size}模型下载完成")
                return True
                
            except Exception as e:
                logger.error(f"下载Whisper模型时出错: {e}")
                return False
        
        # 常规模型下载逻辑
        model_path = self.models_dir / model_name
        temp_path = self.models_dir / f"{model_name}.download"
        
        # 检查是否已下载
        if model_path.exists():
            logger.info(f"模型 {model_name} 已存在，无需下载")
            return True
        
        logger.info(f"开始下载模型 {model_name} 从 {model_info['url']}")
        
        try:
            # 发起请求
            response = requests.get(model_info['url'], stream=True)
            response.raise_for_status()
            
            # 获取文件大小
            total_size = int(response.headers.get('content-length', model_info['size']))
            
            # 使用tqdm创建进度条
            with open(temp_path, 'wb') as f, tqdm(
                desc=model_name,
                total=total_size,
                unit='B',
                unit_scale=True,
                unit_divisor=1024,
            ) as pbar:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        pbar.update(len(chunk))
                        
                        # 调用进度回调
                        if progress_callback:
                            progress = pbar.n / total_size
                            progress_callback(progress)
            
            # 下载完成后重命名
            shutil.move(temp_path, model_path)
            logger.info(f"模型 {model_name} 下载完成")
            return True
            
        except Exception as e:
            logger.error(f"下载模型 {model_name} 时出错: {e}")
            
            # 清理临时文件
            if temp_path.exists():
                os.remove(temp_path)
            
            return False 