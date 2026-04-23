#!/bin/bash

echo "[*] Starting Setup"

#  qt5 dependencies
echo "[*] Installing  Qt5 dependencies..."
sudo apt-get update -y
sudo apt-get install -y qtbase5-dev libqt5websockets5-dev qtdeclarative5-dev

# creating lab folder
echo "[*] Preparing system directories..."
sudo mkdir -p /opt/havoc-client
cd /opt/havoc-client

# havoc binary archive
echo "[*] Downloading pre-compiled Havoc-Client framework"
sudo wget -O havoc-client.tar.gz "https://github.com/PadeanuVlad1501/lab_script_repo/raw/refs/heads/main/Havoc_lab/havoc-client.tar.gz."

#  decompressing tar archive
echo "[*] Extracting resources."
sudo tar -xzvf havoc-client.tar.gz

# adding executable permission
echo "[*] Configurating permissions..."
sudo chmod +x Havoc

# creating symlink
echo "[*] Creating global havoc command"
sudo ln -sf /opt/havoc-client/Havoc /usr/local/bin/havoc-client

# cleanup
sudo rm havoc-client.tar.gz

echo "================================================================"
echo "[+] Setup completed!"
echo "================================================================"
