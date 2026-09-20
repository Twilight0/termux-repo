#!/usr/bin/env bash
set -euo pipefail

# oh-my-pi: Glibc-linked binary with C bootstrapper
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${OMP_VERSION:-18.1.7}"
DEB_VERSION="${VERSION}-0"
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

echo "Compiling bootstrapper (${ARCH})..."
$CC -static -O2 -o "${BUILD_DIR}/omp_helper" "$SCRIPT_DIR/helper/omp.c"

echo "Downloading oh-my-pi ${VERSION} (${OMP_ARCH})..."
curl -fSL "https://github.com/can1357/oh-my-pi/releases/download/v${VERSION}/omp-linux-${OMP_ARCH}" \
    -o "${BUILD_DIR}/omp.bin"

chmod 755 "${BUILD_DIR}/omp.bin"

install -Dm755 "${BUILD_DIR}/omp.bin" "${PKG_DIR}/${PREFIX}/lib/oh-my-pi/omp.bin"
install -Dm755 "${BUILD_DIR}/omp_helper" "${PKG_DIR}/${PREFIX}/bin/omp"
chmod 755 "${PKG_DIR}/${PREFIX}/bin/omp"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: oh-my-pi
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc
Section: devel
Priority: optional
Homepage: https://omp.sh
Description: Oh-My-Pi - a coding agent with the IDE wired in
 Plugin manager for Pi - think oh-my-zsh but for Pi. Install themes,
 agents, commands, and tools with a single command. Uses glibc bridge
 for Termux compatibility.
EOF

DEB_FILE="${DEBS_DIR}/oh-my-pi_${DEB_VERSION}_termux_${ARCH}.deb"
dpkg-deb -Zxz --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
