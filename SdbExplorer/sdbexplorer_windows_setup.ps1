# 1. Creating the cleanup/lab directory
# This path matches the one used in the lab documentation.
$LabDir = "$env:USERPROFILE\Desktop\Labs\SdbExplorerLab"
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null
Write-Host "[+] Lab directory successfully created at: $LabDir" -ForegroundColor Green

# 2. Checking Windows Defender status (Real-Time Protection)
# This ensures evil.dll is not quarantined upon download.
Write-Host "[*] Checking Windows Defender..." -ForegroundColor Cyan
$defenderStatus = Get-MpPreference
if ($defenderStatus.DisableRealtimeMonitoring -eq $true) {
    Write-Host "[+] SUCCESS: Windows Defender Real-Time Protection is DISABLED." -ForegroundColor Green
} else {
    Write-Host "[-] CRITICAL ERROR: Windows Defender is still active! Disable it via Group Policy or Registry before distributing the VM." -ForegroundColor Red
}

# 3. Checking Firewall rules (Outbound)
Write-Host "[*] Checking Outbound Firewall rules..." -ForegroundColor Cyan
$firewallProfiles = Get-NetFirewallProfile
$allOutboundAllowed = $true

foreach ($profile in $firewallProfiles) {
    if ($profile.Enabled -eq $true -and $profile.DefaultOutboundAction -ne "Allow") {
        Write-Host "[-] WARNING: The $($profile.Name) profile has restrictive Outbound rules ($($profile.DefaultOutboundAction))." -ForegroundColor Yellow
        $allOutboundAllowed = $false
    }
}

if ($allOutboundAllowed) {
    # Ports 8001 (HTTP) and 4444 (Reverse Shell) are required for the attack to succeed.
    Write-Host "[+] SUCCESS: All active Firewall profiles allow Outbound connections (Required for ports 8001 and 4444)." -ForegroundColor Green
} else {
    Write-Host "[-] ERROR: You must modify the Firewall to allow Outbound traffic, otherwise the reverse shell will fail." -ForegroundColor Red
}

Write-Host "`nWindows setup and validation completed!" -ForegroundColor White
