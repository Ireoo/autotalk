@echo off
echo ===========================================
echo 构建GPU加速版本 - AutoTalk
echo ===========================================

REM 检查CUDA环境
where nvcc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到CUDA编译器(nvcc)
    echo 请安装CUDA Toolkit并确保其在系统PATH中
    echo 可从https://developer.nvidia.com/cuda-downloads下载
    exit /b 1
)

REM 输出CUDA版本信息
echo [信息] 检测到CUDA:
nvcc --version | findstr release

REM 设置编译环境变量
set WHISPER_CUBLAS=1
set RUSTFLAGS=-C target-feature=+crt-static

echo [信息] 开始构建...
cargo build --release --features real_whisper

if %ERRORLEVEL% NEQ 0 (
    echo [错误] 构建失败
    exit /b 1
)

echo [信息] 构建成功，正在准备发布包...

REM 创建发布目录
if not exist "release-gpu" mkdir release-gpu
if exist "release-gpu\*" del /Q "release-gpu\*"

REM 复制可执行文件
copy /Y "target\release\autotalk.exe" "release-gpu\autotalk-gpu.exe" 

REM 复制CUDA运行时库
set CUDA_PATH_FOUND=0
if defined CUDA_PATH (
    set CUDA_PATH_FOUND=1
) else (
    if exist "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA" (
        for /f "delims=" %%i in ('dir /b "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"') do (
            if exist "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\%%i\bin\cudart64_*.dll" (
                set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\%%i
                set CUDA_PATH_FOUND=1
            )
        )
    )
)

if %CUDA_PATH_FOUND% EQU 1 (
    echo [信息] 使用CUDA路径: %CUDA_PATH%
    if exist "%CUDA_PATH%\bin\cudart64_*.dll" (
        for /f "delims=" %%i in ('dir /b "%CUDA_PATH%\bin\cudart64_*.dll"') do (
            copy /Y "%CUDA_PATH%\bin\%%i" "release-gpu\"
            echo [信息] 已复制 %%i
        )
    )
    if exist "%CUDA_PATH%\bin\cublas64_*.dll" (
        for /f "delims=" %%i in ('dir /b "%CUDA_PATH%\bin\cublas64_*.dll"') do (
            copy /Y "%CUDA_PATH%\bin\%%i" "release-gpu\"
            echo [信息] 已复制 %%i
        )
    )
    if exist "%CUDA_PATH%\bin\cublasLt64_*.dll" (
        for /f "delims=" %%i in ('dir /b "%CUDA_PATH%\bin\cublasLt64_*.dll"') do (
            copy /Y "%CUDA_PATH%\bin\%%i" "release-gpu\"
            echo [信息] 已复制 %%i
        )
    )
) else (
    echo [警告] 未找到CUDA路径，无法复制CUDA运行时库
    echo 程序可能需要用户手动安装CUDA运行时
)

REM 复制其他必要文件
if exist "assets" xcopy /E /I /Y "assets" "release-gpu\assets"
if exist "resources" xcopy /E /I /Y "resources" "release-gpu\resources"
copy /Y "README.md" "release-gpu\"
copy /Y "LICENSE" "release-gpu\"

REM 创建GPU加速说明文件
echo # GPU加速版本使用说明 > "release-gpu\GPU加速说明.txt"
echo 本版本支持NVIDIA GPU加速，需要安装CUDA运行时环境。 >> "release-gpu\GPU加速说明.txt"
echo 要求： >> "release-gpu\GPU加速说明.txt"
echo 1. 安装NVIDIA显卡驱动 >> "release-gpu\GPU加速说明.txt"
echo 2. 如果运行时找不到CUDA动态库，请安装CUDA Toolkit 11.8或更高版本 >> "release-gpu\GPU加速说明.txt"

echo ===========================================
echo 构建完成! 
echo 输出目录: %CD%\release-gpu
echo =========================================== 