@echo off
chcp 65001 >nul
echo ===========================================
echo AutoTalk 测试构建脚本
echo ===========================================

REM 检查Rust环境
where rustc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未找到Rust环境
    exit /b 1
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

REM 构建项目
echo [信息] 开始构建项目...
cargo build --release
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 构建失败
    exit /b 1
)

echo ===========================================
echo 构建完成!
echo =========================================== 