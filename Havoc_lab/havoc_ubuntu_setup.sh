#!/bin/bash

echo "[*] Starting Havoc C2 environment setup..."

# 1. Update
echo "[*] Updating apt..."
apt-get update -y

echo "[*] Installing minimal dependencies..."
apt-get install -y git golang cmake make gcc g++ nasm python3 python3-dev python3-websockets \
    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
    qt6-tools-dev qt6-tools-private-dev qt6-scxml-dev qt6-svg-dev qt6-websockets-dev \
    libqt6websockets6-dev libfontconfig1-dev libfreetype6-dev libx11-dev libxext-dev \
    libxfixes-dev libxi-dev libxrender-dev libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev \
    libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev libxcb-sync-dev libxcb-xfixes0-dev \
    libxcb-shape0-dev libxcb-randr0-dev libxcb-render-util0-dev libxcb-util-dev \
    libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev

echo "[*] Cleaning up apt cache to free disk space..."
apt-get clean

echo "[*] Creating directory structure in /home/ubuntu/BnB..."
mkdir -p /home/ubuntu/BnB
cd /home/ubuntu/BnB


if [ ! -d "Havoc" ]; then
    echo "[*] Cloning Havoc..."
    git clone --depth 1 https://github.com/HavocFramework/Havoc.git
else
    echo "[!] Havoc directory already exists. Skipping clone."
fi

echo "[*] Compiling components..."
cd Havoc

echo "[*] Building Teamserver..."
make ts-build

echo "[*] Building Client UI..."
make client-build

echo "[*] Cleaning Go build cache..."
go clean -cache -modcache

echo "[+] Done! Havoc is installed in /home/ubuntu/BnB/Havoc"
