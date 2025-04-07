#!/bin/bash

# 创建本地模板目录
TEMPLATE_DIR="$(dirname "$0")/../.git-template"
mkdir -p "$TEMPLATE_DIR/hooks"

# 复制钩子脚本到模板目录
cp "$(dirname "$0")/update-version.sh" "$TEMPLATE_DIR/hooks/pre-commit"
chmod +x "$TEMPLATE_DIR/hooks/pre-commit"

# 设置本地Git模板目录
git config init.templateDir "$TEMPLATE_DIR"

# 确保scripts目录存在
mkdir -p "$(dirname "$0")/../scripts"

# 复制脚本到项目目录
cp "$(dirname "$0")/update-version.sh" "$(dirname "$0")/../scripts/"
chmod +x "$(dirname "$0")/../scripts/update-version.sh"

echo "本地Git模板设置完成！"
echo "现在当您在这个项目中提交时，会自动更新版本号。" 