#!/bin/bash

echo "[*] Starting Setup"

echo "[*] Installing Qt5 dependencies..."
sudo apt-get update -y
sudo apt-get install -y qtbase5-dev libqt5websockets5-dev qtdeclarative5-dev

echo "[*] Preparing system directories..."
sudo mkdir -p /home/ubuntu/BnB/Havoc
cd /home/ubuntu/BnB/Havoc

echo "[*] Downloading pre-compiled Havoc-Client framework"
sudo wget -O havoc-client.tar.gz "https://github.com/PadeanuVlad1501/lab_script_repo/raw/refs/heads/main/Havoc_lab/havoc-client.tar.gz"

echo "[*] Extracting resources."
sudo tar -xzvf havoc-client.tar.gz

echo "[*] Configurating permissions..."
sudo chmod +x Havoc

echo "[*] Fixing directory permissions..."
sudo chown -R ubuntu:ubuntu /home/ubuntu/BnB/Havoc

echo "[*] Creating global havoc command"
sudo ln -sf /home/ubuntu/BnB/Havoc/Havoc /usr/local/bin/havoc-client

sudo rm havoc-client.tar.gz

echo "================================================================"
echo "[+] Setup completed!"
echo "================================================================"
