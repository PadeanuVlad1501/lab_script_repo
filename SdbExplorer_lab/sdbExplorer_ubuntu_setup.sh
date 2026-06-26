#!/bin/bash
# =============================================================================
#  ubuntu_setup.sh — SdbExplorer Lab | Automated Staging Setup (v2.0)
# =============================================================================

set -euo pipefail

# Re-attach stdin to the terminal so 'sudo' can prompt for a password inside a "curl | bash" pipe
if [[ ! -t 0 ]] && [[ -c /dev/tty ]]; then
    exec < /dev/tty
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LAB_DIR="$HOME/BnB/SdbExplorer"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/SdbExplorer_lab"

echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}         SdbExplorer Lab — Automated Staging Setup (v2.0)       ${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}\n"

# 1. Install system dependencies
echo -e "${CYAN}[*] Updating package lists and installing dependencies (python3, mingw-w64)...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq python3 mingw-w64 curl wget > /dev/null
echo -e "${GREEN}[+] Dependencies successfully installed.${NC}\n"

# 2. Prepare staging directory
echo -e "${CYAN}[*] Creating lab staging directory at: ${BOLD}$LAB_DIR${NC}"
mkdir -p "$LAB_DIR"

# 3. Fetch C source & Compile 32-bit DLL
echo -e "${CYAN}[*] Fetching demo_payload.c from GitHub...${NC}"
curl -fSL "$GITHUB_RAW_BASE/demo_payload.c" -o "$LAB_DIR/demo_payload.c"

echo -e "${CYAN}[*] Compiling 32-bit benign payload (SysWOW64 target)...${NC}"
i686-w64-mingw32-gcc -shared -o "$LAB_DIR/demo.dll" "$LAB_DIR/demo_payload.c" -luser32 -lkernel32
rm "$LAB_DIR/demo_payload.c" # Remove source file to keep staging directory clean
echo -e "${GREEN}[+] demo.dll successfully compiled.${NC}\n"

# 4. Fetch sdb-explorer.exe
echo -e "${CYAN}[*] Downloading sdb-explorer.exe...${NC}"
# Try fetching latest release via GitHub API, fallback to your raw repo if API fails
SDB_EXP_URL=$(curl -sSL https://api.github.com/repos/evil-e/sdb-explorer/releases/latest | grep -o 'https://[^"]*sdb-explorer\.exe' | head -n 1 || true)

if [[ -z "$SDB_EXP_URL" ]]; then
    SDB_EXP_URL="$GITHUB_RAW_BASE/sdb-explorer.exe"
fi

if curl -fSL "$SDB_EXP_URL" -o "$LAB_DIR/sdb-explorer.exe"; then
    echo -e "${GREEN}[+] sdb-explorer.exe successfully placed.${NC}\n"
else
    echo -e "${RED}[-] Could not download sdb-explorer.exe. Please ensure it is uploaded to your GitHub repo.${NC}\n"
fi

# 5. Fetch patch.sdb
echo -e "${CYAN}[*] Downloading patch.sdb...${NC}"
if curl -fSL "$GITHUB_RAW_BASE/patch.sdb" -o "$LAB_DIR/patch.sdb"; then
    echo -e "${GREEN}[+] patch.sdb successfully placed.${NC}\n"
else
    echo -e "${RED}[!] CRITICAL ERROR: patch.sdb failed to download!${NC}"
    echo -e "${YELLOW}    Because .sdb files must be compiled on Windows via Compatibility Administrator,${NC}"
    echo -e "${YELLOW}    Linux cannot build it. Please generate it and push it to:${NC}"
    echo -e "    $GITHUB_RAW_BASE/patch.sdb\n"
fi

# Summary
echo -e "${BOLD}────────────────────────────────────────────────────────────────${NC}"
echo -e "${GREEN}${BOLD}[✓] Ubuntu Staging Environment Ready!${NC}"
echo -e "Directory contents of ${BOLD}$LAB_DIR${NC}:"
ls -lh "$LAB_DIR" | tail -n +2
echo -e "${BOLD}────────────────────────────────────────────────────────────────${NC}\n"
