#!/bin/bash
# Zero Release Builder
# Creates a release tarball for GitHub releases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${REPO_DIR}/build"

VERSION=$(cat "${REPO_DIR}/VERSION" | tr -d '[:space:]')

echo "Building Zero release v${VERSION}"
echo "=================================="

# Clean build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/release"

# Copy app files
echo "Copying apps..."
cp -r "${REPO_DIR}/apps" "${BUILD_DIR}/release/"

# Copy scripts (excluding dev-only scripts)
echo "Copying scripts..."
mkdir -p "${BUILD_DIR}/release/scripts"
for script in update.sh provision.sh encrypt-secrets.sh; do
    if [ -f "${REPO_DIR}/scripts/$script" ]; then
        cp "${REPO_DIR}/scripts/$script" "${BUILD_DIR}/release/scripts/"
    fi
done

# Copy updates manifest
echo "Copying manifest..."
mkdir -p "${BUILD_DIR}/release/updates"
cp "${REPO_DIR}/updates/manifest.json" "${BUILD_DIR}/release/updates/"

# Copy VERSION
cp "${REPO_DIR}/VERSION" "${BUILD_DIR}/release/"

# Create tarball
echo "Creating tarball..."
cd "${BUILD_DIR}/release"
tar -czvf "../zero-${VERSION}.tar.gz" .

# Create checksum
cd "${BUILD_DIR}"
sha256sum "zero-${VERSION}.tar.gz" > "zero-${VERSION}.tar.gz.sha256"

echo ""
echo "Release files created in ${BUILD_DIR}:"
ls -la "${BUILD_DIR}/"*.tar.gz*

echo ""
echo "To create a GitHub release:"
echo "  1. git tag -a v${VERSION} -m 'Release v${VERSION}'"
echo "  2. git push origin v${VERSION}"
echo "  3. Upload ${BUILD_DIR}/zero-${VERSION}.tar.gz to the release"
echo ""
echo "Or use GitHub CLI:"
echo "  gh release create v${VERSION} ${BUILD_DIR}/zero-${VERSION}.tar.gz --title 'v${VERSION}' --notes 'Release notes here'"
