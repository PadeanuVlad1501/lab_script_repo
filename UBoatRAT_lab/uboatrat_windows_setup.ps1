#requires -Version 5.1

<#
.SYNOPSIS
    Prepares the Windows VM for the benign UBoatRAT behavior laboratory.

.DESCRIPTION
    Downloads and validates the laboratory artifacts, prepares a clean
    lab-specific snapshot baseline, and stages shared analysis tools.

    The Windows VM hosts many independent laboratories. This setup is run
    once by the lab author before the shared VM snapshot is taken. It stages
    only UBoatRAT-specific files and never activates per-lab runtime state.

    This setup script does not:
      - run WinSvcHelper.exe;
      - run lab_start.ps1;
      - disable Microsoft Defender;
      - add Defender exclusions;
      - change the PowerShell version or execution policy;
      - install, start, stop, or reconfigure the Sysmon service;
      - apply sysmon_uboatrat.xml;
      - change audit policy, the hosts file mapping for an active session,
        firewall rules, or BITS service configuration;
      - reset unrelated BITS jobs.

.NOTES
    Run from Windows PowerShell 5.1 as Administrator.
#>

[CmdletBinding()]
param(
    [switch]$SkipToolDownloads
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration
# ============================================================================

$LabDir = "C:\Users\Administrator\Desktop\Labs\UBoatRAT"

$RepoBase = (
    "https://raw.githubusercontent.com/" +
    "PadeanuVlad1501/lab_script_repo/" +
    "refs/heads/main/UBoatRAT_lab"
)

# Update this value whenever WinSvcHelper.exe is rebuilt intentionally.
$ExpectedSimulatorSha256 = (
    "a21580d099091c85a5b71ff3c8117e8434abd601a9a2cde723cc46c17898ec4d"
)

$ExpectedMarkerContent = "BENIGN UBOATRAT TRAINING LAB"
$LabBitsJobName = "UBoatLab_Persistence"
$LabHostname = "uboat-c2.test"

$HostsFile = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

$RuntimeDir = Join-Path $LabDir "runtime"
$InstalledCopy = Join-Path $RuntimeDir "svchost.exe"
$ManifestPath = Join-Path $LabDir "setup_manifest.json"

$ToolsRoot = "$LabDir\tools"

$ProcmonPath = Join-Path $ToolsRoot "Procmon\Procmon64.exe"
$ProcExpPath = Join-Path $ToolsRoot "ProcessExplorer\procexp64.exe"
$SysmonPath  = Join-Path $ToolsRoot "Sysmon\Sysmon64.exe"

$ProcmonUri = "https://live.sysinternals.com/Procmon64.exe"
$ProcExpUri = "https://live.sysinternals.com/procexp64.exe"
$SysmonUri  = "https://live.sysinternals.com/Sysmon64.exe"

$ArtifactDefinitions = @(
    [pscustomobject]@{
        Name     = "lab_start.ps1"
        Required = $true
    },
    [pscustomobject]@{
        Name     = "WinSvcHelper.exe"
        Required = $true
    },
    [pscustomobject]@{
        Name     = "WinSvcHelper.cs"
        Required = $true
    },
    [pscustomobject]@{
        Name     = "UBoatRAT_LAB.marker"
        Required = $true
    },
    [pscustomobject]@{
        Name     = "sysmon_uboatrat.xml"
        Required = $true
    }
)

# ============================================================================
# Output helpers
# ============================================================================

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[-] $Message" -ForegroundColor Red
}

# ============================================================================
# Validation and download helpers
# ============================================================================

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object Security.Principal.WindowsPrincipal(
        $identity
    )

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator
    )
}

function Invoke-RepositoryDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$StagingDirectory,

        [Parameter(Mandatory = $true)]
        [bool]$Required
    )

    $uri = "$RepoBase/$FileName"
    $destination = Join-Path $StagingDirectory $FileName

    Write-Info "Downloading $FileName..."

    try {
        Invoke-WebRequest `
            -Uri $uri `
            -OutFile $destination `
            -UseBasicParsing
    }
    catch {
        if ($Required) {
            throw (
                "Required artifact '$FileName' could not be downloaded. " +
                $_.Exception.Message
            )
        }

        Write-WarningMessage (
            "Optional artifact '$FileName' is not available in Git yet."
        )

        return $null
    }

    if (
        -not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        (Get-Item -LiteralPath $destination).Length -eq 0
    ) {
        if ($Required) {
            throw "Required artifact '$FileName' is empty."
        }

        Write-WarningMessage "Optional artifact '$FileName' is empty."
        return $null
    }

    if ($FileName -notlike "*.exe") {
        $firstLine = Get-Content `
            -LiteralPath $destination `
            -TotalCount 1 `
            -ErrorAction SilentlyContinue

        if (
            $firstLine -match "^\s*<!DOCTYPE" -or
            $firstLine -match "^\s*<html"
        ) {
            throw (
                "'$FileName' contains an HTML page instead of the raw file."
            )
        }
    }

    Write-Success "$FileName downloaded."
    return $destination
}

function Assert-PowerShellSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null

    [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if (
        $null -ne $parseErrors -and
        $parseErrors.Count -gt 0
    ) {
        $messages = (
            $parseErrors |
            ForEach-Object {
                "Line $($_.Extent.StartLineNumber): $($_.Message)"
            }
        ) -join "; "

        throw "PowerShell syntax validation failed: $messages"
    }
}

function Assert-SimulatorBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $header = @(
        Get-Content `
            -LiteralPath $Path `
            -Encoding Byte `
            -TotalCount 2
    )

    if (
        $header.Count -ne 2 -or
        $header[0] -ne 0x4D -or
        $header[1] -ne 0x5A
    ) {
        throw "WinSvcHelper.exe is not a valid PE file."
    }

    $actualHash = (
        Get-FileHash `
            -LiteralPath $Path `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($actualHash -ne $ExpectedSimulatorSha256) {
        throw (
            "WinSvcHelper.exe SHA-256 mismatch. " +
            "Expected: $ExpectedSimulatorSha256; " +
            "received: $actualHash. " +
            "Do not continue until the expected hash is updated intentionally."
        )
    }

    return $actualHash
}

function Assert-LabStartVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Assert-PowerShellSyntax -Path $Path

    $content = [System.IO.File]::ReadAllText($Path)

    if (
        $content -match
        [regex]::Escape("C:\ProgramData\UBoatRAT_Lab")
    ) {
        throw "lab_start.ps1 is the obsolete ProgramData version."
    }

    if (
        $content -notmatch
        '\$InstalledLabRoot\s*=\s*Join-Path\s+\$LabDir\s+"runtime"'
    ) {
        throw (
            "lab_start.ps1 does not use the required lab-local runtime path."
        )
    }

    if (
        $content -notmatch
        [regex]::Escape("UBoatRAT_LAB.marker")
    ) {
        throw "lab_start.ps1 does not validate the lab marker."
    }
}

function Assert-CSharpSourceVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = [System.IO.File]::ReadAllText($Path)

    if (
        $content -match
        [regex]::Escape("C:\ProgramData\UBoatRAT_Lab")
    ) {
        throw "WinSvcHelper.cs is the obsolete ProgramData version."
    }

    if (
        $content -notmatch
        'RuntimeDirectoryName\s*=\s*"runtime"'
    ) {
        throw "WinSvcHelper.cs does not use the runtime subdirectory."
    }

    if (
        $content -notmatch
        [regex]::Escape("BENIGN_BEACON|NO_COMMAND_CHANNEL")
    ) {
        throw "WinSvcHelper.cs does not contain the fixed benign beacon."
    }

    if (
        $content -notmatch
        [regex]::Escape("--bits-callback")
    ) {
        throw "WinSvcHelper.cs does not contain the fixed BITS callback mode."
    }
}

function Assert-Marker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $actualContent = (
        [System.IO.File]::ReadAllText($Path)
    ).Trim()

    if ($actualContent -ne $ExpectedMarkerContent) {
        throw (
            "Unexpected UBoatRAT_LAB.marker content. " +
            "Expected '$ExpectedMarkerContent'."
        )
    }
}

function Assert-SysmonXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        [xml]$configuration = (
            [System.IO.File]::ReadAllText($Path)
        )
    }
    catch {
        throw (
            "sysmon_uboatrat.xml is not valid XML. " +
            $_.Exception.Message
        )
    }

    if ($null -eq $configuration.Sysmon) {
        throw "sysmon_uboatrat.xml does not contain a Sysmon root element."
    }

    if ($null -eq $configuration.Sysmon.EventFiltering) {
        throw "sysmon_uboatrat.xml does not contain EventFiltering rules."
    }

    $requiredEventNodes = @(
        "ProcessCreate",
        "NetworkConnect",
        "FileCreate",
        "DnsQuery"
    )

    $xmlText = [System.IO.File]::ReadAllText($Path)

    foreach ($eventNode in $requiredEventNodes) {
        if ($xmlText -notmatch ("<" + $eventNode + "\b")) {
            throw (
                "sysmon_uboatrat.xml is missing the required " +
                "$eventNode rule."
            )
        }
    }

    if (
        $xmlText -notmatch
        [regex]::Escape("C:\Users\Administrator\Desktop\Labs\UBoatRAT")
    ) {
        throw (
            "sysmon_uboatrat.xml does not target the expected UBoatRAT " +
            "laboratory path."
        )
    }
}

function Test-MicrosoftSignedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path

    if (
        $signature.Status -ne
        [System.Management.Automation.SignatureStatus]::Valid
    ) {
        return $false
    }

    if ($null -eq $signature.SignerCertificate) {
        return $false
    }

    return (
        $signature.SignerCertificate.Subject -match "Microsoft"
    )
}

function Install-SignedSysinternalsTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [string]$StagingDirectory
    )

    if (Test-MicrosoftSignedFile -Path $Destination) {
        Write-Success (
            "$Name is already present with a valid Microsoft signature."
        )

        return
    }

    $temporaryPath = Join-Path `
        $StagingDirectory `
        ([System.IO.Path]::GetFileName($Destination) + ".download")

    Write-Info "Downloading $Name from Sysinternals Live..."

    Invoke-WebRequest `
        -Uri $Uri `
        -OutFile $temporaryPath `
        -UseBasicParsing

    if (-not (Test-MicrosoftSignedFile -Path $temporaryPath)) {
        throw (
            "$Name failed Microsoft Authenticode signature validation."
        )
    }

    $destinationDirectory = Split-Path -Parent $Destination

    New-Item `
        -Path $destinationDirectory `
        -ItemType Directory `
        -Force |
        Out-Null

    Move-Item `
        -LiteralPath $temporaryPath `
        -Destination $Destination `
        -Force

    Write-Success "$Name installed at: $Destination"
}

function Set-SysinternalsEula {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )

    New-Item `
        -Path $RegistryPath `
        -Force |
        Out-Null

    New-ItemProperty `
        -Path $RegistryPath `
        -Name "EulaAccepted" `
        -PropertyType DWord `
        -Value 1 `
        -Force |
        Out-Null
}

function Remove-PreviousLabRuntime {
    Write-Info "Cleaning previous UBoatRAT lab-specific runtime state..."

    try {
        $labProcesses = Get-CimInstance Win32_Process |
            Where-Object {
                $_.ExecutablePath -and
                $_.ExecutablePath.Equals(
                    $InstalledCopy,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }

        foreach ($process in $labProcesses) {
            Stop-Process `
                -Id $process.ProcessId `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-WarningMessage (
            "Could not enumerate the previous runtime process: " +
            $_.Exception.Message
        )
    }

    try {
        Import-Module BitsTransfer -ErrorAction Stop

        $labJobs = @(
            Get-BitsTransfer `
                -AllUsers `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -eq $LabBitsJobName
                }
        )

        foreach ($job in $labJobs) {
            $job |
                Remove-BitsTransfer `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue
        }
    }
    catch {
        & "$env:SystemRoot\System32\bitsadmin.exe" `
            /cancel `
            "$LabBitsJobName" `
            2>$null |
            Out-Null
    }

    Remove-Item `
        -LiteralPath $RuntimeDir `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    foreach ($transientFile in @(
        (Join-Path $LabDir "lab_session.json"),
        (Join-Path $LabDir "UBoatRAT_Lab_Blocked.log"),
        (Join-Path $LabDir "hosts.pre-uboatrat.bak")
    )) {
        Remove-Item `
            -LiteralPath $transientFile `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Write-Success "Previous lab-specific runtime state removed."
}

function Remove-StaleLabHostsEntry {
    Write-Info "Removing any stale $LabHostname snapshot mapping..."

    if (-not (Test-Path -LiteralPath $HostsFile -PathType Leaf)) {
        throw "The Windows hosts file was not found: $HostsFile"
    }

    $hostnamePattern = (
        "(?i)(^|\s)" +
        [regex]::Escape($LabHostname) +
        "(\s|$)"
    )

    $currentLines = @(
        Get-Content `
            -LiteralPath $HostsFile `
            -ErrorAction Stop
    )

    $updatedLines = @()
    $removedCount = 0

    foreach ($line in $currentLines) {
        $trimmedLine = $line.TrimStart()

        if ($trimmedLine.StartsWith("#")) {
            $updatedLines += $line
            continue
        }

        if ($line -match $hostnamePattern) {
            $removedCount++
            continue
        }

        $updatedLines += $line
    }

    if ($removedCount -gt 0) {
        [System.IO.File]::WriteAllLines(
            $HostsFile,
            [string[]]$updatedLines,
            [System.Text.Encoding]::ASCII
        )

        & "$env:SystemRoot\System32\ipconfig.exe" /flushdns |
            Out-Null

        Write-Success (
            "Removed $removedCount stale $LabHostname hosts entry/entries."
        )
    }
    else {
        Write-Success "No stale $LabHostname hosts entry was present."
    }
}

# ============================================================================
# Main
# ============================================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host "       Benign UBoatRAT Laboratory - Windows Setup" `
    -ForegroundColor Cyan
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host ""

if (-not (Test-IsAdministrator)) {
    Write-Failure (
        "Run this setup from Windows PowerShell 5.1 as Administrator."
    )

    exit 1
}

Write-Success "Administrator privileges confirmed."

Write-Info (
    "PowerShell version: " +
    $PSVersionTable.PSVersion.ToString() +
    " [" +
    $PSVersionTable.PSEdition +
    "]"
)

if ($PSVersionTable.PSEdition -ne "Desktop") {
    throw (
        "Use Windows PowerShell 5.1 (powershell.exe), not pwsh.exe."
    )
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw "This laboratory requires 64-bit Windows."
}

# Preserve existing protocols and ensure TLS 1.2 is available.
[Net.ServicePointManager]::SecurityProtocol = (
    [Net.ServicePointManager]::SecurityProtocol -bor
    [Net.SecurityProtocolType]::Tls12
)

$stagingDirectory = Join-Path `
    $env:TEMP `
    ("UBoatRAT_Setup_" + [Guid]::NewGuid().ToString("N"))

$setupError = $null
$downloadedFiles = @{}
$simulatorHash = $null

try {
    New-Item `
        -Path $stagingDirectory `
        -ItemType Directory `
        -Force |
        Out-Null

    # ------------------------------------------------------------------------
    # 1. Download every repository artifact into staging
    # ------------------------------------------------------------------------

    foreach ($artifact in $ArtifactDefinitions) {
        $downloadedPath = Invoke-RepositoryDownload `
            -FileName $artifact.Name `
            -StagingDirectory $stagingDirectory `
            -Required $artifact.Required

        if ($null -ne $downloadedPath) {
            $downloadedFiles[$artifact.Name] = $downloadedPath
        }
    }

    # ------------------------------------------------------------------------
    # 2. Validate everything before replacing local files
    # ------------------------------------------------------------------------

    Write-Info "Validating downloaded laboratory artifacts..."

    Assert-LabStartVersion `
        -Path $downloadedFiles["lab_start.ps1"]

    $simulatorHash = Assert-SimulatorBinary `
        -Path $downloadedFiles["WinSvcHelper.exe"]

    Assert-CSharpSourceVersion `
        -Path $downloadedFiles["WinSvcHelper.cs"]

    Assert-Marker `
        -Path $downloadedFiles["UBoatRAT_LAB.marker"]

    Assert-SysmonXml `
        -Path $downloadedFiles["sysmon_uboatrat.xml"]

    Write-Success "Repository artifact validation passed."

    # ------------------------------------------------------------------------
    # 3. Create the exact requested lab directory and clean old runtime state
    # ------------------------------------------------------------------------

    New-Item `
        -Path $LabDir `
        -ItemType Directory `
        -Force |
        Out-Null

    Remove-PreviousLabRuntime

    # ------------------------------------------------------------------------
    # 4. Copy only validated files into the lab directory
    # ------------------------------------------------------------------------

    Write-Info "Copying validated artifacts into the lab directory..."

    foreach ($artifact in $ArtifactDefinitions) {
        if (-not $downloadedFiles.ContainsKey($artifact.Name)) {
            continue
        }

        Copy-Item `
            -LiteralPath $downloadedFiles[$artifact.Name] `
            -Destination (Join-Path $LabDir $artifact.Name) `
            -Force

        Write-Success "$($artifact.Name) copied."
    }

    $finalHash = (
        Get-FileHash `
            -LiteralPath (Join-Path $LabDir "WinSvcHelper.exe") `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($finalHash -ne $ExpectedSimulatorSha256) {
        throw "WinSvcHelper.exe changed after validation."
    }

    # ------------------------------------------------------------------------
    # 5. Record hashes for documentation and later verification
    # ------------------------------------------------------------------------

    $manifestFiles = @()

    foreach ($artifact in $ArtifactDefinitions) {
        $finalPath = Join-Path $LabDir $artifact.Name

        if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
            continue
        }

        $fileInfo = Get-Item -LiteralPath $finalPath
        $fileHash = (
            Get-FileHash `
                -LiteralPath $finalPath `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        $manifestFiles += [ordered]@{
            Name   = $artifact.Name
            Size   = $fileInfo.Length
            SHA256 = $fileHash
        }
    }

    $manifest = [ordered]@{
        SetupTimeUtc          = (Get-Date).ToUniversalTime().ToString("O")
        PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
        LabDirectory          = $LabDir
        RepositoryBase        = $RepoBase
        SnapshotModel         = "Shared VM; setup once; session reset by revert"
        ExpectedSimulatorHash = $ExpectedSimulatorSha256
        Files                 = $manifestFiles
    }

    $manifest |
        ConvertTo-Json -Depth 5 |
        Set-Content `
            -LiteralPath $ManifestPath `
            -Encoding UTF8

    Write-Success "Setup manifest written to: $ManifestPath"

    # ------------------------------------------------------------------------
    # 6. Stage or verify shared tools without activating services
    # ------------------------------------------------------------------------

    if ($SkipToolDownloads) {
        Write-WarningMessage (
            "Tool downloads were skipped by request."
        )
    }
    else {
        Install-SignedSysinternalsTool `
            -Name "Process Monitor" `
            -Uri $ProcmonUri `
            -Destination $ProcmonPath `
            -StagingDirectory $stagingDirectory

        Install-SignedSysinternalsTool `
            -Name "Process Explorer" `
            -Uri $ProcExpUri `
            -Destination $ProcExpPath `
            -StagingDirectory $stagingDirectory

        Install-SignedSysinternalsTool `
            -Name "Sysmon" `
            -Uri $SysmonUri `
            -Destination $SysmonPath `
            -StagingDirectory $stagingDirectory

        Set-SysinternalsEula `
            -RegistryPath (
                "HKCU:\Software\Sysinternals\Process Monitor"
            )

        Set-SysinternalsEula `
            -RegistryPath (
                "HKCU:\Software\Sysinternals\Process Explorer"
            )

        Write-Success "Sysinternals EULAs accepted for the current user."
    }

    # ------------------------------------------------------------------------
    # 7. Report tool and system status without changing global configuration
    # ------------------------------------------------------------------------

    $wiresharkCandidates = @(
        "C:\Program Files\Wireshark\Wireshark.exe",
        "C:\Program Files (x86)\Wireshark\Wireshark.exe"
    )

    $wiresharkPath = $wiresharkCandidates |
        Where-Object {
            Test-Path -LiteralPath $_ -PathType Leaf
        } |
        Select-Object -First 1

    if ($null -eq $wiresharkPath) {
        Write-WarningMessage (
            "Wireshark is not installed. The Ubuntu tcpdump capture " +
            "can still be used."
        )
    }
    else {
        Write-Success "Wireshark found at: $wiresharkPath"
    }

    $bitsService = Get-CimInstance Win32_Service `
        -Filter "Name='BITS'"

    if ($null -eq $bitsService) {
        throw "The BITS service was not found."
    }

    if ($bitsService.StartMode -eq "Disabled") {
        throw "The BITS service is disabled."
    }

    Write-Success (
        "BITS is available. State: $($bitsService.State); " +
        "start mode: $($bitsService.StartMode)."
    )

    $sysmonService = Get-Service `
        -Name "Sysmon*" `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $sysmonService) {
        Write-Success (
            "No Sysmon service is active in the shared snapshot baseline."
        )
    }
    else {
        Write-Success (
            "Existing shared Sysmon service detected: " +
            "$($sysmonService.Name) [$($sysmonService.Status)]."
        )
    }

    Write-Info (
        "sysmon_uboatrat.xml was staged as a lab asset only."
    )

    Write-Info (
        "The setup did not install Sysmon or replace the active shared " +
        "Sysmon configuration."
    )

    try {
        $defenderStatus = Get-MpComputerStatus

        Write-Host (
            "    Defender antivirus enabled: " +
            $defenderStatus.AntivirusEnabled
        ) -ForegroundColor DarkGray

        Write-Host (
            "    Defender real-time protection: " +
            $defenderStatus.RealTimeProtectionEnabled
        ) -ForegroundColor DarkGray
    }
    catch {
        Write-WarningMessage (
            "Microsoft Defender status could not be queried."
        )
    }

    if (
        -not (
            Test-Path `
                -LiteralPath (Join-Path $LabDir "WinSvcHelper.exe") `
                -PathType Leaf
        )
    ) {
        throw (
            "WinSvcHelper.exe is missing after setup. " +
            "Check Windows Security Protection History."
        )
    }

    # ------------------------------------------------------------------------
    # Finish
    # ------------------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" `
        -ForegroundColor DarkCyan
    Write-Host "       Windows infrastructure setup completed" `
        -ForegroundColor Green
    Write-Host "============================================================" `
        -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "Laboratory directory:" -ForegroundColor Cyan
    Write-Host "  $LabDir" -ForegroundColor White
    Write-Host ""

    Write-Host "WinSvcHelper.exe SHA-256:" -ForegroundColor Cyan
    Write-Host "  $simulatorHash" -ForegroundColor White
    Write-Host ""

    Write-Host "After the Ubuntu server is running:" `
        -ForegroundColor Cyan
    Write-Host "  cd `"$LabDir`"" -ForegroundColor White
    Write-Host "  .\lab_start.ps1 -UbuntuIP <UBUNTU_PRIVATE_IP>" `
        -ForegroundColor White
    Write-Host ""

    Write-WarningMessage (
        "This setup did not run lab_start.ps1 or WinSvcHelper.exe."
    )

    Write-WarningMessage (
        "Microsoft Defender and the PowerShell execution policy were not changed."
    )

    Write-Host ""
    Write-Success (
        "The UBoatRAT files are staged for the shared VM snapshot."
    )

    Write-WarningMessage (
        "Do not run lab_start.ps1 or WinSvcHelper.exe before taking the " +
        "clean snapshot."
    )

    Write-Info (
        "The student will start the Ubuntu server manually during the lab."
    )
}
catch {
    $setupError = $_

    Write-Host ""
    Write-Failure "Windows setup failed."
    Write-Failure $_.Exception.Message
}
finally {
    Remove-Item `
        -LiteralPath $stagingDirectory `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}

if ($null -ne $setupError) {
    exit 1
}
