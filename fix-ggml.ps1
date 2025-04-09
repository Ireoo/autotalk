# 设置编码
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "开始修复whisper-rs-sys构建问题..." -ForegroundColor Green

# 查找ggml-cpu.cpp文件
$targetFile = Get-ChildItem -Path "target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($null -eq $targetFile) {
    Write-Host "未找到ggml-cpu.cpp文件，请先运行'cargo build'以生成构建目录" -ForegroundColor Red
    exit 1
}

Write-Host "找到文件: $($targetFile.FullName)" -ForegroundColor Yellow

# 读取文件内容
$content = Get-Content -Path $targetFile.FullName -Raw

# 修复代码 - 将TEXT("ProcessorNameString")改为"ProcessorNameString"
$fixedContent = $content -replace 'TEXT\("ProcessorNameString"\)', '"ProcessorNameString"'

if ($content -eq $fixedContent) {
    Write-Host "没有找到需要修复的内容，尝试更精确的修复..." -ForegroundColor Yellow
    
    # 更复杂的替换，处理RegQueryValueExA与wchar_t的不兼容问题
    $fixedContent = $content -replace 'RegQueryValueExA\(hKey,\s+TEXT\("ProcessorNameString"\)', 'RegQueryValueExA(hKey, "ProcessorNameString"'
}

# 写回文件
if ($content -ne $fixedContent) {
    Set-Content -Path $targetFile.FullName -Value $fixedContent -Encoding UTF8
    Write-Host "文件已修复，请重新运行'cargo build'命令" -ForegroundColor Green
} else {
    Write-Host "未能自动修复文件，可能需要手动检查" -ForegroundColor Red
} 