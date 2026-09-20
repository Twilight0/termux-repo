#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Pre-patched VA39 binary with C bootstrapper
# Uses wallentx/antigravity-cli-termux pre-built release

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

# Version info - tracks wallentx releases
VERSION="${AGY_VERSION:-1.1.27}"
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
curl -fSL "https://github.com/wallentx/antigravity-cli-termux/releases/download/v${VERSION}/antigravity-termux-standalone.tar.gz" \
    -o "${BUILD_DIR}/agy.tar.gz" 2>/dev/null || {
    # Fallback: download from Google's auto-updater manifest and patch
    echo "Pre-built release not found, downloading official binary and patching..."
    MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json"
    manifest_json="$(curl -fsSL "$MANIFEST_URL")"
    url="$(echo "$manifest_json" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    if [ -n "$url" ]; then
        curl -fSL "$url" -o "${BUILD_DIR}/agy.tar.gz"
    else
        echo "Error: could not fetch manifest" >&2
        rm -rf "$BUILD_DIR"
        exit 1
    fi
}

# Extract tarball
tar -xzf "${BUILD_DIR}/agy.tar.gz" -C "${BUILD_DIR}"

# Find the binary (prefer agy over agy.va39 for Termux)
AGY_BIN="$(find "$BUILD_DIR" -maxdepth 1 -name 'agy' -type f | head -1)"
if [ -z "$AGY_BIN" ]; then
    AGY_BIN="$(find "$BUILD_DIR" -maxdepth 1 -name 'agy*' -type f ! -name '*.tar.gz' | head -1)"
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
Depends: glibc-repo, glibc
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
