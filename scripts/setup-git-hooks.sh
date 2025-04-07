#!/bin/bash

# 确保scripts目录存在
mkdir -p scripts

# 确保update-version.sh脚本存在
if [ ! -f scripts/update-version.sh ]; then
    echo "错误: update-version.sh 脚本不存在"
    exit 1
fi

# 给脚本添加执行权限
chmod +x scripts/update-version.sh

# 创建pre-commit钩子
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
./scripts/update-version.sh
EOF

# 给钩子添加执行权限
chmod +x .git/hooks/pre-commit

echo "Git钩子设置完成！" 