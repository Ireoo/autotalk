#!/bin/bash

echo "===== AutoTalk安装脚本 ====="
echo

# 设置安装目录
INSTALL_DIR="$HOME/miniconda3"
ENV_NAME="autotalk"

# 检查操作系统
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="MacOSX"
else
    OS="Linux"
fi

# 检查Miniconda是否已安装
if [ -f "$INSTALL_DIR/bin/conda" ]; then
    echo "已检测到Miniconda安装，跳过下载和安装步骤..."
else
    echo "下载Miniconda安装程序..."
    curl -o miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-$OS-x86_64.sh
    
    echo "安装Miniconda到 $INSTALL_DIR..."
    bash miniconda.sh -b -p $INSTALL_DIR
    
    if [ $? -ne 0 ]; then
        echo "Miniconda安装失败，请手动安装后重试。"
        exit 1
    fi
    
    # 删除安装程序
    rm miniconda.sh
fi

# 设置PATH以包含conda
export PATH="$INSTALL_DIR/bin:$PATH"

# 初始化conda
$INSTALL_DIR/bin/conda init bash
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source $HOME/.profile

# 创建新环境
echo "创建新环境 $ENV_NAME..."
conda create -n $ENV_NAME python=3.10 -y

# 激活环境
echo "激活环境 $ENV_NAME..."
source $INSTALL_DIR/bin/activate $ENV_NAME

# 安装基础依赖
echo "安装基础依赖..."
conda install -c conda-forge numpy loguru requests tqdm -y
pip install pyperclip

# 安装PyAudio
echo "安装PyAudio..."
conda install -c conda-forge pyaudio -y

# 安装PyQt6
echo "安装PyQt6..."
conda install -c conda-forge pyqt -y

# 安装Whisper实现
echo "安装Whisper实现..."
echo "1. whisper-cpp-python (性能更好，但需要编译)"
echo "2. openai-whisper (纯Python实现，安装更简单)"
echo -n "请选择Whisper实现 (1或2): "
read choice

if [ "$choice" == "2" ]; then
    pip install openai-whisper
else
    pip install whisper-cpp-python
fi

# 完成
echo
echo "===== 安装完成 ====="
echo
echo "要使用AutoTalk，请在新的终端中运行:"
echo "conda activate $ENV_NAME"
echo "cd $(pwd)"
echo "python run.py"
echo
echo "按Enter键退出..."
read 