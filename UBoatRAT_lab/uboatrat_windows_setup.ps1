# ============================================================================
# Script: uboatrat_windows_setup.ps1
# ============================================================================

$LabDir = "C:\Users\Administrator\Desktop\Labs\UBoatRAT"
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
try {
    # Download the start script
    Invoke-WebRequest -Uri "$RepoBase/lab_start.ps1" -OutFile "$LabDir\lab_start.ps1" -UseBasicParsing
    
    # Download the UBoatRAT emulator to the Lab Directory
    Invoke-WebRequest -Uri "$RepoBase/WinSvcHelper.exe" -OutFile "$LabDir\WinSvcHelper.exe" -UseBasicParsing
    
    Write-Host "[+] Files successfully downloaded to $LabDir" -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Could not download the files. Check the Git links." -ForegroundColor Red
}

# 3. Check for required tools and install if missing (Sanity Check & Auto-Install)
Write-Host "[*] Checking required tools..." -ForegroundColor Cyan

# --- Wireshark Check ---
$WiresharkPath = "C:\Program Files\Wireshark\Wireshark.exe"
if (-not (Test-Path $WiresharkPath)) { 
    Write-Host "[!] Warning: Wireshark was not found in the standard location." -ForegroundColor Yellow 
} else {
    Write-Host "[+] Wireshark found." -ForegroundColor Green
}

# --- Procmon Check & Safe Install ---
$ProcmonDir = "C:\Users\Administrator\Desktop\Labs\UBoatRAT"
$ProcmonPath = "$ProcmonDir\Procmon.exe"

if (-not (Test-Path $ProcmonPath)) { 
    Write-Host "[-] Procmon not found. Downloading securely from Sysinternals..." -ForegroundColor Yellow 
    
    if (-not (Test-Path $ProcmonDir)) {
        New-Item -Path $ProcmonDir -ItemType Directory -Force | Out-Null
    }

    try {
        # Direct download from Microsoft/Sysinternals Live
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Procmon.exe" -OutFile $ProcmonPath -UseBasicParsing
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Procmon64.exe" -OutFile "$ProcmonDir\Procmon64.exe" -UseBasicParsing
        
        # Auto-accept Sysinternals EULA for the current user to prevent pop-ups during the lab
        $EulaKey = "HKCU:\Software\Sysinternals\Process Monitor"
        if (-not (Test-Path $EulaKey)) {
            New-Item -Path $EulaKey -Force | Out-Null
        }
        Set-ItemProperty -Path $EulaKey -Name "EulaAccepted" -Value 1 -Type DWord -Force | Out-Null
        
        Write-Host "[+] Procmon successfully downloaded and configured at $ProcmonPath" -ForegroundColor Green
    } catch {
        Write-Host "[-] ERROR: Failed to download Procmon. Please check internet connectivity." -ForegroundColor Red
    }
} else {
    Write-Host "[+] Procmon found." -ForegroundColor Green
}

Write-Host "`n[✓] Infrastructure setup is complete. Take a SNAPSHOT now!" -ForegroundColor Green
