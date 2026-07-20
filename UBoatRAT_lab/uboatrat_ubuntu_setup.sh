#!/usr/bin/env bash
# ============================================================================
# Script: uboatrat_ubuntu_setup.sh
# Purpose: Prepare the Ubuntu VM for the benign UBoatRAT laboratory
# ============================================================================

set -Eeuo pipefail

LAB_DIR="$HOME/BnB/UBoatRAT"
SERVER_PATH="$LAB_DIR/ubuntu_c2_server.py"

REPO_BASE="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/refs/heads/main/UBoatRAT_lab"
SERVER_URL="$REPO_BASE/ubuntu_c2_server.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

log_info() {
    echo -e "${CYAN}[*] $1${RESET}"
}

log_success() {
    echo -e "${GREEN}[+] $1${RESET}"
}

log_warning() {
    echo -e "${YELLOW}[!] $1${RESET}"
}

log_error() {
    echo -e "${RED}[-] $1${RESET}" >&2
}

cleanup_on_error() {
    local exit_code=$?

    log_error "Ubuntu setup failed with exit code $exit_code."
    log_error "The VM has not been prepared successfully."

    exit "$exit_code"
}

trap cleanup_on_error ERR

echo
echo "============================================================"
echo "       Benign UBoatRAT Laboratory — Ubuntu Setup"
echo "============================================================"
echo

# ---------------------------------------------------------------------------
# 1. Install required packages
# ---------------------------------------------------------------------------

log_info "Updating the APT package index..."

sudo apt-get update -y

log_info "Installing required packages..."

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    curl \
    tcpdump \
    tree \
    iproute2 \
    ca-certificates

log_success "Required packages are installed."

# ---------------------------------------------------------------------------
# 2. Create the laboratory directory structure
# ---------------------------------------------------------------------------

log_info "Creating the laboratory directory structure..."

mkdir -p \
    "$LAB_DIR/c2" \
    "$LAB_DIR/resolver" \
    "$LAB_DIR/logs" \
    "$LAB_DIR/captures"

log_success "Laboratory directory created at: $LAB_DIR"

# ---------------------------------------------------------------------------
# 3. Remove obsolete artefacts from the previous implementation
# ---------------------------------------------------------------------------

log_info "Removing obsolete files from the previous implementation..."

rm -rf "$LAB_DIR/uploads"

rm -f \
    "$LAB_DIR/c2/implant.dat" \
    "$LAB_DIR/c2/config.dat" \
    "$LAB_DIR/c2/beacon.dat" \
    "$LAB_DIR/c2/next_stage.dat"

log_success "Obsolete laboratory artefacts removed."

# ---------------------------------------------------------------------------
# 4. Download the benign Ubuntu server
# ---------------------------------------------------------------------------

log_info "Downloading ubuntu_c2_server.py from GitHub..."

TEMP_SERVER="$(mktemp)"

curl \
    --fail \
    --silent \
    --show-error \
    --location \
    "$SERVER_URL" \
    --output "$TEMP_SERVER"

if [[ ! -s "$TEMP_SERVER" ]]; then
    log_error "The downloaded server file is empty."
    rm -f "$TEMP_SERVER"
    exit 1
fi

install \
    -m 0755 \
    "$TEMP_SERVER" \
    "$SERVER_PATH"

rm -f "$TEMP_SERVER"

log_success "Server downloaded to: $SERVER_PATH"

# ---------------------------------------------------------------------------
# 5. Validate the Python source before taking the snapshot
# ---------------------------------------------------------------------------

log_info "Validating the Python server syntax..."

python3 -m py_compile "$SERVER_PATH"

# py_compile creates this directory; it is not needed in the snapshot.
rm -rf "$LAB_DIR/__pycache__"

log_success "Python syntax validation passed."

# ---------------------------------------------------------------------------
# 6. Verify that the server exposes its command-line interface
# ---------------------------------------------------------------------------

log_info "Checking the server command-line interface..."

python3 "$SERVER_PATH" --help >/dev/null

log_success "Server command-line validation passed."

# ---------------------------------------------------------------------------
# 7. Check whether the required ports are already occupied
# ---------------------------------------------------------------------------

log_info "Checking laboratory ports..."

PORT_CONFLICT=0

if ss -lnt | grep -qE '[:.]8080[[:space:]]'; then
    log_warning "TCP port 8080 is already in use."
    PORT_CONFLICT=1
else
    log_success "TCP port 8080 is available."
fi

if ss -lnt | grep -qE '[:.]9001[[:space:]]'; then
    log_warning "TCP port 9001 is already in use."
    PORT_CONFLICT=1
else
    log_success "TCP port 9001 is available."
fi

if [[ "$PORT_CONFLICT" -eq 1 ]]; then
    log_warning "Stop the conflicting service before starting the lab server."
fi

# ---------------------------------------------------------------------------
# 8. Display the available private IPv4 addresses
# ---------------------------------------------------------------------------

echo
log_info "Available non-loopback IPv4 addresses:"

ip -brief -4 address show scope global || true

echo
log_info "Current laboratory directory:"

tree -a "$LAB_DIR"

# ---------------------------------------------------------------------------
# 9. Final instructions
# ---------------------------------------------------------------------------

echo
echo "============================================================"
log_success "Ubuntu infrastructure setup completed successfully."
echo "============================================================"
echo
echo "The setup script did NOT:"
echo "  - start the laboratory server;"
echo "  - open firewall ports;"
echo "  - expose services to the Internet;"
echo "  - create a command-and-control channel."
echo
echo "Start the server during the laboratory with:"
echo
echo "  cd ~/BnB/UBoatRAT"
echo "  python3 ubuntu_c2_server.py"
echo
echo "If automatic IP detection selects the wrong interface:"
echo
echo "  python3 ubuntu_c2_server.py --advertise-ip <UBUNTU_PRIVATE_IP>"
echo
echo "Optional packet capture:"
echo
echo "  sudo tcpdump -ni any 'tcp port 8080 or tcp port 9001' \\"
echo "    -w ~/BnB/UBoatRAT/captures/uboatrat_lab.pcap"
echo
echo "Take the Ubuntu VM snapshot now."
echo
