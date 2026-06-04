# 1. Instalarea serviciului OpenSSH (Nativ în Windows 11)
Write-Host "[*] Installing OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Pornirea și setarea serviciului să pornească automat
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "[+] Serviciul SSH rulează!"

# 3. Crearea userului vulnerabil (User Standard, NU Administrator)
Write-Host "[*] Creating 'victim' user with a weak password..."
$Password = ConvertTo-SecureString "Password123!" -AsPlainText -Force
# Creating User
New-LocalUser -Name "victim" -Password $Password -Description "Vulnerable User"
# (Opțional) Îl ascundem de pe ecranul de login de la Windows ca să fie mai stealth
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList" -Name "victim" -Value 0 -PropertyType DWord -Force

# 4. Securizarea (Izolarea) laboratorului prin Firewall
Write-Host "[*] Configurare Firewall pentru izolare..."

# a. Dezactivăm regula default care permite SSH de oriunde
Get-NetFirewallRule -DisplayName "OpenSSH SSH Server (sshd)" | Disable-NetFirewallRule

# b. Creăm o regulă restrictivă care permite SSH DOAR de la adresa de Ubuntu
# !!! ÎNLOCUIEȘTE IP-UL DE MAI JOS CU IP-UL VM-ULUI DE UBUNTU !!!
$UbuntuIP = "192.168.X.X" 

New-NetFirewallRule -DisplayName "CTF - Allow SSH strictly from Ubuntu" `
    -Direction Inbound `
    -LocalPort 22 `
    -Protocol TCP `
    -Action Allow `
    -RemoteAddress $UbuntuIP

Write-Host "[+] Setup complet! Mașina este vulnerabilă pe SSH doar pentru $UbuntuIP"
