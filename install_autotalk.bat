@echo off
setlocal enabledelayedexpansion

echo ===== AutoTalk安装脚本 =====
echo.

:: 设置安装目录
set INSTALL_DIR=%USERPROFILE%\miniconda3
set ENV_NAME=autotalk

:: 检查Miniconda是否已安装
if exist "%INSTALL_DIR%\Scripts\conda.exe" (
    echo 已检测到Miniconda安装，跳过下载和安装步骤...
    goto setup_env
)

echo 下载Miniconda安装程序...
curl -o miniconda.exe https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe

echo 安装Miniconda到 %INSTALL_DIR%...
start /wait "" miniconda.exe /InstallationType=JustMe /RegisterPython=0 /S /D=%INSTALL_DIR%

if errorlevel 1 (
    echo Miniconda安装失败，请手动安装后重试。
    exit /b 1
)

:: 删除安装程序
del miniconda.exe

:setup_env
:: 设置PATH以包含conda
set PATH=%INSTALL_DIR%;%INSTALL_DIR%\Scripts;%INSTALL_DIR%\Library\bin;%PATH%

:: 创建新环境
echo 创建新环境 %ENV_NAME%...
call conda create -n %ENV_NAME% python=3.10 -y

:: 激活环境
echo 激活环境 %ENV_NAME%...
call conda activate %ENV_NAME%

:: 安装基础依赖
echo 安装基础依赖...
call conda install -c conda-forge numpy loguru requests tqdm -y
call pip install pyperclip

:: 安装PyAudio
echo 安装PyAudio...
call conda install -c conda-forge pyaudio -y

:: 安装PyQt6
echo 安装PyQt6...
call conda install -c conda-forge pyqt -y

:: 安装Whisper实现
echo 安装Whisper实现...
echo 1. whisper-cpp-python (性能更好，但需要编译)
echo 2. openai-whisper (纯Python实现，安装更简单)
choice /c 12 /m "请选择Whisper实现 (1或2): "

if errorlevel 2 (
    call pip install openai-whisper
) else (
    call pip install whisper-cpp-python
)

:: 完成
echo.
echo ===== 安装完成 =====
echo.
echo 要使用AutoTalk，请在新的命令提示符中运行:
echo conda activate %ENV_NAME%
echo cd %cd%
echo python run.py
echo.
echo 按任意键退出...
pause > nul 