$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$downloadDir = Join-Path $PSScriptRoot 'downloads'
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
$installer = Join-Path $downloadDir 'Miniforge3-25.3.1-0-Linux-x86_64.sh'
$expectedHash = '376b160ed8130820db0ab0f3826ac1fc85923647f75c1b8231166e3d559ab768'
if (-not (Test-Path -LiteralPath $installer) -or
    (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/conda-forge/miniforge/releases/download/25.3.1-0/Miniforge3-Linux-x86_64.sh' -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'Miniforge installer SHA256 mismatch.'
}
Write-Host 'Linux conda installer downloaded and SHA256 verified.'
