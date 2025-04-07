@echo off

:: 确保scripts目录存在
if not exist scripts mkdir scripts

:: 确保update-version.bat脚本存在
if not exist scripts\update-version.bat (
    echo 错误: update-version.bat 脚本不存在
    exit /b 1
)

:: 创建pre-commit钩子
(
echo @echo off
echo call scripts\update-version.bat
) > .git\hooks\pre-commit.bat

echo Git钩子设置完成！ 