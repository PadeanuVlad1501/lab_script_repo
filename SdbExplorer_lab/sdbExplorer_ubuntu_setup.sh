#!/bin/bash
# =============================================================================
#  ubuntu_setup.sh  —  SdbExplorer Lab  |  One-time setup (v2.0 Benign DLL)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

LAB_DIR="$HOME/BnB/SdbExplorer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}   SdbExplorer Lab — Ubuntu One-Time Setup (v2.0 Benign)  ${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""

# 1. Verificare Python (pentru web server)
if ! command -v python3 &>/dev/null; then
    die "python3 nu este instalat. Rulează: sudo apt-get install -y python3"
fi
success "python3 găsit"

# 2. Verificare compilator MinGW 32-bit (pentru SysWOW64)
if ! command -v i686-w64-mingw32-gcc &>/dev/null; then
    warn "Compilatorul cross-platform 32-bit nu a fost găsit. Se instalează mingw-w64..."
    sudo apt-get update && sudo apt-get install -y mingw-w64
fi
success "Compilator i686-w64-mingw32-gcc disponibil"

# 3. Creare director laborator
info "Se pregătește directorul: $LAB_DIR"
mkdir -p "$LAB_DIR"

# 4. Generare / Copiere demo.dll
if [[ -f "$SCRIPT_DIR/demo_payload.c" ]]; then
    info "Se compilează demo.dll din demo_payload.c ..."
    i686-w64-mingw32-gcc -shared -o "$LAB_DIR/demo.dll" "$SCRIPT_DIR/demo_payload.c" -luser32 -lkernel32
    success "demo.dll compilat cu succes (Arhitectură: 32-bit)"
elif [[ -f "$SCRIPT_DIR/demo.dll" ]]; then
    cp "$SCRIPT_DIR/demo.dll" "$LAB_DIR/demo.dll"
    success "demo.dll copiat în directorul de laborator"
else
    die "Lipsă fișier sursă! Pune 'demo_payload.c' lângă acest script și re-rulează."
fi

# 5. Copiere patch.sdb
if [[ -f "$SCRIPT_DIR/patch.sdb" ]]; then
    cp "$SCRIPT_DIR/patch.sdb" "$LAB_DIR/patch.sdb"
    success "patch.sdb copiat"
else
    warn "patch.sdb lipsește din folderul scriptului! Laboratorul nu va funcționa fără el."
fi

# 6. Copiere sdb-explorer.exe
if [[ -f "$SCRIPT_DIR/sdb-explorer.exe" ]]; then
    cp "$SCRIPT_DIR/sdb-explorer.exe" "$LAB_DIR/sdb-explorer.exe"
    success "sdb-explorer.exe copiat"
else
    warn "sdb-explorer.exe lipsește din folderul scriptului!"
fi

echo ""
success "Setup finalizat. Studenții pot folosi 'lab_start.sh'."
