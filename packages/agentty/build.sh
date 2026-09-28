#!/usr/bin/env bash
set -euo pipefail

# agentty: AI pair programming agent, native Bionic build for Termux
# (no proot, no glibc, no patches at runtime).
#
# Upstream publishes no Android binary. CI cross-compiles with the NDK
# (see build.yml) and passes the result via AGENTTY_BIN; standalone runs
# fall back to the on-device Termux build published as a termux-repo
# release asset. Built per upstream packaging/termux recipe
# (cmake -B build -DAGENTTY_AUTO_PULL_MAYA=OFF -DAGENTTY_STANDALONE=OFF
# -DAGENTTY_BUILD_TESTS=OFF) plus one fix, kept in android-epoll.patch:
# jaal's epoll_reactor.cpp is gated on CMAKE_SYSTEM_NAME STREQUAL "Linux"
# but Termux reports "Android" -> link fails. Patch: treat Android like
# Linux (epoll is fully available in Bionic).
#
# Usage: build.sh [aarch64] (upstream targets aarch64-linux-android only)
# Env: AGENTTY_VERSION (default: packages/agentty/VERSION),
#      AGENTTY_BIN (CI-built binary, skips download),
#      AGENTTY_SHA256 (expected hash for release downloads)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${AGENTTY_VERSION:-$(cat "$SCRIPT_DIR/VERSION")}"
PKGREL="${AGENTTY_PKGREL:-2}"
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
if [ -n "${AGENTTY_BIN:-}" ]; then
    echo "Using CI-built binary: $AGENTTY_BIN"
    cp "$AGENTTY_BIN" "$BIN_FILE"
    # Sanity check (hash pinning only applies to release downloads below)
    if [ ! -s "$BIN_FILE" ]; then
        echo "Error: CI-built binary is empty" >&2
        exit 1
    fi
    if ! head -c 4 "$BIN_FILE" | grep -q $'\x7fELF'; then
        echo "Error: CI-built binary is not an ELF executable" >&2
        exit 1
    fi
else
    # Bionic binary + checksum of the release asset (on-device Termux build)
    BIN_URL="https://github.com/Twilight0/termux-repo/releases/download/agentty-${VERSION}/agentty-${VERSION}-${ARCH}"
    EXPECTED_SHA="${AGENTTY_SHA256:-50d7e512ada73a1debc19461868a14a4e9033f24f1e88ac2e126371ad9dba486}"

    echo "Downloading agentty ${VERSION} (${ARCH})..."
    curl -fSL "$BIN_URL" -o "$BIN_FILE"

    ACTUAL_SHA="$(sha256sum "$BIN_FILE" | cut -d' ' -f1)"
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
        echo "Error: checksum mismatch" >&2
        echo "  Expected: $EXPECTED_SHA" >&2
        echo "  Actual:   $ACTUAL_SHA" >&2
        rm -rf "$BUILD_DIR"
        exit 1
    fi
    echo "SHA256 verified: ${ACTUAL_SHA}"
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
