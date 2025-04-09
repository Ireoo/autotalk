@echo off
echo 正在应用修复补丁...

REM 设置环境变量
set CFLAGS=/utf-8
set CXXFLAGS=/utf-8

echo 开始构建...
cargo build
if errorlevel 1 (
    echo 构建失败，但这是预期的，准备修复...
) else (
    echo 构建成功，无需修复。
    exit /b 0
)

echo 构建过程开始，定位ggml-cpu.cpp文件...

REM 查找构建过程中生成的ggml-cpu.cpp文件
for /f "delims=" %%i in ('dir /s /b target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp 2^>nul') do (
    echo 找到文件: %%i
    
    REM 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'RegOpenKeyEx\(HKEY_LOCAL_MACHINE,\s+TEXT\(""HARDWARE\\\\DESCRIPTION\\\\System\\\\CentralProcessor\\\\0""\)', 'RegOpenKeyExA(HKEY_LOCAL_MACHINE, ""HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegOpenKeyEx调用
        exit /b 1
    )
    
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueEx\(hKey,\s+TEXT\(""ProcessorNameString""\)', 'RegQueryValueExA(hKey, ""ProcessorNameString""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegQueryValueEx调用
        exit /b 1
    )
    
    echo 文件已修改，继续构建...
    cargo build
    if errorlevel 1 (
        echo 错误：修复后构建仍然失败
        exit /b 1
    ) else (
        echo 修复成功！现在运行程序...
        cargo run
        exit /b 0
    )
    
    goto :done
)

echo 警告：未找到ggml-cpu.cpp文件，尝试查找Debug版本...

REM 尝试使用cargo clean后重新构建
echo 清理并重新构建...
cargo clean
cargo build

REM 查找Debug版本的文件
for /f "delims=" %%i in ('dir /s /b target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp 2^>nul') do (
    echo 找到文件: %%i
    
    REM 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'RegOpenKeyEx\(HKEY_LOCAL_MACHINE,\s+TEXT\(""HARDWARE\\\\DESCRIPTION\\\\System\\\\CentralProcessor\\\\0""\)', 'RegOpenKeyExA(HKEY_LOCAL_MACHINE, ""HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegOpenKeyEx调用
        exit /b 1
    )
    
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueEx\(hKey,\s+TEXT\(""ProcessorNameString""\)', 'RegQueryValueExA(hKey, ""ProcessorNameString""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegQueryValueEx调用
        exit /b 1
    )
    
    echo 文件已修改，继续构建...
    cargo build
    if errorlevel 1 (
        echo 错误：最终构建失败
        exit /b 1
    ) else (
        echo 修复成功！现在运行程序...
        cargo run
        exit /b 0
    )
    
    goto :done
)

:done
echo 脚本执行完成 