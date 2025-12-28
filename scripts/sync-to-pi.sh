#!/bin/bash
# Zero - Sync development changes to running Pi
# Usage: ./scripts/sync-to-pi.sh [pi-address]

set -e

PI_HOST="${1:-zero.local}"
PI_USER="zero"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Syncing to $PI_HOST...${NC}"

# Sync application files
echo "Syncing apps..."
rsync -avz --delete \
    "$REPO_DIR/apps/" \
    "$PI_USER@$PI_HOST:/opt/zero/"

# Sync config templates (not secrets!)
echo "Syncing configs..."
rsync -avz \
    "$REPO_DIR/configs/templates/" \
    "$PI_USER@$PI_HOST:/opt/zero/configs/"

# Sync scripts
echo "Syncing scripts..."
rsync -avz \
    "$REPO_DIR/scripts/provision.sh" \
    "$REPO_DIR/scripts/encrypt-secrets.sh" \
    "$PI_USER@$PI_HOST:/opt/zero/scripts/"

# Restart services
echo "Restarting services..."
ssh "$PI_USER@$PI_HOST" "sudo systemctl restart zero-wifi-portal zero-webapp zero-display 2>/dev/null || true"

echo -e "${GREEN}Sync complete!${NC}"
echo ""
echo "Services restarted. Check status with:"
echo "  ssh $PI_USER@$PI_HOST 'sudo systemctl status zero-*'"
