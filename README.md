# Zero

**WiFi provisioning for Raspberry Pi Zero W** — Connect to hotspot, configure WiFi, done.

## What It Does

1. Flash an SD card with this script
2. Boot your Pi Zero W — it broadcasts **"Zero-Setup"** WiFi
3. Connect with your phone, enter your WiFi password
4. Pi reboots and joins your network

No internet required. No cloud. 100% open source.

## Quick Start

```bash
# Flash your SD card (Linux)
sudo bash scripts/flash.sh /dev/sdX

# Replace /dev/sdX with your SD card device (check with lsblk)
```

**After flashing:**

1. Insert SD card into Pi Zero W
2. Power on and wait ~30 seconds
3. Connect to WiFi: **Zero-Setup** (open network, no password)
4. Captive portal opens automatically
5. Select your WiFi network and enter password
6. Pi reboots and connects to your network

**Default SSH credentials:** `pi` / `zero`

## Technical Details

- **OS:** Raspberry Pi OS Bullseye (32-bit)
- **Stack:** hostapd + dnsmasq + lighttpd + PHP
- **AP IP:** 192.168.4.1
- **DHCP Range:** 192.168.4.2 - 192.168.4.20

### Why This Approach?

The Pi Zero W's `brcmfmac` WiFi driver is notoriously buggy in AP mode. This script includes all the workarounds discovered through extensive testing:

- Bluetooth disabled (shares antenna with WiFi)
- `brcmfmac` module options to prevent crashes
- WMM disabled in hostapd
- WiFi scanning done at boot (before AP starts)
- Mode switching via reboot (live switch crashes)

## Hardware Requirements

- Raspberry Pi Zero W (or Zero 2 W)
- MicroSD card (4GB+)
- 2.4GHz WiFi network (**Pi Zero W does not support 5GHz**)

## License

MIT — Use it however you want.
