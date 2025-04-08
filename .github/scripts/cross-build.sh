#!/bin/bash

# 设置错误时退出
set -e

# 显示执行的命令
set -x

# 检查参数
if [ $# -lt 2 ]; then
    echo "用法: $0 <目标平台> <加速器类型> [CUDA版本]"
    echo "示例: $0 x86_64-pc-windows-msvc NVIDIA-GPU 11.8.0"
    exit 1
fi

TARGET=$1
ACCELERATOR=$2
CUDA_VERSION=${3:-"11.8.0"}

# 设置变量
ARTIFACT_NAME="autotalk"
ASSET_NAME="autotalk"

# 根据目标平台设置文件名
case $TARGET in
    *windows*)
        if [ "$ACCELERATOR" = "NVIDIA-GPU" ]; then
            ARTIFACT_NAME="autotalk-gpu.exe"
            ASSET_NAME="autotalk-windows-x64-gpu.zip"
        else
            ARTIFACT_NAME="autotalk.exe"
            ASSET_NAME="autotalk-windows-x64.zip"
        fi
        ;;
    *linux*)
        if [ "$ACCELERATOR" = "NVIDIA-GPU" ]; then
            ARTIFACT_NAME="autotalk-gpu"
            ASSET_NAME="autotalk-linux-x64-gpu.tar.gz"
        else
            ARTIFACT_NAME="autotalk"
            ASSET_NAME="autotalk-linux-x64.tar.gz"
        fi
        ;;
    *apple-darwin*)
        ARTIFACT_NAME="autotalk"
        ASSET_NAME="autotalk-macos-x64.tar.gz"
        ;;
esac

# 安装交叉编译工具链
install_cross_compiler() {
    echo "安装交叉编译工具链..."
    sudo apt-get update
    sudo apt-get install -y llvm-dev libclang-dev clang cmake pkg-config libssl-dev

    case $TARGET in
        *windows*)
            echo "安装Windows交叉编译工具链..."
            sudo apt-get install -y mingw-w64
            if [[ "$TARGET" == *"x86_64"* ]]; then
                echo "CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER=x86_64-w64-mingw32-gcc" >> $GITHUB_ENV
            elif [[ "$TARGET" == *"aarch64"* ]]; then
                echo "CARGO_TARGET_AARCH64_PC_WINDOWS_MSVC_LINKER=aarch64-w64-mingw32-gcc" >> $GITHUB_ENV
            fi
            ;;
        aarch64-unknown-linux-gnu)
            echo "安装Linux ARM64交叉编译工具链..."
            sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
            echo "CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc" >> $GITHUB_ENV
            ;;
        *apple-darwin*)
            echo "安装macOS交叉编译工具链..."
            sudo apt-get install -y clang
            git clone https://github.com/tpoechtrager/osxcross
            cd osxcross
            wget -nc https://github.com/joseluisq/macosx-sdks/releases/download/11.3/MacOSX11.3.sdk.tar.xz
            mv MacOSX11.3.sdk.tar.xz tarballs/
            UNATTENDED=1 ./build.sh
            echo "PATH=$PATH:$(pwd)/target/bin" >> $GITHUB_ENV
            cd ..
            ;;
    esac
}

# 安装CUDA
install_cuda() {
    if [ "$ACCELERATOR" = "NVIDIA-GPU" ]; then
        echo "安装CUDA..."
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
        sudo dpkg -i cuda-keyring_1.0-1_all.deb
        sudo apt-get update
        sudo apt-get -y --no-install-recommends install \
            cuda-compiler-11-8 \
            cuda-libraries-11-8 \
            cuda-libraries-dev-11-8 \
            cuda-cudart-11-8 \
            cuda-cudart-dev-11-8 \
            cuda-nvcc-11-8 \
            libcublas-11-8 \
            libcublas-dev-11-8
        echo "CUDA_PATH=/usr/local/cuda-11.8" >> $GITHUB_ENV
        echo "/usr/local/cuda-11.8/bin" >> $GITHUB_PATH
        echo "LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64:$LD_LIBRARY_PATH" >> $GITHUB_ENV
    fi
}

# 构建项目
build_project() {
    echo "构建项目..."
    if [ "$ACCELERATOR" = "NVIDIA-GPU" ]; then
        echo "GGML_CUDA=1" >> $GITHUB_ENV
        cargo build --release --target $TARGET --features real_whisper
    else
        echo "GGML_CUDA=0" >> $GITHUB_ENV
        cargo build --release --target $TARGET
    fi
}

# 打包应用
package_app() {
    echo "打包应用..."
    mkdir -p release-package
    cp target/$TARGET/release/$ARTIFACT_NAME release-package/
    cp -r assets release-package/
    cp -r resources release-package/
    cp README.md release-package/
    cp LICENSE release-package/

    # 创建平台信息文件
    echo "# 平台信息" > release-package/平台信息.txt
    echo "目标平台: $TARGET" >> release-package/平台信息.txt
    echo "加速器: $ACCELERATOR" >> release-package/平台信息.txt

    # 对于GPU版本，添加使用说明
    if [ "$ACCELERATOR" = "NVIDIA-GPU" ]; then
        echo "# GPU加速版本使用说明" > release-package/GPU加速说明.txt
        echo "本版本支持NVIDIA GPU加速，需要安装CUDA运行时环境。" >> release-package/GPU加速说明.txt
        echo "要求：" >> release-package/GPU加速说明.txt
        echo "1. 安装NVIDIA显卡驱动" >> release-package/GPU加速说明.txt
        echo "2. 安装CUDA Toolkit $CUDA_VERSION或更高版本" >> release-package/GPU加速说明.txt
    fi

    # 根据平台选择打包方式
    cd release-package
    if [[ "$TARGET" == *"windows"* ]]; then
        7z a ../$ASSET_NAME *
    else
        tar -czvf ../$ASSET_NAME *
    fi
    cd ..
}

# 主流程
main() {
    install_cross_compiler
    install_cuda
    build_project
    package_app
}

# 执行主流程
main 