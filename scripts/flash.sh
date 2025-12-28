#!/bin/bash
# Zero - SD Card Flash Script
# Flashes Pi OS, installs ALL packages via chroot, configures hotspot
# NO INTERNET REQUIRED ON FIRST BOOT

set -e

DEVICE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

IMG_URL="https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2024-11-19/2024-11-19-raspios-bookworm-armhf-lite.img.xz"
IMG_FILE="/tmp/raspios-lite-bookworm.img.xz"
MOUNT_BOOT="/tmp/zero-boot"
MOUNT_ROOT="/tmp/zero-root"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

cleanup() {
    log_step "Cleaning up..."
    # Kill any running qemu processes
    pkill -f "qemu-arm-static" 2>/dev/null || true
    
    # Unmount in reverse order
    umount "$MOUNT_ROOT/proc" 2>/dev/null || true
    umount "$MOUNT_ROOT/sys" 2>/dev/null || true
    umount "$MOUNT_ROOT/dev/pts" 2>/dev/null || true
    umount "$MOUNT_ROOT/dev" 2>/dev/null || true
    umount "$MOUNT_ROOT/boot/firmware" 2>/dev/null || true
    umount "$MOUNT_BOOT" 2>/dev/null || true
    umount "$MOUNT_ROOT" 2>/dev/null || true
    rmdir "$MOUNT_BOOT" 2>/dev/null || true
    rmdir "$MOUNT_ROOT" 2>/dev/null || true
    
    # Remove qemu binary from rootfs
    rm -f "$MOUNT_ROOT/usr/bin/qemu-arm-static" 2>/dev/null || true
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Run as root: sudo $0 $*"
        exit 1
    fi
}

check_deps() {
    log_step "Checking dependencies..."
    
    # Check for qemu-user-static (needed for ARM chroot)
    if ! command -v qemu-arm-static &>/dev/null; then
        log_info "Installing qemu-user-static for ARM emulation..."
        apt-get update && apt-get install -y qemu-user-static binfmt-support
    fi
    
    # Ensure binfmt is set up
    if [ ! -f /proc/sys/fs/binfmt_misc/qemu-arm ]; then
        systemctl restart binfmt-support || update-binfmts --enable qemu-arm
    fi
}

check_device() {
    if [ -z "$DEVICE" ]; then
        echo "Usage: $0 <device>"
        echo "Example: $0 /dev/sdc"
        exit 1
    fi
    
    if [ ! -b "$DEVICE" ]; then
        log_error "Device $DEVICE not found"
        exit 1
    fi
    
    SIZE=$(lsblk -b -d -o SIZE -n "$DEVICE" 2>/dev/null || echo "0")
    SIZE_GB=$((SIZE / 1024 / 1024 / 1024))
    
    if [ "$SIZE_GB" -lt 4 ]; then
        log_error "Device too small (${SIZE_GB}GB). Need 4GB+"
        exit 1
    fi
    
    # Unmount any existing partitions
    umount "${DEVICE}"* 2>/dev/null || true
}

download_image() {
    log_step "Checking for Pi OS image..."
    if [ -f "$IMG_FILE" ]; then
        log_info "Using cached: $IMG_FILE"
    else
        log_info "Downloading Raspberry Pi OS Lite..."
        wget --progress=bar:force -O "$IMG_FILE" "$IMG_URL"
    fi
}

flash_image() {
    log_step "Flashing to $DEVICE..."
    xzcat "$IMG_FILE" | dd of="$DEVICE" bs=4M status=progress conv=fsync
    sync
    partprobe "$DEVICE" 2>/dev/null || true
    sleep 3
}

mount_partitions() {
    log_step "Mounting partitions..."
    
    if [[ "$DEVICE" == *"mmcblk"* ]] || [[ "$DEVICE" == *"nvme"* ]]; then
        BOOT_PART="${DEVICE}p1"
        ROOT_PART="${DEVICE}p2"
    else
        BOOT_PART="${DEVICE}1"
        ROOT_PART="${DEVICE}2"
    fi
    
    mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"
    mount "$ROOT_PART" "$MOUNT_ROOT"
    mount "$BOOT_PART" "$MOUNT_BOOT"
    
    # Mount boot inside root (Pi expects it at /boot/firmware)
    mkdir -p "$MOUNT_ROOT/boot/firmware"
    mount --bind "$MOUNT_BOOT" "$MOUNT_ROOT/boot/firmware"
}

setup_chroot() {
    log_step "Setting up ARM chroot environment..."
    
    # Copy qemu binary for ARM emulation
    cp /usr/bin/qemu-arm-static "$MOUNT_ROOT/usr/bin/"
    
    # Mount system directories for chroot
    mount --bind /dev "$MOUNT_ROOT/dev"
    mount --bind /dev/pts "$MOUNT_ROOT/dev/pts"
    mount --bind /proc "$MOUNT_ROOT/proc"
    mount --bind /sys "$MOUNT_ROOT/sys"
    
    # Copy DNS resolution
    cp /etc/resolv.conf "$MOUNT_ROOT/etc/resolv.conf"
}

run_in_chroot() {
    chroot "$MOUNT_ROOT" /usr/bin/qemu-arm-static /bin/bash -c "$1"
}

install_packages() {
    log_step "Installing packages in chroot (this takes a few minutes)..."
    
    run_in_chroot "apt-get update"
    
    # Install everything we need - NO DOWNLOADS ON BOOT
    run_in_chroot "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3-flask \
        python3-dotenv \
        python3-requests \
        network-manager"
    
    run_in_chroot "apt-get clean"
    
    log_info "Packages installed successfully"
}

configure_system() {
    log_step "Configuring system..."
    
    # Disable dhcpcd (conflicts with NetworkManager)
    run_in_chroot "systemctl disable dhcpcd 2>/dev/null || true"
    run_in_chroot "systemctl mask dhcpcd 2>/dev/null || true"
    
    # IMPORTANT: Keep wpa_supplicant ENABLED - NetworkManager needs it as WiFi backend!
    # Without wpa_supplicant, NetworkManager shows WiFi as "unavailable"
    run_in_chroot "systemctl enable wpa_supplicant"
    
    # Enable NetworkManager
    run_in_chroot "systemctl enable NetworkManager"
    
    # Create wpa_supplicant.conf with country code (CRITICAL for WiFi to work!)
    mkdir -p "$MOUNT_ROOT/etc/wpa_supplicant"
    cat > "$MOUNT_ROOT/etc/wpa_supplicant/wpa_supplicant.conf" << 'WPAEOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
WPAEOF
    
    # Also put it in boot partition (Pi copies it on first boot)
    cat > "$MOUNT_BOOT/wpa_supplicant.conf" << 'WPAEOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
WPAEOF
    
    # Set WiFi regulatory domain
    mkdir -p "$MOUNT_ROOT/etc/default"
    echo "REGDOMAIN=US" > "$MOUNT_ROOT/etc/default/crda"
    
    # Create proper password hash for user 'zero' with password 'zero'
    PASS_HASH=$(echo "zero" | openssl passwd -6 -stdin)
    
    # Enable SSH
    touch "$MOUNT_BOOT/ssh"
    
    # Set username/password via userconf.txt
    echo "zero:$PASS_HASH" > "$MOUNT_BOOT/userconf.txt"
    
    # Pre-configure NetworkManager hotspot profile
    mkdir -p "$MOUNT_ROOT/etc/NetworkManager/system-connections"
    cat > "$MOUNT_ROOT/etc/NetworkManager/system-connections/Zero-Hotspot.nmconnection" << 'NMEOF'
[connection]
id=Zero-Hotspot
type=wifi
autoconnect=false
interface-name=wlan0

[wifi]
mode=ap
ssid=Zero-Setup

[wifi-security]
key-mgmt=wpa-psk
psk=zerowsetup

[ipv4]
method=shared
address1=10.42.0.1/24

[ipv6]
method=ignore
NMEOF
    chmod 600 "$MOUNT_ROOT/etc/NetworkManager/system-connections/Zero-Hotspot.nmconnection"
    
    log_info "User 'zero' created with password 'zero'"
}

install_zero_apps() {
    log_step "Installing Zero applications..."
    
    # Create directories
    mkdir -p "$MOUNT_ROOT/opt/zero/wifi-portal/templates"
    mkdir -p "$MOUNT_ROOT/opt/zero/web/templates"
    mkdir -p "$MOUNT_ROOT/opt/zero/display"
    mkdir -p "$MOUNT_ROOT/opt/zero/scripts"
    mkdir -p "$MOUNT_ROOT/opt/zero/updates"
    mkdir -p "$MOUNT_ROOT/etc/zero"
    
    # Copy apps
    cp "$REPO_DIR/apps/wifi-portal/app.py" "$MOUNT_ROOT/opt/zero/wifi-portal/"
    cp "$REPO_DIR/apps/wifi-portal/templates/"* "$MOUNT_ROOT/opt/zero/wifi-portal/templates/"
    cp "$REPO_DIR/apps/web/app.py" "$MOUNT_ROOT/opt/zero/web/"
    cp "$REPO_DIR/apps/web/templates/"* "$MOUNT_ROOT/opt/zero/web/templates/"
    cp "$REPO_DIR/apps/display/app.py" "$MOUNT_ROOT/opt/zero/display/"
    
    # Copy update system
    cp "$REPO_DIR/VERSION" "$MOUNT_ROOT/opt/zero/"
    cp "$REPO_DIR/scripts/update.sh" "$MOUNT_ROOT/opt/zero/scripts/"
    chmod +x "$MOUNT_ROOT/opt/zero/scripts/update.sh"
    cp "$REPO_DIR/updates/manifest.json" "$MOUNT_ROOT/opt/zero/updates/"
    
    # Copy secrets template
    cp "$REPO_DIR/configs/secrets.env.example" "$MOUNT_ROOT/etc/zero/secrets.env"
    chmod 600 "$MOUNT_ROOT/etc/zero/secrets.env"
    
    # Copy systemd services (including updater timer)
    cp "$REPO_DIR/rootfs/etc/systemd/system/"*.service "$MOUNT_ROOT/etc/systemd/system/"
    cp "$REPO_DIR/rootfs/etc/systemd/system/"*.timer "$MOUNT_ROOT/etc/systemd/system/" 2>/dev/null || true
    
    # Generate unique device ID based on SD card
    DEVICE_ID=$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)
    echo "$DEVICE_ID" > "$MOUNT_ROOT/etc/zero/device-id"
    log_info "Device ID: $DEVICE_ID"
}

create_firstboot_service() {
    log_step "Creating first-boot service..."
    
    # This service runs ONCE on first boot - bulletproof hotspot setup
    cat > "$MOUNT_ROOT/opt/zero/firstboot.sh" << 'EOF'
#!/bin/bash
# Zero First Boot - WiFi Hotspot Setup

LOG="/var/log/zero-firstboot.log"
exec > >(tee -a "$LOG") 2>&1

echo "=========================================="
echo "Zero First Boot - $(date)"
echo "=========================================="

# Give the system time to fully boot (wpa_supplicant needs to start)
echo "Waiting 20 seconds for system to stabilize..."
sleep 20

# Step 1: Unblock WiFi
echo "[1] Unblocking WiFi..."
rfkill unblock wifi || true
rfkill unblock all || true
sleep 2
rfkill list

# Step 2: Set regulatory domain
echo "[2] Setting regulatory domain to US..."
iw reg set US || true

# Step 3: Bring up interface
echo "[3] Bringing up wlan0..."
ip link set wlan0 up || true
sleep 3

# Step 4: Enable WiFi in NetworkManager
echo "[4] Enabling WiFi radio..."
nmcli radio wifi on || true
sleep 5

# Show status
echo "Device status:"
nmcli device status
nmcli general

# Step 5: Generate SSID from MAC
echo "[5] Generating SSID..."
MAC_SUFFIX=$(cat /sys/class/net/wlan0/address 2>/dev/null | tr -d ':' | tail -c 5 | tr '[:lower:]' '[:upper:]')
[ -z "$MAC_SUFFIX" ] && MAC_SUFFIX="0000"
AP_SSID="Zero-Setup-${MAC_SUFFIX}"
AP_PASS="zerowsetup"
echo "SSID: $AP_SSID"

# Step 6: Create hotspot with retries
echo "[6] Creating hotspot..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    echo "Attempt $i of 15..."
    if nmcli device wifi hotspot ifname wlan0 ssid "$AP_SSID" password "$AP_PASS" 2>&1; then
        echo "SUCCESS!"
        break
    fi
    sleep 5
done

# Final status
echo "[7] Final status:"
nmcli device status
nmcli connection show --active

# Save configuration
echo "[8] Saving configuration..."
mkdir -p /etc/zero
cat > /etc/zero/ap.conf << APCONF
AP_SSID=$AP_SSID
AP_PASS=$AP_PASS
CREATED=$(date)
APCONF

touch /etc/zero/.firstboot_done

echo "=========================================="
echo "Zero Ready!"
echo "Connect to: $AP_SSID"
echo "Password: $AP_PASS"
echo "Portal: http://10.42.0.1"
echo "=========================================="
EOF
    chmod +x "$MOUNT_ROOT/opt/zero/firstboot.sh"
    
    # Systemd service for first boot
    cat > "$MOUNT_ROOT/etc/systemd/system/zero-firstboot.service" << 'EOF'
[Unit]
Description=Zero First Boot Setup
After=NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=!/etc/zero/.firstboot_done

[Service]
Type=oneshot
ExecStart=/opt/zero/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # WiFi Portal service (runs after firstboot)
    cat > "$MOUNT_ROOT/etc/systemd/system/zero-portal.service" << 'EOF'
[Unit]
Description=Zero WiFi Portal
After=zero-firstboot.service NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
WorkingDirectory=/opt/zero/wifi-portal
ExecStart=/usr/bin/python3 /opt/zero/wifi-portal/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable services
    run_in_chroot "systemctl enable zero-firstboot.service"
    run_in_chroot "systemctl enable zero-portal.service"
    
    # Enable OTA updater timer (will check daily for updates)
    run_in_chroot "systemctl enable zero-updater.timer"
}

print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Flash Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}What happens on boot:${NC}"
    echo "  1. Pi boots (~30 sec)"
    echo "  2. System stabilizes (~15 sec)"
    echo "  3. Hotspot starts: Zero-Setup-XXXX"
    echo "  4. Portal runs at http://10.42.0.1"
    echo ""
    echo -e "${CYAN}To set up:${NC}"
    echo "  1. Wait ~60 seconds after power on"
    echo "  2. Connect to Zero-Setup-XXXX (pass: zerowsetup)"
    echo "  3. Open http://10.42.0.1 in browser"
    echo "  4. Select your WiFi and enter password"
    echo ""
    echo -e "${CYAN}After WiFi configured:${NC}"
    echo "  ssh zero@zero.local (pass: zero)"
    echo ""
}

main() {
    echo ""
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}   Zero Flash Script${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo ""
    
    check_root
    check_device
    check_deps
    
    log_warn "This will ERASE $DEVICE"
    lsblk "$DEVICE"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    
    trap cleanup EXIT
    
    download_image
    flash_image
    mount_partitions
    setup_chroot
    install_packages
    configure_system
    install_zero_apps
    create_firstboot_service
    
    # Cleanup chroot mounts before final unmount
    umount "$MOUNT_ROOT/proc" 2>/dev/null || true
    umount "$MOUNT_ROOT/sys" 2>/dev/null || true
    umount "$MOUNT_ROOT/dev/pts" 2>/dev/null || true
    umount "$MOUNT_ROOT/dev" 2>/dev/null || true
    rm -f "$MOUNT_ROOT/usr/bin/qemu-arm-static"
    
    trap - EXIT
    
    umount "$MOUNT_ROOT/boot/firmware" 2>/dev/null || true
    umount "$MOUNT_BOOT" 2>/dev/null || true
    umount "$MOUNT_ROOT" 2>/dev/null || true
    sync
    
    print_summary
}

main "$@"
