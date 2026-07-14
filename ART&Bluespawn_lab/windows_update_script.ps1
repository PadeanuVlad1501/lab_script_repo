# update-bluespawn.ps1
# Run this script from an elevated PowerShell session.

$ErrorActionPreference = "Stop"

$ReleaseVersion = "v0.5.2-alpha"
$FileName = "BLUESPAWN-client-x64.exe"

$InstallDirectory = "C:\IntroLabs"
$DestinationPath = Join-Path $InstallDirectory $FileName
$TemporaryPath = Join-Path $env:TEMP "BLUESPAWN-client-x64.download.exe"

$DownloadUrl = "https://github.com/ION28/BLUESPAWN/releases/download/$ReleaseVersion/$FileName"

$ExpectedSha256 = "ccabc1a0eb48577cb23f0c4b8ae73dd36b6d65318315f047d3171a2cdeb245aa"

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "[*] $Message"
}

function Test-Administrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-Administrator)) {
    throw "This script must be run as Administrator."
}

if ($ExpectedSha256 -notmatch "^[A-Fa-f0-9]{64}$") {
    throw "ExpectedSha256 must contain exactly 64 hexadecimal characters."
}

Write-Step "Ensuring the installation directory exists."

New-Item `
    -Path $InstallDirectory `
    -ItemType Directory `
    -Force | Out-Null

Write-Step "Adding narrow Microsoft Defender exclusions."

$ExistingExclusions = (Get-MpPreference).ExclusionPath

if ($DestinationPath -notin $ExistingExclusions) {
    Add-MpPreference -ExclusionPath $DestinationPath
}

if ($TemporaryPath -notin $ExistingExclusions) {
    Add-MpPreference -ExclusionPath $TemporaryPath
}

try {
    Write-Step "Stopping any running BLUESPAWN process."

    Get-Process `
        -Name "BLUESPAWN-client-x64", "BLUESPAWN-client" `
        -ErrorAction SilentlyContinue |
        Stop-Process -Force

    Write-Step "Removing any previous temporary download."

    Remove-Item `
        -Path $TemporaryPath `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Step "Downloading BLUESPAWN $ReleaseVersion from the official GitHub release."

    Invoke-WebRequest `
        -Uri $DownloadUrl `
        -OutFile $TemporaryPath `
        -UseBasicParsing

    if (-not (Test-Path $TemporaryPath)) {
        throw "The BLUESPAWN executable was not downloaded."
    }

    Write-Step "Calculating the downloaded file SHA-256 hash."

    $DownloadedHash = (
        Get-FileHash `
            -Path $TemporaryPath `
            -Algorithm SHA256
    ).Hash

    Write-Host "    Expected: $($ExpectedSha256.ToUpper())"
    Write-Host "    Received: $DownloadedHash"

    if ($DownloadedHash -ne $ExpectedSha256.ToUpper()) {
        throw "SHA-256 verification failed. The existing executable was not changed."
    }

    Write-Step "SHA-256 verification succeeded."

    if (Test-Path $DestinationPath) {
        Write-Step "Removing the previous BLUESPAWN executable."

        Remove-Item `
            -Path $DestinationPath `
            -Force
    }

    Write-Step "Installing the updated BLUESPAWN executable."

    Move-Item `
        -Path $TemporaryPath `
        -Destination $DestinationPath `
        -Force

    Write-Step "Removing the downloaded-file security marker, if present."

    Unblock-File `
        -Path $DestinationPath `
        -ErrorAction SilentlyContinue

    Write-Step "Verifying the installed executable."

    $InstalledFile = Get-Item $DestinationPath

    $InstalledHash = (
        Get-FileHash `
            -Path $DestinationPath `
            -Algorithm SHA256
    ).Hash

    $InstalledFile |
        Select-Object FullName, Length, LastWriteTime

    $InstalledFile.VersionInfo |
        Format-List FileVersion, ProductVersion, OriginalFilename

    Write-Host "    SHA256: $InstalledHash"

    if ($InstalledHash -ne $ExpectedSha256.ToUpper()) {
        throw "The installed executable hash does not match the expected hash."
    }

    Write-Host "[+] BLUESPAWN $ReleaseVersion was installed successfully."
}
finally {
    Remove-Item `
        -Path $TemporaryPath `
        -Force `
        -ErrorAction SilentlyContinue

    # The temporary download exclusion is no longer required.
    Remove-MpPreference `
        -ExclusionPath $TemporaryPath `
        -ErrorAction SilentlyContinue
}
