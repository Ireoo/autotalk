#!/bin/bash

# 获取当前版本号
CURRENT_VERSION=$(grep '^version = ' Cargo.toml | head -n 1 | sed -E 's/version = "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')

# 检查是否成功获取版本号
if [ -z "$CURRENT_VERSION" ]; then
    echo "错误：无法获取当前版本号"
    exit 1
fi

# 解析版本号
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# 检查版本号格式是否正确
if [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
    echo "错误：版本号格式不正确"
    exit 1
fi

# 增加补丁版本号
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# 创建临时文件
TMP_FILE=$(mktemp)
awk -v old_ver="$CURRENT_VERSION" -v new_ver="$NEW_VERSION" '
    /^version = / {
        sub(old_ver, new_ver)
    }
    { print }
' Cargo.toml > "$TMP_FILE"

# 检查临时文件是否创建成功
if [ ! -f "$TMP_FILE" ]; then
    echo "错误：无法创建临时文件"
    exit 1
fi

# 更新版本号
mv "$TMP_FILE" Cargo.toml

# 执行cargo fmt格式化代码
cargo fmt

# 将更新后的文件添加到暂存区
git add Cargo.toml src/

# 输出版本更新信息
echo "版本已更新: $CURRENT_VERSION -> $NEW_VERSION"
echo "代码已格式化"
echo ""
echo "请手动执行以下命令来提交更改："
echo "git commit -m \"chore: 更新版本号 ${CURRENT_VERSION} -> ${NEW_VERSION}\"" 