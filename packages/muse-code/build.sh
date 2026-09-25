#!/usr/bin/env bash
set -euo pipefail

# muse-code: Prebuilt binary from Meta's CDN
# Builds debs for aarch64 and x86_64

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

# Upstream version (update these when new releases drop)
REALVER="${MUSE_REALVER:-1.3.0-R3401.1}"
PKGVER="${MUSE_PKGVER:-1.3.0.r3401.1}"
PKGREL="${MUSE_PKGREL:-1}"
DEB_VERSION="${PKGVER}-${PKGREL}"
PREFIX="data/data/com.termux/files/usr"

# Checksums (update alongside version)
SHA256_AARCH64="${MUSE_SHA256_AARCH64:-5e5ea2a3de3a3fabdff8982aec9423d20eaa7dad05df37efb4264356d0d2e223}"
SHA256_X86_64="${MUSE_SHA256_X86_64:-71b089d055dfe6e4562092bc484896b61bd96fd6ef9fef9da54a14aa174e2a33}"

build_muse_deb() {
    local ARCH="$1"
    local FILE_SUFFIX
    local EXPECTED_SHA

    case "$ARCH" in
        aarch64)
            FILE_SUFFIX="muse-aarch64-linux"
            EXPECTED_SHA="$SHA256_AARCH64"
            ;;
        x86_64)
            FILE_SUFFIX="muse-x86-linux"
            EXPECTED_SHA="$SHA256_X86_64"
            ;;
        *)
            echo "Error: unsupported architecture: $ARCH" >&2
            return 1
            ;;
    esac

    echo "=== Building muse-code ${DEB_VERSION} (${ARCH}) ==="

    local BUILD_DIR
    BUILD_DIR="$(mktemp -d)"
    local PKG_DIR="${BUILD_DIR}/muse-code_${DEB_VERSION}_${ARCH}"
    mkdir -p "${PKG_DIR}/DEBIAN" "${PKG_DIR}/${PREFIX}/bin" "${PKG_DIR}/${PREFIX}/lib/muse"

    # Download binary
    local BIN_URL="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${REALVER}&file=${FILE_SUFFIX}"
    local BIN_FILE="${BUILD_DIR}/muse-${ARCH}"
    echo "Downloading ${FILE_SUFFIX}..."
    curl -fSL "$BIN_URL" -o "$BIN_FILE"

    # Verify checksum
    local ACTUAL_SHA
    ACTUAL_SHA="$(sha256sum "$BIN_FILE" | cut -d' ' -f1)"
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
        echo "Error: checksum mismatch for ${ARCH}" >&2
        echo "  Expected: $EXPECTED_SHA" >&2
        echo "  Actual:   $ACTUAL_SHA" >&2
        rm -rf "$BUILD_DIR"
        return 1
    fi
    echo "SHA256 verified: ${ACTUAL_SHA}"

    # Install files
    install -Dm755 "$BIN_FILE" "${PKG_DIR}/${PREFIX}/lib/muse/muse"
    install -Dm755 "$SCRIPT_DIR/muse.sh" "${PKG_DIR}/${PREFIX}/bin/muse"
    install -Dm755 "$SCRIPT_DIR/muse-session" "${PKG_DIR}/${PREFIX}/lib/muse/muse-session"
    install -Dm755 "$SCRIPT_DIR/muse-mcp" "${PKG_DIR}/${PREFIX}/lib/muse/muse-mcp"

    # Symlinks
    ln -sf muse "${PKG_DIR}/${PREFIX}/bin/muse-code"
    ln -sf "/${PREFIX}/lib/muse/muse-session" "${PKG_DIR}/${PREFIX}/bin/muse-session"
    ln -sf "/${PREFIX}/lib/muse/muse-mcp" "${PKG_DIR}/${PREFIX}/bin/muse-mcp"

    # Calculate installed size
    local INSTALLED_SIZE
    INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

    # Determine optional dependency for x86_64
    local OPT_DEPENDS=""
    if [ "$ARCH" = "x86_64" ]; then
        OPT_DEPENDS="
Suggests: qemu-user-x86-64"
    fi

    # Write control
    cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: muse-code
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: python, ca-certificates, proot${OPT_DEPENDS}
Section: devel
Priority: optional
Homepage: https://dev.meta.ai
Description: Terminal-based AI coding agent powered by Meta's Muse Spark
 Packed with AVX2 legacy fallback, interactive curses TUI session picker,
 and multi-agent MCP configuration management.
EOF

    # Build deb (deterministic: stable bytes for unchanged content)
    local DEB_FILE="${DEBS_DIR}/muse-code_${DEB_VERSION}_termux_${ARCH}.deb"
    export REPRO_MTIME
    REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/muse-code 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
    bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
    echo "Built: $DEB_FILE"
    rm -rf "$BUILD_DIR"
}

# Build for requested architecture or both
if [ "${1:-}" = "aarch64" ] || [ "${1:-}" = "x86_64" ]; then
    build_muse_deb "$1"
else
    build_muse_deb aarch64
    build_muse_deb x86_64
fi
