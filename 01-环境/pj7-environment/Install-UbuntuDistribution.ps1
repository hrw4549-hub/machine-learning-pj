[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-22.04',
    [string]$InstallLocation
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $InstallLocation) {
    $InstallLocation = Join-Path (Split-Path $PSScriptRoot -Parent) '.wsl\Ubuntu-22.04'
}
$wsl = Join-Path $env:ProgramFiles 'WSL\wsl.exe'
if (-not (Test-Path -LiteralPath $wsl)) { $wsl = Join-Path $env:WINDIR 'System32\wsl.exe' }
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$statusPath = Join-Path $logDir 'windows-status.json'
function Set-DistributionStatus([string]$Stage, [string]$Message) {
    @{time=(Get-Date).ToString('o');stage=$Stage;message=$Message;reboot_required=$false;distro=$Distro;install_location=$InstallLocation} |
        ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    Write-Host "$Stage : $Message"
}
try {
    Start-Transcript -Path (Join-Path $logDir 'ubuntu-distribution-install.log') -Append | Out-Null
    & $wsl --set-default-version 2
    if ($LASTEXITCODE -ne 0) { throw 'WSL2 is unavailable. Finish Windows setup and restart first.' }
    $registered = ((& $wsl --list --quiet 2>$null | Out-String) -replace "`0",'') -split '\r?\n'
    if ($registered.Trim() -notcontains $Distro) {
        if ((Test-Path -LiteralPath $InstallLocation) -and (Get-ChildItem -LiteralPath $InstallLocation -Force | Select-Object -First 1)) {
            throw 'The target directory is not empty. Refusing to overwrite an existing installation.'
        }
        $image = Join-Path $PSScriptRoot 'downloads\ubuntu-22.04.5-wsl-amd64.wsl'
        if ((Test-Path -LiteralPath $image) -and $Distro -eq 'Ubuntu-22.04') {
            if ((Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant() -ne '4499c4fe257f2fc83145b429ce211a0a43fd590e70d6261ede616210947d9f8f') {
                throw 'Ubuntu image SHA256 mismatch.'
            }
            Set-DistributionStatus 'install-ubuntu' 'Installing the verified local Ubuntu image.'
            & $wsl --install --from-file $image --name $Distro --location $InstallLocation --version 2 --no-launch
        } else {
            Set-DistributionStatus 'install-ubuntu' 'Downloading and installing Ubuntu from the official WSL distribution source.'
            & $wsl --install --distribution $Distro --location $InstallLocation --version 2 --no-launch --web-download
        }
        if ($LASTEXITCODE -ne 0) { throw 'Ubuntu installation failed. See logs/ubuntu-distribution-install.log.' }
    }
    & $wsl --list --verbose
    if ($LASTEXITCODE -ne 0) { throw 'Unable to verify registered distributions.' }
    Set-DistributionStatus 'ubuntu-installed' 'Ubuntu is installed. Verify Linux startup and complete first-user setup.'
    Stop-Transcript | Out-Null
} catch {
    Set-DistributionStatus 'failed' $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}
    throw
}
