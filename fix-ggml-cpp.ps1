# 设置编码
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "开始修复whisper-rs-sys构建问题..." -ForegroundColor Green

# 首先运行cargo build生成构建目录
Write-Host "执行初始构建以生成文件..." -ForegroundColor Cyan
cargo build

# 查找ggml-cpu.cpp文件
$targetFile = Get-ChildItem -Path "target\debug\build\whisper-rs-sys*\out\whisper.cpp\ggml\src\ggml-cpu\ggml-cpu.cpp" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

if ($null -eq $targetFile) {
    Write-Host "未找到ggml-cpu.cpp文件，请检查构建过程" -ForegroundColor Red
    exit 1
}

Write-Host "找到文件: $($targetFile.FullName)" -ForegroundColor Yellow

# 读取文件内容
$content = Get-Content -Path $targetFile.FullName -Raw

# 创建修复的Windows部分代码
$windowsCode = @'
#ifdef _WIN32
    HKEY hKey;
    std::string description;
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE,
                    "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                    0,
                    KEY_READ,
                    &hKey) == ERROR_SUCCESS) {
        DWORD cpu_brand_size = 0;
        if (RegQueryValueExA(hKey,
                            "ProcessorNameString",
                            NULL,
                            NULL,
                            NULL,
                            &cpu_brand_size) == ERROR_SUCCESS) {
            description.resize(cpu_brand_size);
            if (RegQueryValueExA(hKey,
                                "ProcessorNameString",
                                NULL,
                                NULL,
                                (LPBYTE)&description[0], // NOLINT
                                &cpu_brand_size) == ERROR_SUCCESS) {
                if (description.find('\0') != std::string::npos) {
                    description.resize(description.find('\0'));
                }
            }
        }
        RegCloseKey(hKey);
    }
    return description;
#else
'@

# 修复代码 - 更精确的替换特定问题
$fixedContent = $content

# 处理RegOpenKeyEx问题
$fixedContent = $fixedContent -replace 'RegOpenKeyEx\(HKEY_LOCAL_MACHINE,\s+TEXT\("([^"]+)"\)', 'RegOpenKeyExA(HKEY_LOCAL_MACHINE, "$1"'

# 处理RegQueryValueEx问题
$fixedContent = $fixedContent -replace 'RegQueryValueEx\(([^,]+),\s+TEXT\("([^"]+)"\)', 'RegQueryValueExA($1, "$2"'

# 如果以上修复不起作用，尝试替换整个Windows代码块
if ($content -eq $fixedContent) {
    Write-Host "尝试替换整个Windows代码块..." -ForegroundColor Yellow
    
    # 查找Windows部分的代码
    $pattern = '(?s)#ifdef _WIN32.*?#else'
    if ($content -match $pattern) {
        $fixedContent = $content -replace $pattern, $windowsCode
    }
}

# 写回文件
if ($content -ne $fixedContent) {
    Set-Content -Path $targetFile.FullName -Value $fixedContent -Encoding UTF8
    Write-Host "文件已修复，正在重新构建..." -ForegroundColor Green
    
    # 重新构建
    cargo build
} else {
    Write-Host "未能自动修复文件，可能需要手动检查" -ForegroundColor Red
} 