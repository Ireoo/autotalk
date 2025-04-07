@echo off
echo 正在修复Unicode与ANSI混用问题...

rem 创建临时目录
if not exist temp mkdir temp

rem 下载whisper-rs到临时目录
if not exist temp\whisper-rs (
    echo 下载whisper-rs...
    git clone --depth 1 https://github.com/tazz4843/whisper-rs.git temp\whisper-rs
)

rem 应用补丁
echo 应用补丁...
cd temp\whisper-rs
git apply ..\..\whisper-fix.patch

echo 修复完成！
echo 现在可以尝试编译: cargo build --release

cd ..\.. 