# =============================================================================
#  windows_setup.ps1 — SdbExplorer Lab | Endpoint Validation & Setup (v2.0)
# =============================================================================

$LabDir = "$env:USERPROFILE\Desktop\Labs\SdbExplorerLab"
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Lab directory ready at: $LabDir" -ForegroundColor Green

# 1. Verify WoW64 Subsystem (Crucial for the 32-bit notepad.exe attack vector)
Write-Host "`n[*] Checking WoW64 subsystem support..." -ForegroundColor Cyan
$targetApp = "C:\Windows\SysWOW64\notepad.exe"
if (Test-Path $targetApp) {
    Write-Host "[+] SUCCESS: 32-bit SysWOW64\notepad.exe is present." -ForegroundColor Green
} else {
    Write-Host "[-] CRITICAL ERROR: SysWOW64\notepad.exe not found! This lab requires a 64-bit Windows OS." -ForegroundColor Red
}

# 2. Check Windows Defender Status
Write-Host "`n[*] Checking Windows Defender status..." -ForegroundColor Cyan
$defenderStatus = Get-MpPreference
if ($defenderStatus.DisableRealtimeMonitoring -eq $true) {
    Write-Host "[+] SUCCESS: Windows Defender Real-Time Protection is DISABLED." -ForegroundColor Green
} else {
    Write-Host "[-] WARNING: Windows Defender Real-Time Protection is ACTIVE." -ForegroundColor Yellow
    Write-Host "    Even a benign DLL injected via sdbinst.exe can trigger LotL heuristics." -ForegroundColor DarkYellow
    Write-Host "    Recommendation: Disable Real-Time Protection before distributing the VM." -ForegroundColor DarkYellow
}

# 3. Check Outbound Firewall Rules (HTTP Port 8001)
Write-Host "`n[*] Checking Outbound Firewall profiles..." -ForegroundColor Cyan
$firewallProfiles = Get-NetFirewallProfile
$allOutboundAllowed = $true

foreach ($profile in $firewallProfiles) {
    if ($profile.Enabled -eq $true -and $profile.DefaultOutboundAction -ne "Allow") {
        Write-Host "[-] WARNING: Firewall profile '$($profile.Name)' restricts outbound connections." -ForegroundColor Yellow
        $allOutboundAllowed = $false
    }
}

if ($allOutboundAllowed) {
    Write-Host "[+] SUCCESS: Outbound traffic allowed (VM can reach Ubuntu staging server on port 8001)." -ForegroundColor Green
} else {
    Write-Host "[-] ERROR: Outbound traffic is blocked. Students will fail to download the payload." -ForegroundColor Red
}

Write-Host "`n[***] Windows VM validation finished!" -ForegroundColor White 
