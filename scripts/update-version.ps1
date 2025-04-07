# 获取当前版本号
$content = Get-Content Cargo.toml -Raw
if ($content -match 'version = "([0-9]+\.[0-9]+\.[0-9]+)"') {
    $currentVersion = $matches[1]
} else {
    Write-Host "错误：无法获取当前版本号"
    exit 1
}

# 解析版本号
$versionParts = $currentVersion.Split('.')
$major = $versionParts[0]
$minor = $versionParts[1]
$patch = [int]$versionParts[2]

# 增加补丁版本号
$newPatch = $patch + 1
$newVersion = "$major.$minor.$newPatch"

# 更新版本号
$newContent = $content -replace "version = `"$currentVersion`"", "version = `"$newVersion`""
$newContent | Set-Content Cargo.toml -NoNewline -Encoding UTF8

# 执行cargo fmt格式化代码
cargo fmt

# 将更新后的文件添加到暂存区
git add Cargo.toml src/

# 输出版本更新信息
Write-Host "版本已更新: $currentVersion -> $newVersion"
Write-Host "代码已格式化"
Write-Host ""
Write-Host "请手动执行以下命令来提交更改："
Write-Host "git commit -m `"chore: 更新版本号 $currentVersion -> $newVersion`"" 