#!/bin/bash

# =============================================================================
#  ubuntu_setup.sh  —  SdbExplorer Lab  |  One-time setup
# =============================================================================
#  Run this ONCE before handing the lab to users.
#  Creates ~/BnB/SdbExplorer/ with all files the Python web server needs
#  to serve to the Windows VM:
#
#    demo.dll          32-bit benign payload (popup + log file)
#    target.exe        32-bit Win32 target app  (replaces notepad.exe)
#    patch.sdb         Downloaded from Git (Created cleanly in Windows ADK)
#    sdb-explorer.exe  Forensic SDB parser (Windows executable)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Configuration ────────────────────────────────────────────────────────────
LAB_DIR="$HOME/BnB/SdbExplorer"

# Raw GitHub links to pull the pre-compiled, clean binaries:
PATCH_SDB_URL="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/SdbExplorer_lab/patch.sdb"
SDB_EXPLORER_URL="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/SdbExplorer_lab/sdb-explorer.exe"

# =============================================================================
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}   SdbExplorer Lab — Ubuntu Setup Script    ${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
#  STEP 0 — Prerequisites
# =============================================================================
info "Checking prerequisites..."

if ! command -v python3 &>/dev/null; then
    die "python3 not found. Run: sudo apt-get install -y python3"
fi
success "python3: $(python3 --version)"

# Install mingw-w64 if missing
if ! command -v i686-w64-mingw32-gcc &>/dev/null; then
    info "Installing mingw-w64 cross-compiler..."
    sudo apt-get update -qq && sudo apt-get install -y mingw-w64
fi
success "mingw-w64: $(i686-w64-mingw32-gcc --version | head -1)"

if ! command -v wget &>/dev/null; then
    sudo apt-get install -y wget
fi

# =============================================================================
#  STEP 1 — Create lab directory
# =============================================================================
echo ""
info "Creating lab directory: $LAB_DIR"
mkdir -p "$LAB_DIR"
success "Directory ready"

# =============================================================================
#  STEP 2 — Compile demo.dll  (32-bit benign payload)
# =============================================================================
echo ""
info "Compiling demo.dll (32-bit)..."

PAYLOAD_SRC=$(mktemp /tmp/demo_XXXXXX.c)
cat > "$PAYLOAD_SRC" << 'CSRC'
#include <windows.h>

#define LOG_PATH "C:\\Windows\\Temp\\shimmed.log"
#define LOG_MSG  "[SdbExplorer Lab] demo.dll injected via Application Shimming.\r\n"

static void write_log(void) {
    HANDLE h = CreateFileA(LOG_PATH, GENERIC_WRITE, FILE_SHARE_READ,
                           NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return;
    SetFilePointer(h, 0, NULL, FILE_END);
    DWORD w;
    WriteFile(h, LOG_MSG, (DWORD)(sizeof(LOG_MSG) - 1), &w, NULL);
    CloseHandle(h);
}

BOOL WINAPI DllMain(HINSTANCE hDLL, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hDLL);
        write_log();
        MessageBoxA(NULL,
            "Application Shimming Demo\n\n"
            "This popup was triggered by demo.dll,\n"
            "injected into target.exe by patch.sdb.\n\n"
            "Click OK, then check the Blue Team phase.",
            "SdbExplorer Lab \xE2\x80\x94 Shim Active",
            MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
    }
    return TRUE;
}
CSRC

i686-w64-mingw32-gcc -shared \
    -o "$LAB_DIR/demo.dll" \
    "$PAYLOAD_SRC" \
    -luser32 -lkernel32 \
    -Wl,--subsystem,windows

rm -f "$PAYLOAD_SRC"

if [[ -f "$LAB_DIR/demo.dll" ]]; then
    success "demo.dll compiled → $(du -h "$LAB_DIR/demo.dll" | cut -f1)"
else
    die "demo.dll compilation failed."
fi

# =============================================================================
#  STEP 3 — Compile target.exe  (32-bit Win32 target application)
# =============================================================================
echo ""
info "Compiling target.exe (32-bit)..."

TARGET_SRC=$(mktemp /tmp/target_XXXXXX.c)
cat > "$TARGET_SRC" << 'CSRC'
#include <windows.h>

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR cmdLine, int show) {
    MessageBoxA(NULL,
        "SdbExplorer Lab — Target Application\n\n"
        "If the demo.dll popup appeared BEFORE this box,\n"
        "the Application Shimming injection was successful.\n\n"
        "Leave this window open and switch to PowerShell\n"
        "for the Blue Team detection phase.",
        "SdbExplorer Lab \xE2\x80\x94 Target App",
        MB_OK | MB_ICONINFORMATION);
    return 0;
}
CSRC

i686-w64-mingw32-gcc \
    -o "$LAB_DIR/target.exe" \
    "$TARGET_SRC" \
    -luser32 \
    -mwindows

rm -f "$TARGET_SRC"

if [[ -f "$LAB_DIR/target.exe" ]]; then
    success "target.exe compiled → $(du -h "$LAB_DIR/target.exe" | cut -f1)"
else
    die "target.exe compilation failed."
fi

# =============================================================================
#  STEP 4 — Download VALID patch.sdb (Replacing broken Python generator)
# =============================================================================
echo ""
info "Downloading ADK-generated patch.sdb from Git..."
DEST_SDB="$LAB_DIR/patch.sdb"

if [[ -n "$PATCH_SDB_URL" ]]; then
    wget -q --show-progress -O "$DEST_SDB" "$PATCH_SDB_URL"
    success "patch.sdb downloaded securely."
else
    die "PATCH_SDB_URL is empty! Please set the raw GitHub link at the top."
fi

# =============================================================================
#  STEP 5 — Place sdb-explorer.exe
# =============================================================================
echo ""
info "Downloading sdb-explorer.exe from Git..."
DEST_EXP="$LAB_DIR/sdb-explorer.exe"

if [[ -n "$SDB_EXPLORER_URL" ]]; then
    wget -q --show-progress -O "$DEST_EXP" "$SDB_EXPLORER_URL"
    success "sdb-explorer.exe downloaded securely."
else
    warn "SDB_EXPLORER_URL is empty! Blue Team phase will lack the tool."
fi

# =============================================================================
#  STEP 6 — Final verification
# =============================================================================
echo ""
echo -e "${BOLD}────────────────────────────────────────────${NC}"
info "Lab directory contents:"
echo ""
ls -lh "$LAB_DIR" 2>/dev/null || true
echo ""

ALL_OK=true
for f in demo.dll target.exe patch.sdb sdb-explorer.exe; do
    if [[ -f "$LAB_DIR/$f" ]]; then
        success "$f  ✓"
    else
        warn    "$f  ✗  MISSING"
        ALL_OK=false
    fi
done

echo ""
if [[ "$ALL_OK" == true ]]; then
    echo -e "${GREEN}${BOLD}Setup complete. Run 'python3 -m http.server 8001' to serve files.${NC}"
else
    echo -e "${YELLOW}${BOLD}Setup finished with warnings — resolve missing files before deploying.${NC}"
fi
echo ""
