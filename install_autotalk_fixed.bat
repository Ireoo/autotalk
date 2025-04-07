@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

echo ===== AutoTalk安装脚本(修复版) =====
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
:: 初始化conda
echo 初始化conda...
call "%INSTALL_DIR%\Scripts\activate.bat"
call conda init cmd.exe

:: 退出并重新以新环境启动
echo 请关闭此窗口，并在新的命令提示符中运行install_autotalk_part2.bat

:: 创建第二部分脚本
echo @echo off > install_autotalk_part2.bat
echo chcp 65001 ^> nul >> install_autotalk_part2.bat
echo setlocal enabledelayedexpansion >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo echo ===== AutoTalk安装脚本(第二部分) ===== >> install_autotalk_part2.bat
echo echo. >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 创建新环境，使用Python 3.10而不是3.12 >> install_autotalk_part2.bat
echo echo 创建新环境 %ENV_NAME%... >> install_autotalk_part2.bat
echo call conda create -n %ENV_NAME% python=3.10 -y >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 激活环境 >> install_autotalk_part2.bat
echo echo 激活环境 %ENV_NAME%... >> install_autotalk_part2.bat
echo call conda activate %ENV_NAME% >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 安装基础依赖 >> install_autotalk_part2.bat
echo echo 安装基础依赖... >> install_autotalk_part2.bat
echo call conda install -c conda-forge numpy loguru requests tqdm -y >> install_autotalk_part2.bat
echo call pip install pyperclip >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 安装PyAudio >> install_autotalk_part2.bat
echo echo 安装PyAudio... >> install_autotalk_part2.bat
echo call conda install -c conda-forge pyaudio -y >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 安装PyQt >> install_autotalk_part2.bat
echo echo 安装PyQt... >> install_autotalk_part2.bat
echo call conda install -c conda-forge pyqt -y >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 安装Whisper实现 >> install_autotalk_part2.bat
echo echo 安装Whisper实现... >> install_autotalk_part2.bat
echo echo 1. whisper-cpp-python (C++实现，性能更好，但需要编译工具) >> install_autotalk_part2.bat
echo echo 2. openai-whisper (纯Python实现，安装更简单) >> install_autotalk_part2.bat
echo choice /c 12 /m "请选择Whisper实现 (1或2): " >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo if errorlevel 2 ( >> install_autotalk_part2.bat
echo     echo 安装openai-whisper... >> install_autotalk_part2.bat
echo     call pip install openai-whisper >> install_autotalk_part2.bat
echo ) else ( >> install_autotalk_part2.bat
echo     echo 请先确认已安装Visual C++ Build Tools >> install_autotalk_part2.bat
echo     echo 如果未安装，请访问: https://visualstudio.microsoft.com/visual-cpp-build-tools/ >> install_autotalk_part2.bat
echo     choice /c YN /m "已安装Visual C++ Build Tools? (Y/N): " >> install_autotalk_part2.bat
echo     if errorlevel 2 ( >> install_autotalk_part2.bat
echo         echo 将安装openai-whisper替代... >> install_autotalk_part2.bat
echo         call pip install openai-whisper >> install_autotalk_part2.bat
echo     ) else ( >> install_autotalk_part2.bat
echo         echo 安装whisper-cpp-python... >> install_autotalk_part2.bat
echo         call pip install whisper-cpp-python >> install_autotalk_part2.bat
echo     ) >> install_autotalk_part2.bat
echo ) >> install_autotalk_part2.bat
echo. >> install_autotalk_part2.bat
echo :: 完成 >> install_autotalk_part2.bat
echo echo. >> install_autotalk_part2.bat
echo echo ===== 安装完成 ===== >> install_autotalk_part2.bat
echo echo. >> install_autotalk_part2.bat
echo echo 要使用AutoTalk，请运行: >> install_autotalk_part2.bat
echo echo conda activate %ENV_NAME% >> install_autotalk_part2.bat
echo echo cd %cd% >> install_autotalk_part2.bat
echo echo python run.py >> install_autotalk_part2.bat
echo echo. >> install_autotalk_part2.bat
echo echo 按任意键退出... >> install_autotalk_part2.bat
echo pause ^> nul >> install_autotalk_part2.bat

exit 