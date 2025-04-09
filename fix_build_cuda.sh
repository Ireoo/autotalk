#!/bin/bash

echo "开始修复CUDA编译问题..."

# 创建临时目录用于存放修复日志
mkdir -p ./fix_logs

# 1. 修复RegQueryValueExA与TEXT宏兼容性问题
echo "正在搜索RegQueryValueExA相关问题..."
find ./target -name "ggml-cpu.cpp" | while read -r file; do
    echo "处理文件: $file"
    # 使用sed替换RegQueryValueExA为RegQueryValueExW
    sed -i 's/RegQueryValueExA/RegQueryValueExW/g' "$file"
    echo "已将$file中的RegQueryValueExA替换为RegQueryValueExW" >> ./fix_logs/fix_log.txt
done

# 2. 修复非ASCII字符问题
echo "正在搜索非ASCII字符问题..."
find ./target -name "whisper.cpp" | while read -r file; do
    echo "处理文件: $file"
    
    # 使用sed删除或替换非ASCII字符（主要是「」『』♪♫等）
    # 这里我们用正则表达式匹配非ASCII字符段落并替换为ASCII字符
    
    if [ -f "$file" ]; then
        echo "找到文件: $file"
        cp "fix_windows/whisper.cpp/src/whisper.cpp" "$file"
        echo "已修复$file中的非ASCII字符" >> ./fix_logs/fix_log.txt
    fi
    
    
done

echo "修复完成！"
echo "现在可以尝试运行: cargo build --features cuda"
echo "如果仍有问题，请查看 ./fix_logs/fix_log.txt 获取详细信息" 