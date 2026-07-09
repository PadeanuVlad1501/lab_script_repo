# ============================================================================
# Script: uboatrat_windows_setup.ps1
# ============================================================================

# 0. Require Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host "[-] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "    Right-click PowerShell and select 'Run as Administrator', then try again." -ForegroundColor Red
    exit 1
}

$LabDir  = "C:\Users\Administrator\Desktop\Labs\UBoatRAT"
$RepoBase = "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/main/UBoatRAT_lab"

Write-Host "[*] Starting setup for the UBoatRAT lab..." -ForegroundColor Cyan

# 1. Create the isolated lab directory
if (-not (Test-Path $LabDir)) {
    New-Item -Path $LabDir -ItemType Directory -Force | Out-Null
    Write-Host "[+] Lab directory created: $LabDir" -ForegroundColor Green
} else {
    Write-Host "[*] Lab directory already exists." -ForegroundColor Yellow
}

# 2. Download artifacts from Git to the lab directory
Write-Host "[*] Downloading artifacts from Git..." -ForegroundColor Cyan

# Download the start script
try {
    Invoke-WebRequest -Uri "$RepoBase/lab_start.ps1" -OutFile "$LabDir\lab_start.ps1" -UseBasicParsing
    Write-Host "[+] lab_start.ps1 downloaded." -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Could not download lab_start.ps1. $_" -ForegroundColor Red
}

# Download the UBoatRAT emulator
try {
    Invoke-WebRequest -Uri "$RepoBase/WinSvcHelper.exe" -OutFile "$LabDir\WinSvcHelper.exe" -UseBasicParsing
    Write-Host "[+] WinSvcHelper.exe downloaded." -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Could not download WinSvcHelper.exe. $_" -ForegroundColor Red
}

# 3. Check for required tools and install if missing (Sanity Check & Auto-Install)
Write-Host "[*] Checking required tools..." -ForegroundColor Cyan

# --- Wireshark Check ---
$WiresharkPath = "C:\Program Files\Wireshark\Wireshark.exe"
if (-not (Test-Path $WiresharkPath)) {
    Write-Host "[!] Warning: Wireshark was not found at the standard location." -ForegroundColor Yellow
    Write-Host "    Download from: https://www.wireshark.org/download.html" -ForegroundColor Yellow
} else {
    Write-Host "[+] Wireshark found." -ForegroundColor Green
}

# --- Procmon Check & Safe Install ---
# Placed under C:\Tools\Procmon\ to match the path referenced in the lab guide.
$ProcmonDir  = "C:\Tools\Procmon"
$ProcmonPath = "$ProcmonDir\Procmon.exe"

if (-not (Test-Path $ProcmonPath)) {
    Write-Host "[-] Procmon not found. Downloading securely from Sysinternals..." -ForegroundColor Yellow

    if (-not (Test-Path $ProcmonDir)) {
        New-Item -Path $ProcmonDir -ItemType Directory -Force | Out-Null
    }

    try {
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Procmon.exe"   -OutFile "$ProcmonDir\Procmon.exe"   -UseBasicParsing
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Procmon64.exe" -OutFile "$ProcmonDir\Procmon64.exe" -UseBasicParsing

        # Auto-accept Sysinternals EULA for the current user to prevent pop-ups during the lab
        $EulaKey = "HKCU:\Software\Sysinternals\Process Monitor"
        if (-not (Test-Path $EulaKey)) { New-Item -Path $EulaKey -Force | Out-Null }
        Set-ItemProperty -Path $EulaKey -Name "EulaAccepted" -Value 1 -Type DWord -Force | Out-Null

        Write-Host "[+] Procmon downloaded and configured at $ProcmonPath" -ForegroundColor Green
    } catch {
        Write-Host "[-] ERROR: Failed to download Procmon. $_" -ForegroundColor Red
    }
} else {
    Write-Host "[+] Procmon found." -ForegroundColor Green
}

# --- Process Explorer Check & Safe Install ---
# Placed under C:\Tools\ProcessExplorer\ to match the path referenced in the lab guide.
$ProcExpDir  = "C:\Tools\ProcessExplorer"
$ProcExpPath = "$ProcExpDir\procexp.exe"

if (-not (Test-Path $ProcExpPath)) {
    Write-Host "[-] Process Explorer not found. Downloading from Sysinternals..." -ForegroundColor Yellow

    if (-not (Test-Path $ProcExpDir)) {
        New-Item -Path $ProcExpDir -ItemType Directory -Force | Out-Null
    }

    try {
        Invoke-WebRequest -Uri "https://live.sysinternals.com/procexp.exe"   -OutFile "$ProcExpDir\procexp.exe"   -UseBasicParsing
        Invoke-WebRequest -Uri "https://live.sysinternals.com/procexp64.exe" -OutFile "$ProcExpDir\procexp64.exe" -UseBasicParsing

        $EulaKeyProcExp = "HKCU:\Software\Sysinternals\Process Explorer"
        if (-not (Test-Path $EulaKeyProcExp)) { New-Item -Path $EulaKeyProcExp -Force | Out-Null }
        Set-ItemProperty -Path $EulaKeyProcExp -Name "EulaAccepted" -Value 1 -Type DWord -Force | Out-Null

        Write-Host "[+] Process Explorer downloaded and configured at $ProcExpPath" -ForegroundColor Green
    } catch {
        Write-Host "[-] ERROR: Failed to download Process Explorer. $_" -ForegroundColor Red
    }
} else {
    Write-Host "[+] Process Explorer found." -ForegroundColor Green
}

Write-Host "`n[✓] Infrastructure setup is complete. Take a SNAPSHOT now!" -ForegroundColor Green
