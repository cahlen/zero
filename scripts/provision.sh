#!/bin/bash
# Zero - First Boot Provisioning Script
# Sets up WiFi AP mode and captive portal

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZERO_DIR="/opt/zero"
CONFIG_DIR="/etc/zero"
LOG_FILE="/var/log/zero-provision.log"

# Colors for console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() { log "[INFO] $1"; }
log_warn() { log "[WARN] $1"; }
log_error() { log "[ERROR] $1"; }

# Get MAC address suffix for unique AP name
get_mac_suffix() {
    cat /sys/class/net/wlan0/address | tr -d ':' | tail -c 5 | tr '[:lower:]' '[:upper:]'
}

# Check if WiFi is already configured
is_wifi_configured() {
    if nmcli -t -f NAME connection show | grep -qv "^Zero-Setup"; then
        # Has a non-setup connection
        if nmcli -t -f STATE general | grep -q "connected"; then
            return 0
        fi
    fi
    return 1
}

# Generate unique device ID
generate_device_id() {
    if [ ! -f "$CONFIG_DIR/device_id" ]; then
        # Use MAC address + random bytes for unique ID
        MAC=$(cat /sys/class/net/wlan0/address | tr -d ':')
        RAND=$(head -c 4 /dev/urandom | xxd -p)
        DEVICE_ID="${MAC}-${RAND}"
        echo "$DEVICE_ID" > "$CONFIG_DIR/device_id"
        log_info "Generated device ID: $DEVICE_ID"
    fi
    cat "$CONFIG_DIR/device_id"
}

# Configure NetworkManager hotspot
setup_ap_mode() {
    log_info "Setting up WiFi Access Point..."
    
    MAC_SUFFIX=$(get_mac_suffix)
    AP_SSID="Zero-Setup-${MAC_SUFFIX}"
    AP_PASS="zerowsetup"
    
    # Delete existing hotspot connection if exists
    nmcli connection delete "$AP_SSID" 2>/dev/null || true
    
    # Create hotspot
    nmcli device wifi hotspot \
        ifname wlan0 \
        ssid "$AP_SSID" \
        password "$AP_PASS"
    
    # Get the connection UUID
    HOTSPOT_UUID=$(nmcli -t -f UUID,NAME connection show | grep "$AP_SSID" | cut -d: -f1)
    
    # Configure hotspot to auto-start only when no other connection
    nmcli connection modify "$HOTSPOT_UUID" \
        connection.autoconnect yes \
        connection.autoconnect-priority -100 \
        ipv4.addresses 192.168.4.1/24 \
        ipv4.method shared
    
    log_info "AP configured: SSID=$AP_SSID, Password=$AP_PASS"
    
    # Save AP info for portal
    echo "AP_SSID=$AP_SSID" > "$CONFIG_DIR/ap.conf"
    echo "AP_PASS=$AP_PASS" >> "$CONFIG_DIR/ap.conf"
}

# Install Python dependencies for portal
install_dependencies() {
    log_info "Installing Python dependencies..."
    
    # Create virtual environment if not exists
    if [ ! -d "$ZERO_DIR/.venv" ]; then
        python3 -m venv "$ZERO_DIR/.venv"
    fi
    
    # Install requirements
    "$ZERO_DIR/.venv/bin/pip" install --upgrade pip
    "$ZERO_DIR/.venv/bin/pip" install flask python-dotenv requests
}

# Create systemd service for WiFi portal
create_portal_service() {
    log_info "Creating WiFi portal service..."
    
    cat > /etc/systemd/system/zero-wifi-portal.service << 'EOF'
[Unit]
Description=Zero WiFi Configuration Portal
After=network.target NetworkManager.service
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/zero/wifi-portal
Environment="PATH=/opt/zero/.venv/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/etc/zero/secrets.env
ExecStart=/opt/zero/.venv/bin/python app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zero-wifi-portal
    systemctl start zero-wifi-portal
}

# Create systemd service for web app
create_webapp_service() {
    log_info "Creating web application service..."
    
    cat > /etc/systemd/system/zero-webapp.service << 'EOF'
[Unit]
Description=Zero Web Application
After=network-online.target zero-wifi-portal.service
Wants=network-online.target
ConditionPathExists=/etc/zero/.wifi_configured

[Service]
Type=simple
User=root
WorkingDirectory=/opt/zero/web
Environment="PATH=/opt/zero/.venv/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=/etc/zero/secrets.env
ExecStart=/opt/zero/.venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zero-webapp
}

# Create systemd service for display app
create_display_service() {
    log_info "Creating display application service..."
    
    cat > /etc/systemd/system/zero-display.service << 'EOF'
[Unit]
Description=Zero Display Application
After=local-fs.target
ConditionPathExists=/etc/zero/.wifi_configured

[Service]
Type=simple
User=root
WorkingDirectory=/opt/zero/display
Environment="SDL_VIDEODRIVER=fbcon"
Environment="SDL_FBDEV=/dev/fb0"
EnvironmentFile=/etc/zero/secrets.env
ExecStart=/opt/zero/.venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zero-display
}

# Set correct permissions
set_permissions() {
    log_info "Setting permissions..."
    
    chmod 600 "$CONFIG_DIR/secrets.env"
    chmod 755 "$ZERO_DIR"
    chmod -R 755 "$ZERO_DIR/wifi-portal"
    chmod -R 755 "$ZERO_DIR/web"
    chmod -R 755 "$ZERO_DIR/display"
}

main() {
    log_info "======================================"
    log_info "   Zero Provisioning Starting"
    log_info "======================================"
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$ZERO_DIR"
    mkdir -p /var/log
    
    # Generate device ID
    generate_device_id
    
    # Check if already configured
    if is_wifi_configured; then
        log_info "WiFi already configured, skipping AP setup"
        touch "$CONFIG_DIR/.wifi_configured"
    else
        setup_ap_mode
    fi
    
    # Install dependencies
    install_dependencies
    
    # Create services
    create_portal_service
    create_webapp_service
    create_display_service
    
    # Set permissions
    set_permissions
    
    log_info "======================================"
    log_info "   Zero Provisioning Complete!"
    log_info "======================================"
}

main "$@"
