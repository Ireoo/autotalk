#!/bin/bash

echo "==========================================="
echo "构建GPU加速版本 - AutoTalk"
echo "==========================================="

# 检查CUDA环境
if ! command -v nvcc &> /dev/null; then
    echo "[错误] 未找到CUDA编译器(nvcc)"
    echo "请安装CUDA Toolkit并确保其在系统PATH中"
    echo "可从https://developer.nvidia.com/cuda-downloads下载"
    exit 1
fi

# 输出CUDA版本信息
echo "[信息] 检测到CUDA:"
nvcc --version | grep "release"

# 设置编译环境变量
export WHISPER_CUBLAS=1

echo "[信息] 开始构建..."
cargo build --release --features real_whisper

if [ $? -ne 0 ]; then
    echo "[错误] 构建失败"
    exit 1
fi

echo "[信息] 构建成功，正在准备发布包..."

# 创建发布目录
mkdir -p release-gpu
rm -rf release-gpu/*

# 复制可执行文件
cp target/release/autotalk release-gpu/autotalk-gpu
chmod +x release-gpu/autotalk-gpu

# 复制其他必要文件
if [ -d "assets" ]; then
    cp -r assets release-gpu/
fi

if [ -d "resources" ]; then
    cp -r resources release-gpu/
fi

cp -f README.md release-gpu/ 2>/dev/null || true
cp -f LICENSE release-gpu/ 2>/dev/null || true

# 创建GPU加速说明文件
cat > release-gpu/GPU加速说明.txt << EOL
# GPU加速版本使用说明
本版本支持NVIDIA GPU加速，需要安装CUDA运行时环境。
要求：
1. 安装NVIDIA显卡驱动
2. 安装CUDA Toolkit 11.8或更高版本
3. 确保LD_LIBRARY_PATH包含CUDA库目录
EOL

echo "==========================================="
echo "构建完成!"
echo "输出目录: $(pwd)/release-gpu"
echo "===========================================" 