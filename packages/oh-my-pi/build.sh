#!/usr/bin/env bash
set -euo pipefail

# oh-my-pi: Glibc-linked binary with C bootstrapper

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

# Version info
VERSION="${OMP_VERSION:-18.1.7}"
DEB_VERSION="${VERSION}-0"
PREFIX="data/data/com.termux/files/usr"
ARCH="aarch64"

echo "=== Building oh-my-pi ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/oh-my-pi_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/oh-my-pi"

# Cross-compile the C bootstrapper (static, no deps)
echo "Compiling bootstrapper..."
aarch64-linux-gnu-gcc -static -O2 -o "${BUILD_DIR}/omp_helper" \
    "$SCRIPT_DIR/helper/omp.c"

# Download upstream binary
echo "Downloading oh-my-pi ${VERSION}..."
curl -fSL "https://github.com/can1357/oh-my-pi/releases/download/v${VERSION}/omp-linux-arm64" \
    -o "${BUILD_DIR}/omp.bin"

chmod 755 "${BUILD_DIR}/omp.bin"

# Install files
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
