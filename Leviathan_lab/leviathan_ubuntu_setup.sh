#!/bin/bash

echo "[*] Starting Ubuntu Setup for Leviathan Lab..."

# 1. Update and install core system dependencies 
echo "[*] Installing dependencies (Python3, Python2, virtualenv, git, ncrack, masscan)..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-pip python3-venv python2 virtualenv git ncrack masscan curl

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

# 5. Create and configure the Virtual Environments (venvflask & venvleviathan)
echo "[*] Setting up Python Virtual Environments..."

# 5.1 Crearea mediului pentru serverul Flask (Python 3)
echo "[*] Creating venvflask (Python 3)..."
python3 -m venv venvflask

# 5.2 Crearea mediului pentru Leviathan (Python 2)
echo "[*] Creating venvleviathan (Python 2)..."
virtualenv -p /usr/bin/python2 venvleviathan

# 6. Install dependencies inside the isolated venvs
echo "[*] Installing Flask inside venvflask..."
./venvflask/bin/pip install flask

echo "[*] Installing Leviathan dependencies inside venvleviathan..."
./venvleviathan/bin/pip install -r leviathan_framework/requirements.txt

# 7. Fix permissions
chmod -R 755 ~/BnB/Leviathan

echo "[+] Ubuntu setup is complete! Dual environments (Flask & Leviathan) are ready."
