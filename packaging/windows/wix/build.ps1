# Build Windows MSI installer for ClaudeUsageBar.
# Requires: Rust, WiX 6 dotnet tool (wix), Windows.
#
# Usage:
#   pwsh -ExecutionPolicy Bypass -File packaging/windows/wix/build.ps1

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = Resolve-Path (Join-Path $scriptRoot '..\..\..')
$appRs      = Join-Path $repoRoot 'app-rs'
$exePath    = Join-Path $appRs 'target\release\claude-usage-bar.exe'
$iconPath   = Join-Path $appRs 'app.ico'

if (-not (Test-Path $iconPath)) {
    Write-Host "Generating app.ico from claudeusagebar-icon.png..."
    $src = Join-Path $repoRoot 'app\claudeusagebar-icon.png'
    if (Get-Command magick -ErrorAction SilentlyContinue) {
        magick convert $src -define icon:auto-resize=256,128,64,48,32,16 $iconPath
    } else {
        Copy-Item $src $iconPath
        Write-Warning "ImageMagick not found; using .png renamed as .ico (will work but not optimal)."
    }
}

if (-not (Test-Path $exePath)) {
    Write-Host "Building release binary..."
    Push-Location $appRs
    cargo build --release
    Pop-Location
}

if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
    Write-Host "Installing WiX 6 dotnet tool..."
    dotnet tool install --global wix
}

Push-Location $scriptRoot
$version = "1.2.3"
$msiName = "ClaudeUsageBar-$version-x64.msi"
wix extension add WixToolset.UI.wixext
wix build -ext WixToolset.UI.wixext -arch x64 -out $msiName installer.wxs
Write-Host "Built: $(Join-Path $scriptRoot $msiName)"
Pop-Location
