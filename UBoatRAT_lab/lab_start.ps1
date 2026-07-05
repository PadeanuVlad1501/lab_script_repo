# ============================================================================
# Script: lab_start.ps1
# ============================================================================

Write-Host "=== Initializare Laborator UBoatRAT ===" -ForegroundColor Cyan

# 1. Preluarea IP-ului dinamic si DNS Spoofing
$UbuntuIP = Read-Host "Introdu adresa IP a VM-ului Ubuntu (ex: 10.10.164.199)"

if ($UbuntuIP -match "\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b") {
    $HostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $HostEntry = "$UbuntuIP c2-ubuntu.local"
    
    # Adaugam inregistrarea la finalul fisierului hosts
    Add-Content -Path $HostsFile -Value $HostEntry
    
    # Curatam cache-ul DNS pentru a garanta ca Windows-ul stie de noul domeniu imediat
    ipconfig /flushdns | Out-Null
    
    Write-Host "[+] DNS redirectionat temporar: c2-ubuntu.local -> $UbuntuIP" -ForegroundColor Green
} else {
    Write-Host "[-] Eroare: Nu ai introdus un IP valid. Ruleaza scriptul din nou." -ForegroundColor Red
    exit
}

# 2. Resetarea cozii BITS (Clean Baseline)
Write-Host "[*] Curatare stare BITS (Baseline)..." -ForegroundColor Cyan
$bitsReset = Start-Process -FilePath "bitsadmin.exe" -ArgumentList "/reset /allusers" -Wait -WindowStyle Hidden -PassThru
if ($bitsReset.ExitCode -eq 0) {
    Write-Host "[+] Coada BITS a fost resetata cu succes." -ForegroundColor Green
}

# 3. Activarea Auditing-ului
Write-Host "[*] Armare loguri de sistem..." -ForegroundColor Cyan

# Activam logul operational BITS
wevtutil sl Microsoft-Windows-Bits-Client/Operational /e:true
# Activam logarea crearii de procese
auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null

Write-Host "[+] Auditing activat (BITS Operational & Process Creation)." -ForegroundColor Green

Write-Host "`n[✓] Mediul este pregatit! Puteti incepe investigatia asupra WinSvcHelper.exe." -ForegroundColor Green
