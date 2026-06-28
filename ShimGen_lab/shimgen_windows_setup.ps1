# ==========================================
# ShimGen Lab - Windows Setup
# ==========================================

$ErrorActionPreference = "Stop"

# -------------------------------
# Verify Administrator
# -------------------------------

if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host ""
    Write-Host "[-] Please run this script as Administrator." -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "[+] Starting ShimGen Lab setup..." -ForegroundColor Cyan

# -------------------------------
# Create directories
# -------------------------------

$LabDir = "$env:USERPROFILE\Desktop\Labs\ShimGenLab"

New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Desktop\Labs" | Out-Null
New-Item -ItemType Directory -Force -Path $LabDir | Out-Null

# -------------------------------
# Download lab_start.ps1
# -------------------------------

Write-Host "[+] Downloading lab_start.ps1..."

Invoke-WebRequest `
"https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/main/ShimGen_lab/lab_start.ps1" `
-OutFile "$LabDir\lab_start.ps1"

# -------------------------------
# Configure PowerShell
# -------------------------------

Write-Host "[+] Configuring Execution Policy..."

Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# -------------------------------
# Enable Process Creation Auditing
# -------------------------------

Write-Host "[+] Enabling Process Creation auditing..."

auditpol /set /subcategory:"Process Creation" /success:enable | Out-Null

# -------------------------------
# Install PuTTY
# -------------------------------

if (!(Test-Path "C:\Program Files\PuTTY\putty.exe"))
{
    Write-Host "[+] Installing PuTTY..."

    winget install `
        --id PuTTY.PuTTY `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements
}
else
{
    Write-Host "[+] PuTTY already installed."
}

# -------------------------------
# Verify
# -------------------------------

if (Test-Path "C:\Program Files\PuTTY\putty.exe")
{
    Write-Host "[+] PuTTY OK"
}
else
{
    Write-Host "[-] PuTTY installation failed." -ForegroundColor Red
}

Write-Host ""
Write-Host "[✓] Windows setup complete." -ForegroundColor Green
