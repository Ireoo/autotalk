@echo off
echo 设置特殊的环境变量以解决编码问题...

rem 设置系统代码页为UTF-8
chcp 65001

rem 设置MSVC编译选项
set CFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t
set CXXFLAGS=/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t

rem 强制whisper-rs使用UTF-8编码而非中文编码
set "CODEPAGE_SET=UTF8"
set "CHCP_OUTPUT=65001"
set "CMAKE_CXX_FLAGS=/utf-8"

echo 开始编译项目...
cargo build --verbose

echo 完成 