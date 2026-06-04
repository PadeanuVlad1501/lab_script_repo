# ==============================================================================
# leviathan_lab_start.ps1
# The student runs this as Administrator to activate the vulnerable environment.
# ==============================================================================

Write-Host "[*] Initializing Leviathan Lab Environment..." -ForegroundColor Cyan

# 1. Install and Start OpenSSH Service
Write-Host "[*] Downloading and installing OpenSSH Server (This may take 1-3 minutes. Please wait...)" -ForegroundColor Yellow
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Write-Host "[*] Starting SSH service..."
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# 2. Create the vulnerable standard user ('victim')
Write-Host "[*] Provisioning target accounts..."
$Password = ConvertTo-SecureString "Password123!" -AsPlainText -Force

# Suppress errors if the user already exists
$ErrorActionPreference = "SilentlyContinue"
New-LocalUser -Name "victim" -Password $Password -Description "Vulnerable User"
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList" -Name "victim" -Value 0 -PropertyType DWord -Force
$ErrorActionPreference = "Continue"

# 3. Generate the sensitive file for the BITS exfiltration phase
Write-Host "[*] Staging sensitive data for exfiltration..."
$LabDir = "C:\Users\victim\Desktop\Labs\LeviathanLab"
if (!(Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
}

@"
admin:Password123!
db_user:SuperSecretDBPass2026
root:LeviathanAPT40_hidden
"@ | Out-File -FilePath "$LabDir\passwords.txt" -Encoding utf8

Write-Host "`n[+] Environment is READY!" -ForegroundColor Green
Write-Host "[!] Switch to your Ubuntu VM and use the Leviathan toolkit to gain initial access." -ForegroundColor Yellow
