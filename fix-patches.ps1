# 设置环境变量
Write-Host "正在设置环境变量..." -ForegroundColor Green
$env:CFLAGS = "/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t"
$env:CXXFLAGS = "/utf-8 /D_UNICODE /DUNICODE /Zc:wchar_t"

# 清理旧的构建
Write-Host "清理旧的构建..." -ForegroundColor Green
cargo clean

# 开始构建
Write-Host "开始构建..." -ForegroundColor Green
cargo build

# 构建过程会在第一次失败后暂停，我们可以在这里修复问题
Write-Host "检查并修复ggml-cpu.cpp文件..." -ForegroundColor Green
$files = Get-ChildItem -Path "target\debug\build" -Recurse -Filter "ggml-cpu.cpp" | Where-Object { $_.FullName -like "*whisper-rs-sys*" }

foreach ($file in $files) {
    Write-Host "找到文件: $($file.FullName)" -ForegroundColor Yellow
    
    # 读取文件内容
    $content = Get-Content -Path $file.FullName -Raw
    
    # 修改内容
    $newContent = $content -replace 'TEXT\("ProcessorNameString"\)', '"ProcessorNameString"'
    
    # 写回文件
    Set-Content -Path $file.FullName -Value $newContent
    
    Write-Host "文件已修改，继续构建..." -ForegroundColor Green
    cargo build
    
    break
}

Write-Host "脚本执行完成" -ForegroundColor Green 