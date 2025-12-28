#!/bin/bash
# Zero - QEMU Emulator for local testing
# Boots the Pi image in QEMU for development without needing real hardware
#
# NOTE: WiFi/hotspot can't be tested in emulation (no hardware)
# But you CAN test: boot process, services, Flask apps, file structure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$REPO_DIR/.qemu"
IMG_FILE="/tmp/raspios-lite-bookworm.img.xz"
QEMU_IMG="$WORK_DIR/pi-zero.img"
KERNEL="$WORK_DIR/kernel-qemu-5.10.63-bullseye"
DTB="$WORK_DIR/versatile-pb-bullseye-5.10.63.dtb"

# Download kernel/DTB for QEMU (Pi can't be directly emulated, need these)
KERNEL_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel-qemu-5.10.63-bullseye"
DTB_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/versatile-pb-bullseye-5.10.63.dtb"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Download kernel/DTB and prepare image (first time)"
    echo "  boot      - Boot the emulated Pi"
    echo "  ssh       - SSH into running emulator (port 5022)"
    echo "  clean     - Remove emulator files"
    echo ""
    echo "First run: $0 setup && $0 boot"
}

setup() {
    log_step "Setting up QEMU environment..."
    mkdir -p "$WORK_DIR"
    
    # Download QEMU-compatible kernel
    if [ ! -f "$KERNEL" ]; then
        log_info "Downloading QEMU kernel..."
        wget -O "$KERNEL" "$KERNEL_URL"
    fi
    
    # Download DTB
    if [ ! -f "$DTB" ]; then
        log_info "Downloading DTB..."
        wget -O "$DTB" "$DTB_URL"
    fi
    
    # Check for Pi OS image
    if [ ! -f "$IMG_FILE" ]; then
        log_warn "Pi OS image not found at $IMG_FILE"
        log_info "Run flash.sh first to download it, or download manually"
        exit 1
    fi
    
    # Create a copy of the image for QEMU (don't modify original)
    if [ ! -f "$QEMU_IMG" ]; then
        log_info "Extracting Pi OS image for QEMU..."
        xzcat "$IMG_FILE" > "$QEMU_IMG"
        
        # Resize image to 4GB for more space
        log_info "Resizing image to 4GB..."
        qemu-img resize "$QEMU_IMG" 4G
    fi
    
    # Mount and configure for QEMU boot
    log_step "Configuring image for QEMU..."
    
    LOOP=$(sudo losetup -fP --show "$QEMU_IMG")
    sudo mkdir -p /tmp/qemu-boot /tmp/qemu-root
    sudo mount "${LOOP}p1" /tmp/qemu-boot
    sudo mount "${LOOP}p2" /tmp/qemu-root
    
    # Fix cmdline.txt for QEMU
    echo "console=ttyAMA0 root=/dev/sda2 rootfstype=ext4 rw" | sudo tee /tmp/qemu-boot/cmdline.txt
    
    # Comment out stuff that breaks QEMU in /etc/fstab
    sudo sed -i 's/^/#QEMU#/' /tmp/qemu-root/etc/fstab
    echo "proc /proc proc defaults 0 0" | sudo tee -a /tmp/qemu-root/etc/fstab
    
    # Enable SSH
    sudo touch /tmp/qemu-boot/ssh
    
    # Create user
    HASH=$(echo "zero" | openssl passwd -6 -stdin)
    echo "zero:$HASH" | sudo tee /tmp/qemu-boot/userconf.txt
    
    # Cleanup
    sudo umount /tmp/qemu-boot /tmp/qemu-root
    sudo losetup -d "$LOOP"
    
    log_info "Setup complete! Run: $0 boot"
}

boot() {
    if [ ! -f "$QEMU_IMG" ] || [ ! -f "$KERNEL" ]; then
        log_warn "Run '$0 setup' first"
        exit 1
    fi
    
    log_step "Booting Pi in QEMU..."
    log_info "SSH will be available on localhost:5022"
    log_info "Login: zero / zero"
    log_info "Press Ctrl+A then X to quit QEMU"
    echo ""
    
    qemu-system-arm \
        -M versatilepb \
        -cpu arm1176 \
        -m 256 \
        -kernel "$KERNEL" \
        -dtb "$DTB" \
        -drive file="$QEMU_IMG",format=raw \
        -append "console=ttyAMA0 root=/dev/sda2 rootfstype=ext4 rw" \
        -net nic \
        -net user,hostfwd=tcp::5022-:22,hostfwd=tcp::5080-:80,hostfwd=tcp::5081-:8080 \
        -no-reboot \
        -nographic
}

ssh_connect() {
    log_info "Connecting to emulated Pi..."
    ssh -p 5022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null zero@localhost
}

clean() {
    log_step "Cleaning up QEMU files..."
    rm -rf "$WORK_DIR"
    log_info "Done"
}

case "${1:-}" in
    setup) setup ;;
    boot) boot ;;
    ssh) ssh_connect ;;
    clean) clean ;;
    *) usage ;;
esac
