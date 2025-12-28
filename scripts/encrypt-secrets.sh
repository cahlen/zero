#!/bin/bash
# Zero - Encrypt Secrets Script
# Encrypts secrets.env using device-specific key

set -e

CONFIG_DIR="/etc/zero"
SECRETS_FILE="$CONFIG_DIR/secrets.env"
ENCRYPTED_FILE="$CONFIG_DIR/secrets.env.enc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Generate device-specific encryption key
get_device_key() {
    # Derive key from hardware identifiers
    # This ties encryption to this specific device
    SERIAL=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2)
    MAC=$(cat /sys/class/net/wlan0/address | tr -d ':')
    
    # Create a key by hashing the hardware IDs
    echo -n "${SERIAL}${MAC}zero-salt-2024" | sha256sum | cut -d ' ' -f 1
}

encrypt_secrets() {
    if [ ! -f "$SECRETS_FILE" ]; then
        log_error "Secrets file not found: $SECRETS_FILE"
        exit 1
    fi
    
    KEY=$(get_device_key)
    
    log_info "Encrypting secrets..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$SECRETS_FILE" \
        -out "$ENCRYPTED_FILE" \
        -pass "pass:$KEY"
    
    # Secure the encrypted file
    chmod 600 "$ENCRYPTED_FILE"
    
    # Optionally remove plaintext
    read -p "Remove plaintext secrets file? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$SECRETS_FILE"
        log_info "Plaintext secrets removed"
    fi
    
    log_info "Secrets encrypted to: $ENCRYPTED_FILE"
}

decrypt_secrets() {
    if [ ! -f "$ENCRYPTED_FILE" ]; then
        log_error "Encrypted file not found: $ENCRYPTED_FILE"
        exit 1
    fi
    
    KEY=$(get_device_key)
    
    log_info "Decrypting secrets..."
    openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "$ENCRYPTED_FILE" \
        -out "$SECRETS_FILE" \
        -pass "pass:$KEY"
    
    chmod 600 "$SECRETS_FILE"
    log_info "Secrets decrypted to: $SECRETS_FILE"
}

usage() {
    echo "Usage: $0 [encrypt|decrypt]"
    echo ""
    echo "Commands:"
    echo "  encrypt    Encrypt secrets.env"
    echo "  decrypt    Decrypt secrets.env.enc"
    exit 1
}

case "${1:-}" in
    encrypt)
        encrypt_secrets
        ;;
    decrypt)
        decrypt_secrets
        ;;
    *)
        usage
        ;;
esac
