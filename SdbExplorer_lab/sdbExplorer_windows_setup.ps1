# =============================================================================
#  windows_setup.ps1 — SdbExplorer Lab | Endpoint Validation v2.0 (Benign)
# =============================================================================

$LabDir = "$env:USERPROFILE\Desktop\Labs\SdbExplorerLab"
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Directorul de lab creat la: $LabDir" -ForegroundColor Green

# 1. Verificare existență SysWOW64 (Vital pentru noul vector de atac)
Write-Host "`n[*] Se verifică suportul WoW64..." -ForegroundColor Cyan
$targetApp = "C:\Windows\SysWOW64\notepad.exe"
if (Test-Path $targetApp) {
    Write-Host "[+] SUCCES: 32-bit notepad.exe este prezent." -ForegroundColor Green
} else {
    Write-Host "[-] EROARE CRITICĂ: SysWOW64\notepad.exe lipsește! Lab-ul cere un Windows pe 64-bit." -ForegroundColor Red
}

# 2. Verificare Windows Defender 
# (Chiar și un DLL benign injectat prin sdbinst poate declanșa euristica LotL)
Write-Host "`n[*] Verificare status Windows Defender..." -ForegroundColor Cyan
$defenderStatus = Get-MpPreference
if ($defenderStatus.DisableRealtimeMonitoring -eq $true) {
    Write-Host "[+] SUCCES: Windows Defender Real-Time Protection este DEZACTIVAT." -ForegroundColor Green
} else {
    Write-Host "[-] AVERTISMENT: Windows Defender este activ. Ar putea bloca sdbinst.exe." -ForegroundColor Yellow
    Write-Host "    Recomandare: Dezactivați Real-Time protection din VM înainte de distribuire." -ForegroundColor DarkYellow
}

# 3. Verificare reguli Firewall Outbound (Doar port 8001/HTTP necesar acum)
Write-Host "`n[*] Verificare Firewall Outbound (pentru download-ul de pe Ubuntu)..." -ForegroundColor Cyan
$firewallProfiles = Get-NetFirewallProfile
$allOutboundAllowed = $true

foreach ($profile in $firewallProfiles) {
    if ($profile.Enabled -eq $true -and $profile.DefaultOutboundAction -ne "Allow") {
        Write-Host "[-] AVERTISMENT: Profilul '$($profile.Name)' blochează conexiunile outbound." -ForegroundColor Yellow
        $allOutboundAllowed = $false
    }
}

if ($allOutboundAllowed) {
    Write-Host "[+] SUCCES: Traficul Outbound este permis (Windows va putea contacta Ubuntu:8001)." -ForegroundColor Green
} else {
    Write-Host "[-] EROARE: Firewall-ul blochează ieșirea. Studenții nu vor putea descărca payload-ul." -ForegroundColor Red
}

Write-Host "`n[***] Validarea mașinii Windows a luat sfârșit!" -ForegroundColor White
