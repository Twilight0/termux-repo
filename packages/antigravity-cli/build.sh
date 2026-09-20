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
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/antigravity-cli"

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

# Find all binaries in the tarball
BINS=()
while IFS= read -r -d '' f; do
    BINS+=("$f")
done < <(find "$BUILD_DIR" -maxdepth 1 -type f ! -name '*.tar.gz' -print0)

if [ ${#BINS[@]} -eq 0 ]; then
    echo "Error: could not find any binaries" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "Found binaries: ${BINS[*]}"

for bin_path in "${BINS[@]}"; do
    bin_name="$(basename "$bin_path")"

    # Strip debug symbols
    echo "Stripping ${bin_name}..."
    if [ "$ARCH" = "aarch64" ]; then
        aarch64-linux-gnu-strip "$bin_path" 2>/dev/null || true
    else
        strip "$bin_path" 2>/dev/null || true
    fi

    # Install binary
    install -Dm755 "$bin_path" "${PKG_DIR}/${PREFIX}/lib/antigravity-cli/${bin_name}.bin"

    # Create wrapper script for this binary
    wrapper="${PKG_DIR}/${PREFIX}/bin/${bin_name}"
    this_dir="\$(dirname "\$0")"
    cat > "$wrapper" << 'WRAPEOF'
#!/bin/sh
exec "$(dirname "$0")/../lib/antigravity-cli/agy_helper" BIN_PLACEHOLDER "$@"
WRAPEOF
    sed -i "s|BIN_PLACEHOLDER|${bin_name}|" "$wrapper"
    chmod 755 "$wrapper"
done

# Also install the VA39 patch script
if [ -f "$SCRIPT_DIR/helper/patch_va39.py" ]; then
    install -Dm755 "$SCRIPT_DIR/helper/patch_va39.py" "${PKG_DIR}/${PREFIX}/lib/antigravity-cli/patch_va39.py"
fi

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
