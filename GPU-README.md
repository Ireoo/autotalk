# AutoTalk GPU 加速版本使用指南

本文档提供有关如何编译和使用支持GPU加速的AutoTalk版本的指南。

## 支持的加速方式

AutoTalk支持以下硬件加速方式：

1. **CUDA加速** - 适用于NVIDIA显卡
2. **Metal加速** - 适用于Apple Silicon和Intel Mac设备

## 构建要求

### CUDA (Windows/Linux)

- NVIDIA GPU显卡
- CUDA Toolkit 11.8或更高版本
- 兼容的GPU驱动
- Rust开发环境
- LLVM和Clang

### Metal (MacOS)

- macOS 10.15 (Catalina)或更高版本
- 支持Metal的Apple设备
- Rust开发环境
- XCode命令行工具

## 使用预编译的构建脚本

我们提供了针对各操作系统的构建脚本，可以简化GPU加速版本的编译过程：

### Windows

1. 确保已安装CUDA Toolkit和兼容的GPU驱动
2. 打开命令提示符或PowerShell
3. 运行以下命令：
   ```
   build-gpu.bat
   ```
4. 编译完成后，可执行文件位于`release-gpu`目录下

### Linux

1. 确保已安装CUDA Toolkit和兼容的GPU驱动
2. 打开终端
3. 运行以下命令：
   ```
   ./build-gpu.sh
   ```
4. 编译完成后，可执行文件位于`release-gpu`目录下

### MacOS

1. 确保使用macOS 10.15或更高版本
2. 打开终端
3. 运行以下命令：
   ```
   ./build-metal.sh
   ```
4. 编译完成后，可执行文件位于`release-metal`目录下

## 使用GitHub Actions自动构建

如果您希望通过GitHub Actions自动构建GPU加速版本，我们提供了以下工作流文件：

- `.github/workflows/release-gpu.yml` - 用于CUDA加速版本(Windows/Linux)
- `.github/workflows/release-mac-metal.yml` - 用于Metal加速版本(MacOS)

您可以在GitHub仓库中启用这些工作流来自动构建GPU加速版本。

## 性能优化建议

### NVIDIA GPU用户

- 如果您有多个GPU，可以通过设置环境变量`CUDA_VISIBLE_DEVICES`来指定使用的GPU
- 对于大模型，建议使用显存8GB或以上的GPU
- 建议使用RTX系列显卡以获得最佳性能

### MacOS用户

- 对于M1/M2/M3系列芯片，Metal加速可以显著提升性能
- 对于Intel Mac，性能提升可能不如Apple Silicon明显

## 常见问题

### 找不到CUDA库

如果在运行时遇到找不到CUDA库的错误，请确保：
1. 已安装兼容的CUDA Toolkit
2. 环境变量`PATH`(Windows)或`LD_LIBRARY_PATH`(Linux)包含CUDA库目录

### MacOS安全警告

如果在MacOS上首次运行时收到安全警告，请在系统偏好设置的安全性与隐私中允许运行此应用。

### 性能不如预期

如果GPU加速效果不明显：
1. 检查GPU驱动是否是最新版本
2. 确认显卡是否被其他应用程序占用
3. 考虑使用更大的batch size进行处理

## 支持和反馈

如果您在使用GPU加速版本时遇到任何问题，请在GitHub项目页面提交Issue。 