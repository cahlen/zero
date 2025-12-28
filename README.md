# Zero

### 100% Open Source • Build Your Own AI Fleet • Use It Your Way

<p align="center">
  <strong>An open platform for deploying fleets of AI-enabled Raspberry Pi Zero W devices.</strong>
</p>

---

> ## ⚠️ IMPORTANT: NOT YET FUNCTIONAL ⚠️
> 
> **This project is under active development and DOES NOT WORK yet.**
> 
> Even if you see version numbers or "releases" — **do not expect a working system** until an official announcement declares it functional.
> 
> ### What you CAN use this for:
> - 📚 **Reference material** — Study the architecture, scripts, and patterns
> - 🤖 **LLM fodder** — Feed this repo to your AI coding assistant for inspiration on your own projects
> - 🔬 **Learning** — See how WiFi captive portals, OTA updates, and fleet management can be structured
> - 🍴 **Forking** — Take ideas and build your own thing
> 
> ### What you CANNOT do yet:
> - ❌ Flash an SD card and have a working device
> - ❌ Deploy a fleet of functioning Pi Zeros
> - ❌ Rely on this for any production use
> 
> **We're working on it. Star/watch the repo for updates.**

---

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#vision">Vision</a> •
  <a href="#features">Features</a> •
  <a href="#fleet-management--ota-updates">Fleet Management</a> •
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

---

## Why Zero?

**Zero is yours.** Fork it, modify it, deploy hundreds of devices, build something we never imagined. That's the point.

We're building an open platform for AI-powered edge devices. Today it's a WiFi captive portal and OTA updates. Tomorrow it could be:

- 🤖 **Dynamic AI Apps** — Deploy new AI capabilities to your fleet with a git push
- 👋 **Peer-to-Peer Local Social** — Bump into someone at the mall, school, or market with a similar device and connect instantly. A true *local* social experience, no cloud required
- 🔊 **Voice Assistants** — Your own private AI assistant that respects your privacy
- 📡 **Mesh Networks** — Devices that talk to each other, not just the cloud
- 🎮 **Interactive Displays** — Information kiosks, art installations, smart mirrors
- 🏠 **Home Automation** — Control your world with $15 computers

**The modular architecture means you decide what Zero becomes.**

---

## Features

- **WiFi Captive Portal**: Broadcasts AP on first boot for easy WiFi configuration
- **Web Applications**: Flask-based web server for browser-accessible apps
- **Display Applications**: Pygame framebuffer apps for HDMI/display output
- **AI Integration**: Secure credential management for OpenAI, Gemini, Claude, Groq, Grok
- **Reproducible Builds**: Automated SD card imaging and provisioning
- **OTA Updates**: Automatic over-the-air updates via GitHub releases
- **Fleet Ready**: Unique device IDs, version tracking, rollback support

## Hardware Requirements

- Raspberry Pi Zero W (or Zero 2 W)
- MicroSD card (8GB+ recommended)
- 2.4GHz WiFi network (Pi Zero W does not support 5GHz)

## Quick Start

### 1. Flash the Base Image

```bash
# Flash Raspberry Pi OS Lite to SD card
./scripts/flash.sh /dev/sdX

# Or build a custom image
make image
```

### 2. First Boot Setup

1. Insert SD card and power on the Pi
2. Connect to WiFi network `Zero-Setup-XXXX` (password: `zerowsetup`)
3. Open browser → redirected to setup portal
4. Configure your home WiFi credentials
5. (Optional) Enter AI API keys
6. Pi reboots and connects to your network

### 3. Access Your Device

```bash
# Find your Pi on the network
./scripts/find-zero.sh

# SSH into the device
ssh zero@zero.local
```

## Repository Structure

```
zero/
├── apps/
│   ├── wifi-portal/      # Captive portal for WiFi setup
│   ├── web/              # Web applications (Flask)
│   └── display/          # Display applications (Pygame)
├── configs/
│   ├── templates/        # Config file templates
│   └── secrets.env.example
├── rootfs/               # Overlay files for the image
│   └── etc/systemd/system/
├── scripts/
│   ├── flash.sh          # SD card flashing
│   ├── update.sh         # OTA update system
│   ├── release.sh        # Build release tarballs
│   ├── dev.sh            # Local development server
│   ├── emulate.sh        # QEMU emulation
│   └── test.sh           # Test suite
├── updates/
│   └── manifest.json     # Release metadata
├── .github/workflows/
│   └── release.yml       # Auto-build on git tag
├── VERSION               # Current version
└── Makefile
```

## Configuration

### AI Credentials

Supported providers:
- **OpenAI** (`OPENAI_API_KEY`)
- **Anthropic/Claude** (`ANTHROPIC_API_KEY`)
- **Google Gemini** (`GOOGLE_API_KEY`)
- **Groq** (`GROQ_API_KEY`)
- **xAI/Grok** (`XAI_API_KEY`)

Keys can be configured via:
1. Web portal at `http://zero.local/settings`
2. Captive portal during initial setup
3. Manually in `/etc/zero/secrets.env`

### Network Settings

Edit `configs/templates/hostapd.conf` to customize:
- AP SSID prefix (default: `Zero-Setup-`)
- AP password (default: `zerowsetup`)
- WiFi channel (default: 6)

## Development

### Quick Start

```bash
# Setup Python environment and install Flask
make dev-setup

# Run test suite
make test

# Run WiFi portal locally (port 8080)
make dev-portal

# Run web dashboard locally (port 8081)
make dev-web
```

### QEMU Emulation (Test Without Hardware)

Test your changes without constantly swapping SD cards:

```bash
# First-time setup: download Pi OS image
make emulate-setup

# Boot Pi in QEMU emulator
make emulate

# SSH into running emulator (user: pi, pass: raspberry)
make emulate-ssh
# Port forwards: localhost:5080 → Pi:80, localhost:5081 → Pi:8080
```

**Note**: WiFi/hotspot functionality cannot be emulated (no hardware) but all Flask apps and services can be tested.

### Flash to Hardware

```bash
# Flash SD card
make flash DEVICE=/dev/sdb
```

---

## Fleet Management & OTA Updates

Zero is designed for deploying and managing hundreds of devices. Each device:
- Has a unique device ID (`/etc/zero/device-id`)
- Tracks its version (`/opt/zero/VERSION`)
- Automatically checks for updates daily
- Can rollback to previous version if update fails

### Version Scheme

We use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (rare)
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes

Current version is stored in `VERSION` file at repo root.

### Creating a Release

#### 1. Make Your Changes

```bash
# Edit code in apps/, scripts/, etc.
make test  # Verify everything works
```

#### 2. Bump the Version

```bash
# Automatically increment patch version (0.1.0 → 0.1.1)
make bump-version

# Or manually edit VERSION and updates/manifest.json for minor/major bumps
```

#### 3. Commit and Tag

```bash
git add -A
git commit -m "Release v0.1.1 - Fix WiFi timing issue"

# Create annotated tag
git tag -a v0.1.1 -m "Fix WiFi timing issue

- Increased NetworkManager wait time
- Added retry logic for hotspot creation
"

git push origin main
git push origin v0.1.1
```

#### 4. GitHub Actions Builds the Release

When you push a tag starting with `v`, GitHub Actions automatically:
1. Builds a release tarball (`zero-0.1.1.tar.gz`)
2. Creates SHA256 checksum
3. Publishes to GitHub Releases

#### Manual Release (without GitHub Actions)

```bash
make release
# Creates build/zero-0.1.1.tar.gz

# Then upload to GitHub manually or use gh CLI:
gh release create v0.1.1 build/zero-0.1.1.tar.gz \
  --title "v0.1.1" \
  --notes "Fix WiFi timing issue"
```

### How Devices Receive Updates

#### Automatic Updates

Devices check for updates **daily at 3 AM** (randomized within 1 hour to prevent thundering herd).

The systemd timer `zero-updater.timer` triggers `zero-updater.service` which runs:
```bash
/opt/zero/scripts/update.sh update
```

#### Manual Update (SSH into device)

```bash
# Check if update is available
sudo /opt/zero/scripts/update.sh check

# Apply update
sudo /opt/zero/scripts/update.sh update

# Force re-download current version
sudo /opt/zero/scripts/update.sh force-update
```

### Rollback

If an update causes problems, rollback to the previous version:

```bash
# SSH into the device
ssh zero@device-ip

# Rollback
sudo /opt/zero/scripts/update.sh rollback
```

This restores from `/opt/zero-backup/` which is created before each update.

### Device Status

Check update status and service health:

```bash
sudo /opt/zero/scripts/update.sh status
```

Output:
```
Zero Update Status
==================
Installed version: 0.1.1
Install directory: /opt/zero
Backup directory:  /opt/zero-backup

Services:
  zero-wifi-portal: active
  zero-webapp: active
  zero-display: inactive
  zero-provision: inactive
```

### Update Manifest

The `updates/manifest.json` file tracks component versions:

```json
{
  "version": "0.1.1",
  "release_date": "2024-12-27",
  "min_version": "0.1.0",
  "components": {
    "wifi-portal": { "version": "0.1.1", "restart_service": "zero-wifi-portal" },
    "web": { "version": "0.1.1", "restart_service": "zero-webapp" },
    "display": { "version": "0.1.1", "restart_service": "zero-display" }
  },
  "changelog": ["Fixed WiFi timing", "Added retry logic"]
}
```

### Update Flow Diagram

```
┌─────────────────┐
│  GitHub Repo    │
│  (releases)     │
└────────┬────────┘
         │ HTTPS
         ▼
┌─────────────────┐     ┌─────────────────┐
│   Device #1     │     │   Device #N     │
│  ┌───────────┐  │     │  ┌───────────┐  │
│  │ updater   │  │     │  │ updater   │  │
│  │ timer     │──┼─────┼──│ timer     │  │
│  └─────┬─────┘  │     │  └─────┬─────┘  │
│        │        │     │        │        │
│        ▼        │     │        ▼        │
│  Check version  │     │  Check version  │
│  Download .tar  │     │  Download .tar  │
│  Backup current │     │  Backup current │
│  Extract new    │     │  Extract new    │
│  Restart svcs   │     │  Restart svcs   │
└─────────────────┘     └─────────────────┘
```

### Configuring Update Source

By default, updates come from `github.com/cahlen/zero`. To use a different repo, edit the variables at the top of `/opt/zero/scripts/update.sh`:

```bash
REPO_OWNER="your-org"
REPO_NAME="your-repo"
```

### Disabling Automatic Updates

To disable automatic updates on a device:

```bash
sudo systemctl disable zero-updater.timer
sudo systemctl stop zero-updater.timer
```

To re-enable:
```bash
sudo systemctl enable zero-updater.timer
sudo systemctl start zero-updater.timer
```

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- 🐛 [Report bugs](../../issues)
- 💡 [Suggest features](../../discussions)
- 🔧 [Submit PRs](../../pulls)

## Vision & Roadmap

Zero is more than a provisioning tool — it's a platform for the future of personal, private, distributed computing. See [VISION.md](VISION.md) for:

- The dream we're building toward
- Roadmap (AI integration, P2P local social, mesh networks)
- Philosophy (open source forever, privacy first, modular by design)
- Use cases (personal, educational, community, commercial, creative)

## License

**100% Open Source** — MIT License

Use it, modify it, sell it, give it away. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <strong>Zero is yours. Build something amazing.</strong>
</p>

