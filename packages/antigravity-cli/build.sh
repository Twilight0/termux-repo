#!/usr/bin/env bash
set -euo pipefail

# antigravity-cli: Google's AI coding agent for Termux
# Uses glibc dynamic loader + official Google binary
# Supports both aarch64 and x86_64
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

build_antigravity_deb() {
    local ARCH="$1"
    local AGY_ARCH

    case "$ARCH" in
        aarch64) AGY_ARCH="arm64" ;;
        x86_64)  AGY_ARCH="amd64" ;;
        *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
    esac

    echo "=== Building antigravity-cli (${ARCH}) ==="

    local BUILD_DIR
    BUILD_DIR="$(mktemp -d)"

    # Step 1: Query latest version from Google's manifest
    echo "Querying latest version from Google for ${AGY_ARCH}..."
    local MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_${AGY_ARCH}.json"
    local manifest_json
    manifest_json="$(curl -fsSL "$MANIFEST_URL")"
    local VERSION
    VERSION="$(echo "$manifest_json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    local DOWNLOAD_URL
    DOWNLOAD_URL="$(echo "$manifest_json" | sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

    if [ -z "$VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
        echo "Error: could not parse manifest" >&2
        rm -rf "$BUILD_DIR"
        exit 1
    fi

    local DEB_VERSION="${VERSION}-1"
    echo "Upstream version: ${VERSION} (Debian revision: ${DEB_VERSION})"

    local PREFIX="data/data/com.termux/files/usr"
    local PKG_DIR="${BUILD_DIR}/antigravity-cli_${DEB_VERSION}_${ARCH}"
    local LIB_DIR="${PKG_DIR}/${PREFIX}/lib/antigravity-cli"
    local BIN_DIR="${PKG_DIR}/${PREFIX}/bin"
    mkdir -p "${PKG_DIR}/DEBIAN" "$LIB_DIR" "$BIN_DIR"

    # Step 2: Download official Google binary
    echo "Downloading official Google antigravity ${VERSION} (${AGY_ARCH})..."
    local GOOGLE_DIR="${BUILD_DIR}/google"
    mkdir -p "$GOOGLE_DIR"
    curl -fSL "$DOWNLOAD_URL" -o "${BUILD_DIR}/google.tar.gz"

    tar -xzf "${BUILD_DIR}/google.tar.gz" -C "$GOOGLE_DIR"
    local GOOGLE_BIN
    GOOGLE_BIN="$(find "$GOOGLE_DIR" -maxdepth 1 -type f -executable | head -1)"

    if [ -z "$GOOGLE_BIN" ]; then
        echo "Error: could not find Google binary" >&2
        ls -la "$GOOGLE_DIR"
        rm -rf "$BUILD_DIR"
        exit 1
    fi

    echo "Found Google binary: $(stat -c%s "$GOOGLE_BIN") bytes"

    # Step 3: Install binary
    # On aarch64 Android, apply VA39 patch for 39-bit virtual addressing
    # On x86_64, standard 48-bit VA applies and the official binary runs directly
    if [ "$ARCH" = "aarch64" ]; then
        echo "Applying VA39 patch for aarch64 Android..."
        local PATCHED="${BUILD_DIR}/agy_patched"
        python3 "$SCRIPT_DIR/helper/patch_va39.py" "$GOOGLE_BIN" "$PATCHED"
        install -Dm755 "$PATCHED" "${LIB_DIR}/agy.bin"
    else
        echo "Installing unpatched Google binary for x86_64..."
        install -Dm755 "$GOOGLE_BIN" "${LIB_DIR}/agy.bin"
    fi

    # Compatibility symlinks inside LIB_DIR
    ln -sf agy.bin "${LIB_DIR}/agy.va39"
    ln -sf agy.bin "${LIB_DIR}/antigravity"

    # Step 4: Install launcher wrapper script into bin/
    install -Dm755 "$SCRIPT_DIR/helper/agy.sh" "${BIN_DIR}/agy"
    ln -sf agy "${BIN_DIR}/antigravity"

    local INSTALLED_SIZE
    INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

    cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: antigravity-cli
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, resolv-conf, ca-certificates
Section: devel
Priority: optional
Homepage: https://antigravity.google/cli
Description: Google Antigravity CLI - AI coding agent
 Antigravity CLI brings multi-step reasoning, multi-file editing, tool
 calling, and persistent history to your terminal.
EOF

    find "$PKG_DIR" -type d -exec chmod 755 {} +

    local DEB_FILE="${DEBS_DIR}/antigravity-cli_${DEB_VERSION}_termux_${ARCH}.deb"
    export REPRO_MTIME
    REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/antigravity-cli 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
    bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
    echo "Built: $DEB_FILE"
    rm -rf "$BUILD_DIR"
}

if [ "${1:-}" = "aarch64" ] || [ "${1:-}" = "x86_64" ]; then
    build_antigravity_deb "$1"
else
    build_antigravity_deb aarch64
    build_antigravity_deb x86_64
fi
