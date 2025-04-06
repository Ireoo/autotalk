# Whisper模型文件夹

请将下载的Whisper模型文件放在此目录中。

推荐的模型：
- ggml-tiny.bin (最小，速度快但准确度低)
- ggml-base.bin (中等，平衡速度和准确度)
- ggml-small.bin (较大，准确度好但速度较慢)

## 下载链接

您可以从以下来源下载GGML格式的Whisper模型：

1. whisper.cpp项目：
   https://github.com/ggerganov/whisper.cpp/tree/master/models

2. Hugging Face：
   https://huggingface.co/ggerganov/whisper.cpp/tree/main

下载后，将模型文件放在此目录，并确保文件名与程序中设置的模型路径一致。
默认配置下，程序将寻找 `models/ggml-small.bin` 文件。