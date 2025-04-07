#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
音频处理模块，负责音频捕获和预处理
"""

# 在任何其他导入之前设置环境变量
import os
os.environ['PYTHONIOENCODING'] = 'utf-8'

# 导入其他必要模块
import sys
import threading
import numpy as np
import tempfile
from dataclasses import dataclass
from typing import Optional, List, Callable, Dict
from loguru import logger

# 尝试按优先级导入不同的音频库
try:
    import sounddevice as sd
    import soundfile as sf
    import wave
    AUDIO_IMPL = "sounddevice"
    logger.info("使用SoundDevice进行音频处理")
except ImportError:
    try:
        import pyaudio
        import wave
        AUDIO_IMPL = "pyaudio"
        logger.info("使用PyAudio进行音频处理")
    except ImportError:
        AUDIO_IMPL = "mock"
        logger.warning("未安装音频处理库，将使用模拟实现。音频录制功能不可用。请安装sounddevice或PyAudio以启用完整功能。")

@dataclass
class AudioDevice:
    """音频设备信息"""
    name: str
    index: int
    channels: int
    default: bool = False

class MockAudioManager:
    """音频库不可用时的模拟音频管理器"""
    
    def __init__(self):
        self.is_recording = False
        self.frames = []
        logger.warning("正在使用模拟音频管理器。要启用完整功能，请安装SoundDevice或PyAudio")
        
    def get_devices(self) -> List[AudioDevice]:
        """获取模拟的音频设备列表"""
        return [
            AudioDevice(name="模拟麦克风 (不可用)", index=0, channels=1, default=True),
            AudioDevice(name="模拟立体声麦克风 (不可用)", index=1, channels=2, default=False)
        ]
    
    def start_recording(self, device_name: Optional[str] = None, callback: Optional[Callable[[np.ndarray], None]] = None):
        """模拟开始录音（实际不会录制）"""
        logger.warning("未安装音频处理库，无法录音。请安装SoundDevice或PyAudio")
        self.is_recording = True
        # 生成一些模拟的噪声数据，这样应用程序的其余部分可以继续工作
        if callback:
            # 创建一个小的随机噪声数组作为模拟数据
            mock_data = np.random.randint(-1000, 1000, size=1024, dtype=np.int16)
            callback(mock_data)
    
    def stop_recording(self):
        """模拟停止录音"""
        if not self.is_recording:
            return
            
        self.is_recording = False
        logger.info("停止模拟录音")
    
    def save_recording(self, filename: str):
        """模拟保存录音（实际不会保存）"""
        logger.warning("未安装音频处理库，无法保存录音")
        # 创建一个空文件，这样应用程序的其余部分可以继续工作
        with open(filename, 'wb') as f:
            f.write(b'\x00' * 1024)  # 写入一些无意义的数据
    
    def get_temp_wav_file(self) -> str:
        """返回示例WAV文件路径"""
        logger.warning("未安装音频处理库，无法创建临时录音文件")
        # 创建临时文件
        fd, temp_path = tempfile.mkstemp(suffix='.wav')
        os.close(fd)
        
        # 写入一些模拟数据
        with open(temp_path, 'wb') as f:
            f.write(b'\x00' * 1024)  # 写入一些无意义的数据
        
        return temp_path

# 使用SoundDevice的音频管理器实现
if AUDIO_IMPL == "sounddevice":
    class AudioManager:
        """使用SoundDevice的音频管理器，负责录音和音频处理"""
        
        def __init__(self):
            self.stream = None
            self.is_recording = False
            self.recording_thread = None
            self.frames = []
            self.on_audio_data = None
            
            # 录音参数
            self.channels = 1
            self.rate = 16000  # 16 kHz
            self.chunk = 1024  # 每次读取的帧数
        
        def get_devices(self) -> List[AudioDevice]:
            """获取所有音频输入设备"""
            devices = []
            
            try:
                device_list = sd.query_devices()
                default_device = sd.query_devices(kind='input')
                default_device_index = default_device['index']
                
                for i, device in enumerate(device_list):
                    # 只添加输入设备
                    if device['max_input_channels'] > 0:
                        devices.append(AudioDevice(
                            name=device['name'],
                            index=device['index'],
                            channels=min(device['max_input_channels'], 2),  # 最多使用双声道
                            default=(device['index'] == default_device_index)
                        ))
            except Exception as e:
                logger.error(f"获取音频设备列表失败: {e}")
                # 添加一个模拟设备
                devices.append(AudioDevice(
                    name="默认麦克风",
                    index=0,
                    channels=1,
                    default=True
                ))
            
            return devices
        
        def _audio_callback(self, indata, frames, time, status):
            """音频数据回调函数"""
            if status:
                logger.warning(f"音频流状态: {status}")
            
            # 将数据添加到帧列表
            self.frames.append(indata.copy())
            
            if self.on_audio_data:
                # 回调用户函数
                self.on_audio_data(indata[:, 0].astype(np.int16))  # 只使用第一个声道
        
        def start_recording(self, device_name: Optional[str] = None, callback: Optional[Callable[[np.ndarray], None]] = None):
            """开始录音
            
            Args:
                device_name: 设备名称，如果为None则使用默认设备
                callback: 音频数据回调函数
            """
            if self.is_recording:
                logger.warning("已经在录音中，无需重复启动")
                return
            
            # 清空之前的录音数据
            self.frames = []
            self.on_audio_data = callback
            
            # 选择设备
            device_index = None
            if device_name:
                devices = self.get_devices()
                for device in devices:
                    if device.name == device_name:
                        device_index = device.index
                        self.channels = device.channels
                        break
            
            try:
                # 开始录音流
                self.stream = sd.InputStream(
                    samplerate=self.rate,
                    channels=self.channels,
                    device=device_index,
                    blocksize=self.chunk,
                    callback=self._audio_callback,
                    dtype='int16'
                )
                self.stream.start()
                
                self.is_recording = True
                logger.info(f"开始录音，设备: {device_name if device_name else '默认'}")
            except Exception as e:
                logger.error(f"开始录音失败: {e}")
        
        def stop_recording(self):
            """停止录音"""
            if not self.is_recording:
                return
            
            if self.stream:
                self.stream.stop()
                self.stream.close()
                self.stream = None
            
            self.is_recording = False
            logger.info("停止录音")
        
        def save_recording(self, filename: str):
            """保存录音到文件
            
            Args:
                filename: 保存的文件名
            """
            if not self.frames:
                logger.warning("没有录音数据可保存")
                return
            
            try:
                # 合并所有帧
                audio_data = np.vstack(self.frames)
                
                # 保存为WAV文件
                sf.write(filename, audio_data, self.rate)
                logger.info(f"录音已保存到 {filename}")
            except Exception as e:
                logger.error(f"保存录音失败: {e}")
                # 尝试使用wave模块保存
                try:
                    with wave.open(filename, 'wb') as wf:
                        wf.setnchannels(self.channels)
                        wf.setsampwidth(2)  # 16位
                        wf.setframerate(self.rate)
                        for frame in self.frames:
                            wf.writeframes(frame.tobytes())
                    logger.info(f"录音已保存到 {filename} (使用wave模块)")
                except Exception as e2:
                    logger.error(f"使用wave模块保存也失败: {e2}")
        
        def get_temp_wav_file(self) -> str:
            """将当前录音保存为临时wav文件，并返回文件路径"""
            if not self.frames:
                logger.warning("没有录音数据可保存")
                return ""
            
            # 创建临时文件
            fd, temp_path = tempfile.mkstemp(suffix='.wav')
            os.close(fd)
            
            # 保存录音
            self.save_recording(temp_path)
            
            logger.debug(f"录音已保存到临时文件 {temp_path}")
            return temp_path

# 如果使用PyAudio
elif AUDIO_IMPL == "pyaudio":
    class AudioManager:
        """音频管理器，负责录音和音频处理"""
        
        def __init__(self):
            self.pyaudio = pyaudio.PyAudio()
            self.stream = None
            self.is_recording = False
            self.recording_thread = None
            self.frames = []
            self.on_audio_data = None
            
            # 录音参数
            self.format = pyaudio.paInt16
            self.channels = 1
            self.rate = 16000  # 16 kHz
            self.chunk = 1024  # 每次读取的帧数
        
        def __del__(self):
            """析构函数，确保资源被释放"""
            self.stop_recording()
            self.pyaudio.terminate()
        
        def get_devices(self) -> List[AudioDevice]:
            """获取所有音频输入设备"""
            devices = []
            
            try:
                # 获取默认设备信息
                default_device_index = self.pyaudio.get_default_input_device_info()["index"]
                
                # 遍历所有设备
                for i in range(self.pyaudio.get_device_count()):
                    try:
                        device_info = self.pyaudio.get_device_info_by_index(i)
                        
                        # 只添加输入设备（麦克风）
                        if device_info["maxInputChannels"] > 0:
                            devices.append(AudioDevice(
                                name=device_info["name"],
                                index=device_info["index"],
                                channels=device_info["maxInputChannels"],
                                default=(device_info["index"] == default_device_index)
                            ))
                    except Exception as e:
                        logger.error(f"获取设备 {i} 信息失败: {e}")
            except Exception as e:
                logger.error(f"获取默认设备信息失败: {e}")
                # 添加一个模拟设备
                devices.append(AudioDevice(
                    name="默认麦克风",
                    index=0,
                    channels=1,
                    default=True
                ))
            
            return devices
        
        def start_recording(self, device_name: Optional[str] = None, callback: Optional[Callable[[np.ndarray], None]] = None):
            """开始录音
            
            Args:
                device_name: 设备名称，如果为None则使用默认设备
                callback: 音频数据回调函数
            """
            if self.is_recording:
                logger.warning("已经在录音中，无需重复启动")
                return
            
            # 清空之前的录音数据
            self.frames = []
            self.on_audio_data = callback
            
            # 选择设备
            device_index = None
            if device_name:
                devices = self.get_devices()
                for device in devices:
                    if device.name == device_name:
                        device_index = device.index
                        self.channels = device.channels
                        break
            
            # 非回调方式录音，避免PyAudio的C扩展问题
            def record_thread():
                try:
                    # 打开音频流
                    stream = self.pyaudio.open(
                        format=self.format,
                        channels=self.channels,
                        rate=self.rate,
                        input=True,
                        input_device_index=device_index,
                        frames_per_buffer=self.chunk
                    )
                    
                    self.stream = stream
                    logger.info(f"开始录音，设备: {device_name if device_name else '默认'}")
                    
                    while self.is_recording:
                        try:
                            data = stream.read(self.chunk)
                            self.frames.append(data)
                            
                            if self.on_audio_data:
                                # 将字节数据转换为numpy数组
                                audio_data = np.frombuffer(data, dtype=np.int16)
                                self.on_audio_data(audio_data)
                        except Exception as e:
                            logger.error(f"录音过程出错: {e}")
                            break
                            
                    # 关闭流
                    if stream:
                        stream.stop_stream()
                        stream.close()
                        self.stream = None
                        
                except Exception as e:
                    logger.error(f"录音线程出错: {e}")
                    self.is_recording = False
            
            # 启动录音线程
            self.is_recording = True
            self.recording_thread = threading.Thread(target=record_thread)
            self.recording_thread.daemon = True
            self.recording_thread.start()
        
        def stop_recording(self):
            """停止录音"""
            if not self.is_recording:
                return
            
            self.is_recording = False
            
            # 等待录音线程结束
            if self.recording_thread and self.recording_thread.is_alive():
                self.recording_thread.join(timeout=1.0)
            
            if self.stream:
                try:
                    self.stream.stop_stream()
                    self.stream.close()
                except:
                    pass
                self.stream = None
            
            logger.info("停止录音")
        
        def save_recording(self, filename: str):
            """保存录音到文件
            
            Args:
                filename: 保存的文件名
            """
            if not self.frames:
                logger.warning("没有录音数据可保存")
                return
            
            with wave.open(filename, 'wb') as wf:
                wf.setnchannels(self.channels)
                wf.setsampwidth(self.pyaudio.get_sample_size(self.format))
                wf.setframerate(self.rate)
                wf.writeframes(b''.join(self.frames))
            
            logger.info(f"录音已保存到 {filename}")
        
        def get_temp_wav_file(self) -> str:
            """将当前录音保存为临时wav文件，并返回文件路径"""
            if not self.frames:
                logger.warning("没有录音数据可保存")
                return ""
            
            # 创建临时文件
            fd, temp_path = tempfile.mkstemp(suffix='.wav')
            os.close(fd)
            
            # 保存录音
            with wave.open(temp_path, 'wb') as wf:
                wf.setnchannels(self.channels)
                wf.setsampwidth(self.pyaudio.get_sample_size(self.format))
                wf.setframerate(self.rate)
                wf.writeframes(b''.join(self.frames))
            
            logger.debug(f"录音已保存到临时文件 {temp_path}")
            return temp_path
else:
    # 使用模拟实现
    AudioManager = MockAudioManager 

def _get_audio_manager_impl():
    """获取音频管理器实现"""
    global _AUDIO_MANAGER_IMPL
    if _AUDIO_MANAGER_IMPL is None:
        try:
            import sounddevice as sd
            logger.info("使用SoundDevice进行音频处理")
            _AUDIO_MANAGER_IMPL = "sounddevice"
        except ImportError:
            try:
                import pyaudio
                logger.info("使用PyAudio进行音频处理")
                _AUDIO_MANAGER_IMPL = "pyaudio"
            except ImportError:
                logger.error("未安装音频处理库，无法进行录音")
                _AUDIO_MANAGER_IMPL = "mock"
    
    return _AUDIO_MANAGER_IMPL

class SoundDeviceAudioManager(AudioManager):
    """使用SoundDevice实现音频管理"""
    
    def __init__(self):
        """初始化SoundDevice音频管理器"""
        super().__init__()
        import sounddevice as sd
        import numpy as np
        import queue
        import threading
        
        self.sd = sd
        self.np = np
        self.queue = queue
        self.audio_queue = queue.Queue()
        self.recording = False
        self.recorded_frames = []
        self.record_thread = None
        self.callback_function = None
        
        # 默认格式
        self.sample_rate = 16000
        self.channels = 1
        self.dtype = 'int16'
    
    def get_devices(self) -> List[AudioDevice]:
        """获取可用的音频设备
        
        Returns:
            设备列表
        """
        devices = []
        try:
            for i, dev_info in enumerate(self.sd.query_devices()):
                # 只保留输入设备
                if dev_info['max_input_channels'] > 0:
                    name = dev_info['name']
                    is_default = i == self.sd.default.device[0]
                    devices.append(AudioDevice(name=name, device_id=i, default=is_default))
        except Exception as e:
            logger.error(f"获取音频设备列表失败: {e}")
            devices = [AudioDevice(name="默认设备", device_id=None, default=True)]
        
        return devices
    
    def start_recording(self, device_name: Optional[str] = None, callback_function=None) -> bool:
        """开始录音
        
        Args:
            device_name: 设备名称
            callback_function: 接收音频数据的回调函数
            
        Returns:
            是否成功开始录音
        """
        if self.recording:
            logger.warning("已经在录音中")
            return False
        
        try:
            # 清空已录制的数据
            self.recorded_frames = []
            self.audio_queue = self.queue.Queue()
            
            # 保存回调函数
            self.callback_function = callback_function
            
            # 查找设备
            device_id = None
            
            if device_name:
                for i, dev_info in enumerate(self.sd.query_devices()):
                    if dev_info['name'] == device_name and dev_info['max_input_channels'] > 0:
                        device_id = i
                        break
            
            if device_id is None and device_name is not None:
                logger.warning(f"未找到设备 {device_name}，使用默认输入设备")
            
            # 设置回调函数
            def audio_callback(indata, frames, time, status):
                """SoundDevice音频回调"""
                if status:
                    logger.warning(f"音频回调状态: {status}")
                
                # 转换为单声道
                if self.channels == 1 and indata.shape[1] > 1:
                    mono_data = self.np.mean(indata, axis=1, dtype=indata.dtype).reshape(-1, 1)
                else:
                    mono_data = indata
                
                # 添加到队列
                self.audio_queue.put(mono_data.copy())
                
                # 如果有回调函数，调用它
                if self.callback_function:
                    # 确保数据是合适的格式
                    callback_data = mono_data.flatten()
                    self.callback_function(callback_data)
            
            # 设置录音参数
            self.recording = True
            
            # 启动录音线程
            def record_thread_func():
                """录音线程函数"""
                try:
                    with self.sd.InputStream(
                        samplerate=self.sample_rate,
                        device=device_id,
                        channels=self.channels,
                        dtype=self.dtype,
                        callback=audio_callback
                    ):
                        logger.info(f"开始录音 (设备: {device_name if device_name else '默认'}, 采样率: {self.sample_rate}Hz)")
                        
                        # 持续录音直到停止
                        while self.recording:
                            # 从队列获取录音数据
                            try:
                                frame = self.audio_queue.get(timeout=1.0)
                                self.recorded_frames.append(frame)
                            except self.queue.Empty:
                                continue
                except Exception as e:
                    logger.error(f"录音过程出错: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    self.recording = False
            
            # 启动录音线程
            self.record_thread = threading.Thread(target=record_thread_func)
            self.record_thread.daemon = True
            self.record_thread.start()
            
            return True
        
        except Exception as e:
            logger.error(f"开始录音失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            self.recording = False
            return False

class PyAudioAudioManager(AudioManager):
    """使用PyAudio实现音频管理"""
    
    def __init__(self):
        """初始化PyAudio音频管理器"""
        super().__init__()
        import pyaudio
        import numpy as np
        import threading
        import queue
        
        self.pa = pyaudio
        self.np = np
        self.queue = queue
        self.audio = None
        self.stream = None
        self.recording = False
        self.recorded_frames = []
        self.record_thread = None
        self.audio_queue = queue.Queue()
        self.callback_function = None
        
        # 默认格式
        self.sample_rate = 16000
        self.channels = 1
        self.format = self.pa.paInt16
        self.chunk = 1024
        
        # 初始化PyAudio
        self.audio = self.pa.PyAudio()
    
    def __del__(self):
        """析构函数，释放资源"""
        if self.audio:
            self.audio.terminate()
    
    def get_devices(self) -> List[AudioDevice]:
        """获取可用的音频设备
        
        Returns:
            设备列表
        """
        devices = []
        try:
            for i in range(self.audio.get_device_count()):
                dev_info = self.audio.get_device_info_by_index(i)
                # 只保留输入设备
                if dev_info['maxInputChannels'] > 0:
                    name = dev_info['name']
                    is_default = i == self.audio.get_default_input_device_info()['index']
                    devices.append(AudioDevice(name=name, device_id=i, default=is_default))
        except Exception as e:
            logger.error(f"获取音频设备列表失败: {e}")
            devices = [AudioDevice(name="默认设备", device_id=None, default=True)]
        
        return devices
    
    def start_recording(self, device_name: Optional[str] = None, callback_function=None) -> bool:
        """开始录音
        
        Args:
            device_name: 设备名称
            callback_function: 接收音频数据的回调函数
            
        Returns:
            是否成功开始录音
        """
        if self.recording:
            logger.warning("已经在录音中")
            return False
        
        try:
            # 清空已录制的数据
            self.recorded_frames = []
            self.audio_queue = self.queue.Queue()
            
            # 保存回调函数
            self.callback_function = callback_function
            
            # 查找设备
            device_id = None
            
            if device_name:
                for i in range(self.audio.get_device_count()):
                    dev_info = self.audio.get_device_info_by_index(i)
                    if dev_info['name'] == device_name and dev_info['maxInputChannels'] > 0:
                        device_id = i
                        break
            
            if device_id is None and device_name is not None:
                logger.warning(f"未找到设备 {device_name}，使用默认输入设备")
            
            # 设置回调函数
            def audio_callback(in_data, frame_count, time_info, status):
                """PyAudio音频回调"""
                if status:
                    logger.warning(f"音频回调状态: {status}")
                
                # 转换为numpy数组
                audio_data = self.np.frombuffer(in_data, dtype=self.np.int16)
                
                # 添加到队列
                self.audio_queue.put(audio_data.copy())
                
                # 如果有回调函数，调用它
                if self.callback_function:
                    # 确保数据是合适的格式
                    self.callback_function(audio_data)
                
                return (in_data, self.pa.paContinue)
            
            # 启动录音
            self.stream = self.audio.open(
                format=self.format,
                channels=self.channels,
                rate=self.sample_rate,
                input=True,
                input_device_index=device_id,
                frames_per_buffer=self.chunk,
                stream_callback=audio_callback
            )
            
            self.recording = True
            self.stream.start_stream()
            
            logger.info(f"开始录音 (设备: {device_name if device_name else '默认'}, 采样率: {self.sample_rate}Hz)")
            
            # 启动录音线程收集数据
            def record_thread_func():
                """录音线程函数"""
                try:
                    while self.recording and self.stream.is_active():
                        # 从队列获取录音数据
                        try:
                            frame = self.audio_queue.get(timeout=1.0)
                            self.recorded_frames.append(frame)
                        except self.queue.Empty:
                            continue
                except Exception as e:
                    logger.error(f"录音过程出错: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    self.recording = False
            
            # 启动录音线程
            self.record_thread = threading.Thread(target=record_thread_func)
            self.record_thread.daemon = True
            self.record_thread.start()
            
            return True
        
        except Exception as e:
            logger.error(f"开始录音失败: {e}")
            import traceback
            logger.error(traceback.format_exc())
            self.recording = False
            return False 

# 音频管理器实现
_AUDIO_MANAGER_IMPL = None

def get_audio_manager() -> 'AudioManager':
    """获取音频管理器实例
    
    Returns:
        音频管理器
    """
    impl = _get_audio_manager_impl()
    
    if impl == "sounddevice":
        return SoundDeviceAudioManager()
    elif impl == "pyaudio":
        return PyAudioAudioManager()
    else:
        logger.warning("使用模拟音频管理器")
        return MockAudioManager() 