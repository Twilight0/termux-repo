#!/usr/bin/env bash
set -euo pipefail

# agentty: AI pair programming agent, native Bionic build for Termux
# (no proot, no glibc, no patches at runtime).
#
# Upstream publishes no Android binary. The Bionic binary is cross-compiled
# with the NDK in CI (see build.yml) and passed in via AGENTTY_BIN.
# There is no download fallback: we publish no release assets.
#
# Usage: build.sh [aarch64] (upstream targets aarch64-linux-android only)
# Env: AGENTTY_VERSION (default: packages/agentty/VERSION),
#      AGENTTY_BIN (CI-built binary, required)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${AGENTTY_VERSION:-$(cat "$SCRIPT_DIR/VERSION")}"
PKGREL="${AGENTTY_PKGREL:-1}"
DEB_VERSION="${VERSION}-${PKGREL}"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) ;;
    *) echo "Error: agentty has no Android build for $ARCH (aarch64 only)" >&2; exit 1 ;;
esac

echo "=== Building agentty ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
PKG_DIR="${BUILD_DIR}/agentty_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/agentty"

BIN_FILE="${BUILD_DIR}/agentty"
if [ -z "${AGENTTY_BIN:-}" ]; then
    echo "Error: AGENTTY_BIN is not set (NDK cross-compiled binary from CI, see build.yml)." >&2
    exit 1
fi
echo "Using CI-built binary: $AGENTTY_BIN"
cp "$AGENTTY_BIN" "$BIN_FILE"
# Sanity check: must be a non-empty ELF executable
if [ ! -s "$BIN_FILE" ]; then
    echo "Error: CI-built binary is empty" >&2
    exit 1
fi
if ! head -c 4 "$BIN_FILE" | grep -q $'\x7fELF'; then
    echo "Error: CI-built binary is not an ELF executable" >&2
    exit 1
fi

install -Dm755 "$BIN_FILE" "${PKG_DIR}/${PREFIX}/lib/agentty/agentty.bin"
install -Dm755 "$SCRIPT_DIR/helper/agentty.sh" "${PKG_DIR}/${PREFIX}/bin/agentty"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: agentty
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: openssl, libnghttp2, libc++
Section: devel
Priority: optional
Homepage: https://github.com/1ay1/agentty
Description: Blazing-fast AI pair programming in your terminal
 Native Bionic C++ agent (no proot): one static-ish binary with local
 RAG, any-model providers (including OpenAI-compatible endpoints),
 MCP support and agent skills. Run 'agentty' then /connect.
EOF

DEB_FILE="${DEBS_DIR}/agentty_${DEB_VERSION}_termux_${ARCH}.deb"
export REPRO_MTIME
REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/agentty 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE"
rm -rf "$BUILD_DIR"
