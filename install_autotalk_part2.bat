@echo off 
chcp 65001 > nul 
setlocal enabledelayedexpansion 
 
echo ===== AutoTalk安装脚本(第二部分) ===== 
echo. 
 
:: 创建新环境，使用Python 3.10而不是3.12 
echo 创建新环境 autotalk... 
call conda create -n autotalk python=3.10 -y 
 
:: 激活环境 
echo 激活环境 autotalk... 
call conda activate autotalk 
 
:: 安装基础依赖 
echo 安装基础依赖... 
call conda install -c conda-forge numpy loguru requests tqdm -y 
call pip install pyperclip 
 
:: 安装PyAudio 
echo 安装PyAudio... 
call conda install -c conda-forge pyaudio -y 
 
:: 安装PyQt 
echo 安装PyQt... 
call conda install -c conda-forge pyqt -y 
 
:: 安装Whisper实现 
echo 安装Whisper实现... 
echo 1. whisper-cpp-python (C++实现，性能更好，但需要编译工具) 
echo 2. openai-whisper (纯Python实现，安装更简单) 
choice /c 12 /m "请选择Whisper实现 (1或2): " 
 
if errorlevel 2 ( 
    echo 安装openai-whisper... 
    call pip install openai-whisper 
) else ( 
    echo 请先确认已安装Visual C++ Build Tools 
    echo 如果未安装，请访问: https://visualstudio.microsoft.com/visual-cpp-build-tools/ 
    choice /c YN /m "已安装Visual C++ Build Tools? (Y/N): " 
    if errorlevel 2 ( 
        echo 将安装openai-whisper替代... 
        call pip install openai-whisper 
    ) else ( 
        echo 安装whisper-cpp-python... 
        call pip install whisper-cpp-python 
    ) 
) 
 
:: 完成 
echo. 
echo ===== 安装完成 ===== 
echo. 
echo 要使用AutoTalk，请运行: 
echo conda activate autotalk 
echo cd G:\github\autotalk 
echo python run.py 
echo. 
conda activate autotalk
python run.py 
echo 按任意键退出... 

pause > nul 
