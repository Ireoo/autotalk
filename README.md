# AutoTalk - 高性能桌面端实时语音转文字程序

AutoTalk是一个跨平台的桌面应用程序，可以实时将语音转换为文字。它使用本地Whisper模型进行语音识别，无需联网即可工作。

## 功能特点

- 使用Rust语言开发，性能高效
- 实时录音和转写
- 本地模型处理，保护隐私
- 跨平台支持(Windows, macOS, Linux)
- 可自定义设置输入设备和模型
- 首次运行自动下载所需资源

## 环境需求

- Rust编译器 (最低版本 1.60.0)
- Cargo包管理器
- 可用的麦克风设备
- 网络连接(首次运行需要下载模型和字体)

## 安装步骤

1. 克隆本仓库
```bash
git clone https://github.com/yourusername/autotalk.git
cd autotalk
```

2. 编译运行
```bash
# 编译
cargo build --release

# 运行
cargo run --release
```

也可以直接启动编译好的二进制文件：
```bash
./target/release/autotalk
```

### 资源下载

首次运行时，程序会自动检测并下载必要的资源：
- Whisper语音识别模型(可选择不同大小的模型)
- 中文字体支持

如果你有网络连接问题，也可以手动下载这些资源：

#### 手动下载Whisper模型
从[OpenAI Whisper](https://github.com/openai/whisper)或[whisper.cpp](https://github.com/ggerganov/whisper.cpp)下载模型，推荐使用ggml格式模型。

推荐的模型：
- ggml-tiny.bin (最小，速度快但准确度低)
- ggml-base.bin (中等，平衡速度和准确度)
- ggml-small.bin (较大，准确度好但速度较慢)

将下载的模型文件放在项目根目录下的`models`文件夹中。

#### 手动下载中文字体
下载[Noto Sans SC](https://fonts.google.com/noto/specimen/Noto+Sans+SC)字体，将Regular字体文件重命名为`NotoSansSC-Regular.ttf`并放置在`assets`目录下。

## 使用方法

1. 启动程序
2. 首次运行时，选择要使用的模型并下载必要资源
3. 点击"开始录音"按钮开始捕获和转写
4. 程序会实时显示转写的文字结果
5. 点击"停止录音"停止捕获
6. 可以使用"复制"按钮将文字复制到剪贴板
7. 使用"清空"按钮清除当前文字

## 命令行参数

程序支持以下命令行参数：

```
autotalk [OPTIONS]

OPTIONS:
    -m, --model-path <MODEL_PATH>    Whisper模型路径 [默认: models/ggml-small.bin]
    -d, --device <DEVICE>            录音设备名称，不指定则使用默认设备
    -s, --skip-download              跳过检查和下载资源
    -h, --help                       显示帮助信息
    -V, --version                    显示版本信息
```

## 故障排除

- 如果无法找到默认音频设备，请在设置中手动选择设备
- 如果模型加载失败，请检查模型路径和格式是否正确
- 如果编译失败，请确保Rust工具链是最新的
- 如果下载资源失败，请检查网络连接或手动下载所需资源

## 开发说明

项目采用模块化设计：
- audio.rs - 负责音频捕获和处理
- transcriber.rs - 负责语音转文字处理
- ui.rs - 负责用户界面
- downloader.rs - 负责下载模型和字体资源

## 许可证

[MIT License](LICENSE) 