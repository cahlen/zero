#!/bin/bash
# Zero OTA Update System
# Checks GitHub releases and applies updates

set -e

REPO_OWNER="cahlen"
REPO_NAME="zero"
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
INSTALL_DIR="/opt/zero"
BACKUP_DIR="/opt/zero-backup"
VERSION_FILE="${INSTALL_DIR}/VERSION"
LOG_FILE="/var/log/zero-update.log"

# Colors (for interactive use)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_current_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" | tr -d '[:space:]'
    else
        echo "0.0.0"
    fi
}

version_gt() {
    # Returns 0 if $1 > $2
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$1" ]
}

check_update() {
    log "Checking for updates..."
    
    CURRENT=$(get_current_version)
    log "Current version: $CURRENT"
    
    # Get latest release from GitHub
    RELEASE_INFO=$(curl -s "$GITHUB_API" 2>/dev/null)
    
    if [ -z "$RELEASE_INFO" ] || echo "$RELEASE_INFO" | grep -q "Not Found"; then
        log "Could not fetch release info from GitHub"
        return 1
    fi
    
    LATEST=$(echo "$RELEASE_INFO" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 | tr -d 'v')
    
    if [ -z "$LATEST" ]; then
        log "Could not parse latest version"
        return 1
    fi
    
    log "Latest version: $LATEST"
    
    if version_gt "$LATEST" "$CURRENT"; then
        echo "$LATEST"
        return 0
    else
        log "Already up to date"
        return 1
    fi
}

download_update() {
    VERSION=$1
    DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}/zero-${VERSION}.tar.gz"
    TEMP_DIR=$(mktemp -d)
    
    log "Downloading v${VERSION} from $DOWNLOAD_URL"
    
    if ! curl -L -o "${TEMP_DIR}/update.tar.gz" "$DOWNLOAD_URL" 2>/dev/null; then
        log "Download failed"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Verify download
    if [ ! -s "${TEMP_DIR}/update.tar.gz" ]; then
        log "Downloaded file is empty"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    echo "$TEMP_DIR"
}

backup_current() {
    log "Backing up current installation..."
    
    rm -rf "$BACKUP_DIR"
    
    if [ -d "$INSTALL_DIR" ]; then
        cp -a "$INSTALL_DIR" "$BACKUP_DIR"
        log "Backup created at $BACKUP_DIR"
    fi
}

apply_update() {
    TEMP_DIR=$1
    
    log "Applying update..."
    
    # Extract to temp location first
    EXTRACT_DIR="${TEMP_DIR}/extracted"
    mkdir -p "$EXTRACT_DIR"
    
    if ! tar -xzf "${TEMP_DIR}/update.tar.gz" -C "$EXTRACT_DIR"; then
        log "Failed to extract update"
        return 1
    fi
    
    # Copy new files
    if [ -d "${EXTRACT_DIR}/apps" ]; then
        cp -r "${EXTRACT_DIR}/apps/"* "${INSTALL_DIR}/apps/"
    fi
    
    if [ -f "${EXTRACT_DIR}/VERSION" ]; then
        cp "${EXTRACT_DIR}/VERSION" "${INSTALL_DIR}/VERSION"
    fi
    
    if [ -d "${EXTRACT_DIR}/scripts" ]; then
        cp -r "${EXTRACT_DIR}/scripts/"* "${INSTALL_DIR}/scripts/"
        chmod +x "${INSTALL_DIR}/scripts/"*.sh
    fi
    
    # Read manifest and restart affected services
    if [ -f "${EXTRACT_DIR}/updates/manifest.json" ]; then
        cp "${EXTRACT_DIR}/updates/manifest.json" "${INSTALL_DIR}/updates/"
        
        # Restart services
        for svc in zero-wifi-portal zero-webapp zero-display; do
            if systemctl is-active --quiet "$svc"; then
                log "Restarting $svc..."
                systemctl restart "$svc" || true
            fi
        done
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    log "Update applied successfully"
}

rollback() {
    log "Rolling back to previous version..."
    
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        
        # Restart services
        for svc in zero-wifi-portal zero-webapp zero-display; do
            systemctl restart "$svc" 2>/dev/null || true
        done
        
        log "Rollback completed"
    else
        log "No backup found, cannot rollback"
        return 1
    fi
}

show_status() {
    CURRENT=$(get_current_version)
    echo "Zero Update Status"
    echo "=================="
    echo "Installed version: $CURRENT"
    echo "Install directory: $INSTALL_DIR"
    echo "Backup directory:  $BACKUP_DIR"
    echo ""
    echo "Services:"
    for svc in zero-wifi-portal zero-webapp zero-display zero-provision; do
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not installed")
        echo "  $svc: $STATUS"
    done
}

do_update() {
    FORCE=${1:-false}
    
    # Check for new version
    NEW_VERSION=$(check_update) || {
        if [ "$FORCE" != "true" ]; then
            exit 0
        fi
    }
    
    if [ -z "$NEW_VERSION" ] && [ "$FORCE" != "true" ]; then
        log "No update available"
        exit 0
    fi
    
    # Use current version if forcing
    [ -z "$NEW_VERSION" ] && NEW_VERSION=$(get_current_version)
    
    # Backup current
    backup_current
    
    # Download update
    TEMP_DIR=$(download_update "$NEW_VERSION") || {
        log "Update download failed"
        exit 1
    }
    
    # Apply update
    if ! apply_update "$TEMP_DIR"; then
        log "Update failed, rolling back..."
        rollback
        exit 1
    fi
    
    log "Successfully updated to v${NEW_VERSION}"
    
    # Report back (optional - could POST to a status endpoint)
    DEVICE_ID=$(cat /etc/machine-id 2>/dev/null || hostname)
    log "Device $DEVICE_ID updated to v${NEW_VERSION}"
}

# Main
case "${1:-check}" in
    check)
        NEW=$(check_update) && echo "Update available: v$NEW" || echo "Up to date"
        ;;
    update)
        do_update false
        ;;
    force-update)
        do_update true
        ;;
    rollback)
        rollback
        ;;
    status)
        show_status
        ;;
    version)
        get_current_version
        ;;
    *)
        echo "Zero OTA Update System"
        echo ""
        echo "Usage: $0 {check|update|force-update|rollback|status|version}"
        echo ""
        echo "Commands:"
        echo "  check        - Check if update is available"
        echo "  update       - Download and apply update if available"
        echo "  force-update - Re-download and apply current version"
        echo "  rollback     - Revert to previous version"
        echo "  status       - Show current status"
        echo "  version      - Print current version"
        ;;
esac
