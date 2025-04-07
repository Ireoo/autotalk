@echo off
echo 正在设置编译环境...

rem 设置MSVC编译选项
set CFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t
set CXXFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t

rem 清理和重新编译
echo 开始清理和构建...
cargo clean && cargo build

echo 脚本执行完成 