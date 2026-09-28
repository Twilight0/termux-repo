#!/usr/bin/env bash
set -euo pipefail

# opencode v2: upstream glibc binary + exec-spawn preload shim, no proot
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${OPENCODE_VERSION:-2.0.18}"
DEB_VERSION="${VERSION}-1"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) UPSTREAM_ARCH="arm64" ;;
    x86_64)  UPSTREAM_ARCH="x64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building opencode ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/opencode_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/opencode"

TARBALL="${BUILD_DIR}/opencode.tar.gz"
echo "Downloading opencode ${VERSION} (${UPSTREAM_ARCH})..."
curl -fSL "https://opencode.ai/files/bin/${VERSION}/opencode-linux-${UPSTREAM_ARCH}.tar.gz" \
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

# Do NOT strip, patchelf, or otherwise restructure the binary: Bun
# single-executable bundles embed their payload at fixed offsets and break
# (segfault) when program/section headers are rewritten.

install -Dm755 "$UPSTREAM_BIN" "${PKG_DIR}/${PREFIX}/lib/opencode/opencode-bin"

# Build the exec-spawn preload shim with a glibc-targeting compiler.
# Must NOT be Termux's bionic gcc: the shim loads into the glibc process.
find_glibc_cc() {
    if [ "$ARCH" = "aarch64" ]; then
        for c in "${CC:-aarch64-linux-gnu-gcc}" \
                 "${TERMUX_PREFIX:-/data/data/com.termux/files/usr}/glibc/bin/aarch64-linux-gnu-gcc" \
                 "${TERMUX_PREFIX:-/data/data/com.termux/files/usr}/glibc/bin/aarch64-linux-gnu-gcc-14.2.1"; do
            if command -v "$c" >/dev/null 2>&1; then echo "$c"; return 0; fi
        done
    else
        if command -v "${CC:-gcc}" >/dev/null 2>&1; then echo "${CC:-gcc}"; return 0; fi
    fi
    return 1
}

SHIM_CC="$(find_glibc_cc)" || {
    echo "Error: no glibc-targeting C compiler found." >&2
    echo "On Termux: pkg install glibc-repo && pkg install gcc-glibc" >&2
    echo "On a build host: install gcc-aarch64-linux-gnu (or set CC)." >&2
    rm -rf "$BUILD_DIR"
    exit 1
}
echo "Compiling execshim.so with ${SHIM_CC}..."
# env -u: the glibc toolchain itself cannot start with Termux's bionic
# termux-exec preload active (same LIBC error as at runtime).
# PATH: the driver needs its sibling binutils (as, ld) from the same prefix.
env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    PATH="$(dirname "$SHIM_CC"):$PATH" \
    "$SHIM_CC" -shared -fPIC -O2 -o "${BUILD_DIR}/execshim.so" "$SCRIPT_DIR/helper/execshim.c"
if ! readelf -d "${BUILD_DIR}/execshim.so" | grep -q 'libc\.so\.6'; then
    echo "Error: execshim.so is not glibc-linked (built with a bionic gcc?)" >&2
    rm -rf "$BUILD_DIR"
    exit 1
fi
install -Dm755 "${BUILD_DIR}/execshim.so" "${PKG_DIR}/${PREFIX}/lib/opencode/execshim.so"
install -Dm755 "$SCRIPT_DIR/helper/opencode.sh" "${PKG_DIR}/${PREFIX}/bin/opencode"
chmod 755 "${PKG_DIR}/${PREFIX}/bin/opencode"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: opencode
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, ripgrep, jq, nodejs-lts
Conflicts: opencode-legacy
Section: devel
Priority: optional
Homepage: https://github.com/anomalyco/opencode
Description: AI-powered coding assistant for the terminal (v2)
 OpenCode is an interactive AI coding assistant that runs in your terminal.
 Runs on the glibc bridge with an exec-spawn shim; no proot required.
 Conflicts with `opencode-legacy` (v1): install only one of them.
EOF

DEB_FILE="${DEBS_DIR}/opencode_${DEB_VERSION}_termux_${ARCH}.deb"
export REPRO_MTIME
REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/opencode 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
