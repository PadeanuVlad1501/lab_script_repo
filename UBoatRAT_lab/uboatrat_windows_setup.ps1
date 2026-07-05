# ============================================================================
# Script: uboatrat_windows_setup.ps1
# ============================================================================

$LabDir = "C:\Users\Administrators\Desktop\Labs\UBoatRAT"
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

# 3. Check for required tools (Sanity Check)
Write-Host "[*] Checking required tools..." -ForegroundColor Cyan
$ProcmonPath = "C:\Tools\Procmon\Procmon.exe"
$WiresharkPath = "C:\Program Files\Wireshark\Wireshark.exe"

if (-not (Test-Path $ProcmonPath)) { 
    Write-Host "[!] Warning: Procmon was not found at $ProcmonPath." -ForegroundColor Yellow 
} else {
    Write-Host "[+] Procmon found." -ForegroundColor Green
}

if (-not (Test-Path $WiresharkPath)) { 
    Write-Host "[!] Warning: Wireshark was not found in the standard location." -ForegroundColor Yellow 
} else {
    Write-Host "[+] Wireshark found." -ForegroundColor Green
}

Write-Host "`n[✓] Infrastructure setup is complete. Take a SNAPSHOT now!" -ForegroundColor Green
