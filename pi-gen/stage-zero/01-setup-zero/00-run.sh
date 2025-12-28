#!/bin/bash -e
# Stage-zero: Zero application setup

on_chroot << EOF
# Create directories
mkdir -p /opt/zero
mkdir -p /etc/zero

# Create Python virtual environment
python3 -m venv /opt/zero/.venv

# Install Python dependencies
/opt/zero/.venv/bin/pip install --upgrade pip
/opt/zero/.venv/bin/pip install flask python-dotenv requests pygame

# Set permissions
chmod 755 /opt/zero
chmod 700 /etc/zero
EOF
