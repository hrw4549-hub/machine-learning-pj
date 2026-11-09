[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-22.04',
    [string]$InstallLocation,
    [switch]$Elevated,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $InstallLocation) {
    $InstallLocation = Join-Path (Split-Path $PSScriptRoot -Parent) '.wsl\Ubuntu-22.04'
}
$logDir = Join-Path $PSScriptRoot 'logs'
$downloadDir = Join-Path $PSScriptRoot 'downloads'
New-Item -ItemType Directory -Force -Path $logDir,$downloadDir | Out-Null
$statusPath = Join-Path $logDir 'windows-status.json'
$msiPath = Join-Path $downloadDir 'wsl.3.0.3.0.x64.msi'
$expectedHash = 'ae977286974255bd26bf925f00f40f5692c6b2084155cbc0563c09aea091f211'
$existingWsl = Join-Path $env:ProgramFiles 'WSL\wsl.exe'
if (-not (Test-Path -LiteralPath $existingWsl)) { $existingWsl = Join-Path $env:WINDIR 'System32\wsl.exe' }
& $existingWsl --version *> $null
$wslAlreadyInstalled = ($LASTEXITCODE -eq 0)

function Write-SetupStatus([string]$Stage, [string]$Message, [bool]$RebootRequired = $false) {
    [ordered]@{
        time = (Get-Date).ToString('o'); stage = $Stage; message = $Message
        reboot_required = $RebootRequired; distro = $Distro; install_location = $InstallLocation
    } | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    Write-Host "$Stage : $Message"
}

try {
    # Download before elevation. Only a verified Microsoft-signed package is executed.
    if (-not $wslAlreadyInstalled) {
    if (-not (Test-Path -LiteralPath $msiPath) -or
        (Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        Write-SetupStatus 'download' 'Downloading Microsoft WSL 3.0.3 (about 351 MiB).'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/microsoft/WSL/releases/download/3.0.3/wsl.3.0.3.0.x64.msi' -OutFile $msiPath
    }
    if ((Get-FileHash -LiteralPath $msiPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw 'WSL installer SHA256 mismatch.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $msiPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'WSL installer does not have a valid Microsoft signature.'
    }
    }
    if ($PrepareOnly) { Write-SetupStatus 'prepared' 'WSL is already available or its installer is downloaded and verified.'; exit 0 }

    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if ($Elevated) { throw 'Administrator permission was not granted.' }
        Write-SetupStatus 'awaiting-uac' 'Approve the Windows UAC dialog to enable WSL components.'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevated -Distro "{1}" -InstallLocation "{2}"' -f $PSCommandPath,$Distro,$InstallLocation
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
        Write-Host "Administrator helper PID: $($process.Id). Read logs/windows-status.json for progress."
        exit 0
    }

    Start-Transcript -Path (Join-Path $logDir 'windows-install.log') -Append | Out-Null
    $restartNeeded = $false
    foreach ($featureName in @('VirtualMachinePlatform','Microsoft-Windows-Subsystem-Linux')) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
        if ($feature.State -ne 'Enabled') {
            Write-SetupStatus 'windows-features' "Enabling $featureName without automatic restart."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
            $restartNeeded = $restartNeeded -or $result.RestartNeeded
        }
    }
    if (-not $wslAlreadyInstalled) {
    Write-SetupStatus 'install-wsl' 'Installing the verified WSL MSI without automatic restart.'
    $msiLog = Join-Path $logDir 'wsl-msi.log'
    $installer = Start-Process -FilePath 'msiexec.exe' -WindowStyle Hidden -ArgumentList ('/i "{0}" /qn /norestart /l*v "{1}"' -f $msiPath,$msiLog) -Wait -PassThru
    if ($installer.ExitCode -notin @(0,3010)) { throw "WSL MSI failed with exit code $($installer.ExitCode). See $msiLog" }
    $restartNeeded = $restartNeeded -or ($installer.ExitCode -eq 3010)
    }
    if ($restartNeeded) {
        Write-SetupStatus 'reboot-required' 'Restart Windows manually, then run Install-UbuntuDistribution.ps1.' $true
        Stop-Transcript | Out-Null
        exit 0
    }

    $wsl = Join-Path $env:ProgramFiles 'WSL\wsl.exe'
    if (-not (Test-Path -LiteralPath $wsl)) { $wsl = Join-Path $env:WINDIR 'System32\wsl.exe' }
    & $wsl --set-default-version 2
    if ($LASTEXITCODE -ne 0) { throw 'Cannot set WSL2 default; inspect the Windows install log.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-UbuntuDistribution.ps1') -Distro $Distro -InstallLocation $InstallLocation
    if ($LASTEXITCODE -ne 0) { throw 'Ubuntu distribution setup failed; inspect logs/ubuntu-distribution-install.log.' }
    & $wsl --list --verbose
    Write-SetupStatus 'windows-ready' 'WSL and Ubuntu are installed. Continue with Install-Ubuntu.sh inside Ubuntu.'
    Stop-Transcript | Out-Null
} catch {
    Write-SetupStatus 'failed' $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}
    throw
}
