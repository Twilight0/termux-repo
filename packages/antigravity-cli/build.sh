#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Google's official AI coding agent
# Downloads from Google's auto-updater manifest (always latest version)
# Uses C bootstrapper to bridge Bionic->glibc on Termux
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) CC="aarch64-linux-gnu-gcc"; AGY_ARCH="arm64" ;;
    x86_64)  CC="gcc";                   AGY_ARCH="x64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building antigravity-cli (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"

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
LIB_DIR="${PKG_DIR}/${PREFIX}/lib/antigravity-cli"
BIN_DIR="${PKG_DIR}/${PREFIX}/bin"
mkdir -p "${PKG_DIR}/DEBIAN" "$LIB_DIR" "$BIN_DIR"

echo "Compiling bootstrapper (${ARCH})..."
$CC -static -O2 -o "${BUILD_DIR}/agy_helper" "$SCRIPT_DIR/helper/agy.c"

echo "Downloading antigravity-cli ${VERSION}..."
curl -fSL "$DOWNLOAD_URL" -o "${BUILD_DIR}/agy.tar.gz"

tar -xzf "${BUILD_DIR}/agy.tar.gz" -C "${BUILD_DIR}"

# Find the binary (may be named 'antigravity', 'agy', or something else)
AGY_BIN="$(find "$BUILD_DIR" -maxdepth 2 -type f \( -name 'antigravity' -o -name 'agy' \) ! -name 'agy_helper' ! -name '*.tar.gz' | head -1)"
if [ -z "$AGY_BIN" ]; then
    # Fallback: take the largest executable in the tarball
    AGY_BIN="$(find "$BUILD_DIR" -maxdepth 2 -type f ! -name 'agy_helper' ! -name '*.tar.gz' -executable -printf '%s %p\n' | sort -rn | head -1 | cut -d' ' -f2)"
fi

if [ -z "$AGY_BIN" ]; then
    echo "Error: could not find binary in tarball" >&2
    ls -la "$BUILD_DIR"
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "Found: ${AGY_BIN} ($(stat -c%s "$AGY_BIN") bytes)"

# Install binary (C helper expects .bin suffix)
install -Dm755 "$AGY_BIN" "${LIB_DIR}/antigravity.bin"

# Create wrapper script
cat > "${BIN_DIR}/agy" << 'WRAPEOF'
#!/bin/sh
exec "$(dirname "$0")/../lib/antigravity-cli/agy_helper" antigravity "$@"
WRAPEOF
chmod 755 "${BIN_DIR}/agy"

# Install helper (C bootstrapper)
install -Dm755 "${BUILD_DIR}/agy_helper" "${LIB_DIR}/agy_helper"

# Install the VA39 patch script if present
[ -f "$SCRIPT_DIR/helper/patch_va39.py" ] && \
    install -Dm755 "$SCRIPT_DIR/helper/patch_va39.py" "${LIB_DIR}/patch_va39.py"

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
