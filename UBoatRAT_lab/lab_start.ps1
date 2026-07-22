#requires -Version 5.1

<#
.SYNOPSIS
    Initializes the Windows VM for the benign UBoatRAT behavior lab.

.DESCRIPTION
    This script prepares networking, removes previous lab-specific artefacts,
    enables required telemetry, applies the UBoatRAT-specific Sysmon
    configuration for the current disposable VM session, and verifies that
    the Ubuntu lab server is reachable.

    Sysmon changes are intentionally session-scoped: closing the laboratory
    restores the shared multi-lab snapshot and its original Sysmon state.

    It does not:
      - execute WinSvcHelper.exe;
      - disable Microsoft Defender;
      - add Defender exclusions;
      - reset unrelated BITS jobs;
      - expose any network service;
      - create a command-and-control channel.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$UbuntuIP
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration
# ============================================================================

$LabHostname       = "uboat-c2.test"
$HttpPort          = 8080
$BeaconPort        = 9001
$LabBitsJobName    = "UBoatLab_Persistence"

$ExpectedLabDir = "C:\Users\Administrator\Desktop\Labs\UBoatRAT"

$ScriptPath = $MyInvocation.MyCommand.Path
$LabDir     = Split-Path -Parent $ScriptPath

$SimulatorPath    = Join-Path $LabDir "WinSvcHelper.exe"
$MarkerPath       = Join-Path $LabDir "UBoatRAT_LAB.marker"
$SessionPath      = Join-Path $LabDir "lab_session.json"
$SysmonConfigPath = Join-Path $LabDir "sysmon_uboatrat.xml"
$SysmonDumpPath   = Join-Path $LabDir "sysmon_active_config.txt"

$ToolsDir = Join-Path $LabDir "tools"

$SysmonToolCandidates = @(
    (Join-Path $ToolsDir "Sysmon\Sysmon64.exe"),
    (Join-Path $ToolsDir "Sysmon\Sysmon.exe"),
    "C:\Windows\Sysmon64.exe",
    "C:\Windows\Sysmon.exe"
)

$InstalledLabRoot = Join-Path $LabDir "runtime"
$InstalledCopy    = Join-Path $InstalledLabRoot "svchost.exe"

$TempTriggerPath = Join-Path $InstalledLabRoot "uboat_lab_trigger.dat"
$BlockedLogPath  = Join-Path $LabDir "UBoatRAT_Lab_Blocked.log"

$HostsFile       = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$HostsBackupPath = Join-Path $LabDir "hosts.pre-uboatrat.bak"

# ============================================================================
# Output helpers
# ============================================================================

function Write-Info {
    param([string]$Message)

    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)

    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)

    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Failure {
    param([string]$Message)

    Write-Host "[-] $Message" -ForegroundColor Red
}

# ============================================================================
# Validation helpers
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

function Test-IsPrivateIPv4 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Address
    )

    $parsedAddress = [System.Net.IPAddress]::None

    if (-not [System.Net.IPAddress]::TryParse(
            $Address,
            [ref]$parsedAddress
        )) {
        return $false
    }

    if (
        $parsedAddress.AddressFamily -ne
        [System.Net.Sockets.AddressFamily]::InterNetwork
    ) {
        return $false
    }

    $bytes = $parsedAddress.GetAddressBytes()

    # 10.0.0.0/8
    if ($bytes[0] -eq 10) {
        return $true
    }

    # 172.16.0.0/12
    if (
        $bytes[0] -eq 172 -and
        $bytes[1] -ge 16 -and
        $bytes[1] -le 31
    ) {
        return $true
    }

    # 192.168.0.0/16
    if (
        $bytes[0] -eq 192 -and
        $bytes[1] -eq 168
    ) {
        return $true
    }

    return $false
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMilliseconds = 4000
    )

    $client = New-Object System.Net.Sockets.TcpClient

    try {
        $asyncResult = $client.BeginConnect(
            $ComputerName,
            $Port,
            $null,
            $null
        )

        $connected = $asyncResult.AsyncWaitHandle.WaitOne(
            $TimeoutMilliseconds,
            $false
        )

        if (-not $connected) {
            return $false
        }

        $client.EndConnect($asyncResult)

        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Get-LocalRouteAddress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteAddress
    )

    $udpClient = New-Object System.Net.Sockets.UdpClient

    try {
        # This selects the route without transmitting application data.
        $udpClient.Connect($RemoteAddress, 9)

        $localEndpoint =
            [System.Net.IPEndPoint]$udpClient.Client.LocalEndPoint

        return $localEndpoint.Address.ToString()
    }
    catch {
        return "Unknown"
    }
    finally {
        $udpClient.Dispose()
    }
}

function Get-ExecutablePathFromServiceCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $expandedCommandLine = (
        [Environment]::ExpandEnvironmentVariables(
            $CommandLine
        )
    ).Trim()

    if ([string]::IsNullOrWhiteSpace($expandedCommandLine)) {
        return $null
    }

    if ($expandedCommandLine.StartsWith('"')) {
        $closingQuote = $expandedCommandLine.IndexOf('"', 1)

        if ($closingQuote -gt 1) {
            return $expandedCommandLine.Substring(
                1,
                $closingQuote - 1
            )
        }
    }

    $pathMatch = [regex]::Match(
        $expandedCommandLine,
        '^(?<path>.+?\.exe)(?:\s|$)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($pathMatch.Success) {
        return $pathMatch.Groups["path"].Value.Trim()
    }

    return $null
}

function Get-SysmonServiceRecord {
    return (
        Get-CimInstance Win32_Service |
        Where-Object {
            $_.Name -eq "Sysmon" -or
            $_.Name -eq "Sysmon64"
        } |
        Select-Object -First 1
    )
}

function Get-SysmonExecutablePath {
    param(
        [Parameter(Mandatory = $false)]
        $ServiceRecord
    )

    $candidatePaths = @()

    if (
        $null -ne $ServiceRecord -and
        -not [string]::IsNullOrWhiteSpace(
            $ServiceRecord.PathName
        )
    ) {
        $serviceExecutable = (
            Get-ExecutablePathFromServiceCommandLine `
                -CommandLine $ServiceRecord.PathName
        )

        if (-not [string]::IsNullOrWhiteSpace($serviceExecutable)) {
            $candidatePaths += $serviceExecutable
        }
    }

    $candidatePaths += $SysmonToolCandidates

    foreach ($candidatePath in $candidatePaths) {
        if (
            -not [string]::IsNullOrWhiteSpace($candidatePath) -and
            (Test-Path -LiteralPath $candidatePath -PathType Leaf)
        ) {
            return (
                Resolve-Path -LiteralPath $candidatePath
            ).Path
        }
    }

    return $null
}

function Assert-SysmonConfiguration {
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
        throw (
            "sysmon_uboatrat.xml does not contain a Sysmon root element."
        )
    }

    if ($null -eq $configuration.Sysmon.EventFiltering) {
        throw (
            "sysmon_uboatrat.xml does not contain EventFiltering."
        )
    }

    foreach ($requiredNode in @(
        "ProcessCreate",
        "NetworkConnect",
        "FileCreate",
        "DnsQuery"
    )) {
        if (
            $null -eq $configuration.SelectSingleNode(
                "//$requiredNode"
            )
        ) {
            throw (
                "sysmon_uboatrat.xml is missing the " +
                "$requiredNode rule."
            )
        }
    }

    $configurationText = (
        [System.IO.File]::ReadAllText($Path)
    )

    if (
        $configurationText -notmatch
        [regex]::Escape($ExpectedLabDir)
    ) {
        throw (
            "sysmon_uboatrat.xml does not target the expected " +
            "laboratory directory."
        )
    }
}

function Invoke-NativeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    $previousErrorActionPreference =
        $ErrorActionPreference

    $rawOutput = @()
    $exitCode = $null

    try {
        # Windows PowerShell 5.1 can convert native stderr into
        # ErrorRecord objects. Do not let the global "Stop" setting
        # terminate execution before $LASTEXITCODE is captured.
        $ErrorActionPreference = "Continue"

        $rawOutput = @(
            & $FilePath @Arguments 2>&1
        )

        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference =
            $previousErrorActionPreference
    }

    $cleanOutput = @(
        $rawOutput |
            ForEach-Object {
                $line = $_.ToString()

                if (
                    -not [string]::IsNullOrWhiteSpace($line) -and
                    $line -ne
                        "System.Management.Automation.RemoteException"
                ) {
                    $line
                }
            }
    )

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = $cleanOutput
    }
}

function Initialize-LabSysmon {
    Assert-SysmonConfiguration -Path $SysmonConfigPath

    $serviceRecord = Get-SysmonServiceRecord

    $sysmonExecutable = Get-SysmonExecutablePath `
        -ServiceRecord $serviceRecord

    if ([string]::IsNullOrWhiteSpace($sysmonExecutable)) {
        throw (
            "A Sysmon executable was not found. " +
            "Run uboatrat_windows_setup.ps1 before taking the snapshot."
        )
    }

    $sysmonExecutableHash = (
        Get-FileHash `
            -LiteralPath $sysmonExecutable `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    $sysmonConfigHash = (
        Get-FileHash `
            -LiteralPath $SysmonConfigPath `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($null -eq $serviceRecord) {
        Write-Info (
            "Sysmon is not active in this VM session. " +
            "Installing it with the UBoatRAT lab configuration..."
        )

        $sysmonResult = Invoke-NativeTool `
    -FilePath $sysmonExecutable `
    -Arguments @(
        "-accepteula",
        "-i",
        $SysmonConfigPath
    )

$sysmonOutput = $sysmonResult.Output
$sysmonExitCode = $sysmonResult.ExitCode
$sysmonAction = "InstalledForSession"
    }
    else {
        Write-Info (
            "Applying the UBoatRAT Sysmon configuration " +
            "for this disposable VM session..."
        )

        $sysmonResult = Invoke-NativeTool `
    -FilePath $sysmonExecutable `
    -Arguments @(
        "-c",
        $SysmonConfigPath
    )

$sysmonOutput = $sysmonResult.Output
$sysmonExitCode = $sysmonResult.ExitCode
$sysmonAction = "ReconfiguredForSession"
    }

    if ($sysmonExitCode -ne 0) {
    $outputText = if ($sysmonOutput.Count -gt 0) {
        $sysmonOutput -join " | "
    }
    else {
        "<no output>"
    }

    throw (
        "Sysmon configuration failed with exit code " +
        "$sysmonExitCode. Output: " +
        $outputText
    )
}

    $sysmonService = Get-Service `
        -Name "Sysmon", "Sysmon64" `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $sysmonService) {
        throw (
            "Sysmon reported success, but no Sysmon service was found."
        )
    }

    if ($sysmonService.Status -ne "Running") {
        Start-Service `
            -Name $sysmonService.Name `
            -ErrorAction Stop

        $sysmonService.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(10)
        )

        $sysmonService.Refresh()
    }

    if ($sysmonService.Status -ne "Running") {
        throw "The Sysmon service is not running."
    }
    
$configurationDumpResult = Invoke-NativeTool `
    -FilePath $sysmonExecutable `
    -Arguments @("-c")

$configurationDump =
    $configurationDumpResult.Output

$configurationDumpExitCode =
    $configurationDumpResult.ExitCode

    if ($configurationDumpExitCode -ne 0) {
        throw (
            "Sysmon was configured, but its active configuration " +
            "could not be queried."
        )
    }

    $configurationDump |
        Set-Content `
            -LiteralPath $SysmonDumpPath `
            -Encoding UTF8

    Write-Success (
        "Sysmon is running with the UBoatRAT session configuration."
    )

    Write-Host (
        "    Action: " +
        $sysmonAction
    ) -ForegroundColor DarkGray

    Write-Host (
        "    Service: " +
        $sysmonService.Name
    ) -ForegroundColor DarkGray

    Write-Host (
        "    Executable: " +
        $sysmonExecutable
    ) -ForegroundColor DarkGray

    Write-Host (
        "    Configuration SHA-256: " +
        $sysmonConfigHash
    ) -ForegroundColor DarkGray

    return [pscustomobject]@{
        Action           = $sysmonAction
        ServiceName      = $sysmonService.Name
        ExecutablePath   = $sysmonExecutable
        ExecutableSHA256 = $sysmonExecutableHash
        ConfigPath       = $SysmonConfigPath
        ConfigSHA256     = $sysmonConfigHash
        ConfigDumpPath   = $SysmonDumpPath
    }
}

# ============================================================================
# Start
# ============================================================================

Clear-Host

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host "       Benign UBoatRAT Laboratory — Windows Start" `
    -ForegroundColor Cyan
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host ""

if (-not (Test-IsAdministrator)) {
    Write-Failure "This script must be run from an Administrator PowerShell."
    Write-Failure "Right-click PowerShell and select 'Run as administrator'."
    exit 1
}

Write-Success "Administrator privileges confirmed."

Write-Info (
    "Running under Windows PowerShell " +
    $PSVersionTable.PSVersion.ToString() +
    " [" +
    $PSVersionTable.PSEdition +
    "]"
)

if ($PSVersionTable.PSEdition -ne "Desktop") {
    Write-Failure (
        "Run this script with Windows PowerShell 5.1 " +
        "(powershell.exe), not pwsh.exe."
    )

    exit 1
}

if (
    -not $LabDir.Equals(
        $ExpectedLabDir,
        [System.StringComparison]::OrdinalIgnoreCase
    )
) {
    Write-Failure (
        "This lab must run from: $ExpectedLabDir"
    )

    Write-Failure (
        "Current script directory: $LabDir"
    )

    exit 1
}

Set-Location -LiteralPath $LabDir

Write-Info "Laboratory directory: $LabDir"

# ============================================================================
# 1. Verify required laboratory files
# ============================================================================

Write-Info "Checking required laboratory artefacts..."

$missingFiles = @()

foreach ($requiredFile in @(
    $SimulatorPath,
    $MarkerPath,
    $SysmonConfigPath
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        $missingFiles += $requiredFile
    }
}

if ($missingFiles.Count -gt 0) {
    foreach ($missingFile in $missingFiles) {
        Write-Failure "Missing required file: $missingFile"
    }

    exit 1
}

if ((Get-Item -LiteralPath $SimulatorPath).Length -eq 0) {
    Write-Failure "WinSvcHelper.exe is empty."
    exit 1
}

if ((Get-Item -LiteralPath $MarkerPath).Length -eq 0) {
    Write-Failure "UBoatRAT_LAB.marker is empty."
    exit 1
}

Assert-SysmonConfiguration -Path $SysmonConfigPath

Write-Success "WinSvcHelper.exe found."
Write-Success "UBoatRAT_LAB.marker found."
Write-Success "sysmon_uboatrat.xml found and structurally validated."

$SimulatorHash = (
    Get-FileHash `
        -LiteralPath $SimulatorPath `
        -Algorithm SHA256
).Hash.ToLowerInvariant()

Write-Host "    WinSvcHelper SHA-256: $SimulatorHash" `
    -ForegroundColor DarkGray

# ============================================================================
# 2. Request and validate the Ubuntu IP address
# ============================================================================

if ([string]::IsNullOrWhiteSpace($UbuntuIP)) {
    $UbuntuIP = Read-Host `
        "Enter the private IPv4 address of the Ubuntu VM"
}

$UbuntuIP = $UbuntuIP.Trim()

if (-not (Test-IsPrivateIPv4 -Address $UbuntuIP)) {
    Write-Failure (
        "'$UbuntuIP' is not a valid RFC1918 private IPv4 address."
    )

    Write-Failure (
        "Expected a 10.x.x.x, 172.16-31.x.x, or 192.168.x.x address."
    )

    exit 1
}

Write-Success "Ubuntu private IPv4 validated: $UbuntuIP"

$WindowsIP = Get-LocalRouteAddress -RemoteAddress $UbuntuIP

Write-Host "    Windows source IPv4: $WindowsIP" `
    -ForegroundColor DarkGray

# ============================================================================
# 3. Configure the controlled laboratory hostname
# ============================================================================

Write-Info "Configuring $LabHostname in the Windows hosts file..."

if (-not (Test-Path -LiteralPath $HostsFile)) {
    Write-Failure "The Windows hosts file was not found: $HostsFile"
    exit 1
}

if (-not (Test-Path -LiteralPath $HostsBackupPath)) {
    Copy-Item `
        -LiteralPath $HostsFile `
        -Destination $HostsBackupPath `
        -Force

    Write-Success "Original hosts file backed up to:"
    Write-Host "    $HostsBackupPath" -ForegroundColor DarkGray
}

$hostnamePattern = (
    "(?i)(^|\s)" +
    [regex]::Escape($LabHostname) +
    "(\s|$)"
)

$currentHostsContent = Get-Content -LiteralPath $HostsFile

$filteredHostsContent = foreach ($line in $currentHostsContent) {
    $trimmedLine = $line.TrimStart()

    if ($trimmedLine.StartsWith("#")) {
        $line
        continue
    }

    if ($line -notmatch $hostnamePattern) {
        $line
    }
}

$updatedHostsContent = @($filteredHostsContent)

if (
    $updatedHostsContent.Count -gt 0 -and
    $updatedHostsContent[-1] -ne ""
) {
    $updatedHostsContent += ""
}

$updatedHostsContent += (
    "$UbuntuIP`t$LabHostname`t# Benign UBoatRAT laboratory"
)

[System.IO.File]::WriteAllLines(
    $HostsFile,
    [string[]]$updatedHostsContent,
    [System.Text.Encoding]::ASCII
)

& "$env:SystemRoot\System32\ipconfig.exe" /flushdns |
    Out-Null

Write-Success "$LabHostname mapped to $UbuntuIP."

# Verify that Windows actually resolves the laboratory hostname correctly.

try {
    $resolvedAddresses = @(
        [System.Net.Dns]::GetHostAddresses($LabHostname) |
            Where-Object {
                $_.AddressFamily -eq
                [System.Net.Sockets.AddressFamily]::InterNetwork
            } |
            ForEach-Object {
                $_.ToString()
            }
    )
}
catch {
    Write-Failure "Windows could not resolve $LabHostname."
    Write-Failure $_.Exception.Message
    exit 1
}

if ($resolvedAddresses -notcontains $UbuntuIP) {
    Write-Failure (
        "$LabHostname resolved to '$($resolvedAddresses -join ", ")' " +
        "instead of '$UbuntuIP'."
    )

    exit 1
}

Write-Success "Hostname resolution verified."

# ============================================================================
# 4. Verify Ubuntu services
# ============================================================================

Write-Info "Checking Ubuntu HTTP service on TCP/$HttpPort..."

if (-not (
        Test-TcpPort `
            -ComputerName $LabHostname `
            -Port $HttpPort
    )) {
    Write-Failure (
        "The Ubuntu HTTP server is not reachable at " +
        "$LabHostname`:$HttpPort."
    )

    Write-Host ""
    Write-Host "Start it on Ubuntu with:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  cd ~/BnB/UBoatRAT" -ForegroundColor White
    Write-Host (
        "  python3 ubuntu_c2_server.py " +
        "--bind $UbuntuIP --advertise-ip $UbuntuIP"
    ) -ForegroundColor White
    Write-Host ""

    exit 1
}

Write-Success "TCP/$HttpPort is reachable."

Write-Info "Checking benign TCP beacon listener on TCP/$BeaconPort..."

if (-not (
        Test-TcpPort `
            -ComputerName $LabHostname `
            -Port $BeaconPort
    )) {
    Write-Failure (
        "The Ubuntu beacon listener is not reachable at " +
        "$LabHostname`:$BeaconPort."
    )

    Write-Failure (
        "Both the HTTP and TCP components of ubuntu_c2_server.py " +
        "must be running."
    )

    exit 1
}

Write-Success "TCP/$BeaconPort is reachable."

# ============================================================================
# 5. Verify HTTP resources and resolver contents
# ============================================================================

Write-Info "Checking the Ubuntu health endpoint..."

try {
    $healthResponse = Invoke-WebRequest `
        -Uri "http://$LabHostname`:$HttpPort/health" `
        -UseBasicParsing `
        -TimeoutSec 5
}
catch {
    Write-Failure "The Ubuntu health endpoint could not be reached."
    Write-Failure $_.Exception.Message
    exit 1
}

if (
    $healthResponse.StatusCode -ne 200 -or
    $healthResponse.Content.Trim() -ne "OK"
) {
    Write-Failure "The health endpoint returned an unexpected response."
    exit 1
}

Write-Success "Health endpoint returned OK."

Write-Info "Checking the inert BITS trigger file..."

try {
    $triggerResponse = Invoke-WebRequest `
        -Uri "http://$LabHostname`:$HttpPort/c2/trigger.dat" `
        -Method Head `
        -UseBasicParsing `
        -TimeoutSec 5
}
catch {
    Write-Failure "The inert BITS trigger file is unavailable."
    Write-Failure $_.Exception.Message
    exit 1
}

if ($triggerResponse.StatusCode -ne 200) {
    Write-Failure (
        "The BITS trigger returned HTTP " +
        "$($triggerResponse.StatusCode)."
    )

    exit 1
}

Write-Success "BITS trigger endpoint is available."

Write-Info "Checking the controlled dead-drop resolver..."

try {
    $resolverResponse = Invoke-WebRequest `
        -Uri "http://$LabHostname`:$HttpPort/resolver/README.md" `
        -UseBasicParsing `
        -TimeoutSec 5
}
catch {
    Write-Failure "The resolver endpoint is unavailable."
    Write-Failure $_.Exception.Message
    exit 1
}

$resolverMatch = [regex]::Match(
    $resolverResponse.Content,
    "\[Rudeltaktik\](?<value>[A-Za-z0-9+/=]+)!"
)

if (-not $resolverMatch.Success) {
    Write-Failure (
        "The resolver does not contain the expected " +
        "[Rudeltaktik]<BASE64>! structure."
    )

    exit 1
}

try {
    $decodedResolver = [System.Text.Encoding]::ASCII.GetString(
        [System.Convert]::FromBase64String(
            $resolverMatch.Groups["value"].Value
        )
    )
}
catch {
    Write-Failure "The resolver contains an invalid Base64 value."
    exit 1
}

$expectedResolver = "$UbuntuIP`:$BeaconPort"

if ($decodedResolver -ne $expectedResolver) {
    Write-Failure (
        "Resolver mismatch. Expected '$expectedResolver', " +
        "received '$decodedResolver'."
    )

    Write-Failure (
        "Restart ubuntu_c2_server.py with " +
        "--advertise-ip $UbuntuIP."
    )

    exit 1
}

Write-Success "Resolver decoded correctly: $decodedResolver"

# ============================================================================
# 6. Remove only previous UBoatRAT laboratory artefacts
# ============================================================================

Write-Info "Removing previous UBoatRAT laboratory state..."

# Stop only a process whose executable path matches the lab-installed copy.
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
        Write-WarningMessage (
            "Stopping previous laboratory process PID " +
            "$($process.ProcessId)."
        )

        Stop-Process `
            -Id $process.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
catch {
    Write-WarningMessage (
        "Could not enumerate previous lab processes: " +
        $_.Exception.Message
    )
}

$bitsJobRemoved = $false

try {
    Import-Module BitsTransfer -ErrorAction Stop

    $labBitsJobs = @(
        Get-BitsTransfer `
            -AllUsers `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -eq $LabBitsJobName
            }
    )

    foreach ($job in $labBitsJobs) {
        $job |
            Remove-BitsTransfer `
                -Confirm:$false `
                -ErrorAction SilentlyContinue

        $bitsJobRemoved = $true
    }
}
catch {
    Write-WarningMessage (
        "The BitsTransfer PowerShell module could not remove " +
        "the previous job. Trying bitsadmin."
    )
}

if (-not $bitsJobRemoved) {
    & "$env:SystemRoot\System32\bitsadmin.exe" `
        /cancel `
        "$LabBitsJobName" `
        2>$null |
        Out-Null
}

if (Test-Path -LiteralPath $InstalledLabRoot) {
    Remove-Item `
        -LiteralPath $InstalledLabRoot `
        -Recurse `
        -Force `
        -ErrorAction Stop
}

foreach ($temporaryArtefact in @(
    $TempTriggerPath,
    $BlockedLogPath
)) {
    Remove-Item `
        -LiteralPath $temporaryArtefact `
        -Force `
        -ErrorAction SilentlyContinue
}

Write-Success "Previous lab-specific artefacts removed."

Write-Info "Verifying the BITS baseline..."

$bitsVerificationSucceeded = $false
$remainingLabJobs = @()

try {
    Import-Module BitsTransfer -ErrorAction Stop

    $remainingLabJobs = @(
        Get-BitsTransfer `
            -AllUsers `
            -ErrorAction Stop |
            Where-Object {
                $_.DisplayName -eq $LabBitsJobName
            }
    )

    $bitsVerificationSucceeded = $true
}
catch {
    Write-WarningMessage (
        "Could not verify the BITS queue through the " +
        "BitsTransfer module. Trying bitsadmin."
    )
}

if ($bitsVerificationSucceeded) {
    if ($remainingLabJobs.Count -gt 0) {
        Write-Failure (
            "The previous '$LabBitsJobName' job could not be removed."
        )

        exit 1
    }
}
else {
    $bitsListOutput = & "$env:SystemRoot\System32\bitsadmin.exe" `
        /list `
        /allusers `
        /verbose `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Could not verify the BITS baseline."
        Write-Failure ($bitsListOutput -join " ")
        exit 1
    }

    if (
        ($bitsListOutput -join "`n") -match
        [regex]::Escape($LabBitsJobName)
    ) {
        Write-Failure (
            "The previous '$LabBitsJobName' job still exists."
        )

        exit 1
    }
}

Write-Success (
    "No previous '$LabBitsJobName' job remains."
)

# ============================================================================
# 7. Enable Windows telemetry
# ============================================================================

Write-Info "Enabling the BITS Operational event log..."

$wevtOutput = & "$env:SystemRoot\System32\wevtutil.exe" `
    sl `
    "Microsoft-Windows-Bits-Client/Operational" `
    /e:true `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Failure "Could not enable the BITS Operational log."
    Write-Failure ($wevtOutput -join " ")
    exit 1
}

Write-Success "BITS Operational log enabled."

Write-Info "Enabling process creation auditing..."

$auditOutput = & "$env:SystemRoot\System32\auditpol.exe" `
    /set `
    '/subcategory:Process Creation' `
    /success:enable `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Failure "Could not enable process creation auditing."
    Write-Failure ($auditOutput -join " ")
    exit 1
}

Write-Success "Security Event ID 4688 auditing enabled."

Write-Info "Enabling command-line data in process creation events..."

$AuditRegistryPath = (
    "HKLM:\Software\Microsoft\Windows\" +
    "CurrentVersion\Policies\System\Audit"
)

New-Item `
    -Path $AuditRegistryPath `
    -Force |
    Out-Null

New-ItemProperty `
    -Path $AuditRegistryPath `
    -Name "ProcessCreationIncludeCmdLine_Enabled" `
    -PropertyType DWord `
    -Value 1 `
    -Force |
    Out-Null

Write-Success "Process command-line auditing enabled."

# ============================================================================
# 8. Verify BITS and Sysmon status
# ============================================================================

Write-Info "Checking the BITS service..."

$bitsService = Get-CimInstance Win32_Service `
    -Filter "Name='BITS'"

if ($null -eq $bitsService) {
    Write-Failure "The BITS service was not found."
    exit 1
}

if ($bitsService.StartMode -eq "Disabled") {
    Write-Failure "The BITS service is disabled."
    exit 1
}

Write-Success (
    "BITS service available. " +
    "State: $($bitsService.State); " +
    "Start mode: $($bitsService.StartMode)."
)

Write-Info "Preparing Sysmon telemetry for this VM session..."

try {
    $SysmonSession = Initialize-LabSysmon
}
catch {
    Write-Failure "Sysmon session initialization failed."
    Write-Failure $_.Exception.Message
    exit 1
}

Write-WarningMessage (
    "The active Sysmon configuration was changed only for the " +
    "current disposable VM session."
)

Write-WarningMessage (
    "Closing the laboratory restores the shared snapshot baseline."
)

# ============================================================================
# 9. Report Defender status without modifying it
# ============================================================================

Write-Info "Reading Microsoft Defender status..."

try {
    $defenderStatus = Get-MpComputerStatus

    Write-Host (
        "    Antivirus enabled: " +
        $defenderStatus.AntivirusEnabled
    ) -ForegroundColor DarkGray

    Write-Host (
        "    Real-time protection: " +
        $defenderStatus.RealTimeProtectionEnabled
    ) -ForegroundColor DarkGray

    Write-Success "Microsoft Defender configuration was not modified."
}
catch {
    Write-WarningMessage (
        "Microsoft Defender status could not be queried."
    )
}

# Verify that Defender or another control has not removed the simulator.
if (-not (Test-Path -LiteralPath $SimulatorPath)) {
    Write-Failure (
        "WinSvcHelper.exe disappeared during initialization. " +
        "Check Windows Security protection history."
    )

    exit 1
}

# ============================================================================
# 10. Record the laboratory session start
# ============================================================================

$sessionStartUtc = (Get-Date).ToUniversalTime()

$sessionInformation = [ordered]@{
    SessionStartUtc = $sessionStartUtc.ToString("O")
    WindowsIP       = $WindowsIP
    UbuntuIP        = $UbuntuIP
    LabHostname     = $LabHostname
    HttpPort        = $HttpPort
    BeaconPort      = $BeaconPort
    BitsJobName          = $LabBitsJobName
    SimulatorSHA256      = $SimulatorHash
    LabDirectory         = $LabDir
    SysmonAction         = $SysmonSession.Action
    SysmonService        = $SysmonSession.ServiceName
    SysmonExecutable     = $SysmonSession.ExecutablePath
    SysmonExecutableHash = $SysmonSession.ExecutableSHA256
    SysmonConfig         = $SysmonSession.ConfigPath
    SysmonConfigHash     = $SysmonSession.ConfigSHA256
    SysmonConfigDump     = $SysmonSession.ConfigDumpPath
}

$sessionInformation |
    ConvertTo-Json |
    Set-Content `
        -LiteralPath $SessionPath `
        -Encoding UTF8

Write-Success "Session information written to:"
Write-Host "    $SessionPath" -ForegroundColor DarkGray

# ============================================================================
# Finish
# ============================================================================

Write-Host ""
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host "       UBoatRAT laboratory initialization completed" `
    -ForegroundColor Green
Write-Host "============================================================" `
    -ForegroundColor DarkCyan
Write-Host ""

Write-Host "Ubuntu server:" -ForegroundColor Cyan
Write-Host "  $UbuntuIP" -ForegroundColor White
Write-Host ""

Write-Host "Wireshark display filter:" -ForegroundColor Cyan
Write-Host (
    "  ip.addr == $UbuntuIP && " +
    "(tcp.port == $HttpPort || tcp.port == $BeaconPort)"
) -ForegroundColor White
Write-Host ""

Write-Host "Optional Ubuntu tcpdump capture:" -ForegroundColor Cyan
$TcpdumpCommand = "sudo tcpdump -ni any 'host $WindowsIP and (tcp port $HttpPort or tcp port $BeaconPort)' -w ~/BnB/UBoatRAT/captures/uboatrat_lab.pcap"

Write-Host "  $TcpdumpCommand" -ForegroundColor White
Write-Host ""

Write-Host "Clean BITS baseline:" -ForegroundColor Cyan
Write-Host "  bitsadmin /list /allusers" -ForegroundColor White
Write-Host ""

Write-Host "Sysmon event log:" -ForegroundColor Cyan
Write-Host (
    "  Event Viewer > Applications and Services Logs > " +
    "Microsoft > Windows > Sysmon > Operational"
) -ForegroundColor White
Write-Host ""

Write-Host "Applied Sysmon configuration dump:" -ForegroundColor Cyan
Write-Host "  $SysmonDumpPath" -ForegroundColor White
Write-Host ""

Write-Host "Run the simulator only after starting captures:" `
    -ForegroundColor Cyan

Write-Host "  cd `"$LabDir`"" -ForegroundColor White
Write-Host "  .\WinSvcHelper.exe" -ForegroundColor White
Write-Host ""

Write-WarningMessage (
    "The simulator has NOT been executed by this script."
)

Write-WarningMessage (
    "Do not disable Microsoft Defender globally."
)
