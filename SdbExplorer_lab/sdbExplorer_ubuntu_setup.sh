#!/bin/bash
# =============================================================================
#  ubuntu_setup.sh  —  SdbExplorer Lab  |  One-time setup
# =============================================================================
#  Run this ONCE before handing the lab to users.
#  It creates the lab directory, downloads/copies patch.sdb, and places
#  sdb-explorer.exe so the Python web server (Phase 2) can serve all three
#  files to the Windows VM.
#
#  What this script does NOT do:
#    - Generate evil.dll (IP-dependent; handled by lab_start.sh each session)
#    - Configure the Windows VM (handled separately by the Windows setup script)
#
#  After this script succeeds, ~/BnB/SdbExplorerLab will contain:
#    patch.sdb          Windows Shim Database — created via Windows ADK
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

# ─── patch.sdb ────────────────────────────────────────────────────────────────
# Option A: Seteaza URL-ul direct catre fisierul patch.sdb pre-compilat din ADK
PATCH_SDB_URL=""

# Option B: Daca URL-ul de mai sus e gol, pune fisierul patch.sdb in acelasi 
#           director cu acest script si va fi copiat automat.

# ─── sdb-explorer.exe ─────────────────────────────────────────────────────────
# Option A: Seteaza URL-ul direct catre sdb-explorer.exe
SDB_EXPLORER_URL=""

# Option B: Pune fisierul sdb-explorer.exe in acelasi director cu acest script.

# =============================================================================
#  STEP 0 — Preflight checks
# =============================================================================
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}   SdbExplorer Lab — Ubuntu Setup Script    ${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

info "Checking prerequisites..."

if ! command -v python3 &>/dev/null; then
    die "python3 is not installed. Run: sudo apt-get install -y python3"
fi
success "python3 found: $(python3 --version)"

if command -v msfvenom &>/dev/null; then
    success "msfvenom found (needed by lab_start.sh)"
else
    warn "msfvenom not found. Install Metasploit Framework before running lab_start.sh."
    warn "  sudo apt-get install -y metasploit-framework"
fi

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
#  STEP 2 — Setup patch.sdb
# =============================================================================
echo ""
info "Setting up patch.sdb..."

PATCH_SDB_DEST="$LAB_DIR/patch.sdb"

if [[ -n "$PATCH_SDB_URL" ]]; then
    info "Downloading from $PATCH_SDB_URL ..."
    wget -q --show-progress -O "$PATCH_SDB_DEST" "$PATCH_SDB_URL"
    success "patch.sdb downloaded"
elif [[ -f "$(dirname "$0")/patch.sdb" ]]; then
    cp "$(dirname "$0")/patch.sdb" "$PATCH_SDB_DEST"
    success "patch.sdb copied from script directory"
elif [[ -f "$PATCH_SDB_DEST" ]]; then
    success "patch.sdb already present — skipping"
else
    warn "patch.sdb not found. Do one of the following:"
    warn "  A) Set PATCH_SDB_URL at the top of this script, OR"
    warn "  B) Place patch.sdb in the same folder as ubuntu_setup.sh"
    warn ""
    warn "  (Remember: generate this file using Windows ADK Compatibility Administrator)"
    warn "Continuing without patch.sdb — lab WILL NOT work until added."
fi

# =============================================================================
#  STEP 3 — Place sdb-explorer.exe
# =============================================================================
echo ""
info "Setting up sdb-explorer.exe..."

SDB_EXPLORER_DEST="$LAB_DIR/sdb-explorer.exe"

if [[ -n "$SDB_EXPLORER_URL" ]]; then
    info "Downloading from $SDB_EXPLORER_URL ..."
    wget -q --show-progress -O "$SDB_EXPLORER_DEST" "$SDB_EXPLORER_URL"
    success "sdb-explorer.exe downloaded"
elif [[ -f "$(dirname "$0")/sdb-explorer.exe" ]]; then
    cp "$(dirname "$0")/sdb-explorer.exe" "$SDB_EXPLORER_DEST"
    success "sdb-explorer.exe copied from script directory"
elif [[ -f "$SDB_EXPLORER_DEST" ]]; then
    success "sdb-explorer.exe already present — skipping"
else
    warn "sdb-explorer.exe not found. Do one of the following:"
    warn "  A) Set SDB_EXPLORER_URL at the top of this script, OR"
    warn "  B) Place sdb-explorer.exe in the same folder as ubuntu_setup.sh"
    warn ""
    warn "  Suggested source: https://github.com/evil-e/sdb-explorer/releases"
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

ALL_OK=true
for f in patch.sdb sdb-explorer.exe; do
    if [[ -f "$LAB_DIR/$f" ]]; then
        success "$f  ✓"
    else
        warn    "$f  ✗  MISSING"
        ALL_OK=false
    fi
done

info "evil.dll  —  (generated per-session by lab_start.sh)"

echo ""
if [[ "$ALL_OK" == true ]]; then
    echo -e "${GREEN}${BOLD}Setup complete.${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. At the start of each lab session, run:  ${BOLD}./lab_start.sh${NC}"
else
    echo -e "${YELLOW}${BOLD}Setup finished with warnings — resolve missing files before using this lab.${NC}"
fi
echo ""
