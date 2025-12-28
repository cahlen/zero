.PHONY: all image flash dev-setup test clean help dev-portal dev-web emulate emulate-setup emulate-ssh release bump-version

SHELL := /bin/bash
DEVICE ?= /dev/sdX
IMG_NAME := zero
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help:
	@echo "Zero - Pi Zero W Provisioning System (v$(VERSION))"
	@echo ""
	@echo "Development:"
	@echo "  make dev-setup    Install development dependencies"
	@echo "  make dev-portal   Run WiFi portal locally (port 8080)"
	@echo "  make dev-web      Run web dashboard locally (port 8081)"
	@echo "  make test         Run test suite"
	@echo ""
	@echo "Emulation (test without hardware):"
	@echo "  make emulate-setup  Download Pi OS and setup QEMU"
	@echo "  make emulate        Boot Pi OS in QEMU emulator"
	@echo "  make emulate-ssh    SSH into running emulator"
	@echo ""
	@echo "Hardware:"
	@echo "  make flash DEVICE=/dev/sdX  Flash SD card"
	@echo "  make image        Build custom image with pi-gen"
	@echo ""
	@echo "Release (for OTA updates):"
	@echo "  make release      Build release tarball for GitHub"
	@echo "  make bump-version Increment version number"
	@echo ""
	@echo "Examples:"
	@echo "  make dev-portal   # Test captive portal locally"
	@echo "  make emulate      # Boot Pi in QEMU"
	@echo "  make flash DEVICE=/dev/sdb"
	@echo "  make release      # Build v$(VERSION) release"

all: help

# Build custom image with pi-gen
image:
	@echo -e "$(GREEN)Building custom image...$(NC)"
	@if [ ! -d "pi-gen" ]; then \
		echo "Cloning pi-gen..."; \
		git clone --depth 1 https://github.com/RPi-Distro/pi-gen.git pi-gen-build; \
	fi
	@cp -r pi-gen/stage-zero pi-gen-build/
	@cp pi-gen/config pi-gen-build/
	@cd pi-gen-build && ./build-docker.sh
	@echo -e "$(GREEN)Image built: pi-gen-build/deploy/$(IMG_NAME)-$(VERSION).img$(NC)"

# Flash image to SD card
flash:
	@if [ "$(DEVICE)" = "/dev/sdX" ]; then \
		echo -e "$(YELLOW)Error: Set DEVICE to your SD card (e.g., make flash DEVICE=/dev/sdb)$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)WARNING: This will erase $(DEVICE)$(NC)"
	@read -p "Are you sure? (y/N) " confirm && [ "$$confirm" = "y" ]
	@./scripts/flash.sh $(DEVICE)

# Development setup
dev-setup:
	@echo -e "$(GREEN)Setting up development environment...$(NC)"
	python3 -m venv .venv
	.venv/bin/pip install flask waitress
	@echo -e "$(GREEN)Activate with: source .venv/bin/activate$(NC)"

# Run WiFi portal locally
dev-portal:
	@echo -e "$(GREEN)Starting WiFi portal on http://localhost:8080$(NC)"
	@bash scripts/dev.sh portal

# Run web dashboard locally
dev-web:
	@echo -e "$(GREEN)Starting web dashboard on http://localhost:8081$(NC)"
	@bash scripts/dev.sh web

# Emulator setup
emulate-setup:
	@echo -e "$(GREEN)Setting up QEMU emulator...$(NC)"
	@bash scripts/emulate.sh setup

# Boot emulator
emulate:
	@echo -e "$(GREEN)Booting Pi OS in QEMU...$(NC)"
	@bash scripts/emulate.sh boot

# SSH into emulator
emulate-ssh:
	@bash scripts/emulate.sh ssh

# Run tests
test:
	@echo -e "$(GREEN)Running tests...$(NC)"
	@bash scripts/test.sh

# Build release tarball
release:
	@echo -e "$(GREEN)Building release v$(VERSION)...$(NC)"
	@bash scripts/release.sh

# Bump version number
bump-version:
	@current=$$(cat VERSION); \
	major=$$(echo $$current | cut -d. -f1); \
	minor=$$(echo $$current | cut -d. -f2); \
	patch=$$(echo $$current | cut -d. -f3); \
	new_patch=$$((patch + 1)); \
	new_version="$$major.$$minor.$$new_patch"; \
	echo "$$new_version" > VERSION; \
	sed -i "s/\"version\": \"$$current\"/\"version\": \"$$new_version\"/" updates/manifest.json; \
	echo -e "$(GREEN)Version bumped: $$current → $$new_version$(NC)"

# Clean build artifacts
clean:
	@echo -e "$(GREEN)Cleaning...$(NC)"
	rm -rf pi-gen-build/work
	rm -rf pi-gen-build/deploy
	rm -rf build
	rm -rf .venv
	rm -rf __pycache__ */__pycache__ */*/__pycache__
	rm -rf *.egg-info
	rm -rf .pytest_cache
	rm -rf .qemu

# Package rootfs overlay
package-rootfs:
	@echo -e "$(GREEN)Packaging rootfs overlay...$(NC)"
	tar -czvf build/rootfs-overlay.tar.gz -C rootfs .

# Validate configs
validate:
	@echo -e "$(GREEN)Validating configurations...$(NC)"
	@python3 scripts/validate-configs.py
