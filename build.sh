#!/bin/bash

# 检查下载工具
check_download_tool() {
    if command -v wget &> /dev/null; then
        echo "使用wget下载文件"
        DOWNLOAD_TOOL="wget"
    elif command -v curl &> /dev/null; then
        echo "使用curl下载文件"
        DOWNLOAD_TOOL="curl"
    else
        echo "错误: 未找到wget或curl工具，无法下载文件"
        echo "请安装wget或curl后再运行此脚本:"
        echo "Windows (使用管理员权限运行): choco install wget 或 choco install curl"
        echo "Ubuntu/Debian: sudo apt-get install wget 或 sudo apt-get install curl"
        echo "CentOS/RHEL: sudo yum install wget 或 sudo yum install curl"
        echo "macOS: brew install wget 或 brew install curl"
        return 1
    fi
    return 0
}

# 下载文件的通用函数
download_file() {
    local url="$1"
    local output_path="$2"
    
    if [ "$DOWNLOAD_TOOL" = "wget" ]; then
        wget "$url" -O "$output_path"
    elif [ "$DOWNLOAD_TOOL" = "curl" ]; then
        curl -L "$url" -o "$output_path"
    else
        echo "错误: 无可用的下载工具"
        return 1
    fi
    return 0
}

# 设置错误时退出
set -e

echo "==== 开始构建项目 ===="

# 显示当前工作目录
echo "当前工作目录: $(pwd)"

# 检查下载工具可用性
if ! check_download_tool; then
    echo "错误: 找不到可用的下载工具(wget或curl)，请安装后再试"
    exit 1
fi

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
        local cuda_installer="third_party/cuda/cuda_11.8.0_520.61.05_linux.run"
        download_file "https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_520.61.05_linux.run" "$cuda_installer"
        
        if [ -f "$cuda_installer" ]; then
            chmod +x "$cuda_installer"
            echo "正在安装CUDA，这可能需要几分钟..."
            sudo sh "$cuda_installer" --toolkit --silent
            export CUDA_PATH=/usr/local/cuda
        else
            echo "错误: CUDA安装程序下载失败，将禁用GPU支持"
        fi
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows安装
        mkdir -p third_party/cuda_installer
        local cuda_installer="third_party/cuda_installer/cuda_11.8.0_522.06_windows.exe"
        download_file "https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_522.06_windows.exe" "$cuda_installer"
        
        if [ -f "$cuda_installer" ]; then
            # 静默安装CUDA工具包
            echo "正在安装CUDA，这可能需要几分钟..."
            ./third_party/cuda_installer/cuda_11.8.0_522.06_windows.exe -s
            export CUDA_PATH="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.8"
        else
            echo "错误: CUDA安装程序下载失败，将禁用GPU支持"
        fi
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
    # 检查是否有可用的NVIDIA GPU
    if [ -f "$CUDA_PATH/bin/nvcc" ] || [ -f "$CUDA_PATH/bin/nvcc.exe" ]; then
        echo "找到CUDA编译器，尝试启用GPU加速"
        GPU_ENABLED=1
    else
        echo "CUDA路径存在，但找不到CUDA编译器，禁用GPU加速"
    fi
else
    echo "未找到CUDA路径或CUDA安装不完整，禁用GPU加速"
fi

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows 平台配置
    if [ $GPU_ENABLED -eq 1 ]; then
        # 启用CUDA
        echo "Windows平台：启用CUDA GPU加速"
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
              .. || {
                  echo "CUDA配置失败，回退到CPU模式"
                  cmake -DCMAKE_BUILD_TYPE=Release \
                        -DBUILD_SHARED_LIBS=ON \
                        -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
                        -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
                        -DGGML_CUDA=OFF \
                        ..
                  GPU_ENABLED=0
              }
    else
        # 禁用CUDA
        echo "Windows平台：使用CPU模式"
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
        echo "Linux平台：启用CUDA GPU加速"
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
              .. || {
                  echo "CUDA配置失败，回退到CPU模式"
                  cmake -DCMAKE_BUILD_TYPE=Release \
                        -DBUILD_SHARED_LIBS=ON \
                        -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
                        -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
                        -DGGML_CUDA=OFF \
                        ..
                  GPU_ENABLED=0
              }
    else
        # macOS禁用CUDA
        echo "使用CPU模式"
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
cmake --build . --config Release || {
    echo "构建失败，尝试使用CPU模式重新构建..."
    rm -rf *
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=ON \
          -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
          -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
          -DGGML_CUDA=OFF \
          ..
    cmake --build . --config Release || {
        echo "构建仍然失败，请检查错误信息"
        exit 1
    }
    GPU_ENABLED=0
}

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
            echo "已复制CUDA DLL文件"
        else
            echo "警告: 未找到ggml-cuda.dll，可能会影响GPU加速功能"
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
    CUDA_DLLS_FOUND=0
    for dll in cudart64_*.dll cublas64_*.dll cublasLt64_*.dll; do
        if [ -f "$CUDA_PATH/bin/$dll" ]; then
            cp -f "$CUDA_PATH/bin/$dll" Release/
            CUDA_DLLS_FOUND=1
        fi
    done
    
    if [ $CUDA_DLLS_FOUND -eq 0 ]; then
        echo "警告: 未找到CUDA运行时DLL文件，尝试按通配符名称查找"
        if [ -f "$CUDA_PATH/bin/cudart64_*.dll" ]; then
            cp -f "$CUDA_PATH/bin/cudart64_"*.dll Release/
        fi
        if [ -f "$CUDA_PATH/bin/cublas64_*.dll" ]; then
            cp -f "$CUDA_PATH/bin/cublas64_"*.dll Release/
        fi
        if [ -f "$CUDA_PATH/bin/cublasLt64_*.dll" ]; then
            cp -f "$CUDA_PATH/bin/cublasLt64_"*.dll Release/
        fi
    fi
    
    # 尝试复制cuDNN库（如果有）
    CUDNN_FOUND=0
    if [ -f "$CUDA_PATH/bin/cudnn64_*.dll" ]; then
        cp -f "$CUDA_PATH/bin/cudnn64_"*.dll Release/
        CUDNN_FOUND=1
    elif [ -d "C:/Program Files/NVIDIA/CUDNN" ]; then
        latest_cudnn=$(ls -d "C:/Program Files/NVIDIA/CUDNN/v"* 2>/dev/null | sort -r | head -n 1)
        if [ -n "$latest_cudnn" ] && [ -f "$latest_cudnn/bin/cudnn64_*.dll" ]; then
            cp -f "$latest_cudnn/bin/cudnn64_"*.dll Release/
            CUDNN_FOUND=1
        fi
    fi
    
    if [ $CUDNN_FOUND -eq 0 ]; then
        echo "警告: 未找到cuDNN库，某些模型可能无法使用GPU加速"
    fi
fi

echo "构建完成！"

echo "==== 构建完成 ===="
echo "可执行文件位于 Release 目录中"

# 创建models目录（如果不存在）
if [ ! -d "models" ]; then
    mkdir -p models
    echo "创建模型目录"
    echo "提示: 您需要下载模型文件并放置在models目录中"
    echo "建议下载: ggml-medium-zh.bin (中文模型)"
fi

# 显示GPU状态
if [ $GPU_ENABLED -eq 1 ]; then
    echo "GPU加速已启用 ✓"
    echo "运行程序并检查GPU支持状态..."
    ./Release/autotalk.exe --list-gpus || echo "无法检查GPU状态，但程序已构建完成"
else
    echo "GPU加速未启用，将使用CPU模式运行"
fi

# 运行程序
echo "正在启动程序..."
./Release/autotalk.exe --list || echo "无法列出输入设备，但程序已构建完成"
