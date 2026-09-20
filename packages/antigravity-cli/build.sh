#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Pre-patched VA39 binary with C bootstrapper
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${AGY_VERSION:-1.1.27}"
DEB_VERSION="${VERSION}-0"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) CC="aarch64-linux-gnu-gcc"; AGY_ARCH="arm64" ;;
    x86_64)  CC="gcc";                   AGY_ARCH="x64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building antigravity-cli ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/antigravity-cli_${DEB_VERSION}_${ARCH}"
LIB_DIR="${PKG_DIR}/${PREFIX}/lib/antigravity-cli"
BIN_DIR="${PKG_DIR}/${PREFIX}/bin"
mkdir -p "${PKG_DIR}/DEBIAN" "$LIB_DIR" "$BIN_DIR"

echo "Compiling bootstrapper (${ARCH})..."
$CC -static -O2 -o "${BUILD_DIR}/agy_helper" "$SCRIPT_DIR/helper/agy.c"

echo "Downloading antigravity-cli ${VERSION}..."
curl -fSL "https://github.com/wallentx/antigravity-cli-termux/releases/download/v${VERSION}/antigravity-termux-standalone.tar.gz" \
    -o "${BUILD_DIR}/agy.tar.gz" 2>/dev/null || {
    echo "Pre-built release not found, downloading from Google's manifest..."
    MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_${AGY_ARCH}.json"
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

tar -xzf "${BUILD_DIR}/agy.tar.gz" -C "${BUILD_DIR}"

# Find the actual binaries (may be in a subdirectory)
AGY_BIN="$(find "$BUILD_DIR" -name 'agy' -type f ! -name 'agy_helper' ! -name '*.tar.gz' | head -1)"
AGY_VA39="$(find "$BUILD_DIR" -name 'agy.va39' -type f | head -1)"

echo "Found: agy=${AGY_BIN:-none} agy.va39=${AGY_VA39:-none}"

# Install each binary with .bin suffix + wrapper
for bin_spec in "agy:${AGY_BIN}" "agy.va39:${AGY_VA39}"; do
    bin_name="${bin_spec%%:*}"
    bin_path="${bin_spec#*:}"
    [ -f "$bin_path" ] || continue

    echo "Stripping ${bin_name} ($(stat -c%s "$bin_path") bytes)..."
    if [ "$ARCH" = "aarch64" ]; then
        aarch64-linux-gnu-strip "$bin_path" 2>/dev/null || true
    else
        strip "$bin_path" 2>/dev/null || true
    fi

    install -Dm755 "$bin_path" "${LIB_DIR}/${bin_name}.bin"

    cat > "${BIN_DIR}/${bin_name}" << 'WRAPEOF'
#!/bin/sh
exec "$(dirname "$0")/../lib/antigravity-cli/agy_helper" BIN_PLACEHOLDER "$@"
WRAPEOF
    sed -i "s|BIN_PLACEHOLDER|${bin_name}|" "${BIN_DIR}/${bin_name}"
    chmod 755 "${BIN_DIR}/${bin_name}"
done

# Install helper (the C bootstrapper)
install -Dm755 "${BUILD_DIR}/agy_helper" "${LIB_DIR}/agy_helper"

# Install the VA39 patch script
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
 calling, and persistent history to your terminal. VA39-patched for
 Android/Termux compatibility.
EOF

DEB_FILE="${DEBS_DIR}/antigravity-cli_${DEB_VERSION}_termux_${ARCH}.deb"
dpkg-deb -Zxz --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
