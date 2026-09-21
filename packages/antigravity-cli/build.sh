#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Google's AI coding agent for Termux
# Uses wallentx's Bionic agy bootstrapper (v1.1.27) + official Google binary
# The Bionic agy finds agy.va39 in same dir and invokes glibc loader
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) CC="aarch64-linux-gnu-gcc"; AGY_ARCH="arm64" ;;
    x86_64)  CC="gcc";                   AGY_ARCH="amd64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building antigravity-cli (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"

# Step 1: Get latest version from Google's manifest
echo "Querying latest version from Google..."
MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_${AGY_ARCH}.json"
manifest_json="$(curl -fsSL "$MANIFEST_URL")"
VERSION="$(echo "$manifest_json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
DOWNLOAD_URL="$(echo "$manifest_json" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [ -z "$VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: could not parse manifest" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

DEB_VERSION="${VERSION}-0"
echo "Latest version: ${VERSION}"

PREFIX="data/data/com.termux/files/usr"
PKG_DIR="${BUILD_DIR}/antigravity-cli_${DEB_VERSION}_${ARCH}"
BIN_DIR="${PKG_DIR}/${PREFIX}/bin"
mkdir -p "${PKG_DIR}/DEBIAN" "$BIN_DIR"

# Step 2: Download wallentx Bionic bootstrapper (agy)
echo "Downloading wallentx Bionic bootstrapper..."
curl -fSL "https://github.com/wallentx/antigravity-cli-termux/releases/download/v1.1.27/antigravity-termux-standalone.tar.gz" \
    -o "${BUILD_DIR}/wallentx.tar.gz" 2>/dev/null

tar -xzf "${BUILD_DIR}/wallentx.tar.gz" -C "${BUILD_DIR}"
WALLENTX_AGY="$(find "$BUILD_DIR" -maxdepth 1 -name 'agy' -type f ! -name '*.tar.gz' | head -1)"

if [ -z "$WALLENTX_AGY" ]; then
    echo "Error: could not find wallentx agy bootstrapper" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "Found wallentx bootstrapper: $(stat -c%s "$WALLENTX_AGY") bytes"

# Step 3: Download official Google binary
echo "Downloading official Google antigravity ${VERSION}..."
curl -fSL "$DOWNLOAD_URL" -o "${BUILD_DIR}/google.tar.gz"

tar -xzf "${BUILD_DIR}/google.tar.gz" -C "${BUILD_DIR}"
GOOGLE_BIN="$(find "$BUILD_DIR" -maxdepth 2 -type f \( -name 'antigravity' -o -name 'agy' -o -name 'cli' \) ! -name '*.tar.gz' ! -path "*/wallentx*" | head -1)"

if [ -z "$GOOGLE_BIN" ]; then
    # Fallback: take largest executable that isn't the wallentx one
    GOOGLE_BIN="$(find "$BUILD_DIR" -maxdepth 2 -type f ! -name '*.tar.gz' ! -name 'wallentx*' -executable -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)"
fi

if [ -z "$GOOGLE_BIN" ]; then
    echo "Error: could not find Google binary" >&2
    ls -la "$BUILD_DIR"
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "Found Google binary: $(stat -c%s "$GOOGLE_BIN") bytes"

# Step 4: Install both into bin/
# agy (Bionic bootstrapper) finds agy.va39 in same directory via dirname
install -Dm755 "$WALLENTX_AGY" "${BIN_DIR}/agy"
install -Dm755 "$GOOGLE_BIN" "${BIN_DIR}/agy.va39"

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
 calling, and persistent history to your terminal.
EOF

DEB_FILE="${DEBS_DIR}/antigravity-cli_${DEB_VERSION}_termux_${ARCH}.deb"
dpkg-deb -Zxz --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
