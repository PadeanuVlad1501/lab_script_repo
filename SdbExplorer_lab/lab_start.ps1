# =============================================================================
#  lab_start.ps1 — SdbExplorer Lab 
# =============================================================================

Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    SdbExplorer Lab                                             " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# 1. Verificare sistem 64-bit (Vital pentru SysWOW64 bypass)
Write-Host "[*] Verificare subsistem SysWOW64..." -ForegroundColor Yellow
$targetApp = "C:\Windows\SysWOW64\notepad.exe"
if (Test-Path $targetApp) {
    Write-Host "[+] OK: Arhitectura 64-bit confirmata." -ForegroundColor Green
} else {
    Write-Host "[-] EROARE CRITICA: SysWOW64\notepad.exe lipseste!" -ForegroundColor Red
    Exit
}

# 2. Creare Director Workspace
$LabDir = "$env:USERPROFILE\Desktop\Labs\SdbExplorerLab"
Write-Host "`n[*] Pregatire director de lucru..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Workspace gata la: $LabDir" -ForegroundColor Green

# 3. Regula chirurgicala de Firewall (Permite DOAR iesirea pe TCP 8001)
Write-Host "`n[*] Injectare regula stricta de Firewall (Outbound TCP 8001)..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "SdbLab_Allow_Staging" -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "SdbLab_Allow_Staging" `
                    -Direction Outbound `
                    -Protocol TCP `
                    -RemotePort 8001 `
                    -Action Allow `
                    -Profile Any `
                    -ErrorAction SilentlyContinue | Out-Null
Write-Host "[+] Traficul outbound pe portul 8001 a fost permis." -ForegroundColor Green

# 4. Excluziuni chirurgicale Windows Defender (Motorul AV ramane PORNIT)
Write-Host "`n[*] Configurare exceptii locale Antivirus..." -ForegroundColor Yellow
Add-MpPreference -ExclusionPath "C:\Users\Public" -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath "$env:TEMP" -ErrorAction SilentlyContinue
Write-Host "[+] Folderele Public si TEMP au fost adaugate in excepții." -ForegroundColor Green

Write-Host "`n────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "[✓] Mediul Windows a fost securizat si pregatit! Puteti incepe." -ForegroundColor Green
Write-Host "────────────────────────────────────────────────────────────────`n" -ForegroundColor DarkGray
