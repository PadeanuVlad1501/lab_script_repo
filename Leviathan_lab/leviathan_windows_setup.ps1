# ==============================================================================
# leviathan_windows_setup.ps1
# ==============================================================================

Write-Host "[*] Preparing base image for Leviathan Lab..."

# Define the location of the activation script 
$LabDir = "C:\Users\Public\Desktop\Labs\Leviathan"

# Create the directory if it doesn't exist
if (!(Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
}

# 1. Install Python Silently
Write-Host "[*] Downloading and Installing Python (Silent mode)... This might take a minute."
$PythonInstaller = "$env:TEMP\python_installer.exe"
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" -OutFile $PythonInstaller
Start-Process -FilePath $PythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait

# 2. Refresh Environment Variables so 'pip' works immediately in this session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 3. Install pyftpdlib
Write-Host "[*] Installing pyftpdlib via pip..."
pip install pyftpdlib

# 4. Stage FTP Server Startup Script
Write-Host "[*] Staging FTP Server startup script..."
$FtpScript = "python -m pyftpdlib -p 21 -w -d `"C:\Users\victim\Desktop`" -u `"victim`" -P `"Password123!`""
Set-Content -Path "$LabDir\start_ftp.bat" -Value $FtpScript

# 5. Download the Activation Script
$ScriptUrl = "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/Leviathan_lab/leviathan_lab_start.ps1"
$OutPath = "$LabDir\leviathan_lab_start.ps1"

Write-Host "[*] Downloading activation script from repository..."
Invoke-WebRequest -Uri $ScriptUrl -OutFile $OutPath

Write-Host "[+] Lab setup complete!"
