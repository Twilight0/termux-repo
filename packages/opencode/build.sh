#!/usr/bin/env bash
set -euo pipefail

# opencode: Glibc-linked binary with C bootstrapper
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${OPENCODE_VERSION:-1.18.3}"
DEB_VERSION="${VERSION}-0"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) UPSTREAM_ARCH="arm64"; CC="aarch64-linux-gnu-gcc" ;;
    x86_64)  UPSTREAM_ARCH="x64";   CC="gcc" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building opencode ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/opencode_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/opencode"

echo "Compiling bootstrapper (${ARCH})..."
$CC -static -O2 -o "${BUILD_DIR}/opencode_helper" "$SCRIPT_DIR/helper/opencode.c"

TARBALL="${BUILD_DIR}/opencode.tar.gz"
echo "Downloading opencode ${VERSION} (${UPSTREAM_ARCH})..."
curl -fSL "https://github.com/anomalyco/opencode/releases/download/v${VERSION}/opencode-linux-${UPSTREAM_ARCH}.tar.gz" \
    -o "$TARBALL"

echo "Extracting..."
tar -xzf "$TARBALL" -C "${BUILD_DIR}"

UPSTREAM_BIN="${BUILD_DIR}/opencode"
if [ ! -f "$UPSTREAM_BIN" ]; then
    UPSTREAM_BIN="$(find "$BUILD_DIR" -maxdepth 2 -name 'opencode' -type f | head -1)"
fi
if [ ! -f "$UPSTREAM_BIN" ]; then
    echo "Error: could not find opencode binary in release tarball" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

# Strip debug symbols to reduce size
echo "Stripping binary..."
if [ "$ARCH" = "aarch64" ]; then
    aarch64-linux-gnu-strip "$UPSTREAM_BIN" 2>/dev/null || true
else
    strip "$UPSTREAM_BIN" 2>/dev/null || true
fi

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
