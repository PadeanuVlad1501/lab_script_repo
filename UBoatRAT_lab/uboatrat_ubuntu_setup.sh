#!/bin/bash
# ============================================================================
# Script: uboatrat_ubuntu_setup.sh
# ============================================================================

LAB_DIR="$HOME/BnB/UBoatRAT"
REPO_BASE="https://raw.githubusercontent.com/PadeanuVlad1501/lab_script_repo/main/UBoatRAT_lab"

echo -e "\e[36m[*] Starting setup for the UBoatRAT lab on Ubuntu...\e[0m"

# 1. Create the isolated lab directories
mkdir -p "$LAB_DIR/c2"
mkdir -p "$LAB_DIR/uploads"
echo -e "\e[32m[+] Lab directories created at $LAB_DIR\e[0m"

# 2. Generate dummy C2 payload files (so you don't have to store them in Git)
echo -e "\e[36m[*] Generating dummy payload files...\e[0m"
echo "This is the simulated implant.dat file for T1197." > "$LAB_DIR/c2/implant.dat"
echo "This is the simulated config.dat file for T1197." > "$LAB_DIR/c2/config.dat"
echo "This is the simulated beacon.dat file for T1197." > "$LAB_DIR/c2/beacon.dat"
echo "This is the simulated next_stage.dat file for T1197." > "$LAB_DIR/c2/next_stage.dat"
echo -e "\e[32m[+] Dummy payload files successfully created in $LAB_DIR/c2/\e[0m"

# 3. Download the Python C2 server from Git
echo -e "\e[36m[*] Downloading the Python C2 server from Git...\e[0m"
wget -qO "$LAB_DIR/ubuntu_c2_server.py" "$REPO_BASE/ubuntu_c2_server.py"

if [ $? -eq 0 ]; then
    echo -e "\e[32m[+] ubuntu_c2_server.py successfully downloaded.\e[0m"
else
    echo -e "\e[31m[-] ERROR: Failed to download ubuntu_c2_server.py. Please verify the Git URL.\e[0m"
fi

# Ensure the python script is executable (optional but good practice)
chmod +x "$LAB_DIR/ubuntu_c2_server.py"

echo -e "\n\e[32m[✓] Infrastructure setup for Ubuntu is complete. Take a SNAPSHOT now!\e[0m"
