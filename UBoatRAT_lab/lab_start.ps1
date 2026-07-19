# ============================================================================
# Script: lab_start.ps1
# ============================================================================

Write-Host "=== UBoatRAT Lab Initialization ===" -ForegroundColor Cyan

# 0. Require Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "[-] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "    Right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Red
    exit 1
}

# 1. Retrieve the dynamic IP and perform local DNS Spoofing
$UbuntuIP = Read-Host "Enter the IP address of the Ubuntu VM (e.g., 10.10.164.199)"

if ($UbuntuIP -match "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b") {
    $HostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $HostEntry = "$UbuntuIP c2-ubuntu.local"

    # Remove any existing c2-ubuntu.local entry to avoid duplicates on re-run
    $HostsContent = Get-Content $HostsFile
    $HostsContent = $HostsContent | Where-Object { $_ -notmatch "c2-ubuntu\.local" }
    $HostsContent += $HostEntry
    Set-Content -Path $HostsFile -Value $HostsContent

    # Flush the DNS cache to ensure Windows resolves the new domain immediately
    ipconfig /flushdns | Out-Null

    Write-Host "[+] DNS temporarily redirected: c2-ubuntu.local -> $UbuntuIP" -ForegroundColor Green
} else {
    Write-Host "[-] Error: You did not enter a valid IP address. Run the script again." -ForegroundColor Red
    exit 1
}

# 2. Reset the BITS queue (Clean Baseline)
Write-Host "[*] Cleaning BITS state (Baseline)..." -ForegroundColor Cyan
$bitsReset = Start-Process -FilePath "bitsadmin.exe" -ArgumentList "/reset /allusers" -Wait -WindowStyle Hidden -PassThru
if ($bitsReset.ExitCode -eq 0) {
    Write-Host "[+] BITS queue successfully reset." -ForegroundColor Green
} else {
    Write-Host "[!] Warning: BITS reset returned exit code $($bitsReset.ExitCode). Continuing..." -ForegroundColor Yellow
}

# 3. Enable Auditing
Write-Host "[*] Arming system logs..." -ForegroundColor Cyan

# Enable BITS Operational log
$wevtResult = wevtutil sl Microsoft-Windows-Bits-Client/Operational /e:true 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] BITS Operational log enabled." -ForegroundColor Green
} else {
    Write-Host "[!] Warning: Could not enable BITS Operational log. $wevtResult" -ForegroundColor Yellow
}

# Enable Process Creation logging
auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null
Write-Host "[+] Process Creation auditing enabled." -ForegroundColor Green

Write-Host "[+] Auditing enabled (BITS Operational & Process Creation)." -ForegroundColor Green

# 4. Verify Sysmon is installed and running (required for Phase 13 and 14)
Write-Host "[*] Checking Sysmon status..." -ForegroundColor Cyan
$sysmonSvc = Get-Service -Name "Sysmon*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sysmonSvc -and $sysmonSvc.Status -eq 'Running') {
    Write-Host "[+] Sysmon is running ($($sysmonSvc.Name))." -ForegroundColor Green
} else {
    Write-Host "[!] WARNING: Sysmon is not running or not installed." -ForegroundColor Yellow
    Write-Host "    Phase 13 and 14 (Sysmon event analysis) will not produce results." -ForegroundColor Yellow
    Write-Host "    Install from: https://learn.microsoft.com/sysinternals/downloads/sysmon" -ForegroundColor Yellow
}

Write-Host "`n[+] The environment is ready! You can begin the investigation of WinSvcHelper.exe." -ForegroundColor Green
