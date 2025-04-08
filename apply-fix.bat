@echo off
echo 正在应用修复补丁...

REM 设置环境变量
set CFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t
set CXXFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t

REM 清理之前的构建
echo 开始清理...
cargo clean

@REM REM 开始构建，但在复制源代码后暂停
@REM start /wait cmd /c "echo 开始构建... && cargo build --release || exit /b"

echo 构建过程开始，定位ggml-cpu.cpp文件...

REM 查找构建过程中生成的ggml-cpu.cpp文件
for /f "delims=" %%i in ('dir /s /b target\release\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp') do (
    echo 找到文件: %%i
    
    REM 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueExA', 'RegQueryValueExW' | Set-Content '%%i'"
    powershell -Command "(Get-Content '%%i') -replace 'TEXT\(""ProcessorNameString""\)', 'L""ProcessorNameString""' | Set-Content '%%i'"
    
    echo 文件已修改，继续构建...
    cargo build --release
    
    goto :done
)

REM 如果在release中没找到，尝试debug目录
for /f "delims=" %%i in ('dir /s /b target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp') do (
    echo 找到文件: %%i
    
    REM 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueExA', 'RegQueryValueExW' | Set-Content '%%i'"
    powershell -Command "(Get-Content '%%i') -replace 'TEXT\(""ProcessorNameString""\)', 'L""ProcessorNameString""' | Set-Content '%%i'"
    
    echo 文件已修改，继续构建...
    cargo build
    
    goto :done
)

:done

echo 开始构建...
cargo build --release || exit /b

echo 脚本执行完成 