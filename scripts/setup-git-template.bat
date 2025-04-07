@echo off
setlocal

:: 创建本地模板目录
set "TEMPLATE_DIR=%~dp0..\.git-template"
if not exist "%TEMPLATE_DIR%" mkdir "%TEMPLATE_DIR%"
if not exist "%TEMPLATE_DIR%\hooks" mkdir "%TEMPLATE_DIR%\hooks"

:: 复制钩子脚本到模板目录
copy "%~dp0update-version.bat" "%TEMPLATE_DIR%\hooks\pre-commit.bat" >nul

:: 设置本地Git模板目录
git config init.templateDir "%TEMPLATE_DIR%"

:: 确保scripts目录存在
if not exist "%~dp0..\scripts" mkdir "%~dp0..\scripts"

:: 复制脚本到项目目录
copy "%~dp0update-version.bat" "%~dp0..\scripts\" >nul

echo 本地Git模板设置完成！
echo 现在当您在这个项目中提交时，会自动更新版本号。 