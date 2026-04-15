#!/bin/bash

echo "[*] Updating system packages..."
sudo apt-get update -y

echo "[*] Installing prerequisites (curl, unzip, python3-venv, python3-pip)..."
sudo apt-get install curl unzip python3-venv python3-pip -y

echo "[*] Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/ # Curățăm fișierele de instalare

echo "[*] Creating lab directories in /home/ubuntu/BnB..."
mkdir -p /home/ubuntu/BnB/scoutsuite

echo "[*] Creating the Python Virtual Environment..."
cd /home/ubuntu/BnB/scoutsuite
python3 -m venv venv

echo "[*] Fixing permissions for the ubuntu user..."
sudo chown -R ubuntu:ubuntu /home/ubuntu/BnB/scoutsuite

echo "[+] Setup Complete! AWS CLI and the venv are ready."
aws --version
