#!/bin/bash

# 设置错误时退出
set -e

echo "==== 开始构建项目 ===="

# 显示当前工作目录
echo "当前工作目录: $(pwd)"

# 检查并下载依赖项
if [ ! -d "portaudio" ]; then
    echo "正在下载PortAudio..."
    git clone https://github.com/PortAudio/portaudio.git
fi

# 检查并下载 libsndfile
if [ ! -d "third_party/libsndfile" ]; then
    echo "正在下载 libsndfile..."
    mkdir -p third_party
    git clone https://github.com/libsndfile/libsndfile.git third_party/libsndfile
fi

# 检查CUDA是否已安装
check_cuda_installed() {
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        if [ -d "/usr/local/cuda" ]; then
            return 0
        else
            return 1
        fi
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        if [ -d "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# 设置CUDA路径变量
set_cuda_path() {
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        export CUDA_PATH=/usr/local/cuda
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        if [ -d "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.0" ]; then
            export CUDA_PATH="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.0"
        elif [ -d "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.8" ]; then
            export CUDA_PATH="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.8"
        else
            # 查找最新版本的CUDA
            latest_cuda=$(ls -d "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v"* 2>/dev/null | sort -r | head -n 1)
            if [ -n "$latest_cuda" ]; then
                export CUDA_PATH="$latest_cuda"
            else
                echo "未找到CUDA安装路径，将禁用GPU支持"
                export CUDA_PATH=""
            fi
        fi
    fi
    
    if [ -n "$CUDA_PATH" ]; then
        echo "找到CUDA路径: $CUDA_PATH"
    fi
}

# 下载并安装CUDA（如果尚未安装）
if ! check_cuda_installed; then
    echo "未检测到CUDA安装，正在下载并安装CUDA..."
    mkdir -p third_party/cuda
    
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        # Linux安装
        wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_520.61.05_linux.run -P third_party/cuda/
        chmod +x third_party/cuda/cuda_11.8.0_520.61.05_linux.run
        sudo sh third_party/cuda/cuda_11.8.0_520.61.05_linux.run --toolkit --silent
        export CUDA_PATH=/usr/local/cuda
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows安装
        mkdir -p third_party/cuda_installer
        wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_522.06_windows.exe -P third_party/cuda_installer/
        # 静默安装CUDA工具包
        echo "正在安装CUDA，这可能需要几分钟..."
        ./third_party/cuda_installer/cuda_11.8.0_522.06_windows.exe -s
        export CUDA_PATH="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.8"
    elif [[ "$OSTYPE" == "darwin" || "$OSTYPE" == "darwin23" ]]; then
        echo "CUDA不支持macOS，跳过CUDA安装"
    fi
else
    echo "检测到CUDA已安装，正在设置路径..."
    set_cuda_path
fi

echo "系统类型: $OSTYPE"

# 构建 PortAudio
echo "正在构建 PortAudio..."
cd portaudio
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "darwin" || "$OSTYPE" == "darwin23" ]]; then
    ./configure
    make
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    mkdir -p build
    cd build
    cmake -G "Visual Studio 17 2022" -A x64 ..
    cmake --build . --config Release
    cd ..
fi
cd ..

# 构建 libsndfile
echo "正在构建 libsndfile..."
cd third_party/libsndfile
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "darwin" || "$OSTYPE" == "darwin23" ]]; then
    mkdir -p build
    cd build
    cmake -DBUILD_SHARED_LIBS=ON ..
    cmake --build . --config Release
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    mkdir -p build
    cd build
    cmake -G "Visual Studio 17 2022" -A x64 -DBUILD_SHARED_LIBS=ON ..
    cmake --build . --config Release
fi

# 创建 Release 目录（如果不存在）
mkdir -p ../../../Release

# 复制 DLL 文件
if [ -f "build/src/Release/sndfile.dll" ]; then
    cp "build/src/Release/sndfile.dll" "../../../Release/"
    echo "已找到并复制 sndfile.dll"
elif [ -f "./Release/sndfile.dll" ]; then
    cp "./Release/sndfile.dll" "../../../Release/"
    echo "已找到并复制 sndfile.dll"
else
    echo "错误：找不到 sndfile.dll 文件"
    echo "正在搜索 sndfile.dll..."
    find . -name "sndfile.dll"
    exit 1
fi

cd ../../../

# 清理旧的构建目录
rm -rf build
mkdir -p build
cd build

# 配置CMake
echo "正在配置CMake..."

# 设置GPU加速选项
GPU_ENABLED=0
if [ -n "$CUDA_PATH" ] && [ -d "$CUDA_PATH" ]; then
    echo "启用CUDA GPU加速支持"
    GPU_ENABLED=1
else
    echo "未找到CUDA，禁用GPU加速"
fi

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows 平台配置
    if [ $GPU_ENABLED -eq 1 ]; then
        # 启用CUDA
        cmake -DCMAKE_BUILD_TYPE=Release \
              -DBUILD_SHARED_LIBS=ON \
              -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
              -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
              -DGGML_CUDA=ON \
              -DGGML_CUDA_F16=ON \
              -DGGML_CUDA_FA=ON \
              -DGGML_CUDA_GRAPHS=ON \
              -DGGML_CUDA_FORCE_MMQ=ON \
              -DGGML_CUDA_FORCE_CUBLAS=ON \
              -DCUDA_TOOLKIT_ROOT_DIR="$CUDA_PATH" \
              ..
    else
        # 禁用CUDA
        cmake -DCMAKE_BUILD_TYPE=Release \
              -DBUILD_SHARED_LIBS=ON \
              -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
              -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
              -DGGML_CUDA=OFF \
              ..
    fi
else
    # Linux/macOS 配置
    if [[ "$OSTYPE" == "linux-gnu" ]] && [ $GPU_ENABLED -eq 1 ]; then
        # Linux启用CUDA
        cmake -DCMAKE_BUILD_TYPE=Release \
              -DBUILD_SHARED_LIBS=ON \
              -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
              -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
              -DGGML_CUDA=ON \
              -DGGML_CUDA_F16=ON \
              -DGGML_CUDA_FA=ON \
              -DGGML_CUDA_GRAPHS=ON \
              -DGGML_CUDA_FORCE_MMQ=ON \
              -DGGML_CUDA_FORCE_CUBLAS=ON \
              -DCUDA_TOOLKIT_ROOT_DIR="$CUDA_PATH" \
              ..
    else
        # macOS禁用CUDA
        cmake -DCMAKE_BUILD_TYPE=Release \
              -DBUILD_SHARED_LIBS=ON \
              -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
              -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
              -DGGML_CUDA=OFF \
              ..
    fi
fi

# 构建项目
echo "正在构建项目..."
cmake --build . --config Release

cd ..

# 创建Release目录
rm -rf Release
mkdir -p Release

# 复制可执行文件
if [ -f "build/Release/autotalk.exe" ]; then
    cp -f build/Release/autotalk.exe Release/
elif [ -f "build/autotalk.exe" ]; then
    cp -f build/autotalk.exe Release/
else
    echo "错误: 找不到可执行文件"
    exit 1
fi

# 复制必要的DLL文件
echo "正在复制DLL文件..."

# 复制PortAudio DLL
if [ -f "portaudio/build/Release/portaudio.dll" ]; then
    cp -f portaudio/build/Release/portaudio.dll Release/
elif [ -f "portaudio/build/Debug/portaudio.dll" ]; then
    cp -f portaudio/build/Debug/portaudio.dll Release/
else
    echo "错误: 找不到portaudio.dll"
    exit 1
fi

# 复制whisper和其他必要的DLL文件
if [ -f "build/bin/Release/whisper.dll" ]; then
    cp -f build/bin/Release/whisper.dll Release/
    cp -f build/bin/Release/ggml.dll Release/
    cp -f build/bin/Release/ggml-cpu.dll Release/
    cp -f build/bin/Release/ggml-base.dll Release/
    # 复制GPU相关DLL
    if [ $GPU_ENABLED -eq 1 ]; then
        echo "复制GPU相关DLL文件..."
        if [ -f "build/bin/Release/ggml-cuda.dll" ]; then
            cp -f build/bin/Release/ggml-cuda.dll Release/
        fi
    fi
else
    echo "错误: 找不到whisper.dll"
    exit 1
fi

# 复制CUDA依赖库
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]] && [ $GPU_ENABLED -eq 1 ]; then
    echo "正在复制CUDA依赖库..."
    # 复制主要CUDA运行时DLL
    for dll in cudart64_*.dll cublas64_*.dll cublasLt64_*.dll; do
        if [ -f "$CUDA_PATH/bin/$dll" ]; then
            cp -f "$CUDA_PATH/bin/$dll" Release/
        fi
    done
    
    # 尝试复制cuDNN库（如果有）
    if [ -f "$CUDA_PATH/bin/cudnn64_*.dll" ]; then
        cp -f "$CUDA_PATH/bin/cudnn64_*.dll" Release/
    elif [ -d "C:/Program Files/NVIDIA/CUDNN" ]; then
        latest_cudnn=$(ls -d "C:/Program Files/NVIDIA/CUDNN/v"* 2>/dev/null | sort -r | head -n 1)
        if [ -n "$latest_cudnn" ] && [ -f "$latest_cudnn/bin/cudnn64_*.dll" ]; then
            cp -f "$latest_cudnn/bin/cudnn64_*.dll" Release/
        fi
    fi
fi

echo "构建完成！"

echo "==== 构建完成 ===="
echo "可执行文件位于 Release 目录中"

# 运行程序并检查GPU支持状态
echo "正在检查GPU支持状态..."
./Release/autotalk.exe --list-gpus

# 运行程序
./Release/autotalk.exe --list
