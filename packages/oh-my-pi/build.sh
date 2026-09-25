#!/usr/bin/env bash
set -euo pipefail

# oh-my-pi: Glibc-linked binary with C bootstrapper
# Usage: build.sh [aarch64|x86_64]
# Strategy: deb contains only the tiny C bootstrapper + postinst downloads the large binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${OMP_VERSION:-18.1.7}"
DEB_VERSION="${VERSION}-1"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) CC="aarch64-linux-gnu-gcc"; OMP_ARCH="arm64" ;;
    x86_64)  CC="gcc";                   OMP_ARCH="x64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building oh-my-pi ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/oh-my-pi_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/oh-my-pi"

install -Dm755 "$SCRIPT_DIR/helper/omp.sh" "${PKG_DIR}/${PREFIX}/bin/omp"
chmod 755 "${PKG_DIR}/${PREFIX}/bin/omp"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: oh-my-pi
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, proot, curl
Section: devel
Priority: optional
Homepage: https://omp.sh
Description: Oh-My-Pi - a coding agent with the IDE wired in
 Plugin manager for Pi - think oh-my-zsh but for Pi. Install themes,
 agents, commands, and tools with a single command. Uses glibc bridge
 for Termux compatibility. Binary downloaded on first run.
EOF

cat > "${PKG_DIR}/DEBIAN/postinst" << 'POSTINST'
#!/bin/sh
set -e
PREFIX="data/data/com.termux/files/usr"
LIB_DIR="${PREFIX}/lib/oh-my-pi"
BIN_FILE="${LIB_DIR}/omp.bin"

if [ ! -f "$BIN_FILE" ]; then
    ARCH=$(dpkg --print-architecture)
    case "$ARCH" in
        aarch64) OMP_ARCH="arm64" ;;
        amd64)   OMP_ARCH="x64" ;;
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    VERSION=$(dpkg -s oh-my-pi | grep '^Version:' | awk '{print $2}' | sed 's/-.*//')
    URL="https://github.com/can1357/oh-my-pi/releases/download/v${VERSION}/omp-linux-${OMP_ARCH}"
    echo "Downloading oh-my-pi binary..."
    mkdir -p "$(dirname "$BIN_FILE")"
    curl -fSL "$URL" -o "$BIN_FILE"
    chmod 755 "$BIN_FILE"
fi
POSTINST
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

DEB_FILE="${DEBS_DIR}/oh-my-pi_${DEB_VERSION}_termux_${ARCH}.deb"
export REPRO_MTIME
REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/oh-my-pi 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
rm -rf "$BUILD_DIR"
