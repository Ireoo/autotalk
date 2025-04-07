#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
语音转录模块，负责将音频转换为文本
"""

import os
import time
import tempfile
import threading
import numpy as np
from typing import Optional, Callable, List, Dict
from pathlib import Path
from loguru import logger

# 尝试导入不同的whisper实现
try:
    # 优先使用whisper-cpp-python (C++实现，更快)
    import whisper_cpp
    WHISPER_IMPL = "cpp"
    logger.info("使用whisper-cpp-python实现")
except ImportError:
    try:
        # 如果没有C++实现，使用OpenAI的Python实现
        import whisper
        WHISPER_IMPL = "python"
        logger.info("使用OpenAI whisper实现")
    except ImportError:
        logger.error("无法导入任何whisper实现，将使用模拟实现")
        WHISPER_IMPL = "mock"

class MockTranscriber:
    """Whisper不可用时的模拟转录器"""
    
    def __init__(self, model_path: str):
        """初始化模拟转录器"""
        self.model_path = model_path
        self.language = "zh"
        self.translate = False
        self.is_loaded = True
        self.is_processing = False
        logger.warning(f"使用模拟转录器，功能受限。使用的模型路径: {model_path}")
    
    def load_model(self) -> bool:
        """模拟加载模型"""
        return True
    
    def set_language(self, language: str):
        """设置语言"""
        self.language = language
        logger.info(f"设置语言: {language} (模拟)")
    
    def set_translate(self, translate: bool):
        """设置翻译选项"""
        self.translate = translate
        logger.info(f"设置翻译: {translate} (模拟)")
    
    def transcribe_file(self, audio_file: str) -> str:
        """模拟转录文件"""
        logger.info(f"模拟转录文件: {audio_file}")
        
        # 返回模拟的转录结果
        time.sleep(1)  # 模拟处理时间
        
        if not os.path.exists(audio_file):
            return "错误：音频文件不存在"
            
        results = {
            "zh": "这是一个模拟的转录结果。未安装Whisper库，无法进行真实转录。请安装whisper-cpp-python或openai-whisper库。",
            "en": "This is a mock transcription result. Whisper library is not installed, cannot perform real transcription. Please install whisper-cpp-python or openai-whisper library.",
            "ja": "これはモック転写結果です。Whisperライブラリがインストールされていないため、実際の転写はできません。",
            "ko": "이것은 모의 전사 결과입니다. Whisper 라이브러리가 설치되지 않아 실제 전사를 수행할 수 없습니다.",
            "auto": "这是模拟的转录结果/This is a mock transcription result."
        }
        
        result = results.get(self.language, results["auto"])
        
        if self.translate:
            result = "Translation mode: " + result
            
        return result
    
    def transcribe_audio_data(self, audio_data: np.ndarray, sample_rate: int = 16000) -> str:
        """模拟转录音频数据"""
        logger.info("模拟转录音频数据")
        time.sleep(1)  # 模拟处理时间
        return self.transcribe_file("模拟音频数据")
    
    def transcribe_async(self, audio_file: str, callback: Callable[[str], None]):
        """模拟异步转录"""
        if self.is_processing:
            logger.warning("已有转录任务正在进行中")
            return
            
        def process_task():
            self.is_processing = True
            result = self.transcribe_file(audio_file)
            self.is_processing = False
            callback(result)
            
        thread = threading.Thread(target=process_task)
        thread.daemon = True
        thread.start()
        logger.info(f"模拟启动异步转录任务: {audio_file}")
    
    def get_available_languages(self) -> List[Dict[str, str]]:
        """获取可用的语言列表"""
        languages = [
            {"code": "zh", "name": "中文"},
            {"code": "en", "name": "英文"},
            {"code": "ja", "name": "日文"},
            {"code": "ko", "name": "韩文"},
            {"code": "ru", "name": "俄文"},
            {"code": "fr", "name": "法文"},
            {"code": "de", "name": "德文"},
            {"code": "es", "name": "西班牙文"},
            {"code": "it", "name": "意大利文"},
            {"code": "pt", "name": "葡萄牙文"},
            {"code": "auto", "name": "自动检测"}
        ]
        return languages

class Transcriber:
    """语音转录器，负责将音频转换为文本"""
    
    def __init__(self, model_path: str):
        """初始化转录器
        
        Args:
            model_path: 模型文件路径
        """
        # 如果使用模拟实现，直接返回模拟转录器的实例
        if WHISPER_IMPL == "mock":
            # 由于Python不允许在__init__中返回其他对象，我们使用组合模式
            self.transcriber = MockTranscriber(model_path)
            self.is_mock = True
        else:
            self.model_path = model_path
            self.model = None
            self.is_loaded = False
            self.is_processing = False
            self.processing_thread = None
            self.is_mock = False
            
            # 转录配置
            self.language = "zh"  # 默认中文
            self.translate = False  # 是否翻译为英文
            
            # 检测是否为OpenAI原生Whisper模型
            self.is_openai_model = model_path.startswith("whisper-")
            
            # 初始化模型
            self.load_model()
    
    def load_model(self) -> bool:
        """加载模型
        
        Returns:
            加载是否成功
        """
        if self.is_mock:
            return self.transcriber.load_model()
            
        if self.is_loaded:
            return True
        
        try:
            # 处理OpenAI原生Whisper模型
            if self.is_openai_model:
                # 从路径中提取模型大小(tiny, base, small等)
                import whisper
                model_size = self.model_path.split("-")[1]
                
                try:
                    # 临时修改torch.load行为以处理PyTorch 2.6+兼容性问题
                    import torch
                    _old_default_load = torch.load
                    torch.load = lambda f, *args, **kwargs: _old_default_load(f, *args, **{**kwargs, 'weights_only': False})
                    
                    # 加载模型
                    logger.info(f"加载OpenAI Whisper {model_size}模型...")
                    self.model = whisper.load_model(model_size)
                    
                    # 恢复torch.load原有行为
                    torch.load = _old_default_load
                    
                    logger.info(f"已加载OpenAI Whisper {model_size}模型")
                    self.is_loaded = True
                    return True
                except Exception as e:
                    logger.error(f"加载OpenAI Whisper模型失败: {e}")
                    
                    # 尝试使用mock模式
                    self.transcriber = MockTranscriber(self.model_path)
                    self.is_mock = True
                    return self.transcriber.load_model()
            
            # 处理ggml格式模型
            # 检查模型文件是否存在
            model_path = self.model_path
            if not os.path.exists(model_path) and not os.path.isabs(model_path):
                # 尝试作为相对于models目录的路径
                if not model_path.startswith("models/") and not model_path.startswith("models\\"):
                    alt_path = os.path.join("models", os.path.basename(model_path))
                    if os.path.exists(alt_path):
                        model_path = alt_path
                        self.model_path = model_path  # 更新路径
            
            if not os.path.exists(model_path):
                logger.error(f"模型文件不存在: {model_path}")
                
                # 如果模型不存在，使用模拟模式
                self.transcriber = MockTranscriber(self.model_path)
                self.is_mock = True
                return self.transcriber.load_model()
            
            if WHISPER_IMPL == "cpp":
                # 使用whisper-cpp-python
                self.model = whisper_cpp.Whisper(self.model_path)
                logger.info(f"已加载C++模型: {self.model_path}")
            elif WHISPER_IMPL == "python":
                # 使用OpenAI whisper
                # 首先设置torch.load的默认参数，解决PyTorch 2.6+的兼容性问题
                import torch
                _old_default_load = torch.load
                torch.load = lambda f, *args, **kwargs: _old_default_load(f, *args, **{**kwargs, 'weights_only': False})
                
                # 加载模型
                self.model = whisper.load_model(self.model_path)
                
                # 恢复torch.load原有行为
                torch.load = _old_default_load
                
                logger.info(f"已加载Python模型: {self.model_path}")
            else:
                logger.error("没有可用的whisper实现")
                
                # 如果没有可用实现，使用模拟模式
                self.transcriber = MockTranscriber(self.model_path)
                self.is_mock = True
                return self.transcriber.load_model()
                
            self.is_loaded = True
            return True
        except Exception as e:
            logger.error(f"加载模型失败: {e}")
            
            # 如果加载失败，使用模拟模式
            self.transcriber = MockTranscriber(self.model_path)
            self.is_mock = True
            return self.transcriber.load_model()
    
    def set_language(self, language: str):
        """设置识别语言
        
        Args:
            language: 语言代码，如'zh'、'en'等
        """
        if self.is_mock:
            return self.transcriber.set_language(language)
            
        self.language = language
        logger.info(f"设置识别语言为: {language}")
    
    def set_translate(self, translate: bool):
        """设置是否将识别结果翻译为英文
        
        Args:
            translate: 是否翻译
        """
        if self.is_mock:
            return self.transcriber.set_translate(translate)
            
        self.translate = translate
        logger.info(f"设置翻译模式: {translate}")
    
    def transcribe_file(self, audio_file: str) -> str:
        """转录音频文件
        
        Args:
            audio_file: 音频文件路径
        
        Returns:
            转录结果文本
        """
        if self.is_mock:
            return self.transcriber.transcribe_file(audio_file)
            
        if not self.is_loaded:
            if not self.load_model():
                return "错误：模型未加载"
        
        try:
            logger.info(f"开始转录文件: {audio_file}")
            
            if not os.path.exists(audio_file):
                logger.error(f"音频文件不存在: {audio_file}")
                return f"错误：音频文件不存在：{audio_file}"
            
            # 确认音频文件是否可读
            try:
                with open(audio_file, 'rb') as f:
                    # 只读取前100字节确认文件可读取
                    _ = f.read(100)
                logger.info(f"音频文件可正常读取: {audio_file}")
            except Exception as e:
                logger.error(f"无法读取音频文件: {audio_file}, 错误: {e}")
                return f"错误：无法读取音频文件 - {str(e)}"
            
            if self.is_openai_model:
                # 使用OpenAI Whisper原生API
                import whisper
                import torch
                
                # 打印GPU可用信息
                if torch.cuda.is_available():
                    logger.info(f"使用GPU: {torch.cuda.get_device_name(0)}")
                else:
                    logger.info("使用CPU处理 (速度较慢)")
                
                # 设置模型选项和任务
                logger.info(f"使用语言: {self.language}, 翻译模式: {self.translate}")
                
                try:
                    # 根据whisper库版本决定参数
                    import inspect
                    transcribe_params = inspect.signature(self.model.transcribe).parameters
                    
                    kwargs = {}
                    # 检查是否支持language参数
                    if 'language' in transcribe_params:
                        if self.language != "auto":
                            kwargs['language'] = self.language
                    
                    # 检查是否支持task参数
                    if 'task' in transcribe_params:
                        kwargs['task'] = "translate" if self.translate else "transcribe"
                    
                    # 检查是否支持verbose参数
                    if 'verbose' in transcribe_params:
                        kwargs['verbose'] = True
                    
                    logger.info(f"调用transcribe方法，参数: {kwargs}")
                    result = self.model.transcribe(audio_file, **kwargs)
                    
                    text = result["text"]
                    logger.info(f"OpenAI Whisper转录完成: {len(text)}字符")
                except Exception as e:
                    logger.error(f"OpenAI Whisper转录过程出错: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    return f"错误：OpenAI Whisper转录失败 - {str(e)}"
                    
            elif WHISPER_IMPL == "cpp":
                # 使用whisper-cpp-python
                try:
                    result = self.model.transcribe(audio_file, lang=self.language, translate=self.translate)
                    text = result
                    logger.info(f"Whisper-CPP转录完成: {len(text)}字符")
                except Exception as e:
                    logger.error(f"Whisper-CPP转录过程出错: {e}")
                    return f"错误：Whisper-CPP转录失败 - {str(e)}"
                    
            elif WHISPER_IMPL == "python":
                # 使用OpenAI whisper
                import whisper
                import torch
                
                # 打印GPU可用信息
                if torch.cuda.is_available():
                    logger.info(f"使用GPU: {torch.cuda.get_device_name(0)}")
                else:
                    logger.info("使用CPU处理 (速度较慢)")
                    
                try:
                    # 根据whisper库版本决定参数
                    import inspect
                    transcribe_params = inspect.signature(self.model.transcribe).parameters
                    
                    kwargs = {}
                    # 检查是否支持language参数
                    if 'language' in transcribe_params:
                        if self.language != "auto":
                            kwargs['language'] = self.language
                    
                    # 检查是否支持task参数
                    if 'task' in transcribe_params:
                        kwargs['task'] = "translate" if self.translate else "transcribe"
                    
                    # 检查是否支持verbose参数
                    if 'verbose' in transcribe_params:
                        kwargs['verbose'] = True
                    
                    logger.info(f"调用transcribe方法，参数: {kwargs}")
                    result = self.model.transcribe(audio_file, **kwargs)
                    
                    text = result["text"]
                    logger.info(f"Python Whisper转录完成: {len(text)}字符")
                except Exception as e:
                    logger.error(f"Python Whisper转录过程出错: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    return f"错误：Python Whisper转录失败 - {str(e)}"
                    
            else:
                return "错误：没有可用的whisper实现"
            
            logger.info(f"转录完成，文本长度: {len(text)}")
            return text
        except Exception as e:
            logger.error(f"转录过程出错: {e}")
            # 如果转录失败，尝试降级到模拟模式
            if not self.is_mock:
                logger.warning("转录失败，降级到模拟模式")
                self.transcriber = MockTranscriber(self.model_path)
                self.is_mock = True
                return self.transcriber.transcribe_file(audio_file)
            
            return f"错误：转录失败 - {str(e)}"
    
    def transcribe_audio_data(self, audio_data: np.ndarray, sample_rate: int = 16000) -> str:
        """转录音频数据
        
        Args:
            audio_data: 音频数据numpy数组
            sample_rate: 采样率
        
        Returns:
            转录结果文本
        """
        if self.is_mock:
            return self.transcriber.transcribe_audio_data(audio_data, sample_rate)
            
        # 将音频数据保存为临时文件
        fd, temp_path = tempfile.mkstemp(suffix='.wav')
        os.close(fd)
        
        try:
            # 尝试使用soundfile，如果不可用则使用numpy和wave模块
            try:
                import soundfile as sf
                sf.write(temp_path, audio_data, sample_rate)
            except ImportError:
                logger.warning("未安装soundfile，使用替代方法保存音频数据")
                import wave
                with wave.open(temp_path, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)  # 16-bit
                    wf.setframerate(sample_rate)
                    wf.writeframes(audio_data.tobytes())
            
            # 转录临时文件
            result = self.transcribe_file(temp_path)
            
            # 删除临时文件
            os.unlink(temp_path)
            
            return result
        except Exception as e:
            logger.error(f"处理音频数据时出错: {e}")
            
            # 清理临时文件
            if os.path.exists(temp_path):
                os.unlink(temp_path)
            
            return f"错误：转录失败 - {str(e)}"
    
    def transcribe_async(self, audio_file: str, callback: Callable[[str], None]):
        """异步转录音频文件
        
        Args:
            audio_file: 音频文件路径
            callback: 转录完成后的回调函数，参数为转录结果
        """
        if self.is_mock:
            return self.transcriber.transcribe_async(audio_file, callback)
            
        if self.is_processing:
            logger.warning("已有转录任务正在进行中")
            return
        
        def process_task():
            self.is_processing = True
            result = self.transcribe_file(audio_file)
            self.is_processing = False
            callback(result)
        
        self.processing_thread = threading.Thread(target=process_task)
        self.processing_thread.daemon = True
        self.processing_thread.start()
        logger.info(f"启动异步转录任务: {audio_file}")
    
    def get_available_languages(self) -> List[Dict[str, str]]:
        """获取可用的语言列表
        
        Returns:
            语言列表，每个元素包含code和name字段
        """
        if self.is_mock:
            return self.transcriber.get_available_languages()
            
        languages = [
            {"code": "zh", "name": "中文"},
            {"code": "en", "name": "英文"},
            {"code": "ja", "name": "日文"},
            {"code": "ko", "name": "韩文"},
            {"code": "ru", "name": "俄文"},
            {"code": "fr", "name": "法文"},
            {"code": "de", "name": "德文"},
            {"code": "es", "name": "西班牙文"},
            {"code": "it", "name": "意大利文"},
            {"code": "pt", "name": "葡萄牙文"},
            {"code": "auto", "name": "自动检测"}
        ]
        return languages

class RealtimeTranscriber:
    """实时语音转录器"""
    
    def __init__(self, model_path: str = "tiny"):
        """初始化实时转录器
        
        Args:
            model_path: 模型路径或名称
        """
        import whisper
        import numpy as np
        import collections
        from threading import Lock
        import torch
        
        # 加载模型
        logger.info(f"加载Whisper模型: {model_path}")
        
        # 如果是预设名称（tiny, base等），直接使用名称
        if model_path.startswith("whisper-"):
            self.model = whisper.load_model(model_path.split("-")[1])
        else:
            # 否则尝试加载指定路径的模型
            try:
                self.model = whisper.load_model(model_path)
            except:
                # 加载失败时使用tiny模型
                logger.warning(f"加载模型 {model_path} 失败，使用默认tiny模型")
                self.model = whisper.load_model("tiny")
                
        # 设置语言和翻译选项
        self.language = "zh"
        self.translate = False
        
        # 音频参数
        self.sample_rate = 16000  # whisper期望的采样率
        
        # 音频缓冲区，用于累积足够的音频进行处理
        self.buffer = collections.deque(maxlen=100)  # 约25秒音频(16000*25/4000)
        self.buffer_lock = Lock()
        
        # 转录线程和状态
        self.transcribe_thread = None
        self.is_transcribing = False
        
        # 转录结果
        self.result_text = ""
        
        # 打印设备信息
        if torch.cuda.is_available():
            logger.info(f"使用GPU加速: {torch.cuda.get_device_name(0)}")
        else:
            logger.info("使用CPU处理（速度较慢）")
    
    def add_audio_chunk(self, audio_data):
        """添加音频数据块到缓冲区
        
        Args:
            audio_data: 音频数据（numpy数组）
        """
        if not self.is_transcribing:
            return
            
        # 添加到缓冲区
        with self.buffer_lock:
            self.buffer.append(audio_data)
    
    def start(self):
        """开始实时转录"""
        import threading
        import time
        import numpy as np
        
        if self.is_transcribing:
            logger.warning("已经在进行实时转录")
            return
            
        self.is_transcribing = True
        self.result_text = ""
        
        # 清空缓冲区
        with self.buffer_lock:
            self.buffer.clear()
        
        def transcribe_thread_func():
            """转录线程函数"""
            logger.info("开始实时转录")
            segment_id = 0
            
            while self.is_transcribing:
                # 检查缓冲区中是否有足够的数据
                process_audio = False
                audio_data = None
                
                with self.buffer_lock:
                    if len(self.buffer) >= 5:  # 至少需要约1.25秒的音频
                        # 复制并清空缓冲区
                        audio_data = np.concatenate(list(self.buffer))
                        self.buffer.clear()
                        process_audio = True
                
                # 如果没有足够的数据，等待一段时间
                if not process_audio:
                    time.sleep(0.1)
                    continue
                
                try:
                    # 直接处理内存中的音频数据
                    
                    # 将音频数据转换为浮点数格式，范围为[-1.0, 1.0]
                    # 假设输入是16位整数PCM
                    if audio_data.dtype != np.float32:
                        audio_float = audio_data.astype(np.float32) / 32768.0
                    else:
                        audio_float = audio_data
                    
                    # 确保采样率正确
                    if hasattr(self, 'input_sample_rate') and self.input_sample_rate != self.sample_rate:
                        # 需要重采样
                        try:
                            import librosa
                            audio_float = librosa.resample(
                                audio_float, 
                                orig_sr=self.input_sample_rate, 
                                target_sr=self.sample_rate
                            )
                            logger.debug(f"将音频从 {self.input_sample_rate}Hz 重采样到 {self.sample_rate}Hz")
                        except ImportError:
                            logger.warning("无法导入librosa进行重采样，假设采样率已正确")
                    
                    # 转录音频
                    logger.debug(f"转录音频段 {segment_id}")
                    result = self.model.transcribe(
                        audio_float, 
                        language=self.language if self.language != "auto" else None,
                        task="translate" if self.translate else "transcribe"
                    )
                    
                    text = result["text"].strip()
                    if text:
                        # 更新转录结果
                        self.result_text += text + " "
                        # 打印新的转录结果
                        logger.info(f"实时转录 [{segment_id}]: {text}")
                        # 在同一行清晰地显示转录结果
                        print(f"\r实时转录: {text}{' ':<30}", end="", flush=True)
                    
                    segment_id += 1
                
                except Exception as e:
                    logger.error(f"转录过程出错: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                
                # 短暂休息，避免CPU占用过高
                time.sleep(0.1)
            
            logger.info("实时转录结束")
        
        # 启动转录线程
        self.transcribe_thread = threading.Thread(target=transcribe_thread_func)
        self.transcribe_thread.daemon = True
        self.transcribe_thread.start()
    
    def set_input_sample_rate(self, sample_rate):
        """设置输入音频的采样率
        
        Args:
            sample_rate: 采样率（Hz）
        """
        self.input_sample_rate = sample_rate
        logger.info(f"设置输入音频采样率: {sample_rate}Hz")
    
    def stop(self) -> str:
        """停止实时转录
        
        Returns:
            完整的转录结果
        """
        if not self.is_transcribing:
            return self.result_text
            
        logger.info("停止实时转录")
        self.is_transcribing = False
        
        # 等待转录线程结束
        if self.transcribe_thread and self.transcribe_thread.is_alive():
            self.transcribe_thread.join(timeout=2.0)
        
        return self.result_text
    
    def set_language(self, language: str):
        """设置识别语言
        
        Args:
            language: 语言代码
        """
        self.language = language
        logger.info(f"设置实时转录语言: {language}")
    
    def set_translate(self, translate: bool):
        """设置是否翻译
        
        Args:
            translate: 是否翻译
        """
        self.translate = translate
        logger.info(f"设置实时转录翻译模式: {translate}")

# 如果使用模拟实现，替换Transcriber类
if WHISPER_IMPL == "mock":
    Transcriber = MockTranscriber 