#!/bin/bash -e
# Stage-zero: Enable Zero services

on_chroot << EOF
# Disable dhcpcd in favor of NetworkManager
systemctl disable dhcpcd 2>/dev/null || true

# Enable NetworkManager
systemctl enable NetworkManager

# Enable Zero services
systemctl enable zero-provision.service
systemctl enable zero-wifi-portal.service
systemctl enable zero-webapp.service
systemctl enable zero-display.service
EOF
