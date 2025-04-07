#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
用户界面模块，负责应用的GUI实现
"""

import sys
import os
import time
import numpy as np
import traceback
from typing import Optional, List, Dict, Tuple
from datetime import datetime
from pathlib import Path
from loguru import logger

# 尝试导入PyQt6
try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QPushButton, QComboBox, QLabel, QTextEdit, QProgressBar,
        QDialog, QListWidget, QListWidgetItem, QMessageBox, QFileDialog
    )
    from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QThread
    from PyQt6.QtGui import QFont, QIcon, QPixmap
    PYQT_AVAILABLE = True
    logger.info("使用PyQt6进行GUI渲染")
except ImportError:
    PYQT_AVAILABLE = False
    logger.warning("无法导入PyQt6，将使用命令行界面")

# 尝试导入pyperclip
try:
    import pyperclip
    CLIPBOARD_AVAILABLE = True
except ImportError:
    CLIPBOARD_AVAILABLE = False
    logger.warning("无法导入pyperclip，复制到剪贴板功能不可用")

from audio import AudioManager, AudioDevice
from downloader import ModelDownloader
from transcriber import Transcriber

# 如果PyQt6可用，定义GUI相关类
if PYQT_AVAILABLE:
    class DownloadThread(QThread):
        """模型下载线程"""
        progress_signal = pyqtSignal(float)
        finished_signal = pyqtSignal(bool, str)
        
        def __init__(self, downloader: ModelDownloader, model_name: str):
            super().__init__()
            self.downloader = downloader
            self.model_name = model_name
        
        def run(self):
            """运行下载任务"""
            success = self.downloader.download_model(
                self.model_name, 
                progress_callback=lambda p: self.progress_signal.emit(p)
            )
            self.finished_signal.emit(success, self.model_name)

    class TranscriptionThread(QThread):
        """转录线程"""
        result_signal = pyqtSignal(str)
        
        def __init__(self, transcriber: Transcriber, audio_file: str):
            super().__init__()
            self.transcriber = transcriber
            self.audio_file = audio_file
        
        def run(self):
            """运行转录任务"""
            result = self.transcriber.transcribe_file(self.audio_file)
            self.result_signal.emit(result)

    class ModelSelectionDialog(QDialog):
        """模型选择对话框"""
        
        def __init__(self, downloader: ModelDownloader, parent=None):
            super().__init__(parent)
            self.downloader = downloader
            self.selected_model = ""
            self.download_thread = None
            
            self.setWindowTitle("选择语音模型")
            self.setMinimumWidth(500)
            self.init_ui()
            self.load_models()
        
        def init_ui(self):
            """初始化UI"""
            layout = QVBoxLayout()
            
            # 模型列表
            self.model_list = QListWidget()
            self.model_list.itemClicked.connect(self.on_model_selected)
            layout.addWidget(self.model_list)
            
            # 进度条
            self.progress_layout = QHBoxLayout()
            self.progress_label = QLabel("下载进度:")
            self.progress_bar = QProgressBar()
            self.progress_bar.setRange(0, 100)
            self.progress_bar.setValue(0)
            self.progress_layout.addWidget(self.progress_label)
            self.progress_layout.addWidget(self.progress_bar)
            layout.addLayout(self.progress_layout)
            
            # 按钮
            button_layout = QHBoxLayout()
            self.download_button = QPushButton("下载")
            self.download_button.clicked.connect(self.on_download)
            self.download_button.setEnabled(False)
            
            self.select_button = QPushButton("选择")
            self.select_button.clicked.connect(self.on_select)
            self.select_button.setEnabled(False)
            
            self.cancel_button = QPushButton("取消")
            self.cancel_button.clicked.connect(self.reject)
            
            button_layout.addWidget(self.download_button)
            button_layout.addWidget(self.select_button)
            button_layout.addWidget(self.cancel_button)
            layout.addLayout(button_layout)
            
            self.setLayout(layout)
        
        def load_models(self):
            """加载模型列表"""
            self.model_list.clear()
            models = self.downloader.get_available_models()
            
            for name, info in models.items():
                item = QListWidgetItem(f"{name} - {info['description']}")
                item.setData(Qt.ItemDataRole.UserRole, name)
                if info["downloaded"]:
                    item.setText(f"{name} - {info['description']} [已下载]")
                self.model_list.addItem(item)
        
        def on_model_selected(self, item):
            """模型选择事件"""
            self.selected_model = item.data(Qt.ItemDataRole.UserRole)
            models = self.downloader.get_available_models()
            model_info = models[self.selected_model]
            
            if model_info["downloaded"]:
                self.download_button.setEnabled(False)
                self.select_button.setEnabled(True)
            else:
                self.download_button.setEnabled(True)
                self.select_button.setEnabled(False)
        
        def on_download(self):
            """下载按钮事件"""
            if not self.selected_model:
                return
            
            self.download_button.setEnabled(False)
            self.cancel_button.setEnabled(False)
            self.model_list.setEnabled(False)
            
            self.download_thread = DownloadThread(self.downloader, self.selected_model)
            self.download_thread.progress_signal.connect(self.update_progress)
            self.download_thread.finished_signal.connect(self.on_download_finished)
            self.download_thread.start()
        
        def update_progress(self, progress):
            """更新进度条"""
            self.progress_bar.setValue(int(progress * 100))
        
        def on_download_finished(self, success, model_name):
            """下载完成事件"""
            self.model_list.setEnabled(True)
            self.cancel_button.setEnabled(True)
            
            if success:
                QMessageBox.information(self, "下载完成", f"模型 {model_name} 下载成功")
                self.load_models()
                
                # 重新选择当前模型
                for i in range(self.model_list.count()):
                    item = self.model_list.item(i)
                    if item.data(Qt.ItemDataRole.UserRole) == model_name:
                        self.model_list.setCurrentItem(item)
                        self.selected_model = model_name
                        self.select_button.setEnabled(True)
                        break
            else:
                QMessageBox.critical(self, "下载失败", f"模型 {model_name} 下载失败")
                self.download_button.setEnabled(True)
        
        def on_select(self):
            """选择按钮事件"""
            self.accept()

    class MainWindow(QMainWindow):
        """主窗口"""
        
        def __init__(self, model_path: str, device_name: Optional[str] = None, skip_download: bool = False):
            super().__init__()
            
            # 音频管理器
            self.audio_manager = AudioManager()
            
            # 模型下载器
            self.model_downloader = ModelDownloader()
            
            # 默认模型路径
            self.model_path = model_path
            
            # 检查模型是否存在
            if not os.path.exists(model_path) and not skip_download:
                self.select_model()
            
            # 转录器
            self.transcriber = Transcriber(self.model_path)
            
            # 录音设备
            self.device_name = device_name
            
            # 转录结果
            self.transcription_text = ""
            
            # 转录临时文件
            self.temp_wav_file = ""
            
            # 初始化UI
            self.init_ui()
            
            # 加载设备列表
            self.load_devices()
        
        def init_ui(self):
            """初始化UI"""
            self.setWindowTitle("AutoTalk - 实时语音转文字")
            self.setMinimumSize(800, 600)
            
            # 主布局
            central_widget = QWidget()
            self.setCentralWidget(central_widget)
            main_layout = QVBoxLayout(central_widget)
            
            # 顶部控制区
            top_layout = QHBoxLayout()
            
            # 设备选择
            device_layout = QVBoxLayout()
            device_label = QLabel("录音设备:")
            self.device_combo = QComboBox()
            self.device_combo.setMinimumWidth(250)
            self.refresh_device_button = QPushButton("刷新")
            self.refresh_device_button.clicked.connect(self.load_devices)
            
            device_combo_layout = QHBoxLayout()
            device_combo_layout.addWidget(self.device_combo)
            device_combo_layout.addWidget(self.refresh_device_button)
            
            device_layout.addWidget(device_label)
            device_layout.addLayout(device_combo_layout)
            top_layout.addLayout(device_layout)
            
            # 语言选择
            language_layout = QVBoxLayout()
            language_label = QLabel("识别语言:")
            self.language_combo = QComboBox()
            
            # 添加支持的语言
            languages = self.transcriber.get_available_languages()
            for lang in languages:
                self.language_combo.addItem(lang["name"], lang["code"])
            
            # 默认选择中文
            for i in range(self.language_combo.count()):
                if self.language_combo.itemData(i) == "zh":
                    self.language_combo.setCurrentIndex(i)
                    break
            
            self.language_combo.currentIndexChanged.connect(self.on_language_changed)
            language_layout.addWidget(language_label)
            language_layout.addWidget(self.language_combo)
            top_layout.addLayout(language_layout)
            
            # 翻译选项
            translate_layout = QVBoxLayout()
            translate_label = QLabel("翻译选项:")
            self.translate_combo = QComboBox()
            self.translate_combo.addItem("原始文本", False)
            self.translate_combo.addItem("翻译为英文", True)
            self.translate_combo.currentIndexChanged.connect(self.on_translate_changed)
            translate_layout.addWidget(translate_label)
            translate_layout.addWidget(self.translate_combo)
            top_layout.addLayout(translate_layout)
            
            # 模型选择
            model_layout = QVBoxLayout()
            model_label = QLabel("语音模型:")
            self.model_button = QPushButton("选择模型")
            self.model_button.clicked.connect(self.select_model)
            model_layout.addWidget(model_label)
            model_layout.addWidget(self.model_button)
            top_layout.addLayout(model_layout)
            
            main_layout.addLayout(top_layout)
            
            # 文本显示区
            self.text_edit = QTextEdit()
            self.text_edit.setReadOnly(True)
            self.text_edit.setFont(QFont("Microsoft YaHei", 12))
            main_layout.addWidget(self.text_edit)
            
            # 底部控制区
            bottom_layout = QHBoxLayout()
            
            # 录音控制
            self.record_button = QPushButton("开始录音")
            self.record_button.clicked.connect(self.toggle_recording)
            bottom_layout.addWidget(self.record_button)
            
            # 转录按钮
            self.transcribe_button = QPushButton("转录")
            self.transcribe_button.clicked.connect(self.transcribe_recording)
            self.transcribe_button.setEnabled(False)
            bottom_layout.addWidget(self.transcribe_button)
            
            # 清空按钮
            self.clear_button = QPushButton("清空")
            self.clear_button.clicked.connect(self.clear_text)
            bottom_layout.addWidget(self.clear_button)
            
            # 复制按钮
            self.copy_button = QPushButton("复制")
            self.copy_button.clicked.connect(self.copy_text)
            bottom_layout.addWidget(self.copy_button)
            
            # 保存按钮
            self.save_button = QPushButton("保存")
            self.save_button.clicked.connect(self.save_text)
            bottom_layout.addWidget(self.save_button)
            
            main_layout.addLayout(bottom_layout)
        
        def load_devices(self):
            """加载录音设备列表"""
            # 清空设备列表
            self.device_combo.clear()
            
            # 获取设备列表
            devices = self.audio_manager.get_devices()
            
            # 添加设备到下拉框
            for device in devices:
                self.device_combo.addItem(device.name)
                if device.default:
                    self.device_combo.setCurrentText(device.name)
            
            # 如果指定了设备名称，则选择该设备
            if self.device_name and self.device_name in [device.name for device in devices]:
                self.device_combo.setCurrentText(self.device_name)
        
        def on_language_changed(self, index):
            """语言选择变更事件"""
            language_code = self.language_combo.itemData(index)
            self.transcriber.set_language(language_code)
        
        def on_translate_changed(self, index):
            """翻译选项变更事件"""
            translate = self.translate_combo.itemData(index)
            self.transcriber.set_translate(translate)
        
        def select_model(self):
            """选择模型"""
            dialog = ModelSelectionDialog(self.model_downloader, self)
            if dialog.exec() == QDialog.DialogCode.Accepted and dialog.selected_model:
                models = self.model_downloader.get_available_models()
                model_info = models[dialog.selected_model]
                self.model_path = model_info["path"]
                
                # 重新加载模型
                self.transcriber = Transcriber(self.model_path)
                
                # 重新设置语言和翻译选项
                language_code = self.language_combo.itemData(self.language_combo.currentIndex())
                self.transcriber.set_language(language_code)
                
                translate = self.translate_combo.itemData(self.translate_combo.currentIndex())
                self.transcriber.set_translate(translate)
                
                QMessageBox.information(self, "模型已加载", f"模型 {dialog.selected_model} 已加载")
        
        def toggle_recording(self):
            """切换录音状态"""
            if self.audio_manager.is_recording:
                # 停止录音
                self.audio_manager.stop_recording()
                self.record_button.setText("开始录音")
                self.transcribe_button.setEnabled(True)
                
                # 获取临时文件
                self.temp_wav_file = self.audio_manager.get_temp_wav_file()
            else:
                # 开始录音
                device_name = self.device_combo.currentText()
                self.audio_manager.start_recording(device_name)
                self.record_button.setText("停止录音")
                self.transcribe_button.setEnabled(False)
                self.temp_wav_file = ""
        
        def transcribe_recording(self):
            """转录录音"""
            if not self.temp_wav_file:
                QMessageBox.warning(self, "无录音数据", "没有可用的录音数据，请先录音")
                return
            
            # 禁用按钮
            self.transcribe_button.setEnabled(False)
            self.record_button.setEnabled(False)
            
            # 创建并启动转录线程
            self.transcription_thread = TranscriptionThread(self.transcriber, self.temp_wav_file)
            self.transcription_thread.result_signal.connect(self.on_transcription_result)
            self.transcription_thread.finished.connect(lambda: self.record_button.setEnabled(True))
            self.transcription_thread.start()
        
        def on_transcription_result(self, text):
            """转录结果处理"""
            self.transcription_text += text + "\n\n"
            self.text_edit.setText(self.transcription_text)
            
            # 滚动到底部
            cursor = self.text_edit.textCursor()
            cursor.movePosition(cursor.MoveOperation.End)
            self.text_edit.setTextCursor(cursor)
            
            # 重新启用按钮
            self.transcribe_button.setEnabled(True)
        
        def clear_text(self):
            """清空文本"""
            self.transcription_text = ""
            self.text_edit.clear()
        
        def copy_text(self):
            """复制文本到剪贴板"""
            text = self.text_edit.toPlainText()
            if text:
                if CLIPBOARD_AVAILABLE:
                    pyperclip.copy(text)
                    QMessageBox.information(self, "已复制", "文本已复制到剪贴板")
                else:
                    QMessageBox.warning(self, "功能不可用", "剪贴板功能不可用，请安装pyperclip库")
        
        def save_text(self):
            """保存文本到文件"""
            text = self.text_edit.toPlainText()
            if not text:
                QMessageBox.warning(self, "无内容", "没有可保存的内容")
                return
            
            # 生成默认文件名
            default_filename = f"autotalk_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
            
            # 打开文件对话框
            file_path, _ = QFileDialog.getSaveFileName(
                self, "保存文件", default_filename, "文本文件 (*.txt);;所有文件 (*)"
            )
            
            if file_path:
                try:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(text)
                    QMessageBox.information(self, "保存成功", f"文件已保存到 {file_path}")
                except Exception as e:
                    QMessageBox.critical(self, "保存失败", f"保存文件时出错: {e}")

# 命令行界面版本
class CommandLineUI:
    """命令行界面，在GUI不可用时使用"""
    
    def __init__(self, model_path: str, device_name: Optional[str] = None, skip_download: bool = False):
        """初始化命令行界面
        
        Args:
            model_path: 模型路径
            device_name: 设备名称
            skip_download: 是否跳过下载
        """
        logger.info("使用命令行界面")
        
        # 设置控制台输出编码
        try:
            # Windows平台特定编码设置
            if sys.platform == 'win32':
                import ctypes
                k_handle = ctypes.windll.kernel32
                k_handle.SetConsoleCP(65001)  # 设置控制台输入代码页为UTF-8
                k_handle.SetConsoleOutputCP(65001)  # 设置控制台输出代码页为UTF-8
                sys.stdout.reconfigure(encoding='utf-8')
                sys.stdin.reconfigure(encoding='utf-8')
        except Exception as e:
            logger.warning(f"设置控制台编码失败: {e}")
        
        # 音频管理器
        self.audio_manager = AudioManager()
        
        # 模型下载器
        self.model_downloader = ModelDownloader()
        
        # 模型路径
        self.model_path = model_path
        
        # 检查模型
        if not self.is_valid_model_path() and not skip_download:
            self.download_model()
        
        # 转录器
        self.transcriber = Transcriber(self.model_path)
        
        # 设备名称
        self.device_name = device_name
        self.device = None
        
        # 录音文件
        self.recording_file = ""
        
        # 转录结果
        self.transcription_text = ""
    
    def is_valid_model_path(self) -> bool:
        """检查模型路径是否有效"""
        # OpenAI Whisper模型总是有效的
        if self.model_path.startswith("whisper-"):
            return True
        
        # 检查文件是否存在
        return os.path.exists(self.model_path)
    
    def download_model(self):
        """下载模型"""
        print("\n=== 可用模型列表 ===")
        models = self.model_downloader.get_available_models()
        
        # 显示模型列表
        for i, (name, info) in enumerate(models.items(), 1):
            status = "[已下载]" if info["downloaded"] else "[未下载]"
            print(f"{i}. {name} - {info['description']} {status}")
        
        # 选择模型
        while True:
            try:
                choice = input("\n请选择模型编号 (0=退出): ")
                if choice == "0":
                    print("取消选择模型，将使用默认模型")
                    return
                    
                idx = int(choice) - 1
                if idx < 0 or idx >= len(models):
                    print("输入无效，请重新选择")
                    continue
                    
                selected_model = list(models.keys())[idx]
                model_info = models[selected_model]
                
                if model_info["downloaded"]:
                    print(f"模型已下载，将使用: {selected_model}")
                    self.model_path = model_info["path"]
                    return
                
                # 下载模型
                print(f"开始下载模型: {selected_model}")
                
                def progress_callback(progress):
                    percent = int(progress * 100)
                    print(f"\r下载进度: [{percent}%]", end="", flush=True)
                
                success = self.model_downloader.download_model(selected_model, progress_callback)
                print()  # 换行
                
                if success:
                    print(f"模型下载成功: {selected_model}")
                    self.model_path = model_info["path"]
                    return
                else:
                    print(f"模型下载失败: {selected_model}")
                    # 重新选择
                
            except (ValueError, IndexError):
                print("输入无效，请重新选择")
            except KeyboardInterrupt:
                print("\n取消下载，将使用默认模型")
                return
    
    def select_device(self):
        """选择录音设备"""
        devices = self.audio_manager.get_devices()
        
        if not devices:
            print("没有找到可用的录音设备")
            return False
        
        print("\n=== 可用录音设备 ===")
        for i, device in enumerate(devices, 1):
            default = " (默认)" if device.default else ""
            print(f"{i}. {device.name}{default}")
        
        # 如果指定了设备名称，尝试找到它
        if self.device_name:
            for device in devices:
                if device.name == self.device_name:
                    self.device = device
                    print(f"使用指定的设备: {device.name}")
                    return True
        
        # 否则让用户选择
        try:
            choice = input("\n请选择设备编号 (0=使用默认): ")
            if choice == "0":
                # 使用默认设备
                for device in devices:
                    if device.default:
                        self.device = device
                        print(f"使用默认设备: {device.name}")
                        return True
                
                # 如果没有找到默认设备，使用第一个
                self.device = devices[0]
                print(f"使用设备: {self.device.name}")
                return True
            
            idx = int(choice) - 1
            if idx < 0 or idx >= len(devices):
                print("输入无效，使用默认设备")
                return self.select_device()
            
            self.device = devices[idx]
            print(f"使用设备: {self.device.name}")
            return True
            
        except (ValueError, IndexError):
            print("输入无效，使用默认设备")
            return self.select_device()
        except KeyboardInterrupt:
            print("\n取消选择，使用默认设备")
            return False
    
    def record_audio(self):
        """录制音频"""
        if not self.select_device():
            print("未选择设备，使用默认设备")
        
        print("\n=== 录音模式 ===")
        print("开始录音，按 Ctrl+C 停止...")
        
        try:
            # 开始录音
            device_name = self.device.name if self.device else None
            self.audio_manager.start_recording(device_name)
            
            # 等待用户停止
            while True:
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n停止录音")
            self.audio_manager.stop_recording()
            
            # 保存录音
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"recordings/autotalk_{timestamp}.wav"
            os.makedirs("recordings", exist_ok=True)
            
            self.audio_manager.save_recording(filename)
            self.recording_file = filename
            print(f"录音已保存到: {filename}")
            return True
        except Exception as e:
            print(f"录音出错: {e}")
            return False
    
    def select_file(self):
        """选择音频文件"""
        print("\n=== 选择音频文件 ===")
        print("输入音频文件路径 (wav 格式):")
        
        while True:
            try:
                file_path = input("> ")
                if not file_path:
                    return False
                
                if not os.path.exists(file_path):
                    print(f"文件不存在: {file_path}")
                    continue
                
                self.recording_file = file_path
                return True
            except KeyboardInterrupt:
                print("\n取消选择文件")
                return False
    
    def transcribe(self):
        """转录音频"""
        if not self.recording_file:
            print("没有可用的录音文件，请先录音或选择文件")
            return False
        
        print("\n转录中，请稍候...")
        try:
            result = self.transcriber.transcribe_file(self.recording_file)
            print("\n=== 转录结果 ===")
            print(result)
            
            self.transcription_text = result
            return True
        except Exception as e:
            print(f"转录失败: {e}")
            traceback.print_exc()
            return False
    
    def save_text(self):
        """保存转录结果"""
        if not self.transcription_text:
            print("没有可保存的转录结果")
            return False
        
        print("\n=== 保存转录结果 ===")
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        default_filename = f"autotalk_{timestamp}.txt"
        
        print(f"输入保存文件名 (默认: {default_filename}):")
        try:
            filename = input("> ").strip()
            if not filename:
                filename = default_filename
            
            # 确保文件扩展名
            if not filename.endswith(".txt"):
                filename += ".txt"
            
            # 写入文件
            with open(filename, "w", encoding="utf-8") as f:
                f.write(self.transcription_text)
            
            print(f"转录结果已保存到: {filename}")
            return True
        except KeyboardInterrupt:
            print("\n取消保存")
            return False
        except Exception as e:
            print(f"保存失败: {e}")
            return False
    
    def copy_text(self):
        """复制转录结果到剪贴板"""
        if not self.transcription_text:
            print("没有可复制的转录结果")
            return False
        
        if not CLIPBOARD_AVAILABLE:
            print("复制功能不可用，请安装pyperclip库")
            return False
        
        try:
            pyperclip.copy(self.transcription_text)
            print("转录结果已复制到剪贴板")
            return True
        except Exception as e:
            print(f"复制失败: {e}")
            return False
    
    def set_language(self):
        """设置语言"""
        languages = self.transcriber.get_available_languages()
        
        print("\n=== 设置语言 ===")
        for i, lang in enumerate(languages, 1):
            print(f"{i}. {lang['name']} ({lang['code']})")
        
        try:
            choice = input("\n请选择语言编号: ")
            idx = int(choice) - 1
            if idx < 0 or idx >= len(languages):
                print("输入无效，使用默认语言 (中文)")
                return False
            
            lang = languages[idx]
            self.transcriber.set_language(lang["code"])
            print(f"语言已设置为: {lang['name']}")
            return True
        except (ValueError, IndexError):
            print("输入无效，使用默认语言 (中文)")
            return False
        except KeyboardInterrupt:
            print("\n取消设置语言")
            return False
    
    def set_translate(self):
        """设置翻译选项"""
        print("\n=== 翻译设置 ===")
        print("1. 原始文本 (不翻译)")
        print("2. 翻译为英文")
        
        try:
            choice = input("\n请选择翻译选项: ")
            if choice == "1":
                self.transcriber.set_translate(False)
                print("已设置为不翻译")
                return True
            elif choice == "2":
                self.transcriber.set_translate(True)
                print("已设置为翻译为英文")
                return True
            else:
                print("输入无效，使用默认设置 (不翻译)")
                return False
        except KeyboardInterrupt:
            print("\n取消设置翻译选项")
            return False
    
    def run(self):
        """运行命令行界面"""
        print("\n==================================================")
        print("  AutoTalk-Python 命令行界面")
        print("  实时语音转文字程序")
        print("==================================================")
        print(f"使用模型: {self.model_path}")
        print("提示: 由于PyQt6加载失败，将使用命令行界面\n")
        
        while True:
            print("\n=== 主菜单 ===")
            print("1. 录制音频")
            print("2. 选择音频文件")
            print("3. 转录音频")
            print("4. 保存转录结果")
            print("5. 复制转录结果")
            print("6. 设置语言")
            print("7. 设置翻译选项")
            print("8. 更改模型")
            print("9. 测试Whisper直接转写")
            print("10. 实时语音转录")
            print("0. 退出")
            
            try:
                choice = input("\n请选择操作: ")
                
                if choice == "1":
                    self.record_audio()
                elif choice == "2":
                    self.select_file()
                elif choice == "3":
                    self.transcribe()
                elif choice == "4":
                    self.save_text()
                elif choice == "5":
                    self.copy_text()
                elif choice == "6":
                    self.set_language()
                elif choice == "7":
                    self.set_translate()
                elif choice == "8":
                    self.download_model()
                    self.transcriber = Transcriber(self.model_path)
                elif choice == "9":
                    self.test_whisper_direct()
                elif choice == "10":
                    self.realtime_transcribe()
                elif choice == "0":
                    print("退出程序")
                    break
                else:
                    print("输入无效，请重新选择")
            
            except KeyboardInterrupt:
                print("\n\n按Ctrl+C退出...")
                break
            except Exception as e:
                print(f"操作过程中出错: {e}")
                traceback.print_exc()
        
        return 0
    
    def test_whisper_direct(self):
        """测试Whisper直接转写录音"""
        print("\n=== Whisper直接转写测试 ===")
        
        # 检查是否有录音
        if not self.recording_file:
            print("没有可用的录音文件，先录制一段音频")
            if not self.record_audio():
                return False
        
        try:
            import whisper
            import torch
            
            print(f"使用录音文件: {self.recording_file}")
            
            # 打印GPU可用信息
            if torch.cuda.is_available():
                print(f"使用GPU: {torch.cuda.get_device_name(0)}")
            else:
                print("使用CPU处理 (速度较慢)")
            
            # 加载模型
            print("加载Whisper tiny模型...")
            model = whisper.load_model("tiny")
            print("模型加载成功，开始转写...")
            
            # 转写
            result = model.transcribe(self.recording_file)
            
            print("\n==== Whisper直接转写结果 ====")
            print(result["text"])
            print("==============================")
            
            # 保存结果
            self.transcription_text = result["text"]
            
            return True
        except ImportError:
            print("未安装whisper模块，请安装: pip install openai-whisper")
            return False
        except Exception as e:
            print(f"Whisper测试失败: {e}")
            import traceback
            traceback.print_exc()
            return False

    def realtime_transcribe(self):
        """实时语音转录功能"""
        print("\n=== 实时语音转录 ===")
        print("开始录音并实时转录，按 Ctrl+C 停止...")
        
        try:
            # 导入实时转录器
            from transcriber import RealtimeTranscriber
            
            # 创建实时转录器
            realtime_transcriber = RealtimeTranscriber(self.model_path)
            
            # 设置语言和翻译选项
            realtime_transcriber.set_language(self.transcriber.language)
            realtime_transcriber.set_translate(self.transcriber.translate)
            
            # 录音设备选择
            if not self.device:
                devices = self.audio_manager.get_devices()
                
                print("\n=== 可用录音设备 ===")
                for i, device in enumerate(devices, 1):
                    default_mark = " (默认)" if device.default else ""
                    print(f"{i}. {device.name}{default_mark}")
                
                while True:
                    try:
                        choice = input("\n请选择设备编号 (0=使用默认): ")
                        if not choice.strip():
                            self.device = None
                            break
                            
                        choice = int(choice)
                        if choice == 0:
                            self.device = None
                            break
                            
                        if 1 <= choice <= len(devices):
                            self.device = devices[choice-1]
                            break
                        else:
                            print("无效的选择，请重试")
                    except ValueError:
                        print("请输入有效的数字")
            
            device_name = self.device.name if self.device else None
            print(f"使用设备: {device_name if device_name else '默认'}")
            
            # 启动实时转录
            print("\n开始实时转录...")
            realtime_transcriber.start()
            
            # 设置录音回调函数
            def audio_callback(audio_data):
                realtime_transcriber.add_audio_chunk(audio_data)
            
            # 开始录音
            self.audio_manager.start_recording(device_name, audio_callback)
            
            # 等待用户按Ctrl+C停止
            try:
                import time
                print("\n正在转录中... (按 Ctrl+C 停止)")
                while True:
                    time.sleep(0.5)
            except KeyboardInterrupt:
                print("\n\n停止实时转录...")
            finally:
                # 停止录音
                self.audio_manager.stop_recording()
                
                # 停止转录
                result = realtime_transcriber.stop()
                
                # 保存录音
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                filename = f"recordings/autotalk_{timestamp}.wav"
                self.audio_manager.save_recording(filename)
                print(f"录音已保存到: {filename}")
                
                # 显示转录结果
                self.recording_file = filename
                self.transcription_text = result
                
                print("\n=== 实时转录结果 ===")
                print(result)
            
            return True
            
        except ImportError:
            print("无法导入实时转录器，请确保已安装whisper库")
            return False
        except Exception as e:
            print(f"实时转录出错: {e}")
            import traceback
            traceback.print_exc()
            return False

def run_gui(model_path: str, device_name: Optional[str] = None, skip_download: bool = False):
    """启动PyQt图形界面
    
    Args:
        model_path: 模型文件路径
        device_name: 录音设备名称
        skip_download: 是否跳过下载资源
    """
    try:
        from PyQt6.QtWidgets import QApplication
        app = QApplication(sys.argv)
        window = MainWindow(model_path, device_name, skip_download)
        window.show()
        return app.exec()
    except Exception as e:
        logger.error(f"启动GUI时出错: {e}")
        logger.info("切换到命令行界面")
        run_cli(model_path, device_name, skip_download)

def run_cli(model_path: str, device_name: Optional[str] = None, skip_download: bool = False):
    """启动命令行界面
    
    Args:
        model_path: 模型文件路径
        device_name: 录音设备名称
        skip_download: 是否跳过下载资源
    """
    try:
        # 设置控制台编码
        if sys.platform == 'win32':
            import ctypes
            k_handle = ctypes.windll.kernel32
            k_handle.SetConsoleCP(65001)  # 设置控制台输入代码页为UTF-8
            k_handle.SetConsoleOutputCP(65001)  # 设置控制台输出代码页为UTF-8
            sys.stdout.reconfigure(encoding='utf-8')
            sys.stdin.reconfigure(encoding='utf-8')
            
            # 设置环境变量
            os.environ['PYTHONIOENCODING'] = 'utf-8'
    except Exception as e:
        logger.warning(f"设置控制台编码失败: {e}")
    
    # 测试Whisper能否直接工作
    test_whisper_working()
    
    cli = CommandLineUI(model_path, device_name, skip_download)
    return cli.run()

def test_whisper_working():
    """测试Whisper是否可以正常工作"""
    print("\n=== 测试Whisper功能 ===")
    try:
        import whisper
        print("√ whisper模块已安装")
        
        # 尝试加载tiny模型
        model = whisper.load_model("tiny")
        print("√ 成功加载whisper tiny模型")
        
        # 检查录音目录中是否有wav文件可用于测试
        recording_files = []
        recordings_dir = Path("recordings")
        if recordings_dir.exists():
            for file in recordings_dir.glob("*.wav"):
                recording_files.append(str(file))
        
        if recording_files:
            # 使用最新的录音文件进行测试
            latest_file = max(recording_files, key=os.path.getctime)
            print(f"√ 找到录音文件: {latest_file}")
            
            # 尝试转写
            print("尝试转写录音文件...")
            result = model.transcribe(latest_file)
            print(f"√ 转写成功! 结果: {result['text']}")
            print("Whisper功能测试通过!")
        else:
            print("✓ Whisper模型加载正常，但未找到可用的录音文件进行测试")
            print("请先录制一段音频，然后再尝试转写")
        
    except ImportError:
        print("✗ 未安装whisper模块，请安装: pip install openai-whisper")
    except Exception as e:
        print(f"✗ Whisper测试失败: {e}")
        import traceback
        traceback.print_exc()
    
    print("继续启动AutoTalk主程序...\n")

def select_model(downloader: ModelDownloader, current_model: str) -> str:
    """选择要使用的模型
    
    Args:
        downloader: 模型下载器
        current_model: 当前使用的模型名
    
    Returns:
        选择的模型路径
    """
    models = downloader.get_available_models()
    
    # 创建选项列表
    options = []
    i = 1
    model_map = {}
    
    # 先添加所有的ggml模型
    for name, info in sorted(models.items()):
        if name.startswith("ggml-"):
            status = "[已下载]" if info["downloaded"] else "[未下载]"
            option = f"{i}. {name} - {info['description']} {status}"
            options.append(option)
            model_map[i] = name
            i += 1
    
    # 再添加所有的OpenAI原生Whisper模型
    for name, info in sorted(models.items()):
        if name.startswith("whisper-"):
            status = ""  # OpenAI模型不需要显示下载状态
            option = f"{i}. {name} - {info['description']} {status}"
            options.append(option)
            model_map[i] = name
            i += 1
    
    # 打印选项
    print("\n=== 可用模型列表 ===")
    for option in options:
        print(option)
    
    # 获取用户选择
    while True:
        try:
            choice = input("\n请选择模型编号 (0=退出): ")
            if not choice.strip():
                return current_model
                
            choice = int(choice)
            if choice == 0:
                print("取消选择模型，将使用默认模型")
                return current_model
                
            if choice in model_map:
                model_name = model_map[choice]
                
                # 检查是否需要下载
                if model_name.startswith("whisper-"):
                    # OpenAI原生Whisper模型直接返回
                    print(f"将使用OpenAI Whisper {model_name.split('-')[1]}模型")
                    return model_name
                
                if not models[model_name]["downloaded"]:
                    print(f"开始下载模型: {model_name}")
                    if downloader.download_model(model_name):
                        print(f"模型下载成功: {model_name}")
                    else:
                        print(f"\n模型下载失败: {model_name}")
                        continue
                
                print(f"模型已下载，将使用: {model_name}")
                # 返回models目录下的模型路径，但不添加双重目录
                if model_name.startswith("models/") or model_name.startswith("models\\"):
                    return model_name
                return os.path.join("models", model_name)
            else:
                print("无效的选择，请重试")
        except ValueError:
            print("请输入有效的数字")

def run_app(model_path: str, device_name: Optional[str] = None, skip_download: bool = False):
    """运行应用程序
    
    Args:
        model_path: 模型文件路径
        device_name: 录音设备名称
        skip_download: 是否跳过下载资源
    """
    try:
        import PyQt6
        logger.info("使用PyQt6图形界面")
        run_gui(model_path, device_name, skip_download)
    except ImportError:
        # 使用命令行界面
        logger.info("使用命令行界面")
        run_cli(model_path, device_name, skip_download) 