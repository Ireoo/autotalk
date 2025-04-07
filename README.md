# AutoTalk - 实时语音转文字工具

AutoTalk是一个基于Python的实时语音转文字工具，使用Whisper语音识别技术，支持多种语言和即时翻译功能。

## 功能特点

- **实时语音转文本**: 实时录制麦克风输入并转换为文本
- **多语言支持**: 支持中文、英文、日文等多种语言
- **转换与翻译**: 可选择将语音转换为其他语言
- **双界面模式**: 支持GUI图形界面和命令行界面
- **高性能转录**: 支持使用C++实现的whisper-cpp或原始Python版本

## 安装说明

### 基本安装

1. 克隆仓库:
```bash
git clone https://github.com/yourusername/autotalk.git
cd autotalk
```

2. 安装基本依赖:
```bash
pip install -r requirements.txt
```

### 完整功能安装

要启用所有功能，需要额外安装:

1. **PyAudio** (音频录制):
   - Windows用户:
     ```bash
     pip install pipwin
     pipwin install pyaudio
     ```
     或下载对应Python版本的wheel: https://www.lfd.uci.edu/~gohlke/pythonlibs/#pyaudio
   
   - Linux用户:
     ```bash
     sudo apt-get install portaudio19-dev python3-pyaudio
     pip install pyaudio
     ```
   
   - macOS用户:
     ```bash
     brew install portaudio
     pip install pyaudio
     ```

2. **PyQt6** (图形界面):
   ```bash
   pip install PyQt6
   ```

3. **Whisper** (语音识别引擎，二选一):
   - 选项1: whisper-cpp-python (性能更好)
     ```bash
     # Windows用户可能需要先安装Visual C++ Build Tools
     pip install whisper-cpp-python
     ```
   
   - 选项2: openai-whisper (纯Python，更容易安装)
     ```bash
     pip install openai-whisper
     ```

### 一键安装所有依赖 (推荐)

```bash
pip install PyAudio PyQt6 whisper-cpp-python
```

## 使用方法

### 基本使用

启动程序:
```bash
python run.py
```

首次启动会下载语音模型，可能需要一些时间。

### 命令行参数

```bash
python run.py [-m MODEL_PATH] [-d DEVICE_NAME] [-s]
```

参数说明:
- `-m, --model-path`: 指定Whisper模型路径 (默认: models/demo-model.bin)
- `-d, --device`: 指定录音设备名称 (默认使用系统默认设备)
- `-s, --skip-download`: 跳过检查和下载资源

### 图形界面

如果安装了PyQt6，将启动图形界面:

- 点击"录音"按钮开始录制语音
- 停止录音后自动转录为文本
- 使用下拉菜单选择语言和翻译模式
- 可以保存、复制转录结果

### 命令行界面

如果没有PyQt6或在终端中运行，将使用命令行界面:

- 按照菜单提示操作
- 支持录音、文件转录、保存结果等功能

## 故障排除

1. **音频录制问题**:
   - 检查麦克风是否正常工作
   - 确认PyAudio安装正确
   - 查看logs/autotalk.log中的错误信息

2. **模型下载失败**:
   - 检查网络连接
   - 使用`--skip-download`跳过下载
   - 手动下载模型并放入models目录

3. **转录质量不佳**:
   - 尝试使用更大的模型(medium或large)
   - 确保录音环境噪音较小
   - 对中文识别，推荐使用ggml-medium-zh.bin模型

## 许可证

本项目使用MIT许可证 - 详见[LICENSE](LICENSE)文件

## 鸣谢

- [OpenAI Whisper](https://github.com/openai/whisper)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- 所有贡献者和问题反馈者 