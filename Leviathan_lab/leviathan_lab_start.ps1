# ==============================================================================
# leviathan_lab_start.ps1
# The student runs this as Administrator to activate the vulnerable environment.
# ==============================================================================

Write-Host "[*] Initializing Leviathan Lab Environment..." -ForegroundColor Cyan

# 1. Install and Start OpenSSH Service
Write-Host "[*] Downloading and installing OpenSSH Server (This may take 1-3 minutes. Please wait...)" -ForegroundColor Yellow
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

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

# 3. Configure OpenSSH to remove Domain restrictions and limit to internal IPs
Write-Host "[*] Securing SSH access to internal subnets only..."
$SshConfig = "C:\ProgramData\ssh\sshd_config"
$Domain = $env:USERDOMAIN

if (Test-Path $SshConfig) {
    # Remove any restrictive AllowGroups policy
    (Get-Content $SshConfig) -replace '(?i)^AllowGroups.*', '#AllowGroups' | Set-Content $SshConfig
    
    # Add restriction to allow the victim account ONLY from internal NAT networks and localhost
    $SecureRule = "`nAllowUsers ${Domain}\victim@10.* ${Domain}\victim@172.* ${Domain}\victim@192.168.* ${Domain}\victim@127.0.0.1"
    Add-Content -Path $SshConfig -Value $SecureRule
    
    # Restart the service to apply changes immediately
    Restart-Service sshd
}

# Start the FTP Server in the background
Start-Process -FilePath "C:\Users\Administrator\Desktop\Labs\Leviathan\start_ftp.bat" -WindowStyle Hidden

# 4. Generate the sensitive file for the BITS exfiltration phase
Write-Host "[*] Staging sensitive data for exfiltration..."
$ExfilDir = "C:\Users\victim\Desktop\Labs\LeviathanLab"
if (!(Test-Path -Path $ExfilDir)) {
    New-Item -ItemType Directory -Path $ExfilDir -Force | Out-Null
}

@"
admin:Password123!
db_user:SuperSecretDBPass2026
root:LeviathanAPT40_hidden
"@ | Out-File -FilePath "$ExfilDir\passwords.txt" -Encoding utf8

Write-Host "`n[+] Environment is READY!" -ForegroundColor Green
Write-Host "================================================================"
Write-Host "[!] Exact SSH command to use from Ubuntu:" -ForegroundColor Yellow
Write-Host "ssh victim@${Domain}@<WINDOWS_IP>" -ForegroundColor Cyan
Write-Host "[!] Password: Password123!" -ForegroundColor Cyan
Write-Host "================================================================"
Write-Host "[!] Switch to your Ubuntu VM and use the Leviathan toolkit to gain initial access." -ForegroundColor Yellow
