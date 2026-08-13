# Package the mod -> exports/dst_hermit_bossify_mod/
# Usage:
#   .\package.ps1        # only package to exports/
#   .\package.ps1 -g     # package then install to the DST mods dir below

param(
    [switch]$g
)

$ErrorActionPreference = "Stop"

$modName = "dst_hermit_bossify_mod"
$exportRoot = "$PSScriptRoot\exports"
$outputDir = "$exportRoot\$modName"

# DST mods directory (change to your own path)
$dstModsDir = "D:\steam\steamapps\common\Don't Starve Together\mods"

# Clear old output
if (Test-Path $outputDir) {
    Remove-Item -Recurse -Force $outputDir
}
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Copy modinfo.lua and modmain.lua
Copy-Item "$PSScriptRoot\modinfo.lua" $outputDir
Copy-Item "$PSScriptRoot\modmain.lua" $outputDir

# Copy scripts/ (only the mod's own scripts, not dst_origin_script)
Copy-Item "$PSScriptRoot\scripts" "$outputDir\scripts" -Recurse

Write-Host "Build complete: $outputDir" -ForegroundColor Green

if ($g) {
    if (-not (Test-Path $dstModsDir)) {
        Write-Error "DST mods dir not found: $dstModsDir (edit `$dstModsDir at the top of package.ps1)"
    }

    $installDir = Join-Path $dstModsDir $modName
    if (Test-Path $installDir) {
        Remove-Item -Recurse -Force $installDir
    }
    Copy-Item $outputDir $installDir -Recurse
    Write-Host "Installed to: $installDir" -ForegroundColor Green
} else {
    Write-Host "Copy the folder '$modName' to $dstModsDir" -ForegroundColor Yellow
}
