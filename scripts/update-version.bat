@echo off
setlocal enabledelayedexpansion

:: 获取当前版本号
for /f "tokens=2 delims==" %%a in ('findstr "version = " Cargo.toml') do (
    set "CURRENT_VERSION=%%a"
    set "CURRENT_VERSION=!CURRENT_VERSION:"=!"
)

:: 解析版本号
for /f "tokens=1-3 delims=." %%a in ("%CURRENT_VERSION%") do (
    set "MAJOR=%%a"
    set "MINOR=%%b"
    set "PATCH=%%c"
)

:: 增加补丁版本号
set /a NEW_PATCH=PATCH+1
set "NEW_VERSION=%MAJOR%.%MINOR%.%NEW_PATCH%"

:: 更新Cargo.toml中的版本号
powershell -Command "(Get-Content Cargo.toml) -replace 'version = \"%CURRENT_VERSION%\"', 'version = \"%NEW_VERSION%\"' | Set-Content Cargo.toml"

:: 执行cargo fmt格式化代码
cargo fmt

:: 将更新后的文件添加到暂存区
git add Cargo.toml
git add src/

:: 输出版本更新信息
echo 版本已更新: %CURRENT_VERSION% -^> %NEW_VERSION%
echo 代码已格式化 