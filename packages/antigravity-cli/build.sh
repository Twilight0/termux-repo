#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Pre-patched VA39 binary with C bootstrapper
# Uses wallentx/antigravity-cli-termux pre-built release

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

# Version info - tracks wallentx releases
VERSION="${AGY_VERSION:-1.4.2}"
DEB_VERSION="${VERSION}-0"
PREFIX="data/data/com.termux/files/usr"
ARCH="aarch64"

echo "=== Building antigravity-cli ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/antigravity-cli_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/antigravity-cli"

# Cross-compile the C bootstrapper (static, no deps)
echo "Compiling bootstrapper..."
aarch64-linux-gnu-gcc -static -O2 -o "${BUILD_DIR}/agy_helper" \
    "$SCRIPT_DIR/helper/agy.c"

# Download pre-patched release from wallentx
echo "Downloading antigravity-cli ${VERSION}..."
curl -fSL "https://github.com/wallentx/antigravity-cli-termux/releases/download/v${VERSION}/agy-termux-${VERSION}-linux-arm64.tar.gz" \
    -o "${BUILD_DIR}/agy.tar.gz" 2>/dev/null || {
    # Fallback: try official install script to get the binary, then patch
    echo "Pre-built release not found, downloading official binary and patching..."
    curl -fSL "https://antigravity.google/cli/install.sh" -o "${BUILD_DIR}/install.sh"
    # Download the arm64 binary directly
    curl -fSL "https://dl.google.com/antigravity/cli/latest/linux-arm64/agy" \
        -o "${BUILD_DIR}/agy.original"
    # Apply VA39 patches
    python3 "$SCRIPT_DIR/helper/patch_va39.py" \
        "${BUILD_DIR}/agy.original" "${BUILD_DIR}/agy.bin"
}

# Extract if tarball, otherwise use patched binary
if [ -f "${BUILD_DIR}/agy.tar.gz" ]; then
    tar -xzf "${BUILD_DIR}/agy.tar.gz" -C "${BUILD_DIR}"
    # Find the patched binary
    AGY_BIN="$(find "$BUILD_DIR" -name 'agy*' -type f -executable | head -1)"
    if [ -z "$AGY_BIN" ]; then
        AGY_BIN="$(find "$BUILD_DIR" -name 'agy*' -type f | head -1)"
    fi
else
    AGY_BIN="${BUILD_DIR}/agy.bin"
fi

if [ ! -f "$AGY_BIN" ]; then
    echo "Error: could not find antigravity-cli binary" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

# Install files
install -Dm755 "$AGY_BIN" "${PKG_DIR}/${PREFIX}/lib/antigravity-cli/agy.bin"
install -Dm755 "${BUILD_DIR}/agy_helper" "${PKG_DIR}/${PREFIX}/bin/agy"
chmod 755 "${PKG_DIR}/${PREFIX}/bin/agy"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: antigravity-cli
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, python
Section: devel
Priority: optional
Homepage: https://antigravity.google/cli
Description: Google Antigravity CLI - AI coding agent
 Antigravity CLI brings multi-step reasoning, multi-file editing, tool
 calling, and persistent history to your terminal. VA39-patched for
 Android/Termux compatibility.
EOF

DEB_FILE="${DEBS_DIR}/antigravity-cli_${DEB_VERSION}_termux_${ARCH}.deb"
dpkg-deb -Zxz --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
