# ==============================================================================
# leviathan_windows_setup.ps1
# ==============================================================================

Write-Host "[*] Preparing base image for Leviathan Lab..."

# Define the location where the student will find the activation script
$LabDir = "C:\Users\Public\Desktop\Labs\Leviathan"

# Create the directory if it doesn't exist
if (!(Test-Path -Path $LabDir)) {
    New-Item -ItemType Directory -Path $LabDir -Force | Out-Null
}

# Download the Activation Script from your personal repository
# !!! REPLACE THE URL BELOW WITH YOUR ACTUAL RAW GITHUB URL !!!
$ScriptUrl = "YOUR_RAW_GITHUB_URL_HERE"
$OutPath = "$LabDir\Start_Leviathan_Lab.ps1"

Write-Host "[*] Downloading activation script from repository..."
Invoke-WebRequest -Uri $ScriptUrl -OutFile $OutPath

Write-Host "[+] Base setup complete. The VM can now be snapshotted."
