cd build

echo "正在配置CMake..."
cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DPortAudio_DIR="$(pwd)/../portaudio/install/lib/cmake/portaudio" \
      -DCMAKE_PREFIX_PATH="$(pwd)/../portaudio/install" \
      -DGGML_CUDA=ON \
      ..

cmake --build . --config Release

cd ..

# 复制可执行文件
if [ -f "build/Release/autotalk.exe" ]; then
    cp -f build/Release/autotalk.exe Release/
elif [ -f "build/autotalk.exe" ]; then
    cp -f build/autotalk.exe Release/
else
    echo "错误: 找不到可执行文件"
    exit 1
fi

./Release/autotalk.exe --mic 2 --model models/ggml-tiny.bin