@echo off
setlocal enabledelayedexpansion

:: 获取当前版本号
for /f "tokens=3 delims= " %%a in ('findstr /B "version =" Cargo.toml') do (
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

:: 创建临时文件并更新版本号
(for /f "delims=" %%a in (Cargo.toml) do (
    set "line=%%a"
    if "!line:~0,8!"=="version " (
        echo version = "%NEW_VERSION%"
    ) else (
        echo %%a
    )
)) > temp.toml
move /y temp.toml Cargo.toml

:: 执行cargo fmt格式化代码
cargo fmt

:: 将更新后的文件添加到暂存区
git add Cargo.toml src/

:: 输出版本更新信息
echo 版本已更新: %CURRENT_VERSION% -^> %NEW_VERSION%
echo 代码已格式化
echo.
echo 请手动执行以下命令来提交更改：
echo git commit -m "chore: 更新版本号 %CURRENT_VERSION% -^> %NEW_VERSION%" 