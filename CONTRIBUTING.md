# Contributing to Zero

First off, thank you for considering contributing to Zero! It's people like you that make Zero a truly open platform.

## Code of Conduct

Be kind. Be respectful. We're all here to build something cool.

## How Can I Contribute?

### 🐛 Reporting Bugs

Found a bug? [Open an issue](../../issues/new) with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Your device (Zero W, Zero 2 W)
- Your OS version

### 💡 Suggesting Features

Have an idea? We'd love to hear it! [Open a discussion](../../discussions) or issue with:
- What problem does it solve?
- How would it work?
- Who would use it?

### 🔧 Pull Requests

1. Fork the repo
2. Create a branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### 📝 Documentation

Documentation improvements are always welcome! See something confusing? Fix it.

### 🧪 Testing

- Test on real hardware
- Report what works and what doesn't
- Try edge cases

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/zero.git
cd zero

# Set up development environment
make dev-setup

# Run tests
make test

# Run apps locally
make dev-portal  # WiFi portal on port 8080
make dev-web     # Web dashboard on port 8081

# Test in QEMU (no hardware needed)
make emulate-setup
make emulate
```

## Project Structure

```
zero/
├── apps/           # Application code (wifi-portal, web, display)
├── scripts/        # Tooling (flash, update, release, test)
├── configs/        # Configuration templates
├── rootfs/         # Files copied to device
├── updates/        # OTA update manifests
└── docs/           # Documentation
```

## Adding a New App

1. Create a directory under `apps/your-app/`
2. Add `app.py` as the entry point
3. Add `templates/` for any HTML
4. Create a systemd service in `rootfs/etc/systemd/system/`
5. Update `scripts/flash.sh` to copy your app
6. Update `updates/manifest.json` to include your app
7. Document it!

## Coding Style

### Python
- Use Python 3.9+ features
- Follow PEP 8
- Keep it simple — these run on limited hardware
- Add docstrings for public functions

### Bash
- Use `shellcheck` to validate
- Quote your variables: `"$var"` not `$var`
- Use `set -e` for scripts that should fail fast
- Add comments for non-obvious logic

### General
- Small, focused commits
- Descriptive commit messages
- Test your changes on real hardware when possible

## Release Process

See [README.md - Creating a Release](README.md#creating-a-release) for the full process.

Quick version:
```bash
make bump-version
git commit -am "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Release notes"
git push origin main vX.Y.Z
```

## Questions?

- Open a [discussion](../../discussions)
- Check existing [issues](../../issues)

## Recognition

Contributors will be recognized in our README and release notes. Every contribution matters, no matter how small.

---

**Thank you for making Zero better!** 🎉
