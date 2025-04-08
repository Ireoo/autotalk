#!/bin/bash

echo "==========================================="
echo "构建Metal加速版本 - AutoTalk (MacOS)"
echo "==========================================="

# 检查操作系统是否为MacOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "[错误] 此脚本仅支持MacOS系统"
    exit 1
fi

# 检查MacOS版本是否支持Metal
os_version=$(sw_vers -productVersion)
required_version="10.15"

if [[ "$(printf '%s\n' "$required_version" "$os_version" | sort -V | head -n1)" != "$required_version" ]]; then
    echo "[错误] MacOS版本过低，需要MacOS 10.15 (Catalina)或更高版本"
    echo "当前版本: $os_version"
    exit 1
fi

# 确保已安装必要的开发工具
if ! command -v clang &> /dev/null; then
    echo "[警告] 未检测到clang，尝试安装Command Line Tools"
    xcode-select --install
fi

# 设置编译环境变量
export WHISPER_METAL=1

echo "[信息] 开始构建..."
cargo build --release --features real_whisper

if [ $? -ne 0 ]; then
    echo "[错误] 构建失败"
    exit 1
fi

echo "[信息] 构建成功，正在准备发布包..."

# 创建发布目录
mkdir -p release-metal
rm -rf release-metal/*

# 复制可执行文件
cp target/release/autotalk release-metal/autotalk-metal
chmod +x release-metal/autotalk-metal

# 复制其他必要文件
if [ -d "assets" ]; then
    cp -r assets release-metal/
fi

if [ -d "resources" ]; then
    cp -r resources release-metal/
fi

cp -f README.md release-metal/ 2>/dev/null || true
cp -f LICENSE release-metal/ 2>/dev/null || true

# 创建Metal加速说明文件
cat > release-metal/Metal加速说明.txt << EOL
# Metal加速版本使用说明
本版本支持Apple Metal加速，针对Mac设备优化。
要求：
1. macOS 10.15 (Catalina) 或更高版本
2. 支持Metal的Apple设备
3. 如果需要，请在系统设置中允许运行此应用程序
EOL

echo "==========================================="
echo "构建完成!"
echo "输出目录: $(pwd)/release-metal"
echo "===========================================" 