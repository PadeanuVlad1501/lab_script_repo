# =============================================================================
#  lab_start.ps1 — ShimgenLab
# =============================================================================

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                       Shimgen Lab Start                        " -ForegroundColor Cyan
Write-Host "================================================================`n" -ForegroundColor Cyan

# 1. Verify 64-bit OS (Crucial for SysWOW64 bypass vector)
Write-Host "[*] Verifying SysWOW64 subsystem..." -ForegroundColor Yellow
$targetApp = "C:\Windows\SysWOW64\notepad.exe"
if (Test-Path $targetApp) {
    Write-Host "[+] OK: 64-bit architecture confirmed." -ForegroundColor Green
} else {
    Write-Host "[-] CRITICAL ERROR: SysWOW64\notepad.exe missing! Lab requires 64-bit Windows." -ForegroundColor Red
    Exit
}

# 2. Create Workspace Directory
$LabDir = "$env:USERPROFILE\Desktop\Labs\ShimGenLab"
Write-Host "`n[*] Preparing workspace directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Workspace ready at: $LabDir" -ForegroundColor Green

# 3. Surgical Firewall Rule (Allow outbound ONLY to TCP port 8001)
Write-Host "`n[*] Injecting Firewall rule (Outbound TCP 8001)..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "SdbLab_Allow_Staging" -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "SdbLab_Allow_Staging" `
                    -Direction Outbound `
                    -Protocol TCP `
                    -RemotePort 8001 `
                    -Action Allow `
                    -Profile Any `
                    -ErrorAction SilentlyContinue | Out-Null
Write-Host "[+] Outbound traffic on TCP port 8001 allowed." -ForegroundColor Green

# 4. Antivirus Exclusions (AV Engine stays ON)
Write-Host "`n[*] Configuring local Antivirus exclusions..." -ForegroundColor Yellow
Add-MpPreference -ExclusionPath "C:\Users\Public" -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue
Write-Host "[+] Public and TEMP folders added to exclusions." -ForegroundColor Green

Write-Host "`n----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "[OK] Windows environment successfully secured and prepared!" -ForegroundColor Green
Write-Host "----------------------------------------------------------------`n" -ForegroundColor DarkGray
