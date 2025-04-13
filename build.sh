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
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows 平台配置 - 禁用CUDA
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=ON \
          -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
          -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
          -DGGML_CUDA=OFF \
          ..
else
    # Linux/macOS 配置 - 禁用CUDA
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=ON \
          -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
          -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
          -DGGML_CUDA=OFF \
          ..
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
else
    echo "错误: 找不到whisper.dll"
    exit 1
fi

# 不再需要复制CUDA DLL文件，因为已禁用CUDA
# if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
#     cp -f "$CUDA_PATH/bin/cudart64_12.dll" Release/
#     cp -f "$CUDA_PATH/bin/cublas64_12.dll" Release/
#     cp -f "$CUDA_PATH/bin/cublasLt64_12.dll" Release/
#     cp -f "$CUDA_PATH/bin/cudnn64_8.dll" Release/
# fi

echo "构建完成！"

echo "==== 构建完成 ===="
echo "可执行文件位于 Release 目录中"

# 运行程序
./Release/autotalk.exe --list
