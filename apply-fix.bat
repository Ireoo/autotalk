@echo off
echo 正在应用修复补丁...

REM 设置环境变量
set CFLAGS=/utf-8
set CXXFLAGS=/utf-8

REM 清理之前的构建
echo 开始清理...
@REM cargo clean
@REM if errorlevel 1 (
@REM     echo 警告：清理失败，继续构建...
@REM )

echo 开始构建...
cargo build --release
if errorlevel 1 (
    echo 错误：构建失败
)

echo 构建过程开始，定位ggml-cpu.cpp文件...

REM 查找构建过程中生成的ggml-cpu.cpp文件
for /f "delims=" %%i in ('dir /s /b target\release\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp 2^>nul') do (
    echo 找到文件: %%i
    
    REM 修改该文件
    echo 修改文件...
    powershell -Command "(Get-Content '%%i') -replace 'RegOpenKeyEx\(HKEY_LOCAL_MACHINE,\s+TEXT\(""HARDWARE\\\\DESCRIPTION\\\\System\\\\CentralProcessor\\\\0""\)', 'RegOpenKeyExA(HKEY_LOCAL_MACHINE, ""HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegOpenKeyEx调用
        exit /b 1
    )
    
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueExA\(hKey,\s+TEXT\(""ProcessorNameString""\)', 'RegQueryValueExA(hKey, ""ProcessorNameString""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegQueryValueExA调用
        exit /b 1
    )
    
    REM 获取whisper.cpp目录路径
    for %%j in ("%%i\..\..\..\..\..") do set "WHISPER_DIR=%%~fj"
    echo 使用whisper.cpp目录: %WHISPER_DIR%
    
    REM 检查CMakeLists.txt是否存在
    if not exist "%WHISPER_DIR%\CMakeLists.txt" (
        echo 错误：在%WHISPER_DIR%中未找到CMakeLists.txt
        exit /b 1
    )
    
    echo 文件已修改，继续构建...
    cargo build --release
    if errorlevel 1 (
        echo 错误：最终构建失败
        exit /b 1
    )
    
    goto :done
)

echo 警告：未找到ggml-cpu.cpp文件，尝试查找Debug版本...

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
    
    powershell -Command "(Get-Content '%%i') -replace 'RegQueryValueExA\(hKey,\s+TEXT\(""ProcessorNameString""\)', 'RegQueryValueExA(hKey, ""ProcessorNameString""' | Set-Content -Encoding UTF8 '%%i'"
    if errorlevel 1 (
        echo 错误：无法修改RegQueryValueExA调用
        exit /b 1
    )
    
    REM 获取whisper.cpp目录路径
    for %%j in ("%%i\..\..\..\..\..") do set "WHISPER_DIR=%%~fj"
    echo 使用whisper.cpp目录: %WHISPER_DIR%
    
    REM 检查CMakeLists.txt是否存在
    if not exist "%WHISPER_DIR%\CMakeLists.txt" (
        echo 错误：在%WHISPER_DIR%中未找到CMakeLists.txt
        exit /b 1
    )
    
    echo 文件已修改，继续构建...
    cargo build
    if errorlevel 1 (
        echo 错误：最终构建失败
        exit /b 1
    )
    
    goto :done
)

:done
echo 脚本执行完成 