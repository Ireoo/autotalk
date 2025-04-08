@echo off
chcp 65001 >nul
echo ===========================================
echo AutoTalk 一键构建脚本
echo ===========================================

REM 检查Rust环境
where rustc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到Rust环境
    echo 请安装Rust: https://www.rust-lang.org/tools/install
    exit /b 1
)
for /f "tokens=*" %%i in ('rustc --version') do (
    echo [信息] 检测到Rust: %%i
)

REM 检查CUDA环境
where nvcc >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    for /f "tokens=*" %%i in ('nvcc --version ^| findstr release') do (
        echo [信息] 检测到CUDA: %%i
    )
    set useGPU=1
) else (
    echo [警告] 未找到CUDA环境
    echo 将构建CPU版本
    set useGPU=0
)

REM 检查LLVM环境
where clang >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到LLVM/Clang环境
    echo 请安装LLVM: https://github.com/llvm/llvm-project/releases
    exit /b 1
)
for /f "tokens=*" %%i in ('clang --version') do (
    echo [信息] 检测到LLVM/Clang: %%i
)

REM 检查CMake环境
where cmake >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到CMake环境
    echo 请安装CMake: https://cmake.org/download/
    exit /b 1
)
for /f "tokens=*" %%i in ('cmake --version') do (
    echo [信息] 检测到CMake: %%i
)

REM 检查模型文件
if not exist "models" mkdir models
if not exist "models\ggml-tiny.bin" (
    echo [信息] 未找到模型文件，开始下载...
    powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin' -OutFile 'models\ggml-tiny.bin'"
    if %ERRORLEVEL% NEQ 0 (
        echo [错误] 模型下载失败
        exit /b 1
    )
    echo [信息] 模型下载完成
)

REM 设置环境变量
set RUSTFLAGS=-C target-feature=+crt-static
if %useGPU% EQU 1 (
    set WHISPER_CUBLAS=1
)

REM 构建项目
echo [信息] 开始构建项目...
if %useGPU% EQU 1 (
    cargo build --release --features real_whisper
) else (
    cargo build --release
)
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 构建失败
    exit /b 1
)

REM 创建发布目录
set releaseDir=release
if %useGPU% EQU 1 (
    set releaseDir=release-gpu
)
if exist "%releaseDir%" (
    rd /s /q "%releaseDir%"
)
mkdir "%releaseDir%"

REM 复制可执行文件
set exeName=autotalk.exe
if %useGPU% EQU 1 (
    set exeName=autotalk-gpu.exe
)
copy /Y "target\release\autotalk.exe" "%releaseDir%\%exeName%"

REM 如果是GPU版本，复制CUDA运行时库
if %useGPU% EQU 1 (
    if defined CUDA_PATH (
        set cudaPath=%CUDA_PATH%
    ) else (
        set cudaPath=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA
    )
    
    if exist "%cudaPath%" (
        echo [信息] 使用CUDA路径: %cudaPath%
        for %%i in ("%cudaPath%\bin\cudart64_*.dll") do (
            copy /Y "%%i" "%releaseDir%"
            echo [信息] 已复制 %%~nxi
        )
        for %%i in ("%cudaPath%\bin\cublas64_*.dll") do (
            copy /Y "%%i" "%releaseDir%"
            echo [信息] 已复制 %%~nxi
        )
        for %%i in ("%cudaPath%\bin\cublasLt64_*.dll") do (
            copy /Y "%%i" "%releaseDir%"
            echo [信息] 已复制 %%~nxi
        )
    ) else (
        echo [警告] 未找到CUDA路径，无法复制CUDA运行时库
        echo 程序可能需要用户手动安装CUDA运行时
    )
)

REM 复制其他必要文件
if exist "assets" xcopy /E /I /Y "assets" "%releaseDir%\assets"
if exist "resources" xcopy /E /I /Y "resources" "%releaseDir%\resources"
if exist "README.md" copy /Y "README.md" "%releaseDir%"
if exist "LICENSE" copy /Y "LICENSE" "%releaseDir%"
xcopy /E /I /Y "models" "%releaseDir%\models"

REM 创建说明文件
if %useGPU% EQU 1 (
    (
        echo # GPU加速版本使用说明
        echo 本版本支持NVIDIA GPU加速，需要安装CUDA运行时环境。
        echo.
        echo 要求：
        echo 1. 安装NVIDIA显卡驱动
        echo 2. 如果运行时找不到CUDA动态库，请安装CUDA Toolkit 11.8或更高版本
        echo.
        echo 模型说明：
        echo 1. 已包含ggml-tiny.bin模型，适合低配置设备
        echo 2. 如需更高准确度，可从以下地址下载其他模型：
        echo    https://huggingface.co/ggerganov/whisper.cpp/tree/main
        echo 3. 下载后放入models目录即可
    ) > "%releaseDir%\使用说明.txt"
) else (
    (
        echo # CPU版本使用说明
        echo 本版本使用CPU进行语音识别，无需额外配置。
        echo.
        echo 系统要求：
        echo 1. 支持AVX2指令集的CPU
        echo 2. 至少4GB可用内存
        echo.
        echo 模型说明：
        echo 1. 已包含ggml-tiny.bin模型，适合低配置设备
        echo 2. 如需更高准确度，可从以下地址下载其他模型：
        echo    https://huggingface.co/ggerganov/whisper.cpp/tree/main
        echo 3. 下载后放入models目录即可
    ) > "%releaseDir%\使用说明.txt"
)

echo ===========================================
echo 构建完成!
echo 输出目录: %CD%\%releaseDir%
echo =========================================== 