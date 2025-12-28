# Zero Quick Reference

## Development Commands

| Command | Description |
|---------|-------------|
| `make test` | Run test suite |
| `make dev-portal` | Run WiFi portal locally (port 8080) |
| `make dev-web` | Run web dashboard locally (port 8081) |
| `make dev-setup` | Install Python dev environment |

## Emulation (no hardware needed)

| Command | Description |
|---------|-------------|
| `make emulate-setup` | Download Pi OS image |
| `make emulate` | Boot Pi in QEMU |
| `make emulate-ssh` | SSH into emulator |

## Hardware Flashing

```bash
make flash DEVICE=/dev/sdb
```

## Release Workflow

```bash
# 1. Make changes and test
make test

# 2. Bump version (0.1.0 → 0.1.1)
make bump-version

# 3. Commit and tag
git add -A
git commit -m "Release v0.1.1 - description"
git tag -a v0.1.1 -m "Release notes"
git push origin main v0.1.1

# GitHub Actions automatically builds release
```

## On-Device Commands (SSH)

| Command | Description |
|---------|-------------|
| `sudo /opt/zero/scripts/update.sh check` | Check for updates |
| `sudo /opt/zero/scripts/update.sh update` | Apply update |
| `sudo /opt/zero/scripts/update.sh rollback` | Revert to previous |
| `sudo /opt/zero/scripts/update.sh status` | Show version & services |
| `sudo /opt/zero/scripts/update.sh version` | Print version only |

## Key Paths (on device)

| Path | Contents |
|------|----------|
| `/opt/zero/` | Main installation |
| `/opt/zero/VERSION` | Current version |
| `/opt/zero-backup/` | Rollback backup |
| `/etc/zero/device-id` | Unique device ID |
| `/etc/zero/secrets.env` | API keys |
| `/var/log/zero-update.log` | Update log |

## Services

| Service | Port | Description |
|---------|------|-------------|
| `zero-wifi-portal` | 80 | Captive portal |
| `zero-webapp` | 8080 | Web dashboard |
| `zero-display` | - | Pygame display |
| `zero-updater.timer` | - | Daily update check |

```bash
# Check service status
systemctl status zero-wifi-portal
systemctl status zero-webapp

# View logs
journalctl -u zero-wifi-portal -f
```

## Version File Format

`VERSION`: Plain text, single line
```
0.1.1
```

`updates/manifest.json`: Full metadata
```json
{
  "version": "0.1.1",
  "release_date": "2024-12-27",
  "components": { ... }
}
```
