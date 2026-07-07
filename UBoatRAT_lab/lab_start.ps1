# ============================================================================
# Script: lab_start.ps1
# ============================================================================

Write-Host "=== UBoatRAT Lab Initialization ===" -ForegroundColor Cyan

# 1. Retrieve the dynamic IP and perform local DNS Spoofing
$UbuntuIP = Read-Host "Enter the IP address of the Ubuntu VM (e.g., 10.10.164.199)"

if ($UbuntuIP -match "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b") {
    $HostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $HostEntry = "$UbuntuIP c2-ubuntu.local"
    
    # Add the record to the end of the hosts file
    Add-Content -Path $HostsFile -Value $HostEntry
    
    # Flush the DNS cache to ensure Windows resolves the new domain immediately
    ipconfig /flushdns | Out-Null
    
    Write-Host "[+] DNS temporarily redirected: c2-ubuntu.local -> $UbuntuIP" -ForegroundColor Green
} else {
    Write-Host "[-] Error: You did not enter a valid IP address. Run the script again." -ForegroundColor Red
    exit
}

# 2. Reset the BITS queue (Clean Baseline)
Write-Host "[*] Cleaning BITS state (Baseline)..." -ForegroundColor Cyan
$bitsReset = Start-Process -FilePath "bitsadmin.exe" -ArgumentList "/reset /allusers" -Wait -WindowStyle Hidden -PassThru
if ($bitsReset.ExitCode -eq 0) {
    Write-Host "[+] BITS queue successfully reset." -ForegroundColor Green
}

# 3. Enable Auditing
Write-Host "[*] Arming system logs..." -ForegroundColor Cyan

# Enable BITS Operational log
wevtutil sl Microsoft-Windows-Bits-Client/Operational /e:true
# Enable Process Creation logging
auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null

Write-Host "[+] Auditing enabled (BITS Operational & Process Creation)." -ForegroundColor Green

# ASCII safe string for successful initialization
Write-Host "`n[+] The environment is ready! You can begin the investigation of WinSvcHelper.exe." -ForegroundColor Green
