# ============================================================================
# Script: uboatrat_windows_setup.ps1
# ============================================================================

$LabDir = "C:\Users\Administrators\Desktop\Labs\UBoatRAT"
$RepoBase = "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/main/UBoatRAT_lab"

Write-Host "[*] Incepere setup pentru laboratorul UBoatRAT..." -ForegroundColor Cyan

# 1. Crearea directorului de laborator
if (-not (Test-Path $LabDir)) {
    New-Item -Path $LabDir -ItemType Directory -Force | Out-Null
    Write-Host "[+] Directorul de laborator creat: $LabDir" -ForegroundColor Green
} else {
    Write-Host "[*] Directorul de laborator exista deja." -ForegroundColor Yellow
}

# 2. Descarcarea artefactelor din Git in directorul laboratorului
Write-Host "[*] Descarcare artefacte din Git..." -ForegroundColor Cyan
try {
    # Descarcam scriptul de start
    Invoke-WebRequest -Uri "$RepoBase/lab_start.ps1" -OutFile "$LabDir\lab_start.ps1" -UseBasicParsing
    
    # Descarcam emulatorul UBoatRAT in Lab Directory
    Invoke-WebRequest -Uri "$RepoBase/WinSvcHelper.exe" -OutFile "$LabDir\WinSvcHelper.exe" -UseBasicParsing
    
    Write-Host "[+] Fisiere descarcate cu succes in $LabDir" -ForegroundColor Green
} catch {
    Write-Host "[-] EROARE: Nu s-au putut descarca fisierele. Verifica link-urile din Git." -ForegroundColor Red
}

# 3. Verificarea tool-urilor necesare (Sanity Check)
Write-Host "[*] Verificare tool-uri necesare..." -ForegroundColor Cyan
$ProcmonPath = "C:\Tools\Procmon\Procmon.exe"
$WiresharkPath = "C:\Program Files\Wireshark\Wireshark.exe"

if (-not (Test-Path $ProcmonPath)) { 
    Write-Host "[!] Avertisment: Procmon nu a fost gasit la $ProcmonPath." -ForegroundColor Yellow 
} else {
    Write-Host "[+] Procmon gasit." -ForegroundColor Green
}

if (-not (Test-Path $WiresharkPath)) { 
    Write-Host "[!] Avertisment: Wireshark nu a fost gasit in locatia standard." -ForegroundColor Yellow 
} else {
    Write-Host "[+] Wireshark gasit." -ForegroundColor Green
}

Write-Host "`n[✓] Setup-ul de infrastructura este complet. Executati un SNAPSHOT acum!" -ForegroundColor Green
