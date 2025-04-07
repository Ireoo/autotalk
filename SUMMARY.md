# AutoTalk-Python 项目总结

AutoTalk-Python 是 AutoTalk 的 Python 重构版本。该项目是一个桌面端实时语音转文字程序，使用 Whisper 模型进行语音识别。

## 项目结构

```
python_autotalk/
├── LICENSE              # MIT 许可证
├── README.md            # 项目说明文档
├── SUMMARY.md           # 本文件，项目总结
├── requirements.txt     # Python 依赖列表
├── run.py               # 启动脚本
└── src/                 # 源代码目录
    ├── audio.py         # 音频录制和处理模块
    ├── downloader.py    # 模型下载模块
    ├── main.py          # 主程序入口
    ├── transcriber.py   # 语音转录模块
    └── ui.py            # 图形用户界面模块
```

## 技术选择

1. **GUI 框架**: PyQt6，功能丰富的跨平台 GUI 框架
2. **音频处理**: PyAudio，用于音频录制和处理
3. **语音识别**: 支持两种实现:
   - whisper-cpp-python: C++ 实现，更高性能
   - OpenAI Whisper: 原始 Python 实现，更高灵活性
4. **并发处理**: 使用 QThread 处理耗时操作，避免界面卡顿

## 功能对比

| 功能 | Rust 版本 | Python 版本 |
|------|-----------|------------|
| 语音转文字 | ✅ | ✅ |
| 多语言支持 | ✅ | ✅ |
| 模型下载 | ✅ | ✅ |
| 设备选择 | ✅ | ✅ |
| 文本保存与复制 | ✅ | ✅ |
| GUI 界面 | egui | PyQt6 |

## 运行方式

1. 安装依赖: `pip install -r requirements.txt`
2. 运行程序: `python run.py`

## 依赖库版本

- PyQt6: 6.6.1
- PyAudio: 0.2.13
- whisper-cpp-python: 1.0.0
- openai-whisper: 20231117

## 注意事项

1. 首次使用需要下载语音模型
2. PyAudio 安装可能需要额外系统依赖
3. whisper-cpp-python 在 Windows 上可能需要 Visual C++ 运行时 