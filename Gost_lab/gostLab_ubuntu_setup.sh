#!/bin/bash

echo "[*] Updating..."
sudo apt-get update -y

echo "[*] Installing unzip, python3, wget..."
sudo apt-get install -y unzip python3 wget

# Preparing Directory
TARGET_DIR="/home/ubuntu/BnB/GostLab"
echo "[*] Creating $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || exit

echo "[*] Preparing Gost for Linux..."
wget -q https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip -f gost-linux-amd64-2.11.5.gz
mv gost-linux-amd64-2.11.5 gost
chmod +x gost

# 5. Descarcare și extragere Gost pentru Windows (Payload)
echo "[*] Preparing gost for windows (payload for windows)..."
wget -q https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-windows-amd64-2.11.5.zip
unzip -j -o gost-windows-amd64-2.11.5.zip "gost-windows-amd64.exe" -d .
mv gost-windows-amd64.exe gost.exe
rm gost-windows-amd64-2.11.5.zip

echo "--------------------------------------------------"
echo "[+] SUCCESSFUL UBUNTU CONFIGURATION!"
echo "[+] Location: $TARGET_DIR"
echo "[+] Files ready: gost (Linux) & gost.exe (Windows)"
echo "--------------------------------------------------"
ls -F
