# Windows构建测试脚本

# 检查管理员权限
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "请以管理员权限运行此脚本！"
    Write-Warning "请右键点击PowerShell，选择'以管理员身份运行'"
    exit 1
}

# 检查必要的工具
function Test-Command {
    param($Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# 检查并安装必要的工具
if (-NOT (Test-Command "choco")) {
    Write-Warning "未找到Chocolatey，正在安装..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# 安装必要的包
Write-Host "正在安装必要的包..."
choco install llvm cmake -y
if ($LASTEXITCODE -ne 0) {
    Write-Error "安装包失败"
    exit 1
}

# 设置环境变量
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
$env:LLVM_CONFIG_PATH = "C:\Program Files\LLVM\bin\llvm-config"
$env:PATH = "$env:PATH;C:\Program Files\LLVM\bin"
$env:CMAKE_C_FLAGS = "-DUNICODE -D_UNICODE"
$env:CMAKE_CXX_FLAGS = "-DUNICODE -D_UNICODE"

# 验证LLVM安装
if (-NOT (Test-Path $env:LIBCLANG_PATH)) {
    Write-Error "LLVM未正确安装，请检查安装路径"
    exit 1
}

# 验证CMake安装
if (-NOT (Test-Command "cmake")) {
    Write-Error "CMake未正确安装"
    exit 1
}

# 创建修复脚本
@"
param(`$filePath)

Write-Host "正在处理文件: `$filePath"

# 读取文件内容
`$content = Get-Content `$filePath -Raw

# 替换RegQueryValueExA为RegQueryValueExW
`$newContent = `$content -replace "RegQueryValueExA\(hKey,\s*L\"ProcessorNameString\"", "RegQueryValueExW(hKey, L\"ProcessorNameString\""

# 检查是否有变化
if (`$newContent -ne `$content) {
    Write-Host "正在修复文件..."
    Set-Content -Path `$filePath -Value `$newContent
    Write-Host "已修复文件: `$filePath"
} else {
    Write-Host "文件不需要修改或模式匹配失败"
    
    # 尝试完全替换Windows部分代码
    `$windowsCode = "#ifdef _WIN32`r`n" +
        "        HKEY hKey;`r`n" +
        "        if (RegOpenKeyEx(HKEY_LOCAL_MACHINE,`r`n" +
        "                        TEXT(""HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0""),`r`n" +
        "                        0,`r`n" +
        "                        KEY_READ,`r`n" +
        "                        &hKey) == ERROR_SUCCESS) {`r`n" +
        "            DWORD cpu_brand_size = 0;`r`n" +
        "            if (RegQueryValueExW(hKey,`r`n" +
        "                                L""ProcessorNameString"",`r`n" +
        "                                NULL,`r`n" +
        "                                NULL,`r`n" +
        "                                NULL,`r`n" +
        "                                &cpu_brand_size) == ERROR_SUCCESS) {`r`n" +
        "                std::vector<wchar_t> wbuffer(cpu_brand_size / sizeof(wchar_t));`r`n" +
        "                if (RegQueryValueExW(hKey,`r`n" +
        "                                    L""ProcessorNameString"",`r`n" +
        "                                    NULL,`r`n" +
        "                                    NULL,`r`n" +
        "                                    (LPBYTE)wbuffer.data(),`r`n" +
        "                                    &cpu_brand_size) == ERROR_SUCCESS) {`r`n" +
        "                    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wbuffer.data(), -1, NULL, 0, NULL, NULL);`r`n" +
        "                    if (size_needed > 0) {`r`n" +
        "                        description.resize(size_needed);`r`n" +
        "                        WideCharToMultiByte(CP_UTF8, 0, wbuffer.data(), -1, &description[0], size_needed, NULL, NULL);`r`n" +
        "                        if (description.find('\\0') != std::string::npos) {`r`n" +
        "                            description.resize(description.find('\\0'));`r`n" +
        "                        }`r`n" +
        "                    }`r`n" +
        "                }`r`n" +
        "            }`r`n" +
        "            RegCloseKey(hKey);`r`n" +
        "        }`r`n" +
        "#endif"
    
    # 使用正则表达式替换整个Windows代码块
    `$pattern = "(?s)#ifdef _WIN32.*?RegQueryValueExA.*?RegCloseKey.*?#endif"
    `$newContent = [regex]::Replace(`$content, `$pattern, `$windowsCode)
    
    if (`$newContent -ne `$content) {
        Write-Host "正在替换整个Windows代码块..."
        Set-Content -Path `$filePath -Value `$newContent
        Write-Host "已完全替换Windows代码块: `$filePath"
    } else {
        Write-Host "无法自动修复，将显示文件内容进行调试..."
        `$fileContent = Get-Content `$filePath -Raw
        Write-Host "`$fileContent"
    }
}
"@ | Out-File -FilePath fix-ggml-cpu.ps1 -Encoding utf8

Write-Host "修复脚本已创建"

# 在cargo目录中查找ggml-cpu.cpp文件
Write-Host "正在搜索目录: .cargo\registry\src"
if (Test-Path ".cargo\registry\src") {
    Get-ChildItem -Path ".cargo\registry\src" -Filter "ggml-cpu.cpp" -Recurse | ForEach-Object {
        Write-Host "找到文件: $($_.FullName)"
        powershell -File fix-ggml-cpu.ps1 -filePath $_.FullName
    }
} else {
    Write-Host "目录 .cargo\registry\src 不存在，跳过搜索"
}

# 在target目录中查找ggml-cpu.cpp文件
Write-Host "正在搜索目录: target"
if (Test-Path "target") {
    Get-ChildItem -Path "target" -Filter "ggml-cpu.cpp" -Recurse | ForEach-Object {
        Write-Host "找到文件: $($_.FullName)"
        powershell -File fix-ggml-cpu.ps1 -filePath $_.FullName
    }
} else {
    Write-Host "目录 target 不存在，跳过搜索"
}

# 添加CMake配置修复
@"
cmake_minimum_required(VERSION 3.10)
project(whisper-rs-sys)

# 设置CMake策略
cmake_policy(SET CMP0066 NEW)
cmake_policy(SET CMP0082 NEW)
cmake_policy(SET CMP0156 NEW)
cmake_policy(SET CMP0128 NEW)

# 设置Windows特定选项
if(WIN32)
    add_definitions(-DUNICODE -D_UNICODE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc")
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS OFF)
    set(CMAKE_C_STANDARD 11)
    set(CMAKE_C_STANDARD_REQUIRED ON)
    set(CMAKE_C_EXTENSIONS OFF)
endif()

# 查找必要的包
find_package(OpenSSL REQUIRED)
find_package(LLVM REQUIRED CONFIG)

# 添加源文件
add_library(whisper-rs-sys SHARED
    src/whisper.cpp
)

# 设置包含目录
target_include_directories(whisper-rs-sys PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${LLVM_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIR}
)

# 链接必要的库
if(WIN32)
    target_link_libraries(whisper-rs-sys PRIVATE
        advapi32
        kernel32
        ${LLVM_LIBRARIES}
        OpenSSL::SSL
        OpenSSL::Crypto
    )
endif()

# 设置输出目录
set_target_properties(whisper-rs-sys PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)
"@ | Out-File -FilePath CMakeLists.txt -Encoding utf8

Write-Host "CMake配置已更新"

# 创建构建目录
New-Item -ItemType Directory -Force -Path "build"
Set-Location "build"

# 配置CMake
Write-Host "正在配置CMake..."
cmake .. -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake配置失败"
    exit 1
}

# 构建项目
Write-Host "正在构建项目..."
cmake --build . --config Release
if ($LASTEXITCODE -ne 0) {
    Write-Error "构建失败，错误代码: $LASTEXITCODE"
    exit 1
}

Write-Host "构建成功完成" 