#!/bin/bash

echo "[*] Starting Ubuntu Setup for Leviathan Lab..."

# 1. Update and install core system dependencies (ADDED ncrack and 2to3)
echo "[*] Installing dependencies (Python3, git, ncrack, 2to3)..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv git ncrack 2to3

# 2. Create the main Lab Directory
echo "[*] Creating lab directory at ~/BnB/Leviathan..."
mkdir -p ~/BnB/Leviathan
cd ~/BnB/Leviathan

# 3. Download the C2 Flask Server
echo "[*] Downloading C2 Flask Server..."
wget -q -O c2_server.py "https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/Leviathan_lab/flask_server.py"

# 4. Clone the Leviathan Framework
echo "[*] Cloning Leviathan Framework..."
if [ ! -d "leviathan_framework" ]; then
    git clone https://github.com/utkusen/leviathan.git leviathan_framework
fi

# 5. Convert Python 2 code to Python 3 automatically
echo "[*] Patching Leviathan code to Python 3..."
2to3 -w -n leviathan_framework/ > /dev/null 2>&1

# 6. Create and configure the Virtual Environment (venv)
echo "[*] Setting up Python Virtual Environment..."
python3 -m venv venv

# Install ALL dependencies inside the isolated venv
echo "[*] Installing Flask and Leviathan dependencies inside venv..."
./venv/bin/pip install flask
./venv/bin/pip install -r leviathan_framework/requirements.txt

# Fix permissions
chmod -R 755 ~/BnB/Leviathan

echo "[+] Ubuntu setup is complete! Environment is ready."
