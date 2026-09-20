#!/usr/bin/env bash
set -euo pipefail

# opencode: Glibc-linked binary with C bootstrapper
# Requires glibc-repo and glibc packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

# Version info
VERSION="${OPENCODE_VERSION:-1.18.3}"
DEB_VERSION="${VERSION}-0"
PREFIX="data/data/com.termux/files/usr"
ARCH="aarch64"

echo "=== Building opencode ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/opencode_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/opencode"

# Cross-compile the C bootstrapper (static, no deps)
echo "Compiling bootstrapper..."
aarch64-linux-gnu-gcc -static -O2 -o "${BUILD_DIR}/opencode_helper" \
    "$SCRIPT_DIR/helper/opencode.c"

# Download upstream release
TARBALL="${BUILD_DIR}/opencode.tar.gz"
echo "Downloading opencode ${VERSION}..."
curl -fSL "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-arm64.tar.gz" \
    -o "$TARBALL"

echo "Extracting..."
tar -xzf "$TARBALL" -C "${BUILD_DIR}"

# Find the binary
UPSTREAM_BIN="${BUILD_DIR}/opencode"
if [ ! -f "$UPSTREAM_BIN" ]; then
    # Try finding it in extracted directory
    UPSTREAM_BIN="$(find "$BUILD_DIR" -maxdepth 2 -name 'opencode' -type f | head -1)"
fi
if [ ! -f "$UPSTREAM_BIN" ]; then
    echo "Error: could not find opencode binary in release tarball" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

# Install files
install -Dm755 "$UPSTREAM_BIN" "${PKG_DIR}/${PREFIX}/lib/opencode/opencode-bin"
install -Dm755 "${BUILD_DIR}/opencode_helper" "${PKG_DIR}/${PREFIX}/bin/opencode"
chmod 755 "${PKG_DIR}/${PREFIX}/bin/opencode"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: opencode
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, ripgrep, jq, nodejs-lts
Section: devel
Priority: optional
Homepage: https://github.com/anomalyco/opencode
Description: AI-powered coding assistant for the terminal
 OpenCode is an interactive AI coding assistant that runs in your terminal.
 Uses glibc bridge for Termux compatibility.
EOF

DEB_FILE="${DEBS_DIR}/opencode_${DEB_VERSION}_termux_${ARCH}.deb"
dpkg-deb -Zxz --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
