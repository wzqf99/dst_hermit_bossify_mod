# 打包模组 → exports/dst_hermit_bossify_mod/
# 运行后把 exports 里的文件夹复制到 DST mods 目录即可

$ErrorActionPreference = "Stop"

$modName = "dst_hermit_bossify_mod"
$exportRoot = "$PSScriptRoot\exports"
$outputDir = "$exportRoot\$modName"

# 清空旧输出
if (Test-Path $outputDir) {
    Remove-Item -Recurse -Force $outputDir
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# 复制 modinfo.lua 和 modmain.lua
Copy-Item "$PSScriptRoot\modinfo.lua" $outputDir
Copy-Item "$PSScriptRoot\modmain.lua" $outputDir

# 复制 scripts/（只复制模组自身脚本，不包含 dst_origin_script）
Copy-Item "$PSScriptRoot\scripts" "$outputDir\scripts" -Recurse

Write-Host "Build complete: $outputDir" -ForegroundColor Green
Write-Host "Copy the folder '$modName' to Documents\Klei\DoNotStarveTogether\mods\" -ForegroundColor Yellow
