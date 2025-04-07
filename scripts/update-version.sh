#!/bin/bash

# 获取当前版本号
CURRENT_VERSION=$(grep -m 1 'version = ' Cargo.toml | cut -d '"' -f 2)

# 解析版本号
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]}
PATCH=${VERSION_PARTS[2]}

# 增加补丁版本号
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# 更新Cargo.toml中的版本号
sed -i "s/version = \"$CURRENT_VERSION\"/version = \"$NEW_VERSION\"/" Cargo.toml

# 执行cargo fmt格式化代码
cargo fmt

# 将更新后的文件添加到暂存区
git add Cargo.toml
git add src/

# 输出版本更新信息
echo "版本已更新: $CURRENT_VERSION -> $NEW_VERSION"
echo "代码已格式化" 