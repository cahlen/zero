#!/bin/bash -e
# Stage-zero: Zero custom additions
# Package installation

on_chroot << EOF
# Update package list
apt-get update

# Install NetworkManager (for WiFi portal)
apt-get install -y network-manager

# Install Python and pip
apt-get install -y python3 python3-pip python3-venv

# Install pygame dependencies
apt-get install -y libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
