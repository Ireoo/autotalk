@echo off
echo 开始修复 whisper-rs-sys 构建问题...
powershell -ExecutionPolicy Bypass -File fix-ggml-cpp.ps1

if %ERRORLEVEL% neq 0 (
    echo 修复脚本执行失败，请检查错误信息
    exit /b 1
)

echo 修复完成，尝试运行程序...
cargo run

echo 完成 