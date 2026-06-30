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

# Downloads pre-compiled official executable (v2.3) and renames it to shimgen.exe
wget -q https://github.com/jphilbert/shim_executable/releases/download/v2.3/shim_exec.exe -O shimgen.exe
wget -q ${REPO}/rcedit.exe
# Downloads strings.exe directly from Sysinternals (Licensing compliance)
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
