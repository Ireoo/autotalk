@echo off
echo 正在应用修复补丁...

rem 设置环境变量
set CFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t
set CXXFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t

rem 清理之前的构建
echo 开始清理...
cargo clean

rem 开始构建，但在复制源代码后暂停
start /wait cmd /c "echo 开始构建... && cargo build || exit /b"

echo 构建过程开始，定位ggml-cpu.cpp文件...

rem 查找构建过程中生成的ggml-cpu.cpp文件
for /f "delims=" %%i in ('dir /s /b target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp') do (
    echo 找到文件: %%i
    
    rem 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'TEXT\(""ProcessorNameString""\)', '""ProcessorNameString""' | Set-Content '%%i'"
    
    echo 文件已修改，继续构建...
    cargo build
    
    goto :done
)

:done
echo 脚本执行完成 