# =============================================================================
#  windows_setup.ps1 — SdbExplorer Lab | Master Staging & Provisioning (v2.0)
# =============================================================================
#  Run this ONCE as Administrator before taking the VM Snapshot.

Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "     SdbExplorer Lab — Windows Master Setup Script (v2.0)       " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Verify 64-bit Architecture (SysWOW64 requirement)
Write-Host "[*] Checking SysWOW64 subsystem support..." -ForegroundColor Yellow
$targetApp = "C:\Windows\SysWOW64\notepad.exe"
if (Test-Path $targetApp) {
    Write-Host "[+] SUCCESS: 32-bit SysWOW64\notepad.exe is present." -ForegroundColor Green
} else {
    Write-Host "[-] CRITICAL ERROR: SysWOW64\notepad.exe missing! Lab requires 64-bit Windows." -ForegroundColor Red
    Exit
}

# 2. Create Student Workspace Directory
$LabDir = "$env:USERPROFILE\Desktop\Labs\SdbExplorerLab"
Write-Host "`n[*] Creating Lab Directory at: $LabDir" -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Lab Directory successfully created." -ForegroundColor Green

# 3. Fetch lab_start.ps1 from GitHub and place it in the Lab Directory
$GitHubRawUrl = "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/SdbExplorer_lab/lab_start.ps1"
$LabStartDest = "$LabDir\lab_start.ps1"

Write-Host "`n[*] Downloading lab_start.ps1 into student workspace..." -ForegroundColor Yellow
try {
    # Force TLS 1.2 to avoid older PowerShell connection issues with GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $GitHubRawUrl -OutFile $LabStartDest -UseBasicParsing
    Write-Host "[+] SUCCESS: lab_start.ps1 placed in $LabDir" -ForegroundColor Green
} catch {
    Write-Host "[-] ERROR: Failed to download lab_start.ps1 from GitHub!" -ForegroundColor Red
    Write-Host "    Make sure 'lab_start.ps1' is committed and pushed to your repo." -ForegroundColor DarkYellow
    Write-Host "    Error details: $_" -ForegroundColor DarkGray
    Exit
}

# 4. Final Verification
Write-Host "`n────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if (Test-Path $LabStartDest) {
    Write-Host "[✓] Windows Master Staging Complete!" -ForegroundColor Green
    Write-Host "    You may now shut down this VM and create the student snapshot." -ForegroundColor White
} else {
    Write-Host "[!] Setup failed. Please check the errors above." -ForegroundColor Red
}
Write-Host "────────────────────────────────────────────────────────────────`n" -ForegroundColor DarkGray
