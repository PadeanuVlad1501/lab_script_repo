#!/bin/bash

set -e

echo ""
echo "[+] Updating packages..."

sudo apt update

echo ""
echo "[+] Installing dependencies..."

sudo apt install -y \
python3 \
curl \
wget \
git \
tree

echo ""
echo "[+] Creating lab directory..."

mkdir -p ~/BnB/ShimGen

cd ~/BnB/ShimGen

REPO="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/main/ShimGen_lab"

echo ""
echo "[+] Downloading lab files..."

wget -q ${REPO}/shimgen.exe
wget -q ${REPO}/rcedit.exe
# Download strings.exe directly from Sysinternals (Licensing compliance)
wget -q https://live.sysinternals.com/strings.exe -O strings.exe
wget -q ${REPO}/payload.ps1
wget -q ${REPO}/putty.ico

chmod +x shimgen.exe || true
chmod +x rcedit.exe || true

echo ""
echo "[+] Current IP address:"

hostname -I

echo ""
echo "[✓] Ubuntu setup complete."
