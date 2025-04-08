# 设置编码为UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "==========================================="
Write-Host "AutoTalk 一键构建脚本"
Write-Host "==========================================="

# 检查Rust环境
try {
    $rustcVersion = rustc --version
    Write-Host "[信息] 检测到Rust: $rustcVersion"
} catch {
    Write-Host "[错误] 未找到Rust环境"
    Write-Host "请安装Rust: https://www.rust-lang.org/tools/install"
    exit 1
}

# 检查CUDA环境
try {
    $nvccVersion = nvcc --version
    Write-Host "[信息] 检测到CUDA:"
    Write-Host $nvccVersion
    $useGPU = $true
} catch {
    Write-Host "[警告] 未找到CUDA环境"
    Write-Host "将构建CPU版本"
    $useGPU = $false
}

# 检查LLVM环境
try {
    $llvmVersion = clang --version
    Write-Host "[信息] 检测到LLVM/Clang:"
    Write-Host $llvmVersion
} catch {
    Write-Host "[错误] 未找到LLVM/Clang环境"
    Write-Host "请安装LLVM: https://github.com/llvm/llvm-project/releases"
    exit 1
}

# 检查CMake环境
try {
    $cmakeVersion = cmake --version
    Write-Host "[信息] 检测到CMake:"
    Write-Host $cmakeVersion
} catch {
    Write-Host "[错误] 未找到CMake环境"
    Write-Host "请安装CMake: https://cmake.org/download/"
    exit 1
}

# 设置环境变量
$env:RUSTFLAGS = "-C target-feature=+crt-static"
if ($useGPU) {
    $env:WHISPER_CUBLAS = "1"
}

# 构建项目
Write-Host "[信息] 开始构建项目..."
try {
    if ($useGPU) {
        cargo build --release --features real_whisper
    } else {
        cargo build --release
    }
} catch {
    Write-Host "[错误] 构建失败: $_"
    exit 1
}

# 创建发布目录
$releaseDir = if ($useGPU) { "release-gpu" } else { "release" }
if (Test-Path $releaseDir) {
    Remove-Item -Path "$releaseDir\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

# 复制可执行文件
$exeName = if ($useGPU) { "autotalk-gpu.exe" } else { "autotalk.exe" }
Copy-Item "target\release\autotalk.exe" "$releaseDir\$exeName"

# 如果是GPU版本，复制CUDA运行时库
if ($useGPU) {
    $cudaPath = $env:CUDA_PATH
    if (-not $cudaPath) {
        $cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    }
    
    if (Test-Path $cudaPath) {
        Write-Host "[信息] 使用CUDA路径: $cudaPath"
        $cudaDlls = @(
            "cudart64_*.dll",
            "cublas64_*.dll",
            "cublasLt64_*.dll"
        )
        
        foreach ($dll in $cudaDlls) {
            $dllPath = Join-Path $cudaPath "bin\$dll"
            if (Test-Path $dllPath) {
                Copy-Item $dllPath $releaseDir
                Write-Host "[信息] 已复制 $dll"
            }
        }
    } else {
        Write-Host "[警告] 未找到CUDA路径，无法复制CUDA运行时库"
        Write-Host "程序可能需要用户手动安装CUDA运行时"
    }
}

# 复制其他必要文件
$filesToCopy = @(
    "assets",
    "resources",
    "README.md",
    "LICENSE"
)

foreach ($file in $filesToCopy) {
    if (Test-Path $file) {
        if (Test-Path $file -PathType Container) {
            Copy-Item -Path $file -Destination $releaseDir -Recurse -Force
        } else {
            Copy-Item -Path $file -Destination $releaseDir -Force
        }
    }
}

# 创建说明文件
$readmePath = Join-Path $releaseDir "使用说明.txt"
$readmeContent = if ($useGPU) {
@"
# GPU加速版本使用说明
本版本支持NVIDIA GPU加速，需要安装CUDA运行时环境。

要求：
1. 安装NVIDIA显卡驱动
2. 如果运行时找不到CUDA动态库，请安装CUDA Toolkit 11.8或更高版本
"@
} else {
@"
# CPU版本使用说明
本版本使用CPU进行语音识别，无需额外配置。

系统要求：
1. 支持AVX2指令集的CPU
2. 至少4GB可用内存
"@
}

Set-Content -Path $readmePath -Value $readmeContent

Write-Host "==========================================="
Write-Host "构建完成!"
Write-Host "输出目录: $(Resolve-Path $releaseDir)"
Write-Host "===========================================" 