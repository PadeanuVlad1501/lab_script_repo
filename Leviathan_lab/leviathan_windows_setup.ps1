# ==============================================================================
# leviathan_windows_setup.ps1
# ==============================================================================

Write-Host "[*] Preparing base image for Leviathan Lab..."

# Define the location where the student will find the activation script
$LabDir = "C:\Users\Administrator\Desktop\Labs\Leviathan"

# Create the directory if it doesn't exist
if (!(Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
}

# Download the Activation Script
$ScriptUrl = "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/Leviathan_lab/leviathan_lab_start.ps1"
$OutPath = "$LabDir\leviathan_windows_setup.ps1"

Write-Host "[*] Downloading activation script from repository..."
Invoke-WebRequest -Uri $ScriptUrl -OutFile $OutPath

Write-Host "[+] Lab setup complete !"
