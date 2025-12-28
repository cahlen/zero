#!/bin/bash
# Zero - Find Device on Network
# Scans local network for Zero devices

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Searching for Zero devices on the network..."
echo ""

# Method 1: mDNS/Avahi
echo -e "${GREEN}Checking mDNS (zero.local)...${NC}"
if ping -c 1 -W 2 zero.local &>/dev/null; then
    IP=$(getent hosts zero.local | awk '{ print $1 }')
    echo -e "  Found: ${GREEN}zero.local${NC} -> $IP"
else
    echo "  Not found via mDNS"
fi

echo ""

# Method 2: ARP scan (requires nmap or arp-scan)
echo -e "${GREEN}Scanning local network...${NC}"

# Get local network range
NETWORK=$(ip route | grep -v default | grep -E "^[0-9]" | head -1 | awk '{print $1}')

if command -v nmap &>/dev/null; then
    echo "  Using nmap to scan $NETWORK..."
    nmap -sn "$NETWORK" 2>/dev/null | grep -B 2 -i "raspberry\|zero" || echo "  No Raspberry Pi found via nmap"
elif command -v arp-scan &>/dev/null; then
    echo "  Using arp-scan..."
    sudo arp-scan --localnet 2>/dev/null | grep -i "raspberry" || echo "  No Raspberry Pi found via arp-scan"
else
    echo -e "  ${YELLOW}Install nmap or arp-scan for network scanning:${NC}"
    echo "    sudo apt install nmap"
    echo "    # or"
    echo "    sudo apt install arp-scan"
fi

echo ""

# Method 3: Check known Zero AP
echo -e "${GREEN}Checking for Zero setup hotspot...${NC}"
nmcli device wifi list 2>/dev/null | grep -i "Zero-Setup" || echo "  No Zero setup hotspot found"

echo ""
echo "======================================"
echo "To connect via SSH:"
echo "  ssh zero@zero.local"
echo "  # or"
echo "  ssh zero@<IP_ADDRESS>"
echo ""
echo "Default password: zero"
echo "======================================"
