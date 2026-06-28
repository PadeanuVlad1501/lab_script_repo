Write-Host "[*] Starting Windows setup for ShimGen Lab..." -ForegroundColor Cyan

# 1. Create the lab environment directories
$LabDir = "$env:USERPROFILE\Desktop\Labs\ShimGenLab"
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null

# 2. Install PuTTY silently (Required for the masquerading simulation)
Write-Host "[*] Installing PuTTY in the background..." -ForegroundColor Cyan
$PuttyMsi = "$env:TEMP\putty.msi"
$PuttyUrl = "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi"
Invoke-WebRequest -Uri $PuttyUrl -OutFile $PuttyMsi

# Run the MSI installer without UI and without rebooting
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $PuttyMsi /qn /norestart" -Wait -PassThru
Remove-Item $PuttyMsi -Force

if (Test-Path "C:\Program Files\PuTTY\putty.exe") {
    Write-Host "[+] PuTTY installed successfully!" -ForegroundColor Green
} else {
    Write-Host "[-] Error installing PuTTY. Please check your permissions." -ForegroundColor Red
}

# 3. Generate the Lab Start script
Write-Host "[*] Generating lab_start.ps1..." -ForegroundColor Cyan

$LabStartContent = @'
Write-Host "[*] Initializing ShimGen Lab..." -ForegroundColor Yellow

# A. Enable Process Creation auditing (Event ID 4688)
# This step is crucial for the Blue Team phase (Process Lineage Analysis)[cite: 2]
Write-Host "[*] Enabling Process Creation auditing (Event ID 4688)..." -ForegroundColor Yellow
auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null

# B. Configure Firewall rules
# Allow outbound traffic to the Ubuntu C2 server on port 8001
Write-Host "[*] Applying Firewall rules for Ubuntu C2 communication..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "ShimGen Lab - Allow Outbound 8001" -Direction Outbound -LocalPort Any -RemotePort 8001 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host "`n[✓] Lab is ready! Leave this terminal open and proceed with the guide." -ForegroundColor Green
'@

Set-Content -Path "$LabDir\lab_start.ps1" -Value $LabStartContent

Write-Host "[✓] Windows setup complete! The machine is now ready for a Snapshot." -ForegroundColor Green
